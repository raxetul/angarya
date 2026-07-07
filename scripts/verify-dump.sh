#!/usr/bin/env bash
#
# verify-dump.sh — verify a PostgreSQL dump by test-restoring it into a
# throwaway, in-memory Postgres running in a Docker container, then running
# sanity checks.
#
# Docker-only: the host needs only Docker + bash (no local postgres client).
# The dump is copied into the container and restored there with pg-restore.sh
# (expected next to this file); verification queries run via `docker exec`.
# The container's data directory is a tmpfs mount, so the whole database lives
# in RAM and never touches disk; the container is force-removed on exit.
#
# Images (latest main releases by default):
#   plain      postgres:latest
#   vectorchord tensorchord/vchord-suite:pg18-latest   (vchord + pgvector + contrib)
#
# The dump's required extensions are auto-detected. If any is a TensorChord
# extension (vchord, vectors, vchord_bm25, ...), the VectorChord image is used
# automatically; otherwise the plain postgres image is used. Override with
# --image, or force the VectorChord image with --vchord.
#
# What "PASS" means:
#   1. pg-restore.sh exits 0 (the dump restored without error), AND
#   2. the restored database has at least --min-tables user tables.
# Row counts (post-ANALYZE, approximate) are printed for information.
#
# Usage:
#   verify-dump.sh -f <dumpfile> [-d dbname] [--image IMG | --vchord]
#                  [--pg-image IMG] [--vchord-image IMG]
#                  [--min-tables N] [--size SIZE] [--keep]
#
# Options:
#   -f, --file FILE       dump to verify (file or directory)            [required]
#   -d, --dbname NAME     database name to restore into            [default verifydb]
#       --image IMG       force a specific image (skips auto-detection)
#       --vchord          force the VectorChord image
#       --pg-image IMG    plain postgres image             [default postgres:latest]
#       --vchord-image I  vectorchord image     [default tensorchord/vchord-suite:pg18-latest]
#       --min-tables N    minimum user tables required to PASS           [default 1]
#       --size SIZE       tmpfs size for the data dir                 [default 2048m]
#       --keep            do not remove the container on exit (for debugging)
#   -h, --help            show this help
#
# Exit status: 0 = PASS, 1 = FAIL / error.
#
set -euo pipefail

PROG=$(basename "$0")
HERE=$(cd "$(dirname "$0")" && pwd)
RESTORE="$HERE/pg-restore.sh"

# TensorChord extensions that require the VectorChord image.
TENSORCHORD_EXTS="vchord vectors vchordrq vchord_bm25 pg_tokenizer"

FILE=
DBNAME=verifydb
IMAGE=
FORCE_VCHORD=false
PG_IMAGE=postgres:latest
VCHORD_IMAGE=tensorchord/vchord-suite:pg18-latest
MIN_TABLES=1
TMPFS_SIZE=2048m
KEEP=false
PASSWORD=verify

die() { echo "$PROG: $*" >&2; exit 1; }
usage() { sed -n '2,48p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    -f|--file)         FILE=${2:?}; shift 2 ;;
    -d|--dbname)       DBNAME=${2:?}; shift 2 ;;
    --image)           IMAGE=${2:?}; shift 2 ;;
    --vchord)          FORCE_VCHORD=true; shift ;;
    --pg-image)        PG_IMAGE=${2:?}; shift 2 ;;
    --vchord-image)    VCHORD_IMAGE=${2:?}; shift 2 ;;
    --min-tables)      MIN_TABLES=${2:?}; shift 2 ;;
    --size)            TMPFS_SIZE=${2:?}; shift 2 ;;
    --keep)            KEEP=true; shift ;;
    -h|--help)         usage 0 ;;
    *)                 echo "$PROG: unknown argument: $1" >&2; usage 1 ;;
  esac
done

[ -n "$FILE" ]    || die "-f/--file is required"
[ -e "$FILE" ]    || die "dump not found: $FILE"
[ -f "$RESTORE" ] || die "pg-restore.sh not found next to this script ($RESTORE)"
command -v docker >/dev/null 2>&1 || die "docker not found in PATH"
docker info >/dev/null 2>&1        || die "docker daemon is not running"

ABS_FILE=$(cd "$(dirname "$FILE")" && pwd)/$(basename "$FILE")
BASENAME=$(basename "$FILE")

# --- detect required extensions -------------------------------------------
# Plain SQL: grep. Archive formats: list the TOC with pg_restore inside a
# throwaway container (keeps the "docker-only" promise — no host pg client).
detect_extensions() {
  case "$FILE" in
    *.sql)
      grep -hioE 'CREATE EXTENSION( IF NOT EXISTS)? +"?[a-z0-9_]+"?' "$FILE" 2>/dev/null \
        | sed -E 's/.*EXTENSION( IF NOT EXISTS)? +//I; s/"//g' ;;
    *.sql.gz)
      gunzip -c "$FILE" 2>/dev/null \
        | grep -ioE 'CREATE EXTENSION( IF NOT EXISTS)? +"?[a-z0-9_]+"?' \
        | sed -E 's/.*EXTENSION( IF NOT EXISTS)? +//I; s/"//g' ;;
    *)
      docker run --rm -v "$ABS_FILE":"/in/$BASENAME":ro "$PG_IMAGE" \
        pg_restore -l "/in/$BASENAME" 2>/dev/null \
        | sed -nE 's/.* EXTENSION - ([a-zA-Z0-9_]+).*/\1/p' ;;
  esac
}

echo "$PROG: scanning '$FILE' for required extensions ..."
REQ_EXTS=()
while IFS= read -r ext; do
  [ -n "$ext" ] && REQ_EXTS+=("$ext")
done < <(detect_extensions | tr '[:upper:]' '[:lower:]' | sort -u)
if [ "${#REQ_EXTS[@]}" -gt 0 ]; then
  echo "$PROG: extensions in dump: ${REQ_EXTS[*]}"
else
  echo "$PROG: no CREATE EXTENSION statements detected"
fi

# --- choose image ----------------------------------------------------------
needs_vchord=false
if [ "${#REQ_EXTS[@]}" -gt 0 ]; then
  for e in "${REQ_EXTS[@]}"; do
    case " $TENSORCHORD_EXTS " in *" $e "*) needs_vchord=true ;; esac
  done
fi

if [ -n "$IMAGE" ]; then
  :  # explicit override, keep as-is
elif [ "$FORCE_VCHORD" = true ] || [ "$needs_vchord" = true ]; then
  IMAGE=$VCHORD_IMAGE
  [ "$needs_vchord" = true ] && echo "$PROG: dump needs a TensorChord extension -> using $IMAGE"
else
  IMAGE=$PG_IMAGE
fi
echo "$PROG: using image: $IMAGE"

CNAME="pgverify-$$-${RANDOM}"

# shellcheck disable=SC2329  # cleanup is invoked via the EXIT trap
cleanup() {
  if [ "$KEEP" = true ]; then
    echo "$PROG: leaving container '$CNAME' running (remove: docker rm -f $CNAME)"
    return
  fi
  docker rm -f "$CNAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "$PROG: starting ephemeral in-memory postgres ($IMAGE, tmpfs=$TMPFS_SIZE) ..."
docker run -d --rm \
  --name "$CNAME" \
  -e POSTGRES_PASSWORD="$PASSWORD" \
  -e PGDATA=/var/lib/postgresql/data \
  --tmpfs "/var/lib/postgresql/data:rw,size=$TMPFS_SIZE" \
  "$IMAGE" >/dev/null

printf '%s: waiting for postgres to accept connections' "$PROG"
ready=false
for _ in $(seq 1 60); do
  if docker exec "$CNAME" pg_isready -U postgres >/dev/null 2>&1; then
    ready=true; break
  fi
  printf '.'; sleep 1
done
printf '\n'
if [ "$ready" != true ]; then
  echo "$PROG: postgres did not become ready in time" >&2
  docker logs "$CNAME" 2>&1 | tail -20 >&2
  exit 1
fi

echo "$PROG: copying dump and pg-restore.sh into container ..."
docker cp "$ABS_FILE" "$CNAME:/tmp/$BASENAME"
docker cp "$RESTORE" "$CNAME:/tmp/pg-restore.sh"

echo "$PROG: restoring via pg-restore.sh (inside container) ..."
restore_ok=true
if ! docker exec -e PGPASSWORD="$PASSWORD" "$CNAME" \
      bash /tmp/pg-restore.sh \
        -f "/tmp/$BASENAME" -d "$DBNAME" \
        -H 127.0.0.1 -p 5432 -U postgres --create --clean; then
  restore_ok=false
fi

psqlx() {
  docker exec -e PGPASSWORD="$PASSWORD" "$CNAME" \
    psql -v ON_ERROR_STOP=1 --no-psqlrc -U postgres -d "$DBNAME" -tAc "$1"
}

echo "$PROG: analyzing and inspecting restored database ..."
psqlx "ANALYZE;" >/dev/null 2>&1 || true

table_count=$(psqlx "SELECT count(*) FROM pg_stat_user_tables;" 2>/dev/null | tr -d '[:space:]')
[ -n "$table_count" ] || table_count=0
installed_exts=$(psqlx "SELECT string_agg(extname, ', ' ORDER BY extname) FROM pg_extension;" 2>/dev/null || true)

echo "----------------------------------------------------------------"
echo " Dump:            $FILE"
echo " Image:           $IMAGE  (db=$DBNAME)"
echo " Installed exts:  ${installed_exts:-none}"
echo " User tables:     $table_count"
if [ "$table_count" -gt 0 ]; then
  echo " Largest tables (approx rows):"
  psqlx "SELECT schemaname||'.'||relname||E'\t'||n_live_tup
         FROM pg_stat_user_tables ORDER BY n_live_tup DESC LIMIT 10;" 2>/dev/null \
    | while IFS=$'\t' read -r tbl rows; do
        [ -n "$tbl" ] && printf '   %-50s %12s\n' "$tbl" "$rows"
      done
fi
echo "----------------------------------------------------------------"

if [ "$restore_ok" = true ] && [ "$table_count" -ge "$MIN_TABLES" ]; then
  echo "$PROG: PASS — dump restored cleanly with $table_count user table(s)"
  exit 0
fi

if [ "$restore_ok" != true ]; then
  echo "$PROG: FAIL — pg-restore.sh reported errors (see output above)" >&2
else
  echo "$PROG: FAIL — only $table_count user table(s), need >= $MIN_TABLES" >&2
fi
exit 1

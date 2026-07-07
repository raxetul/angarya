#!/usr/bin/env bash
#
# pg-restore.sh — restore a PostgreSQL dump into a target database.
#
# Standalone: no Ansible, no templating. Reusable core used both for real
# restores and by verify-dump.sh to test a dump against a throwaway server.
#
# Format is auto-detected (override with --format):
#   *.dump            -> custom     (pg_restore)
#   *.tar             -> tar        (pg_restore)
#   *.dir / a dir/    -> directory  (pg_restore)
#   *.sql             -> plain      (psql)
#   *.sql.gz          -> plain, gunzipped on the fly (psql)
#   anything else     -> sniffed via `pg_restore -l`, falling back to plain
#
# The dump password is taken from the environment (PGPASSWORD or PGPASSFILE);
# it is never accepted on the command line.
#
# Usage:
#   pg-restore.sh -f <dumpfile> -d <dbname> \
#       [-H host] [-p port] [-U user] [--create] [--clean] [-j N] [--format F]
#
# Options:
#   -f, --file FILE     dump file (or directory for directory-format)   [required]
#   -d, --dbname NAME   target database                                 [required]
#   -H, --host HOST     server host                              [default 127.0.0.1]
#   -p, --port PORT     server port                                     [default 5432]
#   -U, --user USER     server user                                 [default postgres]
#   -C, --create        create the target database if it is missing
#       --clean         drop existing objects before restore (archive formats only)
#   -j, --jobs N        parallel restore workers (archive formats only) [default 1]
#       --format F      force format: custom|tar|directory|plain|plain-gz
#   -h, --help          show this help
#
set -euo pipefail

PROG=$(basename "$0")

HOST=127.0.0.1
PORT=5432
USER_NAME=postgres
DBNAME=
FILE=
CREATE=false
CLEAN=false
JOBS=1
FORMAT=

die() { echo "$PROG: $*" >&2; exit 1; }

usage() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    -f|--file)    FILE=${2:?}; shift 2 ;;
    -d|--dbname)  DBNAME=${2:?}; shift 2 ;;
    -H|--host)    HOST=${2:?}; shift 2 ;;
    -p|--port)    PORT=${2:?}; shift 2 ;;
    -U|--user)    USER_NAME=${2:?}; shift 2 ;;
    -j|--jobs)    JOBS=${2:?}; shift 2 ;;
    --format)     FORMAT=${2:?}; shift 2 ;;
    -C|--create)  CREATE=true; shift ;;
    --clean)      CLEAN=true; shift ;;
    -h|--help)    usage 0 ;;
    *)            echo "$PROG: unknown argument: $1" >&2; usage 1 ;;
  esac
done

[ -n "$FILE" ]   || die "-f/--file is required"
[ -n "$DBNAME" ] || die "-d/--dbname is required"
[ -e "$FILE" ]   || die "dump not found: $FILE"

for bin in psql pg_restore; do
  command -v "$bin" >/dev/null 2>&1 || die "$bin not found in PATH (install postgresql-client)"
done

PSQL_BASE=(psql -v ON_ERROR_STOP=1 --no-psqlrc \
  --host="$HOST" --port="$PORT" --username="$USER_NAME")

# --- detect format ---------------------------------------------------------
fmt=$FORMAT
if [ -z "$fmt" ]; then
  if [ -d "$FILE" ]; then
    fmt=directory
  else
    case "$FILE" in
      *.dump)   fmt=custom ;;
      *.tar)    fmt=tar ;;
      *.dir)    fmt=directory ;;
      *.sql)    fmt=plain ;;
      *.sql.gz) fmt=plain-gz ;;
      *)
        if pg_restore -l "$FILE" >/dev/null 2>&1; then fmt=custom; else fmt=plain; fi
        ;;
    esac
  fi
fi

# --- create target database if requested -----------------------------------
if [ "$CREATE" = true ]; then
  exists=$("${PSQL_BASE[@]}" --dbname=postgres -tAc \
    "SELECT 1 FROM pg_database WHERE datname='$DBNAME'")
  if [ "$exists" = "1" ]; then
    echo "$PROG: database '$DBNAME' already exists"
  else
    echo "$PROG: creating database '$DBNAME'"
    "${PSQL_BASE[@]}" --dbname=postgres -c "CREATE DATABASE \"$DBNAME\""
  fi
fi

echo "$PROG: restoring '$FILE' (format=$fmt) into ${USER_NAME}@${HOST}:${PORT}/${DBNAME}"

case "$fmt" in
  plain)
    "${PSQL_BASE[@]}" --dbname="$DBNAME" -f "$FILE"
    ;;
  plain-gz)
    gunzip -c "$FILE" | "${PSQL_BASE[@]}" --dbname="$DBNAME"
    ;;
  custom|tar|directory)
    args=(--host="$HOST" --port="$PORT" --username="$USER_NAME" --dbname="$DBNAME"
          --no-owner --no-privileges --exit-on-error --verbose)
    [ "$CLEAN" = true ] && args+=(--clean --if-exists)
    [ "$JOBS" -gt 1 ]   && args+=(--jobs="$JOBS")
    pg_restore "${args[@]}" "$FILE"
    ;;
  *)
    die "unknown format: $fmt (expected custom|tar|directory|plain|plain-gz)"
    ;;
esac

echo "$PROG: restore completed OK"

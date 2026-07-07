# Backup / dump utilities

Standalone helper scripts — **not** invoked by Ansible. They only need `bash`,
plus `postgresql-client` for `pg-restore.sh` (or Docker for `verify-dump.sh`,
which runs the client inside the container).

## `pg-restore.sh` — restore a dump into a target database

Restores a PostgreSQL dump into an existing/target server. Format is
auto-detected (`custom` / `tar` / `directory` / `plain` / `plain-gz`); password
comes from `PGPASSWORD` or `PGPASSFILE`.

```bash
PGPASSWORD=secret ./pg-restore.sh \
  -f /media/backup/postgres/immich-2026-07-06--03-00-00.dump \
  -d immich -H 10.0.0.10 -p 5432 -U immich --create --clean
```

## `verify-dump.sh` — test-restore a dump in a throwaway in-memory Postgres

Spins an **ephemeral, tmpfs-backed (in-RAM)** Postgres container, copies the
dump in, restores it with `pg-restore.sh` *inside the container*, runs sanity
checks (table count, approximate row counts), then removes the container.
Docker-only — the host needs nothing but Docker.

```bash
./verify-dump.sh -f immich-2026-07-06--03-00-00.dump
```

Images (latest main releases by default, override with `--image`):

| Dump needs                       | Image used (auto)                        |
|----------------------------------|------------------------------------------|
| no / plain extensions, pgvector  | `postgres:latest`                        |
| `vchord` / other TensorChord ext | `tensorchord/vchord-suite:pg18-latest`   |

The dump's `CREATE EXTENSION`s are scanned first (via `pg_restore -l` in a
throwaway container) and the VectorChord image is selected automatically when a
TensorChord extension is present. Force it with `--vchord`, or pin any image
with `--image <ref>`.

**PASS** = restore exited 0 **and** at least `--min-tables` (default 1) user
tables exist. Exit status is 0 on PASS, 1 on FAIL.

### Caveats

- **immich vector extension:** recent immich uses `vchord` (covered by the
  VectorChord suite). If your immich dump instead uses `vectors` (pgvecto.rs)
  and the suite image does not ship it, pin immich's own DB image with
  `--image ghcr.io/immich-app/postgres:<tag>`. *(YOU SHOULD VERIFY which
  extension your immich version uses.)*
- Restoring an older-major dump into a newer server (e.g. PG16 dump → PG18
  image) normally works, but pin `--pg-image postgres:<major>` if you need an
  exact match.

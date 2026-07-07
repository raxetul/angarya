# Angarya

Angarya means drudgery, angary.

A personal collection of Ansible playbooks for installing and configuring my home
server and small homelab. The repo is opinionated to my setup but the roles are
self-contained — feel free to take what you need.

It is also the button to start doomsday. :supervillain:

---

## What's in this repo

Three scopes, one playbook (`site.yml`):

| Role          | Path           | Purpose                                                              |
|---------------|----------------|----------------------------------------------------------------------|
| `base`        | `base/`        | Common base packages, users, groups, anything every machine needs.   |
| `server`      | `server/`      | Bare-metal: RAID, samba, network, LXC, docker, backup, HomeAssistant.|
| `kube-on-lxc` | `kube-on-lxc/` | Kubernetes cluster running inside LXC containers.                    |

All three roles run against the host `merkez` (see `site.yml` and `inventory`).
Use tags to scope what runs (see [Tags](#tags) below).

---

## Dependencies

**On the controller (your laptop):**

- `ansible` ≥ 2.14
- SSH access to the target host as `root` (or a user with passwordless sudo)

**On the target host:**

- A Debian-based OS (tested on Debian 12)
- `python3`
- For the `backup` tag specifically: `postgresql-client` (for `pg_dump` and `psql`)

---

## First-time setup

1. **Clone the repo.**

   ```bash
   git clone <this-repo> my-installation
   cd my-installation
   ```

2. **Set up the inventory.** Edit `inventory` so the `merkez` group points at your
   server's reachable address.

3. **Populate variables.** This repo uses two layers of variables:

   - **Root-level** (passed via `--extra-vars`):

     ```bash
     cp my-variables-sample.yml my-variables.yml
     # edit my-variables.yml
     ```

     `my-variables.yml` is gitignored. It holds user/host-specific bits like
     network config, user accounts, RAID partitions, etc.

   - **Role-level** (per-role `vars/main.yml`, also gitignored via `**/vars/main.yml`):

     ```bash
     cp server/vars/main-sample.yml server/vars/main.yml
     # edit server/vars/main.yml
     ```

     Repeat for any other role you'll run that has a `vars/main-sample.yml`.

4. **(Optional) Set up secrets with ansible-vault.** Required if you use the
   `backup` tag with database targets. See [Secrets with ansible-vault](#secrets-with-ansible-vault).

5. **First run.**

   ```bash
   ansible-playbook site.yml --extra-vars "@my-variables.yml"
   ```

---

## Running the playbook

### Full run

```bash
ansible-playbook site.yml --extra-vars "@my-variables.yml"
```

With vault-encrypted secrets:

```bash
ansible-playbook site.yml \
  --extra-vars "@my-variables.yml" \
  --extra-vars "@my-secrets.yml" \
  --ask-vault-pass
```

### Tag-scoped run

Run only the parts you need with `--tags`, or exclude noisy parts with `--skip-tags`:

```bash
# Only the backup setup
ansible-playbook site.yml --extra-vars "@my-variables.yml" --tags backup

# Multiple concerns at once
ansible-playbook site.yml --extra-vars "@my-variables.yml" --tags backup,network

# Everything except RAID + LXC
ansible-playbook site.yml --extra-vars "@my-variables.yml" --skip-tags raid,lxc
```

### Tags

| Tag             | Scope         | What it does                                                              |
|-----------------|---------------|---------------------------------------------------------------------------|
| `base`          | site-level    | Run only the `base` role.                                                 |
| `server`        | site-level    | Run only the `server` role.                                               |
| `kube`          | site-level    | Run only the `kube-on-lxc` role.                                          |
| `raid`          | server        | Format and mount RAID partitions.                                         |
| `samba`         | server        | Samba shares.                                                             |
| `network`       | server        | NetworkManager / interface configuration.                                 |
| `lxc`           | server        | LXC host setup.                                                           |
| `docker`        | server        | Rootless docker for a non-privileged user.                                |
| `homeassistant` | server        | Home Assistant in a libvirt KVM domain.                                   |
| `backup`        | server        | USB-triggered backup of files + PostgreSQL DBs (see [Backup](#backup)).   |
| `hello`         | server        | A no-op smoke test.                                                       |

Every task block in `<role>/tasks/main.yml` carries one of these tags, so
partial runs are exact and don't require commenting out code.

---

## Secrets with ansible-vault

Sensitive values (database passwords, eventually anything else that shouldn't
live in plaintext) go into a separate vault-encrypted file: `my-secrets.yml`.

### One-time setup

1. **Copy the sample and fill it in.**

   ```bash
   cp my-secrets-sample.yml my-secrets.yml
   $EDITOR my-secrets.yml
   ```

2. **Encrypt it.**

   ```bash
   ansible-vault encrypt my-secrets.yml
   ```

   You'll be prompted for a vault password — pick one and keep it somewhere safe
   (a password manager). After this, `my-secrets.yml` is unreadable without that
   password.

3. **Decide how to supply the password to Ansible.** Two common options:

   - **Interactive** (`--ask-vault-pass`): Ansible prompts you each run.
   - **Password file** (`--vault-password-file ~/.vault-pass`): a plain file
     outside the repo containing the password. Convenient for unattended runs;
     **never** commit this file.

### Daily use

- **Edit a value:** `ansible-vault edit my-secrets.yml`
- **View it without writing:** `ansible-vault view my-secrets.yml`
- **Change the vault password:** `ansible-vault rekey my-secrets.yml`
- **Decrypt it (back to plaintext):** `ansible-vault decrypt my-secrets.yml`
- **Run the playbook:**

  ```bash
  ansible-playbook site.yml \
    --extra-vars "@my-variables.yml" \
    --extra-vars "@my-secrets.yml" \
    --ask-vault-pass
  ```

### What goes in `my-secrets.yml`

Currently just the DB password map for the backup feature:

```yaml
postgresql_secrets:
  immich: "<password for the immich DB user>"
  nextcloud: "<password for the nextcloud DB user>"
```

Keys here must match the keys under the top-level `postgresql` map in
`server/vars/main.yml`. See `my-secrets-sample.yml` for the template.

`my-secrets.yml` is in `.gitignore`. If you want to commit the encrypted file so
it lives alongside the repo, force-add it explicitly with `git add -f
my-secrets.yml` — but make sure it's encrypted first.

---

## Backup

The `backup` tag wires up an unattended USB-triggered backup that runs whenever
a specific external drive is plugged into the server.

### How it works

```text
USB plug
  │
  ▼
udev rule (matches by ID_SERIAL)         /etc/udev/rules.d/99-<server>-usb-rsync-backup.rules
  │  sets SYSTEMD_WANTS=<server>-backup@<dev>.service
  ▼
systemd templated unit                    /etc/systemd/system/<server>-backup@.service
  │  LoadCredential=pgpass:/etc/credstore/pgpass-<server>
  │  ExecStart=/opt/scripts/backup-server.sh /dev/<partition>
  ▼
backup-server.sh  (orchestrator)
  │  mount the disk
  │  fire HA webhook: started
  ├──► backup-files.sh <mount>   (rsync each backup.tasks entry)
  ├──► backup-db.sh    <mount>   (pg_dump each `postgresql` server entry + log row counts)
  │  unmount the disk
  │  fire HA webhook: completed / has_error
```

Each script writes to its own log under `/tmp/backup/` while running and copies
all logs to `backup.log_dir` (on the external drive) at the end.

### Required variables

In `server/vars/main.yml` (copy from `server/vars/main-sample.yml`):

```yaml
backup:
  server_name: my-server                  # used in unit / udev rule names
  webhook:
    started:    { id: "<HA webhook id>" }
    completed:  { id: "<HA webhook id>" }
    has_error:  { id: "<HA webhook id>" }
  external_drive:
    serial: "WDC_..."                     # matched against udev ENV{ID_SERIAL}
  log_dir: "/media/backup/synched/log"    # on the external drive
  target_mount: "/media/backup"           # where the drive gets mounted
  tasks:                                  # files-rsync targets
    photos:
      source: "/media/photos"
      target: "/media/backup/synched"
    nextcloud_data:
      source: "/home/rootless/docker/nextcloud/data"
      target: "/media/backup/synched/docker/nextcloud/data"
      excludes: ["**/backups/**"]
  # db_subdir: "postgres"                 # optional; dumps go to <target_mount>/<db_subdir>/
```

DB servers live in a separate top-level `postgresql` map (server name →
connection details). `pg_dump` runs once per entry:

```yaml
postgresql:
  immich:                                 # extension DB (VectorChord)
    host: 10.0.0.10
    port: 5432
    user: immich
    dbname: immich
    format: plain                         # custom | plain | tar | directory
    compress: true                        # gzip -> immich-<ts>.sql.gz (plain only)
    extra_args: ["--clean", "--if-exists"]
  nextcloud:
    host: 10.0.0.11
    port: 5432
    user: nextcloud
    dbname: nextcloud
    format: custom
```

`--clean`/`--if-exists` are plain-format options; for archive formats
(`custom`/`tar`/`directory`) the restore performs the clean instead.

> **Extension databases (immich).** immich uses the `vchord` extension, and a
> naive dump can restore poorly. immich's docs recommend a plain-format
> `pg_dump --clean --if-exists`, gzipped, restored into a **matching immich
> version** (cross-version restores need migrations). The settings above follow
> that shape — **verify the exact procedure for your immich version**, and use
> `scripts/verify-dump.sh` to confirm each dump actually restores.

In `my-secrets.yml` (vault-encrypted), one password per `postgresql` key:

```yaml
postgresql_secrets:
  immich: "..."
```

### Where credentials live on the host

Database passwords reach `pg_dump` through systemd's `LoadCredential=` mechanism:

1. Ansible renders a [PostgreSQL password file](https://www.postgresql.org/docs/current/libpq-pgpass.html)
   to `/etc/credstore/pgpass-<server_name>` with mode `0400 root:root`, one line per DB:
   `host:port:db:user:password`.
2. The systemd unit declares
   `LoadCredential=pgpass:/etc/credstore/pgpass-<server_name>`. When the unit
   runs, systemd copies that file into a private directory that **only this
   service invocation** can read, and exposes it as
   `$CREDENTIALS_DIRECTORY/pgpass`.
3. `backup-db.sh` exports `PGPASSFILE=$CREDENTIALS_DIRECTORY/pgpass`. libpq reads
   it automatically — no password ever appears on the command line, in env vars,
   in `ps`, or anywhere else outside the credstore file.

The plain DB connection metadata (host/port/db/user) stays in
`server/vars/main.yml` and is reviewable. Only passwords live in the vault.

### What logs you get

- `/tmp/backup/server.log` — orchestrator: mount/unmount, child exit codes,
  webhook fires.
- `/tmp/backup/rsync.log` — files backup: each task's start/end + failure detail.
- `/tmp/backup/db-dump.log` — DB backup. For each target, logs:
  - `[pg_dump] <name> started (host=… db=… format=…)`
  - `[stats] <db>: N user tables (row counts via pg_stat_user_tables.n_live_tup; approximate)`
  - `[stats]   public.users           42103 rows`
  - `[pg_dump] <name> -> <path> OK (<size> bytes)` or `… FAILED rc=… (see <err_log>)`

At the end of the run, all logs are copied to `<backup.log_dir>` on the external
drive so they persist after unmount.

### Testing without unplugging

You can fire the unit by hand against an already-attached partition:

```bash
sudo systemctl start <server_name>-backup@sda1.service
```

To watch it live:

```bash
sudo journalctl -u <server_name>-backup@sda1.service -f
```

To inspect logs without waiting for the unmount copy:

```bash
sudo ls /tmp/backup/
```

### Idempotency

Re-running `--tags backup` should always be a no-op when nothing has changed:

```bash
ansible-playbook site.yml --extra-vars "@my-variables.yml" \
  --extra-vars "@my-secrets.yml" --ask-vault-pass --tags backup
# expect PLAY RECAP: changed=0
```

If you see `changed > 0` on a second run, something is non-idempotent — see
`.claude/rules/idempotency.md` for the rules this repo follows.

---

## Repo structure

```text
.
├── site.yml                       # top-level play, runs all three roles against `merkez`
├── inventory                      # hosts
├── ansible.cfg                    # ansible defaults
├── my-variables-sample.yml        # root-level vars sample (copy → my-variables.yml)
├── my-secrets-sample.yml          # vault-encryptable secrets sample (copy → my-secrets.yml)
├── base/                          # role: base packages, users, groups
├── server/                        # role: bare-metal server
│   ├── tasks/
│   │   ├── main.yml               # imports one concern per tag
│   │   ├── backup.yml             # USB backup setup
│   │   ├── network.yml
│   │   ├── raid.yml
│   │   └── …
│   ├── templates/                 # *.j2 — scripts deployed to /opt/scripts/, configs, unit files
│   └── vars/main-sample.yml       # role-scoped vars sample
├── kube-on-lxc/                   # role: k8s on LXC
└── CLAUDE.md                      # repo conventions (for Claude Code)
```

Conventions used throughout (also enforced via `.claude/rules/`):

- Tasks split per concern under `<role>/tasks/<concern>.yml`, imported from
  `main.yml` via `import_tasks` (so tags propagate).
- Every `import_tasks` in `main.yml` carries a `tags: [<concern>]` line — that's
  how `--tags <name>` works.
- Scripts deployed to hosts live in `<role>/templates/*.sh.j2` and ship to
  `/opt/scripts/` via the `template` module (content-addressed → idempotent).
- systemd units are templated as small `copy:` blocks (static) or `template:`
  files (parameterized).

---

## License

See [LICENSE](LICENSE).

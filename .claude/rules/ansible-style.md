# Ansible Style Rules

Required conventions when writing/editing Ansible content in this repo.

## Module naming

- Use FQCN for builtin modules: `ansible.builtin.file`, `ansible.builtin.copy`, `ansible.builtin.template`, `ansible.builtin.systemd`, `ansible.builtin.command`, `ansible.builtin.import_tasks`.
- For community modules use the full FQCN (e.g. `community.general.foo`).

## Task structure

- Every task **must** have a human-readable `name:`.
- Group related tasks under a parent `name:` + `block:` when they share `become:` / `tags:` / `when:` to avoid repetition.
- Prefer `import_tasks` over `include_tasks` for static composition — tags propagate to imported tasks, `include_tasks` does not.

## Tagging

- In each role's `tasks/main.yml`, every `import_tasks` entry MUST carry `tags: [<concern>]`.
- Tag names should match the subtask filename (e.g. `backup.yml` → `tags: [backup]`).
- Site-level roles in `site.yml` carry a role-level tag (`tags: [server]`, `tags: [kube]`).
- This enables `--tags <tag>` and `--skip-tags <tag>` workflows without commenting code.

## Variables

- User-provided vars enter via `--extra-vars "@my-variables.yml"`. Sample lives in `my-variables-sample.yml`. Keep sample in sync when adding required vars.
- Role-scoped vars live in `<role>/vars/main.yml`.
- Never hardcode IPs, hostnames, paths to user data, or device serials — accept them via vars.

## Idempotency

- Every task must be safe to re-run. See `idempotency.md`.

## Scripts and templates

- Scripts deployed to hosts are Jinja2 templates under `<role>/templates/*.sh.j2`.
- Deploy via the `template:` module, target `/opt/scripts/<name>.sh`, mode `0755`, owner `root`.
- The `template:` module is content-addressed — re-rendering with unchanged inputs is a no-op. This is the idempotent way to deploy scripts.
- Never use `copy:` with inline content for anything that references vars (use `template:`).

## systemd units

- Service files live in `/etc/systemd/system/<name>.service` (or `<name>@.service` for templated).
- Deploy via `ansible.builtin.copy:` with inline `content:` for small static units, `template:` for parameterized.
- After deploying a unit, call `ansible.builtin.systemd: daemon_reload: true`.
- For `Type=oneshot` units that run long workloads, set `TimeoutStartSec=0` to disable the default 90s timeout.

## Pre-commit guards

- Never use destructive flags (`--no-verify`, `--force`) on git operations without explicit user approval.

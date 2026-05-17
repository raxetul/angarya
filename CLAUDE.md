# Project: Angarya — Ansible Installations

Personal collection of Ansible playbooks for installing/configuring:
- **server** — physical server (RAID, samba, networking, lxc, rootless docker, backup, home-assistant kvm)
- **kube-on-lxc** — kubernetes cluster running inside LXC containers
- **base** — common base packages and arrangements

## Entry Points

- `site.yml` — top-level play targeting `merkez` host with role list
- `my-variables.yml` — user secrets / vars (gitignored), sample at `my-variables-sample.yml`
- Run: `ansible-playbook site.yml --extra-vars "@my-variables.yml"`
- Tag-scoped run: `--tags <tag>` / `--skip-tags <tag>`

## Scopes

| Scope             | Path           | Examples                                |
|-------------------|----------------|-----------------------------------------|
| personal-computer | `base/`        | user setup, dotfiles, baseline packages |
| homelab           | `kube-on-lxc/` | k8s on lxc                              |
| server            | `server/`      | services on bare-metal server           |

## Conventions

- **Line length**: max 120 cols. Wrap long pipelines, dicts, jinja loops across lines. Do not collapse user's multi-line dicts or shell pipelines into one-liners when editing. See `.editorconfig`.
- Tasks split per concern under `<role>/tasks/<concern>.yml`, imported via `import_tasks` (not `include_tasks`) so tags propagate.
- Every `import_tasks` in `main.yml` carries `tags: [<concern>]` to support partial runs.
- Scripts deployed to hosts live in `<role>/templates/*.sh.j2` and are deployed to `/opt/scripts/` via the `template` module.
- systemd units deployed via `copy:` with inline content (small) or `template:` (parameterized).
- Idempotency required for every task. See `.claude/rules/idempotency.md`.

## Key files for an agent landing here

- `site.yml` — play definition
- `<role>/tasks/main.yml` — role entry, lists tagged subtask imports
- `<role>/vars/main.yml` — role-scoped vars
- `my-variables-sample.yml` — declared user-provided vars
- `README.md` — human-facing usage

## Where to read more

- `.claude/rules/` — required style + idempotency rules
- `.claude/skills/` — step-by-step workflows for common operations
- `.claude/commands/` — slash commands for repeated audits
- `.claude/agents/` — specialized review subagent

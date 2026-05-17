# Idempotency Rules

Every Ansible task must produce the same result when run repeatedly. Second + nth run should report `changed=0`. This file lists the patterns to use and the traps to avoid.

## Idempotent modules (use these by default)

- `ansible.builtin.file` — state + mode + owner declarative
- `ansible.builtin.copy` — content-addressed
- `ansible.builtin.template` — content-addressed via rendered output
- `ansible.builtin.lineinfile` — regex-anchored
- `ansible.builtin.blockinfile` — marker-bracketed block
- `ansible.builtin.systemd` — service state declarative
- `ansible.builtin.apt` / `ansible.builtin.dnf` — package state declarative
- `ansible.builtin.user`, `ansible.builtin.group` — declarative

## Non-idempotent by default (must guard)

- `ansible.builtin.command` and `ansible.builtin.shell` always report `changed`. Either:
  - Add `creates:` / `removes:` arg to skip when target exists/missing, OR
  - Add a `register:` + `changed_when:` clause that inspects output, OR
  - Replace with a real module that expresses the desired state.

## Common traps

- **`include_tasks` with tags** — tags do NOT propagate to included tasks. Use `import_tasks` for tag-scoped runs.
- **Inline scripts via `command:`** that mutate the host — re-run will mutate again. Wrap with `creates:` pointing to a sentinel file, or rewrite as a module call.
- **Appending to config files** with `lineinfile` regex too loose — second run may add a second line. Anchor the regex tightly or use `blockinfile` with `marker:`.
- **udev / systemd reloads** — `command: udevadm control --reload-rules` and `systemd: daemon_reload: true` should be idempotent themselves but only fire when something actually changed: register the upstream change task and gate with `when: <result>.changed` (or use handlers).
- **Mounting and partitions** — never re-format. Check existing state with `ansible.builtin.command: blkid` + `register:` before any destructive op.

## Verification workflow

After writing a task:
1. Run the playbook with `--tags <tag>` — expect `changed=N` first time.
2. Run again with the same tag — expect `changed=0`.
3. If second run shows `changed`, the task is not idempotent. Investigate which module reports the spurious change.

## When non-idempotency is unavoidable

Some real-world ops (e.g. one-shot init scripts that have side effects) cannot be perfectly idempotent. For those:
- Gate execution with `creates:` pointing to a marker file the script itself writes on success.
- Or wrap in `block:` with `when:` that inspects a registered probe.

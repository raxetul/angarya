# Modularity Rules

How to split tasks so partial runs and reuse work cleanly.

## File layout per role

```
<role>/
├── tasks/
│   ├── main.yml          # only import_tasks lines, each tagged
│   ├── <concern>.yml     # one file per concern
│   └── subtasks/         # shared sub-task fragments (optional)
├── templates/            # *.j2 — scripts, configs, units
├── vars/main.yml         # role-scoped vars
├── defaults/main.yml     # default values for vars
├── handlers/main.yml     # restart-on-change handlers
└── files/                # static files (no templating)
```

## main.yml shape

`main.yml` should contain only `import_tasks` lines, each with a tag. Example:

```yaml
- name: Setup networking
  ansible.builtin.import_tasks: network.yml
  tags: [network]

- name: Setup backups
  ansible.builtin.import_tasks: backup.yml
  tags: [backup]
```

No logic, no vars, no tasks directly. Anything more belongs in a concern file.

## Concern files

A concern file (`backup.yml`, `network.yml`, etc.) holds a single `block:` (or a flat list) that solves one user-facing concern.

- Use `block:` to share `become:` / `tags:` / `when:` across the related tasks.
- Keep concern files under ~100 lines. If longer, split into sub-task files in `subtasks/` and `import_tasks:` them.

## Templates and scripts

- A script that has repeated logic (e.g. per-item rsync) should define a bash function and call it per item via a Jinja2 loop, not unroll the loop into N copies of the same code.
- Vars consumed by templates should be structured (e.g. `backup.tasks: { name: { source: ..., target: ..., excludes: [...] } }`), so adding a new item is a config-only change.

## When to extract a new role vs a new concern file

- New **concern file** if it's a step inside an existing role's responsibility (e.g. "set up backups" inside `server`).
- New **role** if it's a self-contained unit that could be reused on a different host (e.g. `k8s-master`, `samba-server`).

## Anti-patterns to avoid

- Commenting out subtasks in `main.yml` to skip them — use tags instead.
- Hardcoded `when: ansible_hostname == 'merkez'` — instead, gate with a var so the same role works on other hosts.
- Duplicate bash code across templates — extract into a function in the template.
- One mega `tasks/main.yml` containing all tasks — split per concern.

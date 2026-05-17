---
name: add-script-task
description: Workflow for adding a new managed shell script to a role — creates the Jinja2 template, the Ansible deploy task, the vars schema, and the tag wiring. Use when the user asks to "add a script", "deploy a script", or describes a script that should be installed on a host.
---

# Add a managed script task

A managed script is a Jinja2 template under `<role>/templates/*.sh.j2` that Ansible renders and deploys to `/opt/scripts/<name>.sh` on the host. Templates are idempotent — re-running with the same vars produces no change.

## Inputs to gather from the user

Before writing anything, confirm:

1. **Which role?** `server`, `kube-on-lxc`, or `base`.
2. **Script name** (e.g. `backup-files`, `rotate-logs`). Use kebab-case.
3. **Concern** — is this part of an existing concern file (e.g. `backup.yml`) or a new one?
4. **Vars consumed** — what config does the script need? Propose a structured shape under the concern's namespace in `vars/main.yml`.
5. **How is it triggered?** — manually via SSH, by systemd timer, by udev event, by another script. (If by a service, also run `add-systemd-service`.)

## Steps

### 1. Create the template

`<role>/templates/<name>.sh.j2`:

```bash
#!/bin/bash
set -uo pipefail

# Render-time vars from Ansible
SOMETHING="{{ <concern>.something }}"

# Helpers and main logic here
```

Conventions:
- `set -uo pipefail`. Do NOT use `-e` if you have a `trap EXIT` cleanup handler — the trap will exit on the first non-zero command in cleanup and mask the real exit code. Handle errors explicitly with `if/else`.
- Quote all variable expansions: `"$VAR"`, `"${array[@]}"`.
- Long-running commands that may produce errors should log stderr to a per-task error log file via `2>"$err_log"`.

### 2. Add the deploy task

In the concern's task file (e.g. `<role>/tasks/<concern>.yml`), inside the existing `block:`:

```yaml
- name: Ensure /opt/scripts directory exists
  ansible.builtin.file:
    path: /opt/scripts
    state: directory
    mode: '0755'
    owner: root
    group: root

- name: Deploy <name> script
  ansible.builtin.template:
    src: <name>.sh.j2
    dest: /opt/scripts/<name>.sh
    mode: '0755'
    owner: root
    group: root
```

If `/opt/scripts` is already created elsewhere in the same role, don't duplicate the directory task.

### 3. Wire vars

Add the vars shape to `<role>/vars/main.yml` AND `my-variables-sample.yml` (so users know to provide them). Use a structured shape:

```yaml
<concern>:
  scripts:
    <name>:
      something: <value>
```

### 4. Wire the tag

If this is a new concern file, in `<role>/tasks/main.yml`:

```yaml
- name: Setup <concern>
  ansible.builtin.import_tasks: <concern>.yml
  tags: [<concern>]
```

Also update README.md "Available tags" line.

### 5. Test the deploy

```bash
ansible-playbook site.yml --extra-vars "@my-variables.yml" --tags <concern>
ssh merkez "cat /opt/scripts/<name>.sh"   # verify rendered content
```

Run the playbook a second time — should report `changed=0`. If not, the template inputs are non-deterministic.

## Anti-patterns

- Hardcoding values in the template that should be vars.
- Using `copy:` with inline content when the script references any var (use `template:`).
- Forgetting to ensure `/opt/scripts` exists.
- Putting the script under `/usr/local/bin` — keep them under `/opt/scripts` so it's clear they are managed by this repo.

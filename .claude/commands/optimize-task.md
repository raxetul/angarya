---
description: Audit an Ansible task file (or the whole role) for style, idempotency, and modularity issues. Reports findings; only edits when the user confirms.
---

# /optimize-task

Optimize a single Ansible task file or a role for the conventions in this repo.

## How to run

User invokes:
- `/optimize-task` — without arg, ask which file/role to audit.
- `/optimize-task <path>` — audit the given file or directory.

## Procedure

1. **Read the target file(s)** and any closely related files (`main.yml` of the same role, `vars/main.yml`, templates the tasks reference).
2. **Read the three rule files** under `.claude/rules/`. They define the standard you are auditing against.
3. **Produce a findings report**, one section per issue, in this shape:

   ```
   ### <issue title>
   - File: <path>:<line>
   - Severity: must-fix | should-fix | nit
   - Problem: <one sentence>
   - Fix: <concrete change or code snippet>
   ```

4. **Check specifically**:
   - FQCN module names (`ansible.builtin.*`, etc.)
   - `import_tasks` vs `include_tasks` (prefer import when tags matter)
   - `tags:` present on every `import_tasks` in `main.yml`
   - `command:` / `shell:` tasks have `creates:` / `removes:` / `changed_when:` guards
   - `lineinfile` regexes are anchored and won't append duplicates
   - Tasks have `name:`
   - `block:` is used to share `become:`/`tags:`/`when:` across related tasks
   - Scripts deployed via `template:` not `copy:` if they reference any var
   - systemd unit deploys are followed by a `daemon_reload` (ideally gated by `.changed`)
   - `Type=oneshot` with long-running script has `TimeoutStartSec=0`
   - Templates don't unroll Jinja2 loops into N copies of the same bash block — extract a function
   - Vars used in templates / tasks are declared in `vars/main.yml` and `my-variables-sample.yml`

5. **Wait for confirmation** before applying edits. If user says "apply", make the changes in batched edits and report what changed.

## Anti-patterns to flag automatically

- Commented-out tasks ("skip me by uncommenting") → propose tagging
- Hardcoded IPs / hostnames / paths → propose extracting to vars
- Duplicate `become: true` repeated on every task in a related group → propose wrapping in `block:`
- `shell:` used where a real module exists → propose the module
- Handlers used as a workaround for non-idempotent tasks → fix the task instead

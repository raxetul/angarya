---
description: Verify a role or tag-scoped run is idempotent — runs the playbook twice and reports any task that reports changed on the second run.
---

# /check-idempotency

Run an idempotency check against a tag or role.

## How to run

- `/check-idempotency <tag>` — runs `ansible-playbook ... --tags <tag>` twice and diffs.
- Without arg, ask which tag.

## Procedure

1. Confirm `my-variables.yml` exists. If not, abort with an error.
2. First pass — record full output:

   ```bash
   ansible-playbook site.yml --extra-vars "@my-variables.yml" --tags <tag> 2>&1 | tee /tmp/idempotency-pass1.log
   ```

   Expect `changed > 0` on a fresh host. On an already-converged host, even pass 1 may be `changed=0`.

3. Second pass:

   ```bash
   ansible-playbook site.yml --extra-vars "@my-variables.yml" --tags <tag> 2>&1 | tee /tmp/idempotency-pass2.log
   ```

   Expect `changed=0`.

4. Parse the `PLAY RECAP` from both logs. Report:
   - Pass 1: `ok=N changed=M`
   - Pass 2: `ok=N changed=M` — if `changed != 0`, list which tasks reported changed.

5. For each task that reported changed on pass 2, read the task definition and propose the fix. Common causes are in `.claude/rules/idempotency.md`.

## Output shape

```
Idempotency check: tag=<tag>
Pass 1: ok=12 changed=4
Pass 2: ok=12 changed=1   ← NOT IDEMPOTENT

Non-idempotent tasks:
- [Reload udev rules] (server/tasks/backup.yml:62)
  Cause: command: udevadm always reports changed.
  Fix: register the upstream rule write, gate this with `when: rule.changed`.
```

## Safety

- Only runs ansible commands, no destructive operations.
- If the user's tag would hit a production-only resource, ask before running.

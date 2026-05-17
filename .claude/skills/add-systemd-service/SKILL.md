---
name: add-systemd-service
description: Workflow for adding a new systemd unit that runs a script automatically — covers service vs templated service, trigger choice (timer, udev, dependency), deploy task, reload, and verification. Use when the user asks to "run X automatically", "on boot", "on schedule", "when USB plugged", "as a service".
---

# Add a systemd service

A managed systemd service runs a script (or binary) on the host on some trigger. This skill covers the four trigger styles used in this repo plus the wiring needed in Ansible.

## Inputs to gather

1. **What does it run?** Path to script (usually `/opt/scripts/<name>.sh`). If the script doesn't exist yet, also run `add-script-task`.
2. **Trigger style?** One of:
   - **On-demand / one-shot** — runs once when started by hand or by another unit. Plain `Type=oneshot`.
   - **Timer** — runs on a schedule. Needs a `.service` + `.timer` pair.
   - **Device event (udev)** — runs when a specific device is plugged. Needs `<name>@.service` templated by device + a udev rule wiring it.
   - **Daemon** — runs persistently. `Type=simple` or `Type=notify`. (Rare in this repo.)
3. **Run as which user?** Default `root`. If non-root, also need `User=`/`Group=`.
4. **Expected runtime?** If > 90s and `Type=oneshot`, must set `TimeoutStartSec=0` to disable systemd's default timeout.
5. **Multiple steps?** A oneshot unit can have multiple `ExecStart=` lines — they run sequentially, stops on first failure unless prefixed with `-`.

## Steps

### 1. Write the unit

Place inside the concern's task file. Use `ansible.builtin.copy:` with inline `content:` for small static units; use `ansible.builtin.template:` if it references vars.

#### Plain oneshot service

```yaml
- name: Create systemd service for <name>
  ansible.builtin.copy:
    dest: /etc/systemd/system/<name>.service
    content: |
      [Unit]
      Description=<what it does>
      After=network-online.target
      Wants=network-online.target

      [Service]
      Type=oneshot
      TimeoutStartSec=0
      ExecStart=/opt/scripts/<name>.sh

      [Install]
      WantedBy=multi-user.target
    mode: '0644'
```

#### Templated service (per-device)

```yaml
- name: Create systemd service for USB backup
  ansible.builtin.copy:
    dest: /etc/systemd/system/<name>@.service
    content: |
      [Unit]
      Description=<what it does> %i
      After=dev-%i.device
      BindsTo=dev-%i.device

      [Service]
      Type=oneshot
      TimeoutStartSec=0
      ExecStartPre=/bin/sleep 5
      ExecStart=/opt/scripts/<name>.sh /dev/%I

      [Install]
      WantedBy=dev-%i.device
    mode: '0644'
```

Note: `%i` is escaped instance name (e.g. `sdc1`), `%I` is unescaped. For device paths, use `%I` so `/dev/sdc1` is correct.

#### Timer

```yaml
- name: Create timer for <name>
  ansible.builtin.copy:
    dest: /etc/systemd/system/<name>.timer
    content: |
      [Unit]
      Description=Run <name> on schedule

      [Timer]
      OnCalendar=daily
      Persistent=true

      [Install]
      WantedBy=timers.target
    mode: '0644'

- name: Enable and start <name>.timer
  ansible.builtin.systemd:
    name: <name>.timer
    enabled: true
    state: started
    daemon_reload: true
```

#### udev rule (for templated device service)

```yaml
- name: Create udev rule
  ansible.builtin.blockinfile:
    path: /etc/udev/rules.d/99-<name>.rules
    create: true
    marker: "# {mark} ANSIBLE MANAGED BLOCK - <NAME>"
    block: |
      ACTION=="add", SUBSYSTEM=="block", ENV{DEVTYPE}=="partition", ENV{ID_SERIAL}=="{{ <var>.serial }}", ENV{SYSTEMD_WANTS}="<name>@%k.service"

- name: Reload udev rules
  ansible.builtin.command: udevadm control --reload-rules
```

### 2. Reload systemd

After any unit file change:

```yaml
- name: Reload systemd
  ansible.builtin.systemd:
    daemon_reload: true
```

Better: register the deploy task's result and gate the reload with `when: <result>.changed`. Or use a handler.

### 3. Enable / start (if not device-triggered)

For timers and persistently-enabled services, add an explicit enable+start task with `ansible.builtin.systemd: enabled: true, state: started`.

For udev-triggered templated services, do NOT enable manually — udev's `SYSTEMD_WANTS` does the wiring.

### 4. Tag wiring

Same as `add-script-task` — ensure the concern file is imported with a tag in `main.yml`.

### 5. Verify

```bash
ssh merkez "systemctl cat <name>.service"        # check rendered unit
ssh merkez "systemctl status <name>.service"     # current state
ssh merkez "journalctl -u <name>.service -n 50"  # last run logs
```

For udev-triggered: unplug/replug the device, then check journal.

## Gotchas

- `Type=oneshot` defaults to 90s `TimeoutStartSec`. Long jobs WILL be killed and exit with code 1. Set `TimeoutStartSec=0` for backups, syncs, etc.
- `BindsTo=dev-X.device` means the unit stops if the device disappears. For a backup that might briefly lose the device under load this can cause failure — use `Requires=` + `After=` if that's a concern.
- Multiple `ExecStart=` lines run sequentially; first non-zero stops the chain unless prefixed with `-` to ignore failures.
- `set -e` in the script + a `trap EXIT` cleanup handler is a classic footgun — see `idempotency.md`.

# Home Assistant Network Connectivity Fix

This document explains how to fix the `host_internet: false` issue in Home Assistant Supervised running in an LXC container.

## Problem

When running `ha network info` in the Home Assistant container, you may see:

```
docker:
  address: 172.30.32.0/23
  dns: 172.30.32.3
  gateway: 172.30.32.1
  interface: hassio
host_internet: false
interfaces: []
supervisor_internet: true
```

The `host_internet: false` status can cause issues with add-ons and integrations that require internet connectivity.

## Automatic Fix

A dedicated playbook has been created to fix this issue. Run:

```bash
ansible-playbook -i inventory fix-ha-network.yml
```

This playbook will:

1. Ensure the Home Assistant container is running
2. Run the enhanced network fix script
3. Configure DNS properly
4. Force NetworkManager to check connectivity
5. Reload Home Assistant network configuration
6. Verify the fix was successful

## Manual Fix

If you prefer to fix the issue manually, you can SSH into the Home Assistant container and run:

```bash
/usr/local/bin/fix-ha-network.sh
```

This script:
- Checks DNS resolution
- Adds Google DNS (8.8.8.8) as a fallback if needed
- Verifies internet connectivity
- Restarts NetworkManager
- Forces a connectivity check
- Reloads Home Assistant network configuration
- Displays the current network status

## Verifying the Fix

After running either the automatic or manual fix, you should see `host_internet: true` when running:

```bash
ha network info
```

## Troubleshooting

If the issue persists:

1. Check that the container has proper network connectivity:
   ```bash
   ping -c 3 8.8.8.8
   ```

2. Verify DNS resolution is working:
   ```bash
   ping -c 3 google.com
   ```

3. Check NetworkManager status:
   ```bash
   nmcli networking connectivity
   ```

4. Restart the Home Assistant supervisor:
   ```bash
   systemctl restart hassio-supervisor
   ```

5. Wait a few minutes and check again:
   ```bash
   ha network info
   ```

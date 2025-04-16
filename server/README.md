Role Name
=========
Server side role for installations and configurations:
- Find and mount RAID partitions(idempotent)
- Samba installation with cockpit-file-sharing which makes samba configuration management easy
- Rootless docker installation

Requirements
------------
``` shell
ansible-galaxy collection install community.general
```

Role Variables
--------------
See my-variables-sample file:
- raid-partitions for mounting raid operations

Dependencies
------------
- Debian host
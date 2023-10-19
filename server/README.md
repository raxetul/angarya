Role Name
=========
Server side role for installations and configurations:
- Find and mount RAID partitions(idempotent)

Requirements
------------
No requirement is needed.

Role Variables
--------------
See my-variables-sample file:
- raid-partitions for mounting raid operations
- Samba installation with cockpit-file-sharing which makes samba configuration management easy

Dependencies
------------
- Debian host
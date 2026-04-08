# Angarya
Angarya means drudgery, angary.

This is my collection ansible playbooks of my server installations.
It includes several tasks in roles and feel free to what you need.

I'm quite aware of that there are unnecessary ansible abstractions in the base role but, this repo is something like my ansible notes gather from several places.
And also this repo is a button to start doomsday. :supervillain:

# Dependencies
A debian host with SSH key installed to root account.

# Usage
- Create a my-variables.yml file from my-variables-sample.yml file according to your needs.
- Run ansible-playbook:
  ``` bash
  ansible-playbook site.yml --extra-vars "@my-variables.yml"
  ```
- Run specific tasks using tags:
  ``` bash
  # Run only backup
  ansible-playbook site.yml --extra-vars "@my-variables.yml" --tags backup

  # Run multiple tasks
  ansible-playbook site.yml --extra-vars "@my-variables.yml" --tags backup,homeassistant

  # Run everything except specific tasks
  ansible-playbook site.yml --extra-vars "@my-variables.yml" --skip-tags raid,lxc
  ```
- Available tags: `raid`, `samba`, `network`, `lxc`, `docker`, `backup`, `homeassistant`

# Structure

## Roles
Roles are in the run order, see site.yml in the root.

### Base
Base package installations and arrangements mostly needed.
See [Base README file](base/README.md)

### Server
Installation and arrangements for servers


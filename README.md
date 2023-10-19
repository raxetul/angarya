# Angarya
Angarya means drudgery, angary.

This is my collection ansible playbooks of my server installations.
It includes several tasks in roles and feel free to what you need.

I'm quite aware of that there are unnecessary ansible abstractions in the base role but, this repo is something like my ansible notes gather from several places.
And also this repo is a button to start doomsday. :supervillain:

# Dependencies
A debian host with SSH key installed to root account.

# Usage
- Uncomment the part you need in main.yml files
- Create a my-variables.yml file from my-variables-sample.yml file according to your needs.
- Run ansible-playbook:
  ``` bash
  ansible-playbook site.yml --extra-vars "@my-variables.yml" 
  ```

# Structure

## Roles
Roles are in the run order, see site.yml in the root.

### Base
Base package installations and arrangements mostly needed.
See [Base README file](base/README.md)

### Server
Installation and arrangements for servers


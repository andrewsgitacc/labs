# DNS Lab

**Author:** Andrew Kyle — [LinkedIn](https://www.linkedin.com/in/andrew-kyle-1007591/)

Deploys a VM from template and installs BIND.

## Requirements

- VMware Fusion
- VM template: `CentOS9aarch64`
  - User account with sudo access: `admin`
  - Password: `admin` *(lab only — do not use in production)*
- Ansible

## Usage

```bash
git clone git@github.com:andrewsgitacc/labs.git
cd dns
ansible-playbook dns.yml -k -K
```

When prompted, enter the `admin` account password and root password (both `admin`).

# Verification - run on Mac
```bash
dig @172.16.79.10 k8s-api.lab.local +short
```

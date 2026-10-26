# Jenkins Lab

**Author:** Andrew Kyle — [LinkedIn](https://www.linkedin.com/in/andrew-kyle-1007591/)

Deploys a Jenkins CI/CD server on a CentOS Stream 9 VM in VMware Fusion using Ansible. Jenkins runs on `172.16.79.60` (`jenkins.lab.local`) and serves as a central CI server for all labs.

## Requirements

- VMware Fusion with `CentOS9aarch64` template
  - User account with sudo access: `admin`
  - Password: `admin` *(lab only)*
- Ansible on MacBook (`brew install ansible`)
- Ansible collections:
  ```bash
  ansible-galaxy collection install community.general ansible.posix
  ```
- DNS server deployed — see `labs/dns`
- GitHub SSH key at `~/.ssh/id_github` on the Mac (used as the Jenkins `github-ssh` credential)

## DNS

The `jenkins.lab.local` A record is defined in `labs/dns/configure_dns_server.yml`. Re-run that playbook before provisioning Jenkins if your DNS server was rebuilt:

```bash
cd labs/dns
ansible-playbook configure_dns_server.yml -k -K
```

## Deployment

```bash
ansible-playbook configure_jenkins.yml -k -K
```

When prompted, enter `admin` for both the SSH password (`-k`) and sudo password (`-K`).

The playbook will:
1. Clone the `CentOS9aarch64` template and power on the VM
2. Discover the DHCP IP and connect over SSH
3. Set the hostname to `jenkins.lab.local`
4. Install Java 21, Git, Ansible, ansible-lint, and Jenkins LTS
5. Open port 8080 in firewalld
6. **Set up Jenkins unattended** (no setup wizard):
   - Install the plugins in `files/plugins.txt` with the official plugin installation manager
   - Copy your GitHub SSH key (`~/.ssh/id_github` on the Mac) to the VM and trust GitHub's host keys
   - Apply **Configuration as Code** (`templates/jenkins.yaml.j2`): admin user, Jenkins URL, the `github-ssh` credential, and all pipeline jobs
7. Start Jenkins and wait until the admin login works
8. Set the static IP `172.16.79.60` and drop the connection *(expected)*

## Logging In

Open **http://172.16.79.60:8080** and log in as `admin` / `admin` *(lab only)*.

> **Note:** Chrome may fail to reach the Jenkins UI due to VMware NAT subnet routing. Use Safari if Chrome shows `ERR_ADDRESS_UNREACHABLE`.

There is nothing else to set up. The plugins, credential and jobs are already in place.

## What Gets Configured

All settings live in `group_vars/all.yml`:

| Setting | Default | Purpose |
|---|---|---|
| `jenkins_admin_user` / `jenkins_admin_password` | `admin` / `admin` | First admin user |
| `github_ssh_key` | `~/.ssh/id_github` (on the Mac) | Loaded as credential `github-ssh` (username `git`) |
| `jenkins_jobs` | see below | Pipeline jobs, each polling GitHub every 5 minutes |
| `plugin_manager_version` | `2.15.0` | Version of the plugin installation manager |

Jobs created by default:

| Job | Repo | Branch | Script Path |
|---|---|---|---|
| `k8s-cluster` | `git@github.com:andrewsgitacc/labs.git` | `*/main` | `k8s/Jenkinsfile` |
| `puppet-lab` | `git@github.com:andrewsgitacc/labs.git` | `*/main` | `puppet/Jenkinsfile` |
| `puppet-control-repo` | `https://github.com/andrewsgitacc/puppet-control-repo.git` | `*/production` | `Jenkinsfile` |

`puppet-control-repo` needs the Puppet tools on this VM. Run `labs/puppet/04_configure_jenkins_for_puppet.yml` once after building Jenkins.

> **Configuration as Code wins.** Jenkins re-applies `/var/lib/jenkins/casc_configs/jenkins.yaml` on every start. Anything it defines (admin user, credential, jobs) reverts to the playbook's version after a restart if you changed it in the UI. Make permanent changes in `group_vars/all.yml` or the template, then re-run the playbook (this rebuilds the VM).

## Day-2 Operations

```bash
# SSH
ssh -q -l admin "$(dig @172.16.79.10 jenkins.lab.local +short | tail -1)"

# Restart Jenkins
ssh -q -t -l admin "$(dig @172.16.79.10 jenkins.lab.local +short | tail -1)" "sudo systemctl restart jenkins"

# View logs
ssh -q -t -l admin "$(dig @172.16.79.10 jenkins.lab.local +short | tail -1)" "sudo journalctl -u jenkins -f"
```

Ad-hoc Ansible against the static inventory:

```bash
ansible -i jenkins_inventory.ini jenkins -m command -a "systemctl status jenkins" -b -k -K
```

## Adding a New Lab

1. Add a `Jenkinsfile` to the lab (copy from `k8s/Jenkinsfile` and adapt)
2. Add a `.ansible-lint` config if the lab uses Ansible playbooks
3. Add an entry to `jenkins_jobs` in `group_vars/all.yml` and re-run `configure_jenkins.yml`. This rebuilds the Jenkins VM from scratch, which is safe because everything is recreated automatically.

Jenkins on this VM handles all lab pipelines centrally.

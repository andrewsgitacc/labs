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
6. Start and enable the Jenkins service
7. Set the static IP `172.16.79.60` and drop the connection *(expected)*

## Post-Deploy Setup

### 1. Trust GitHub's host key

Run once after provisioning so Jenkins can clone from GitHub:

```bash
ssh -q -t -l admin "$(dig @172.16.79.10 jenkins.lab.local +short | tail -1)" \
  "sudo -u jenkins ssh-keyscan github.com | sudo tee -a /var/lib/jenkins/.ssh/known_hosts"
```

### 2. Unlock Jenkins

```bash
ssh -q -t -l admin "$(dig @172.16.79.10 jenkins.lab.local +short | tail -1)" \
  "sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
```

Open **http://172.16.79.60:8080** in a browser, paste the password, and choose **Install suggested plugins**.

> **Note:** Chrome may fail to reach the Jenkins UI due to VMware NAT subnet routing. Use Safari if Chrome shows `ERR_ADDRESS_UNREACHABLE`.

### 3. Add GitHub SSH key

Jenkins authenticates to GitHub over SSH:

1. **Manage Jenkins → Credentials → (global) → Add Credentials**
2. Kind: `SSH Username with private key`
3. Username: `git`
4. Private Key: paste the contents of `~/.ssh/id_github`

### 4. Create a Pipeline Job

1. **New Item** → name it (e.g., `k8s-cluster`) → **Pipeline** → OK
2. Under **Pipeline**:
   - Definition: `Pipeline script from SCM`
   - SCM: `Git`
   - Repository URL: `git@github.com:andrewsgitacc/labs.git`
   - Credentials: select the `git` credential added above
   - Branch: `*/main`
   - Script Path: `k8s/Jenkinsfile` *(adjust per lab)*
3. Save → **Build Now**

Jenkins polls GitHub every 5 minutes and triggers automatically on new commits.

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

1. Add a `Jenkinsfile` to the lab repo (copy from `k8s/Jenkinsfile` and adapt)
2. Add a `.ansible-lint` config if the lab uses Ansible playbooks
3. Create a new Pipeline job in Jenkins pointing at the new repo path

Jenkins on this VM handles all lab pipelines centrally.

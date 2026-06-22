# Jenkins Setup — VM-Based (Ansible)

Jenkins runs on a dedicated CentOS Stream 9 VM at `172.16.79.60` (`jenkins.lab.local`), provisioned and configured entirely by Ansible from your MacBook.

## Prerequisites

- `CentOS9aarch64` VMware Fusion template exists
- DNS server at `172.16.79.10` has an A record for `jenkins.lab.local → 172.16.79.60` (see note below)
- Ansible installed on your MacBook (`brew install ansible`)
- Community and POSIX collections installed:
  ```bash
  ansible-galaxy collection install community.general ansible.posix
  ```

## Deploy

Run the master playbook from your MacBook. It will clone the VM, wait for it to boot, discover its DHCP IP, configure networking, and install Jenkins in one pass.

```bash
ansible-playbook configure_jenkins.yml -k -K
```

When prompted:
- `-k` → SSH password (`admin`)
- `-K` → sudo password (`admin`)

> **Note:** The playbook applies a static IP (`172.16.79.60`) then drops the connection — this is expected. Jenkins will be reachable at the static IP once it completes.

## Unlock Jenkins

SSH into the VM and grab the initial admin password:

```bash
ssh -q -l admin 172.16.79.60
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Open **http://172.16.79.60:8080** in safari (don't use chrome) and paste the password.

Choose **"Install suggested plugins"** when prompted.

## Create the Pipeline Job

1. **New Item** → name it (e.g., `k8s-cluster`) → select **Pipeline** → OK
2. Under **Pipeline**:
   - Definition: `Pipeline script from SCM`
   - SCM: `Git`
   - Repository URL: `git@github.com:andrewsgitacc/labs.git`
   - Branch: `*/main`
   - Script Path: `k8s/Jenkinsfile` *(adjust to match your repo layout)*
3. Save

## Add Your SSH Key to Jenkins

Jenkins needs to authenticate to GitHub over SSH:

1. **Manage Jenkins → Credentials → (global) → Add Credentials**
2. Kind: `SSH Username with private key`
3. Username: `git`
4. Private Key: paste the contents of `~/.ssh/id_ed25519` (or whichever key GitHub knows)
5. Reference this credential in the pipeline job under **Credentials**

## Trigger a Build

Click **Build Now** on the pipeline job. On subsequent pushes, Jenkins polls GitHub every 5 minutes automatically (configured in the `Jenkinsfile`).

## Day-2 Operations

```bash
# SSH directly
ssh -q -l admin jenkins.lab.local

# Restart Jenkins
ssh -q -l admin jenkins.lab.local "sudo systemctl restart jenkins"

# View logs
ssh -q -l admin jenkins.lab.local "sudo journalctl -u jenkins -f"
```

Or use the static inventory for ad-hoc Ansible commands:

```bash
ansible -i jenkins_inventory.ini jenkins -m command -a "systemctl status jenkins" -b -k -K
```

## Reusing for Other Labs

For each new lab repo:

1. Add a `Jenkinsfile` at the repo root (copy and adapt the one in this repo)
2. Add a `.ansible-lint` config if the lab uses Ansible
3. Create a new Pipeline job in Jenkins pointing at the new repo

Jenkins on the VM handles all lab pipelines centrally — no per-project CI infrastructure needed.

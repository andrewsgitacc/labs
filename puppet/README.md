# Puppet Lab (OpenVox)

**Author:** Andrew Kyle — [LinkedIn](https://www.linkedin.com/in/andrew-kyle-1007591/)

Deploys a Puppet server and two Puppet clients on CentOS Stream 9 VMs in VMware Fusion using Ansible. It uses **[OpenVox](https://voxpupuli.org/openvox/)**, the community-maintained, drop-in fork of open-source Puppet. Perforce no longer publishes free public builds of open-source Puppet.

The Puppet code lives in a separate GitHub repo, **[puppet-control-repo](https://github.com/andrewsgitacc/puppet-control-repo)**. The server pulls it directly with **r10k** every 5 minutes, and each Git branch becomes a Puppet environment.

| VM | FQDN | IP | vCPU / RAM |
|---|---|---|---|
| puppet | `puppet.lab.local` | 172.16.79.70 | 2 / 4096 MB |
| puppet-client-01 | `puppet-client-01.lab.local` | 172.16.79.71 | 2 / 2048 MB |
| puppet-client-02 | `puppet-client-02.lab.local` | 172.16.79.72 | 2 / 2048 MB |

> **Public control repo:** A Puppet control repo would normally be **private**, and the Puppet server would read it with a read-only GitHub **deploy key**. In this lab the repo is **public**, purely for learning, so r10k clones it over HTTPS with no credentials. Don't do this with real infrastructure code: control repos often describe internal hosts, users and settings.

## Requirements

- VMware Fusion with the `CentOS9aarch64` template
  - User account with sudo access: `admin`
  - Password: `admin` *(lab only)*
- Ansible on the Mac (`brew install ansible`)
- Ansible collections:
  ```bash
  ansible-galaxy collection install community.general ansible.posix
  ```
- DNS server deployed (see `labs/dns`)
- Optional: Jenkins deployed (see `labs/jenkins`) for CI on the control repo

## DNS

The `puppet`, `puppet-client-01` and `puppet-client-02` records are in `labs/dns/configure_dns_server.yml`. Re-run that playbook first so the new records are live:

```bash
cd labs/dns
ansible-playbook configure_dns_server.yml -k -K
```

Agents find the server as `puppet.lab.local`. Its certificate also includes `puppet` as an alternative name.

## Deployment

```bash
git clone git@github.com:andrewsgitacc/labs.git
cd labs/puppet
```

Run the playbooks in order. When prompted, enter `admin` for both the SSH password (`-k`) and the sudo password (`-K`).

```bash
# 1. Clone 3 VMs, set hostnames, then switch to static IPs (the connection drop at the end is expected)
ansible-playbook 01_configure_puppet_nodes.yml -k -K

# 2. Install OpenVox Server + r10k, deploy the control repo, start puppetserver
ansible-playbook -i puppet_inventory.ini 02_install_puppet_server.yml -k -K

# 3. Install OpenVox Agent on both clients, run Puppet, enable the agent service
ansible-playbook -i puppet_inventory.ini 03_install_puppet_agents.yml -k -K

# 4. (Optional) Add puppet / puppet-lint / r10k to the Jenkins VM for control-repo CI
ansible-playbook -i puppet_inventory.ini 04_configure_jenkins_for_puppet.yml -k -K
```

What each step does:

1. **01**: Clones the `CentOS9aarch64` template three times, sets vCPU and RAM, and finds each VM's DHCP IP. It then sets the hostname, installs baseline packages and applies the static IP and lab DNS.
2. **02**: Installs the OpenVox 8 repo, `openvox-server` and Java 17, and sets the JVM heap to 2 GB. It configures `puppet.conf` with `dns_alt_names` and enables autosigning for `*.lab.local`. It installs r10k into OpenVox's bundled Ruby and deploys every branch of the control repo. It adds a systemd timer (`r10k-deploy.timer`) that redeploys every 5 minutes, opens port 8140, starts `puppetserver`, and runs the agent once on the server itself.
3. **03**: Installs `openvox-agent` and points it at `puppet.lab.local` with a 10-minute run interval. The first `puppet agent -t` run requests a certificate, which is autosigned, and applies the catalog. It then enables the `puppet` service.
4. **04**: Installs `openvox-agent` (CLI only, service disabled), `puppet-lint` and `r10k` on `jenkins.lab.local`.

## Verification

From the Mac:

```bash
dig @172.16.79.10 puppet.lab.local +short             # 172.16.79.70
dig @172.16.79.10 puppet-client-01.lab.local +short   # 172.16.79.71
```

On the Puppet server:

```bash
ssh -q -t admin@172.16.79.70

sudo /opt/puppetlabs/bin/puppetserver ca list --all    # both clients + server signed
ls /etc/puppetlabs/code/environments                   # production (+ any other branches)
systemctl list-timers r10k-deploy.timer                # next r10k run
```

On a client:

```bash
ssh -q -t admin@172.16.79.71

cat /etc/motd                                  # client-01 shows its Hiera override
cat /etc/puppet-managed
sudo /opt/puppetlabs/bin/puppet agent -t       # should finish with no errors
```

### End-to-end test

1. Change `profile::base::motd_message` in `data/common.yaml` in the control repo and push it.
2. Wait for r10k, or force a deploy now: `ssh -t admin@172.16.79.70 "sudo systemctl start r10k-deploy.service"`
3. Run the agent on client-02: `ssh -t admin@172.16.79.72 "sudo /opt/puppetlabs/bin/puppet agent -t"`
4. `cat /etc/motd` on client-02 shows the new message.

## Jenkins CI for the control repo

After running playbook 04, create a Pipeline job in Jenkins (see `labs/jenkins/README.md`):

- Name: `puppet-control-repo`
- Definition: `Pipeline script from SCM`, SCM: `Git`
- Repository URL: `https://github.com/andrewsgitacc/puppet-control-repo.git` *(public, no credentials needed)*
- Branch: `*/production`
- Script Path: `Jenkinsfile`

The control repo's pipeline checks the Puppetfile, YAML, `puppet parser validate`, `puppet epp validate` and `puppet-lint`.

You can also add a second job for this lab's Ansible playbooks: repo `git@github.com:andrewsgitacc/labs.git`, branch `*/main`, Script Path `puppet/Jenkinsfile`.

## Day-2 Operations

```bash
# SSH
ssh -q -l admin "$(dig @172.16.79.10 puppet.lab.local +short | tail -1)"

# Force an r10k deploy now (instead of waiting for the 5-minute timer)
ssh -q -t admin@172.16.79.70 "sudo systemctl start r10k-deploy.service"

# r10k / puppetserver logs
ssh -q -t admin@172.16.79.70 "sudo journalctl -u r10k-deploy -n 50"
ssh -q -t admin@172.16.79.70 "sudo tail -f /var/log/puppetlabs/puppetserver/puppetserver.log"

# Remove a client's cert (e.g. before rebuilding it)
ssh -q -t admin@172.16.79.70 "sudo /opt/puppetlabs/bin/puppetserver ca clean --certname puppet-client-01.lab.local"
```

Ad-hoc Ansible against the static inventory:

```bash
# Puppet run on all clients
ansible -i puppet_inventory.ini puppet_agents -m command -a "/opt/puppetlabs/bin/puppet agent -t" -b -k -K
```

## Rebuilding

`01_configure_puppet_nodes.yml` deletes and re-clones **all three** VMs, so re-running the playbooks 01 to 03 gives you a fresh server with a new CA and new clients. No certificate cleanup is needed.

If you rebuild only one client by hand, clean its old certificate on the server first (see Day-2 above). Otherwise the server rejects the client's new certificate.

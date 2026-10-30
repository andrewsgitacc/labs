# Admin tools (utility server)

**Author:** Andrew Kyle — [LinkedIn](https://www.linkedin.com/in/andrew-kyle-1007591/)

Installs the platform admin CLI tools on the **utility server**. In this lab the
utility server is the DNS server, `dns.lab.local` (172.16.79.10) — see
[Why the DNS server is also the utility server](#why-the-dns-server-is-also-the-utility-server).

Nothing is installed on the Mac. You SSH to the utility server to manage the cluster.

| Tool | Purpose | Source |
|---|---|---|
| kubectl | Kubernetes CLI (`k` alias) | pkgs.k8s.io, same minor version as the cluster |
| helm | Kubernetes package manager | get.helm.sh (checksum verified) |
| k9s | Terminal UI for the cluster | GitHub release (checksum verified) |
| stern | Tail logs from many pods | GitHub release (checksum verified) |
| yq / jq | YAML / JSON processing | GitHub release / dnf |
| git, gh | Git and GitHub CLI | dnf / cli.github.com repo |
| argocd | Argo CD CLI (same version as the server) | GitHub release (checksum verified) |
| dig, nsupdate | DNS testing (bind-utils) | dnf |

Versions are pinned in [`vars/tool_versions.yml`](vars/tool_versions.yml). Later
phases add tools here (kubeseal, kargo).

## Why the DNS server is also the utility server

In a production environment these would be two separate machines: DNS is critical
infrastructure and is kept minimal, and a dedicated admin box (bastion / jump host)
holds the tools and cluster credentials. For this lab they're combined because:

- **It's always running.** Every lab depends on DNS, so the tools are always available
  without starting another VM.
- **It saves resources.** One less VM frees about 4 GB of RAM on the Mac for the
  cluster workers.
- **It already has what the admin box needs.** It resolves `lab.local` natively (no
  macOS `.local` / Bonjour issues) and already holds the external-dns key.
- **It keeps the Mac clean.** No CLI tools or cluster credentials on the laptop.

The trade-offs, accepted for a lab:

- **Bigger blast radius.** The server holds the cluster's admin kubeconfig (long-lived
  certificates, see `labs/k8s`), so access to the DNS server means admin access to the
  cluster, and the other way round.
- **Shared rebuilds.** Rebuilding the DNS VM also removes the tools. Both are built by
  Ansible, so re-running `labs/dns` and then this playbook restores everything.

The tools are installed by their **own playbook and inventory**, separate from the DNS
build. To move them to a dedicated admin VM later, point `admin_inventory.ini` (and
`[admin_hosts]` in `k8s/k8s_inventory.ini`) at the new VM and re-run.

## Usage

Run from the Mac:

```bash
cd admin
ansible-playbook -i admin_inventory.ini install_admin_tools.yml -k -K
```

If the cluster is already built (`k8s/admin.conf` exists on the Mac), the playbook also
installs it as `~/.kube/config` for `admin`. `k8s/03_init_control_plane.yml` does the
same after every cluster build, so the order doesn't matter.

## Verification

```bash
ssh admin@dns.lab.local
kubectl get nodes -o wide
k get pods -A             # alias + tab completion
helm version
k9s                       # :q to quit
```

# Platform lab

**Author:** Andrew Kyle — [LinkedIn](https://www.linkedin.com/in/andrew-kyle-1007591/)

A GitOps platform on the `k8s` lab cluster, built to look like a real infrastructure
environment: everything in GitHub, CI with GitHub Actions, CD with Argo CD and Kargo.
It's built one phase at a time; each phase below has simple step-by-step build instructions.

## Architecture

- **Cluster:** `labs/k8s` — kubeadm, 3 control planes + 3 workers, Calico, Ceph disks on the workers
- **DNS:** `labs/dns` — BIND; `apps.lab.local` is updated automatically by external-dns
- **CI:** GitHub Actions — PR checks on GitHub-hosted runners, image builds on self-hosted runners in the cluster
- **CD:** Argo CD deploys from Git; Kargo promotes dev → staging → prod
- **Utility server:** `dns.lab.local` doubles as the admin box — kubectl, helm, k9s, argocd and the
  cluster kubeconfig live there (`labs/admin`). Nothing is installed on the Mac; it only runs
  Ansible and the browser

## Repos

| Repo | Purpose |
|---|---|
| `labs` | VM/cluster build (Ansible), DNS, admin tools, platform docs (this file) |
| [`platform-gitops`](https://github.com/andrewsgitacc/platform-gitops) | Every platform component (chart, values, manifests) and the Argo CD setup; detailed runbooks |
| `sample-app` (private) | Demo app source + CI pipeline (build, scan, push to Harbor) |
| `sample-app-deploy` | dev/staging/prod config that Kargo updates |

## IP plan (VMware Fusion NAT 172.16.79.0/24)

| Range | Use |
|---|---|
| .1 | Mac (vmnet8) |
| .2 | NAT gateway |
| .10 | dns.lab.local — DNS + utility server (admin tools) |
| .21–.23 | k8s control planes |
| .31–.33 | k8s workers |
| .50 | client |
| .60 | jenkins |
| .70–.72 | puppet lab |
| **.100–.119** | **MetalLB LoadBalancer IPs** (.100 = lab-gateway, .119 = MetalLB test) |
| .128–.254 | Fusion DHCP — never use for static IPs or MetalLB |

## MacBook requirements

The lab is sized for a **64 GB** Apple Silicon Mac. The VMs' RAM is fixed from Phase 1;
later phases use more of the **workers'** RAM and the cluster's disks, not more Mac RAM,
until the workers fill up (see the note under the table).

**VM sizes (from Phase 1)**

| VM | Count | vCPU / RAM each | System disk | Extra disk | RAM total |
|---|---|---|---|---|---|
| dns (DNS + utility server) | 1 | 2 / 2 GB | ~13 GB | — | 2 GB |
| k8s control planes | 3 | 2 / 4 GB | 20 GB | — | 12 GB |
| k8s workers | 3 | 4 / 10 GB | 40 GB | 100 GB (Ceph) | 30 GB |
| **Total** | | **20 vCPU** | | | **44 GB** |

Leave **~15 GB** for macOS and your apps, and **power off the Jenkins and Puppet VMs**
(another ~12 GB) while the platform is running. All disks are **thin provisioned**: they only
use Mac disk space as they fill, up to the sizes above (~500 GB maximum in total).

**Per phase** (approximate; "worker RAM used" is what the platform consumes inside the
30 GB of worker RAM, "Mac disk used" is real space used on the Mac by all lab VM disks)

| # | Phase | Adds | Worker RAM used (cumulative) | Mac disk used (cumulative) | Free Mac disk to have |
|---|---|---|---|---|---|
| 1 | Prep | Kubernetes, Calico | ~3 GB | ~35 GB | 100 GB |
| 2 | Cluster foundation | MetalLB, cert-manager, Envoy Gateway, external-dns, hello | ~4 GB | ~45 GB | 100 GB |
| 3 | Argo CD | Argo CD (server, repo server, controller, ApplicationSets, Redis) | ~6 GB | ~55 GB | 100 GB |
| 4 | Sealed Secrets | controller | ~6 GB | ~55 GB | 100 GB |
| 5 | Rook-Ceph | 3 monitors, managers, 3 OSDs, S3 gateway, file service | ~15 GB | ~70 GB | 150 GB |
| 6 | Observability | Prometheus, Grafana, Alertmanager, Loki, Alloy | ~20 GB | ~100 GB (metrics/logs in Ceph) | 200 GB |
| 7 | Keycloak | Keycloak + database | ~22 GB | ~105 GB | 200 GB |
| 8 | Harbor | registry, database, Redis, Trivy scanner | ~25 GB | ~140 GB (images in Ceph) | 250 GB |
| 9 | CI | runner controller; build runners on demand (~2 GB each while building) | ~26–28 GB | ~160 GB | 250 GB |
| 10 | Kargo | controller, API | ~27–29 GB | ~160 GB | 250 GB |
| 11 | Hardening | Kyverno, Velero | ~28–30 GB | ~180 GB (backups) | 300 GB |

> **Watch the workers from Phase 5.** Ceph and observability take most of the 30 GB of worker
> RAM. If pods go `Pending` with "Insufficient memory" or are `OOMKilled`, raise the workers to
> 12 GB (`ram` in `k8s/provision_k8s_nodes.yml`, or the VM settings in Fusion, one node at a
> time): +6 GB on the Mac, 50 GB of VMs in total. Disk space inside the VMs is checked with
> `df -h /` on each node; Kubernetes evicts pods at ~85% full (see `k8s/README.md` → DiskPressure).

## Build order

| # | Phase | Status |
|---|---|---|
| 1 | Prep: Mac DNS resolver, `apps.lab.local` zone, admin tools on the utility server, cluster rebuild (v1.36, Calico, bigger workers, Ceph disks), new repos | ✅ done |
| 2 | Cluster foundation: MetalLB, Envoy Gateway, cert-manager, external-dns | ✅ done |
| 3 | Argo CD (self-managed; GitOps from here) | ✅ done |
| 4 | Sealed Secrets | 🚧 in progress |
| 5 | Rook-Ceph (block, file, S3 object) | |
| 6 | Observability: Prometheus, Grafana, Alertmanager, Loki, Alloy | |
| 7 | Keycloak SSO | |
| 8 | Harbor | |
| 9 | CI: ARC runners, sample-app pipeline, Renovate | |
| 10 | Kargo | |
| 11 | Hardening and day-2: Kyverno, Velero, alerts, k8s 1.36 → 1.37 upgrade, break/fix | |

## How to build each phase

Conventions:

- **Mac** steps run on the MacBook in `~/GitHub/labs` (Ansible, browser, `curl -k`).
- **Utility server** steps run after `ssh admin@172.16.79.10`, mostly in `~/platform-gitops`.
- Ansible prompts: SSH password and become password are both `admin` (*lab only*).
- The lab CA isn't trusted on the Mac (by choice): use `curl -k` there and click through
  browser certificate warnings.
- Each phase's detailed runbook (expected output, troubleshooting) is linked at the end of it.

### Phase 1 — Prep

1. **Mac:** stop the Jenkins and Puppet VMs to free RAM. Leave `dns` running.
2. **Mac:** point `*.lab.local` at the lab DNS: `./platform/workstation/setup_workstation.sh`
3. **Mac:** add the dynamic DNS zone for external-dns:
   ```bash
   cd dns && ansible-playbook -i dns_inventory.ini add_apps_zone.yml -k -K && cd ..
   ```
4. **Mac:** install the admin tools on the utility server:
   ```bash
   cd admin && ansible-playbook -i admin_inventory.ini install_admin_tools.yml -k -K && cd ..
   ```
5. **Mac:** build the cluster (destroys and recreates the six k8s VMs):
   ```bash
   cd k8s
   ansible-playbook 01_configure_k8s_cluster.yml -k -K
   ansible-playbook -i k8s_inventory.ini 02_install_k8s_software.yml -k -K
   ansible-playbook -i k8s_inventory.ini 03_init_control_plane.yml -k -K
   ansible-playbook -i k8s_inventory.ini 04_join_nodes.yml -k -K
   ansible-playbook -i k8s_inventory.ini 05_install_calico.yml -k -K
   ansible-playbook -i k8s_inventory.ini 06_configure_firewall_for_cni.yml -k -K
   cd ..
   ```
6. **Utility server:** check: `kubectl get nodes` (6 Ready, v1.36), `kubectl get tigerastatus` (True), `df -h /` on the workers (~38 GB).
7. Create the repos `platform-gitops` (public), `sample-app` (private), `sample-app-deploy` (public) on GitHub, and clone them into `~/GitHub` on the Mac.

Done when: nodes Ready, Calico Available, NetworkPolicy and Ceph-disk tests in
[`k8s/README.md`](../k8s/README.md) pass, the repos exist.

### Phase 2 — Cluster foundation

1. **Utility server:** get the repo:
   ```bash
   git clone https://github.com/andrewsgitacc/platform-gitops.git ~/platform-gitops   # first time
   cd ~/platform-gitops && git pull
   ```
2. **Utility server:** MetalLB: `./scripts/install.sh metallb`, then create the `lb-test`
   service on 172.16.79.119 (commands in the detailed runbook) and check
   `curl -s http://172.16.79.119` works **from the Mac**. Stop if it doesn't. Delete `lb-test`.
3. **Utility server:** cert-manager and the lab CA:
   ```bash
   ./scripts/install.sh cert-manager
   ./scripts/export-lab-ca.sh
   ```
4. **Utility server:** the gateway: `./scripts/install.sh envoy-gateway`, then
   `kubectl -n envoy-gateway-system get gateway lab-gateway` shows 172.16.79.100, Programmed True.
5. **Utility server:** external-dns:
   ```bash
   ./scripts/create-external-dns-secret.sh
   ./scripts/install.sh external-dns
   ```
6. **Utility server:** test app: `kubectl apply -f apps/hello/hello.yaml`, wait a minute, then
   `dig +short hello.apps.lab.local` (172.16.79.100) and `curl https://hello.apps.lab.local`.
7. **Mac:** `curl -k https://hello.apps.lab.local`

Done when: the Mac reaches the hello app through the gateway, and the DNS record appears and
disappears with its route.
Detailed runbook: [platform-gitops README → Phase 2](https://github.com/andrewsgitacc/platform-gitops#phase-2-runbook-history).

Design choices: **Envoy Gateway** (Kubernetes Gateway API, the successor to Ingress); **one
shared gateway** with a wildcard certificate, so apps only add an HTTPRoute; **the CA private key
stays in the cluster**; Helm from the utility server for now, adopted by Argo CD in Phase 3.

### Phase 3 — Argo CD (GitOps)

From this phase, **Git drives the cluster**: a merged pull request to `platform-gitops` `main`
is a deployment, and manual changes in the cluster are reverted.

1. **Mac:** add the `argocd` CLI to the utility server (re-run the admin tools playbook):
   ```bash
   git pull && cd admin && ansible-playbook -i admin_inventory.ini install_admin_tools.yml -k -K && cd ..
   ```
2. **Utility server:** install Argo CD and get the first password:
   ```bash
   cd ~/platform-gitops && git pull
   ./scripts/install.sh argocd
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
   ```
3. **Utility server:** log in, set your own password, remove the initial one:
   ```bash
   argocd login argocd.apps.lab.local --grpc-web --username admin
   argocd account update-password
   kubectl -n argocd delete secret argocd-initial-admin-secret
   ```
4. **Utility server:** hand the platform to Argo CD and wait for everything to be Synced + Healthy:
   ```bash
   kubectl apply -f bootstrap/root.yaml
   watch kubectl -n argocd get applications
   ```
5. **Utility server:** remove the old Helm records (**never** `helm uninstall`):
   ```bash
   for r in metallb-system/metallb cert-manager/cert-manager envoy-gateway-system/eg external-dns/external-dns argocd/argocd; do
     kubectl -n "${r%/*}" delete secret -l owner=helm,name="${r#*/}"
   done
   ```
6. **Test:** `kubectl -n hello scale deployment podinfo --replicas=1` is reverted to 2; a merged
   PR changing hello to 3 replicas shows up within ~3 minutes.
7. **Mac:** UI at https://argocd.apps.lab.local (click through the certificate warning).

Done when: all Applications (root, metallb, cert-manager, envoy-gateway, external-dns, argocd,
app-hello) are Synced + Healthy, `helm list -A` is empty, self-heal and a Git change both work.
Detailed runbook: [platform-gitops README → Phase 3](https://github.com/andrewsgitacc/platform-gitops#phase-3-runbook-argo-cd).

Design choices: **ApplicationSets** (a folder per component or app, no hand-kept list);
**adopt, don't reinstall** the Phase 2 components; **automated sync with prune and self-heal**;
**polling, not webhooks** (GitHub can't reach the lab).

### Phase 4 — Sealed Secrets

Secrets go into Git **encrypted**: only the cluster's Sealed Secrets controller can decrypt them.

1. **Mac:** add `kubeseal` to the utility server (re-run the admin tools playbook):
   ```bash
   git pull && cd admin && ansible-playbook -i admin_inventory.ini install_admin_tools.yml -k -K && cd ..
   ```
2. **GitHub:** merge the Phase 4 pull request in `platform-gitops`. Argo CD installs the
   controller within ~3 minutes (`sealed-secrets` Application Synced + Healthy).
3. **Utility server:** back up the sealing key, then **Mac:** copy it somewhere safe, outside Git:
   ```bash
   cd ~/platform-gitops && git pull && ./scripts/backup-sealing-key.sh
   ```
   ```bash
   mkdir -p ~/lab-secrets && chmod 700 ~/lab-secrets && scp admin@172.16.79.10:sealed-secrets-key.yaml ~/lab-secrets/
   ```
4. **Utility server:** seal the external-dns key: `./scripts/seal-external-dns-secret.sh`
5. **Mac:** copy `tsig-sealedsecret.yaml` into `platform-gitops`, commit, PR, merge
   (exact commands in the detailed runbook).
6. **Test:** delete the Secret `external-dns/external-dns-rfc2136`; the controller recreates it
   from Git and `hello.apps.lab.local` keeps resolving.

Done when: the controller is running, the key is backed up on the Mac, the TSIG key is in Git
as a SealedSecret, and a deleted Secret comes back by itself.
Detailed runbook: [platform-gitops README → Phase 4](https://github.com/andrewsgitacc/platform-gitops#phase-4-runbook-sealed-secrets).

Design choices: **Sealed Secrets** rather than an external vault for now: no extra service to
run, and the encrypted secrets live in Git with everything else. **One sealing key, rotation off**
(lab only), backed up outside Git — losing it means re-sealing every secret.

### Rebuilding the platform from scratch

On a freshly built cluster (Phase 1 step 5), the whole platform comes back with:

1. **Mac:** copy the sealing key backup to the utility server:
   `scp ~/lab-secrets/sealed-secrets-key.yaml admin@172.16.79.10:`
2. **Utility server:** `cd ~/platform-gitops && git pull`
3. **Utility server:** `./scripts/install.sh` — installs every component in order, restores the
   sealing key before the Sealed Secrets controller starts, then Argo CD
4. **Utility server:** `./scripts/export-lab-ca.sh`
5. **Utility server:** Phase 3 steps 2–5 (password, `bootstrap/root.yaml`, Helm records — add
   `kube-system/sealed-secrets-controller` to the Helm records list)

## Notes

- `.local` is reserved for mDNS (Bonjour). The resolver file makes it work on macOS,
  but if lookups are slow or flaky, the long-term fix is a domain like `lab.internal`
  (`.internal` is reserved for private networks).
- The Calico CNI is bootstrap, owned by Ansible. Everything from Phase 2 onwards is
  installed with Helm and, from Phase 3, managed by Argo CD.
- Troubleshooting: node and disk problems in [`k8s/README.md`](../k8s/README.md#troubleshooting);
  platform components in the [platform-gitops README](https://github.com/andrewsgitacc/platform-gitops#troubleshooting).

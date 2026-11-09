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
| k8s control planes | 3 | 2 / 6 GB | 20 GB | — | 18 GB |
| k8s workers | 3 | 4 / 10 GB | 40 GB | 100 GB (Ceph) | 30 GB |
| **Total** | | **20 vCPU** | | | **50 GB** |

Leave **~14 GB** for macOS and your apps, and **power off the Jenkins and Puppet VMs**
(another ~12 GB) while the platform is running. All disks are **thin provisioned**: they only
use Mac disk space as they fill, up to the sizes above (~500 GB maximum in total).

**Per phase** ("worker RAM used" is what the platform consumes inside the 30 GB of worker
RAM, "Mac disk used" is real space used on the Mac by all lab VM disks). Phases marked
*measured* are real figures from `kubectl top nodes`; the rest are estimates.

| # | Phase | Adds | Worker RAM used (cumulative) | Mac disk used (cumulative) | Free Mac disk to have |
|---|---|---|---|---|---|
| 1 | Prep | Kubernetes, Calico | ~3 GB | ~35 GB | 100 GB |
| 2 | Cluster foundation | MetalLB, cert-manager, Envoy Gateway, external-dns, hello | ~4 GB | ~45 GB | 100 GB |
| 3 | Argo CD | Argo CD (server, repo server, controller, ApplicationSets, Redis) | ~6 GB | ~55 GB | 100 GB |
| 4 | Sealed Secrets | controller | ~6 GB | ~55 GB | 100 GB |
| 5 | Rook-Ceph | 3 monitors, manager, 3 OSDs, S3 gateway, file service, metrics-server | **~9 GB** *measured* (~3 GB per worker, 30%) | ~70 GB | 150 GB |
| 6 | Observability | Prometheus, Grafana, Alertmanager, Loki, Alloy | **~17 GB** *measured* (~5.6 GB per worker, 59%) | ~100 GB (metrics/logs in Ceph) | 200 GB |
| 7 | Keycloak | Keycloak, its PostgreSQL (CloudNativePG), trust-manager | **~16 GB** *measured* (~5.4 GB per worker, 57%; Keycloak + DB ~0.7 GB) | ~105 GB | 200 GB |
| 8 | Harbor | core, registry, jobservice, portal, Trivy, Valkey, its PostgreSQL | **~18 GB** *measured* (5.6–6.5 GB per worker, 60–69%; Harbor ~0.3 GB at rest) | ~140 GB (images in Ceph) | 250 GB |
| 9 | CI | ARC controller + listener, Renovate (hourly job); runner pods on demand (~0.5–2.5 GB each while building, max 2) | **~18.4 GB** *measured* idle (59–70% per worker); +up to ~2.5 GB per running build | ~160 GB | 250 GB |
| 10 | Kargo | API, controller, management controller, 2 webhook servers (~130 MB in total); sample-app ×4 pods (dev, staging, prod ×2). 10b adds nothing in the cluster, but the Puppet VMs need **+8 GB** on the Mac while they run | **~16.6 GiB** *measured* idle (48–70% per worker) | ~160 GB | 250 GB |
| 11 | Hardening | Kyverno, Velero | ~22–25 GB | ~180 GB (backups) | 300 GB |

> **Watch the workers' memory** with `kubectl top nodes` after each phase. After Phase 5 the
> workers sat at ~30% (Ceph's sizes are cut down for the lab); after Phase 6 they're at ~59%
> (Prometheus alone is ~1.4 GB), and after Phase 7 still ~57% (Keycloak and its database
> add ~0.7 GB). The later phases will bring them towards the 30 GB, so check after Phase 8
> (Harbor) and add worker RAM before Phase 9 if they pass ~75%. After Phase 8 the busiest
> worker is at 69%, so 10 GB is still enough for Phase 9; re-check after it. **Watch the control planes too**: the API
> servers grow with every CRD the platform adds, and in Phase 7 the 4 GB control planes ran
> out of memory (API timeouts, a node NotReady); they have 6 GB since then.
> If pods go `Pending` with "Insufficient memory" or are `OOMKilled`, raise the workers with
> `k8s/12_resize_vm_memory.yml` (one node at a time; also set `ram` in
> `k8s/provision_k8s_nodes.yml` for rebuilds). 12 GB workers would make 56 GB of VMs, leaving
> only ~8 GB for macOS, so 11 GB (53 GB in total) is the safer step on a 64 GB Mac. Disk space inside the VMs is checked with
> `df -h /` on each node; Kubernetes evicts pods at ~85% full (see `k8s/README.md` → DiskPressure).

## Build order

| # | Phase | Status |
|---|---|---|
| 1 | Prep: Mac DNS resolver, `apps.lab.local` zone, admin tools on the utility server, cluster rebuild (v1.36, Calico, bigger workers, Ceph disks), new repos | ✅ done |
| 2 | Cluster foundation: MetalLB, Envoy Gateway, cert-manager, external-dns | ✅ done |
| 3 | Argo CD (self-managed; GitOps from here) | ✅ done |
| 4 | Sealed Secrets | ✅ done |
| 5 | Rook-Ceph (block, file, S3 object) | ✅ done |
| 6 | Observability: Prometheus, Grafana, Alertmanager, Loki, Alloy | ✅ done |
| 7 | Keycloak SSO: trust-manager (lab CA for pods), CloudNativePG, Keycloak; SSO for Argo CD and Grafana | ✅ done |
| 8 | Harbor (v2.16.0-rc1, the first arm64 release): registry + Trivy, Keycloak login, Ceph S3 storage | ✅ done |
| 9 | CI: ARC runners with rootless BuildKit, sample-app pipeline to Harbor, Renovate | ✅ done |
| 10 | Kargo: sample-app dev → staging → prod (10a ✅ done), Puppet code environments (10b ⏭️ next) | 🚧 in progress |
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
5. **Mac:** copy the sealed file into `platform-gitops`, commit, PR, merge:
   `scp admin@172.16.79.10:tsig-sealedsecret.yaml components/external-dns/manifests/`
   (full commands in the detailed runbook).
6. **Test:** delete the Secret `external-dns/external-dns-rfc2136`; the controller recreates it
   from Git and `hello.apps.lab.local` keeps resolving.

Done when: the controller is running, the key is backed up on the Mac, the TSIG key is in Git
as a SealedSecret, and a deleted Secret comes back by itself.
Detailed runbook: [platform-gitops README → Phase 4](https://github.com/andrewsgitacc/platform-gitops#phase-4-runbook-sealed-secrets).

Design choices: **Sealed Secrets** rather than an external vault for now: no extra service to
run, and the encrypted secrets live in Git with everything else. **One sealing key, rotation off**
(lab only), backed up outside Git — losing it means re-sealing every secret.

### Phase 5 — Rook-Ceph storage

Ceph turns the empty 100 GB disk on each worker into replicated storage: **block**
(`ceph-block`, the default StorageClass), **shared filesystem** (`ceph-filesystem`) and
**S3 object storage** (`ceph-bucket`, https://s3.apps.lab.local). Also adds metrics-server
(`kubectl top`).

1. **Mac:** prepare the workers (kernel modules, disk check) and sync all clocks with the
   lab NTP server (Ceph monitors need clocks within 50 ms):
   ```bash
   cd dns && ansible-playbook -i dns_inventory.ini add_ntp_server.yml -k -K && cd ..
   cd k8s && ansible-playbook -i k8s_inventory.ini 08_prepare_ceph_nodes.yml -k -K
   ansible-playbook -i k8s_inventory.ini 09_configure_time_sync.yml -k -K && cd ..
   ```
2. **GitHub:** merge the Phase 5 pull request in `platform-gitops`. Argo CD installs
   metrics-server, the Rook operator, the Ceph CSI drivers and the Ceph cluster (5–10 minutes).
3. **Utility server:** wait for the 3 OSD pods, then check Ceph:
   ```bash
   watch kubectl -n rook-ceph get pods
   kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status     # HEALTH_OK, 3 osds up
   kubectl get storageclass                                            # ceph-block (default)
   kubectl top nodes
   ```
4. **Utility server:** test a volume and an S3 bucket (commands in the detailed runbook).
5. **Utility server:** set the dashboard's `admin` password to `admin` (**lab only**; Rook
   re-applies the Secret, so change both):
   ```bash
   P=admin
   kubectl -n rook-ceph patch secret rook-ceph-dashboard-password -p "{\"stringData\":{\"password\":\"$P\"}}"
   printf '%s' "$P" | kubectl -n rook-ceph exec -i deploy/rook-ceph-tools -- \
     sh -c 'cat > /tmp/p && ceph dashboard ac-user-set-password admin -i /tmp/p --force-password; rm -f /tmp/p'
   unset P
   ```
6. **Mac:** dashboard at https://ceph.apps.lab.local, log in as `admin` / `admin`.

Done when: HEALTH_OK with 3 OSDs, a PVC's data survives its pod, an S3 bucket works, the
dashboard opens, and the workers still have memory headroom.

Lessons from the build: since Rook v1.21 the CSI drivers that create and mount volumes come
from a **separate chart** (`ceph-csi-drivers`), without which every PVC stays `Pending`; Ceph
monitors need the nodes' clocks within 50 ms (lab NTP server); Ceph v20 warns about the CSI
keys' older cipher, which can't change until the nodes run kernel 7.0+ (warnings muted).
Detailed runbook: [platform-gitops README → Phase 5](https://github.com/andrewsgitacc/platform-gitops#phase-5-runbook-rook-ceph-storage).

Design choices: **Rook** (Ceph run by a Kubernetes operator, managed through Git like
everything else); **3-way replication across the workers**, so losing one worker loses no
data; **sizes cut down for the lab** (1 manager, 1 metadata server, OSD memory capped at
~1.5 GB); Ceph's own **S3 gateway** instead of MinIO for object storage.

### Phase 6 — Observability

Metrics, alerts, logs and dashboards for the whole platform: **Prometheus** and
**Alertmanager**, **Grafana** (https://grafana.apps.lab.local), **Loki** for logs (stored in
a Ceph S3 bucket) and **Alloy** collecting every pod's logs on every node. Ceph, Argo CD and
cert-manager expose their metrics too.

1. **GitHub:** merge the Phase 6 pull request in `platform-gitops`. Argo CD installs
   everything (5–10 minutes):
   ```bash
   watch kubectl -n argocd get applications          # kube-prometheus-stack, loki, alloy: Synced + Healthy
   kubectl -n monitoring get pods,pvc
   ```
2. **Mac:** https://prometheus.apps.lab.local → Status → Targets: everything **UP**.
3. **Mac:** https://alertmanager.apps.lab.local: only **Watchdog** firing.
4. **Mac:** https://grafana.apps.lab.local, **admin / admin** (lab only). Check the
   Kubernetes dashboards and the **Platform** folder (Ceph, Argo CD).
5. **Mac (Grafana):** Explore → Loki → `{namespace="argocd"}` shows Argo CD's logs. (The
   hello app only logs when it starts or stops, so it's often empty for the last hour.)
6. **Utility server:** the same checks from the command line, through the API server (the
   Prometheus and Loki images have no `wget`/`curl` to `kubectl exec` with):
   ```bash
   P=/api/v1/namespaces/monitoring/services
   kubectl get --raw "$P/kube-prometheus-stack-prometheus:9090/proxy/api/v1/targets?state=active" \
     | jq -r '.data.activeTargets[] | select(.health!="up") | .labels.job'      # blank = all up
   kubectl get --raw "$P/kube-prometheus-stack-prometheus:9090/proxy/api/v1/alerts" \
     | jq -r '.data.alerts[] | select(.state=="firing") | .labels.alertname'   # Watchdog
   kubectl get --raw "$P/loki:3100/proxy/loki/api/v1/labels" | jq -r '.data[]'  # namespace, pod...
   kubectl top nodes                                                           # workers ~60%
   ```

Done when: all targets up, only Watchdog firing, dashboards show data, logs searchable.

Lessons from the build: the old grafana.com Ceph dashboards use pre-v20 metric names (mostly
"N/A"), so the lab loads **Ceph's own dashboards** for the Ceph version it runs; a password
changed at Grafana's first-login prompt is kept on its volume and **overrides the chart's**
`adminPassword` (click **Skip**; reset with `grafana cli` if needed), and Grafana's login
lockout is turned off (lab only); the Prometheus/Loki images have no shell tools, so
command-line checks go through `kubectl get --raw .../proxy/`; Phase 6 roughly doubled worker
memory use (~9 GB → ~17 GB).
Detailed runbook: [platform-gitops README → Phase 6](https://github.com/andrewsgitacc/platform-gitops#phase-6-runbook-observability).

Design choices: **kube-prometheus-stack** (the standard bundle: operator, Prometheus,
Alertmanager, Grafana, exporters, Kubernetes dashboards and alerts); **Loki + Alloy** for
logs, queried in the same Grafana; Loki in **monolithic mode** with its data in **Ceph S3**;
metrics and logs kept **7 days**; the kubeadm control-plane components (etcd, scheduler,
controller-manager, kube-proxy) aren't scraped yet because they only listen on 127.0.0.1.

### Phase 7 — Keycloak single sign-on

**Keycloak** (https://keycloak.apps.lab.local) becomes the login for **Argo CD** and
**Grafana**: log in once as `admin`, and membership of the Keycloak group
`platform-admins` makes you admin in both. Keycloak's database is **PostgreSQL** run by the
**CloudNativePG** operator, and **trust-manager** shares the lab CA with pods so Argo CD and
Grafana can talk to Keycloak over HTTPS. The Keycloak setup (realm, clients, group, user)
is code in Git, applied by **keycloak-config-cli** after every change.

1. **Mac:** push the `phase-7-keycloak` branch in `platform-gitops` and open the pull
   request, but **don't merge yet**.
2. **Utility server:** create and seal the secrets (asks for a password for the Keycloak
   user `admin`):
   ```bash
   cd ~/platform-gitops && git fetch && git checkout phase-7-keycloak
   ./scripts/seal-keycloak-secrets.sh
   git checkout main
   ```
3. **Mac:** copy the three sealed files into the branch, commit, push:
   ```bash
   cd ~/GitHub/platform-gitops && git checkout phase-7-keycloak
   scp admin@172.16.79.10:keycloak-sealed/realm-secrets-sealedsecret.yaml components/keycloak/manifests/
   scp admin@172.16.79.10:keycloak-sealed/argocd-oidc-sealedsecret.yaml components/argocd/manifests/
   scp admin@172.16.79.10:keycloak-sealed/grafana-oidc-sealedsecret.yaml components/kube-prometheus-stack/manifests/
   git add components/*/manifests/*-sealedsecret.yaml
   git commit -m "Phase 7: sealed Keycloak SSO secrets" && git push
   ```
4. **GitHub:** CI green, merge. Argo CD installs everything (5–10 minutes):
   ```bash
   watch kubectl -n argocd get applications          # trust-manager, cloudnative-pg, keycloak: Synced + Healthy
   kubectl -n keycloak get cluster,pods              # keycloak-db healthy, keycloak-0 1/1
   ```
5. **Utility server:** restart the two apps that call Keycloak, so they load the lab CA:
   ```bash
   kubectl -n argocd rollout restart deployment argocd-server
   kubectl -n monitoring rollout restart deployment kube-prometheus-stack-grafana
   ```
6. **Mac:** https://keycloak.apps.lab.local/admin, **admin / admin** (lab only): realm
   **platform** has the clients `argocd` and `grafana`, group `platform-admins`, user `admin`.
7. **Mac:** https://argocd.apps.lab.local → **LOG IN VIA KEYCLOAK** → `admin`: full access.
8. **Mac:** https://grafana.apps.lab.local → **Sign in with Keycloak** → `admin`: Admin role.
9. **Utility server:** `kubectl top nodes` — workers still have headroom.

Done when: both UIs log in through Keycloak with admin rights, and the workers have headroom.
Detailed runbook: [platform-gitops README → Phase 7](https://github.com/andrewsgitacc/platform-gitops#phase-7-runbook-keycloak-single-sign-on).

Lessons from the build: the **control planes ran out of memory** when CloudNativePG's large
CRDs arrived (`kubectl` "TLS handshake timeout", a node NotReady): the API servers hold every
CRD in memory, so the control planes now have **6 GB** (`k8s/12_resize_vm_memory.yml`);
during that outage Argo CD's first attempt to create the Keycloak database failed and its
sync then **waited forever** for Keycloak, which was waiting for the database (fixed by
applying `database.yaml` by hand; see platform-gitops Troubleshooting); Argo CD and Grafana
read the lab CA **once at start-up**, so they need a restart after `lab-ca-bundle` first
appears; keycloak-config-cli built for Keycloak 26.5 works fine with 26.8.

Design choices: **Keycloak** (the standard open-source identity provider; Harbor and Kargo
will use it too) from codecentric's **keycloakx** chart with the official image (Bitnami's
free images were withdrawn in 2025); **CloudNativePG** for PostgreSQL, reused by Harbor in
Phase 8; realm **as code with keycloak-config-cli** rather than a one-time import, so Git
stays the source of truth; Argo CD talks **OIDC to Keycloak directly** (no Dex); the
built-in `admin` logins stay as a way in when Keycloak is down; the lab CA is **shared by
trust-manager** because it's regenerated on every rebuild and can't be stored in Git.

### Phase 8 — Harbor

**Harbor** (https://harbor.apps.lab.local) is the platform's container registry: images
pushed there are scanned for vulnerabilities by **Trivy**, and the cluster pulls from it.
Login is through Keycloak. Its database is PostgreSQL from CloudNativePG and the image
layers are stored in a **Ceph S3 bucket**.

> Harbor only has **arm64** images from **v2.16.0**, and so far only its release candidate
> (v2.16.0-rc1) exists, so that's what the lab runs, with the 1.19.4 chart. Move to v2.16.0
> when it's released.

1. **Mac:** add podman, skopeo and htpasswd to the utility server:
   ```bash
   cd admin && ansible-playbook -i admin_inventory.ini install_admin_tools.yml -k -K && cd ..
   ```
2. **Mac:** push the `phase-8-harbor` branch in `platform-gitops` and open the pull
   request, but **don't merge yet**.
3. **Utility server:** create and seal Harbor's secrets (asks for a password for Harbor's
   local `admin`):
   ```bash
   cd ~/platform-gitops && git fetch && git checkout phase-8-harbor && git pull
   ./scripts/seal-harbor-secrets.sh
   git checkout main
   ```
4. **Mac:** copy the three sealed files into the branch, commit, push:
   ```bash
   cd ~/GitHub/platform-gitops && git checkout phase-8-harbor
   scp admin@172.16.79.10:harbor-sealed/harbor-secrets-sealedsecret.yaml components/harbor/manifests/
   scp admin@172.16.79.10:harbor-sealed/harbor-token-sealedsecret.yaml components/harbor/manifests/
   scp admin@172.16.79.10:harbor-sealed/harbor-client-sealedsecret.yaml components/keycloak/manifests/
   git add components/*/manifests/*-sealedsecret.yaml
   git commit -m "Phase 8: sealed Harbor secrets" && git push
   ```
5. **GitHub:** CI green, merge. Argo CD installs Harbor (5–10 minutes):
   ```bash
   watch kubectl -n argocd get applications          # harbor: Synced + Healthy
   curl -s https://harbor.apps.lab.local/api/v2.0/ping; echo   # Pong
   ```
6. **Mac:** the nodes trust the lab CA, so they can pull from Harbor:
   ```bash
   cd k8s && ansible-playbook -i k8s_inventory.ini 13_trust_lab_ca.yml -k -K && cd ..
   ```
7. **Mac:** https://harbor.apps.lab.local → **LOGIN VIA OIDC PROVIDER** → Keycloak `admin`:
   you're in as Harbor admin `admin@lab.local`. Copy your **CLI secret** (User Profile).
8. **Utility server:** push an image, then pull it into the cluster:
   ```bash
   podman login harbor.apps.lab.local -u admin@lab.local      # password: the CLI secret
   podman pull docker.io/library/busybox:1.37
   podman tag docker.io/library/busybox:1.37 harbor.apps.lab.local/library/busybox:1.37
   podman push harbor.apps.lab.local/library/busybox:1.37
   kubectl run harbor-pull-test --image=harbor.apps.lab.local/library/busybox:1.37 \
     --restart=Never --rm -i -- sh -c 'echo pulled from Harbor'
   ```
9. **Mac (Harbor):** Projects → library → busybox → **SCAN**: Trivy lists vulnerabilities.
10. **Utility server:** `kubectl top nodes` — workers still have headroom.

Done when: Keycloak login works, an image is pushed, scanned and pulled by a pod.

Lessons from the build: Harbor publishes **arm64 images only from v2.16** (so the lab runs
its release candidate); OpenSSL 3 writes keys in a format (PKCS#8) Harbor's token service
can't read, so `podman login` failed with a 500 until the seal script made a PKCS#1 key;
**merge only when the pull request shows the sealed-secrets commit** (one was pushed after
the merge, and Harbor started without its secrets); copy the sealed files with **one** `scp`
(pasted lines after the first are taken as passwords); with Keycloak login, `podman login`
uses the **CLI secret** from Harbor's User Profile; the login button is "LOGIN WITH Keycloak".
Detailed runbook: [platform-gitops README → Phase 8](https://github.com/andrewsgitacc/platform-gitops#phase-8-runbook-harbor).

Design choices: **Harbor** (the CNCF-graduated standard for self-hosted registries, with
scanning, projects, robot accounts and replication) over the lighter Zot, accepting a
release candidate for arm64; **PostgreSQL from CloudNativePG** like Keycloak instead of the
chart's own database; image layers in **Ceph S3** rather than a volume, so the registry pod
holds no data; **all of Harbor's secrets sealed in Git**, because the chart would otherwise
generate new random ones on every Argo CD sync; the nodes **trust the lab CA** in the OS
(`13_trust_lab_ca.yml`) instead of marking Harbor as an insecure registry.

### Phase 9 — CI

GitHub Actions jobs for **sample-app** run **inside the cluster**: the **Actions Runner
Controller (ARC)** starts a runner pod for each job and deletes it afterwards. Each runner pod
has a **rootless BuildKit** sidecar (the engine behind `docker build`, no privileges or Docker
needed) that builds the image and pushes it to **Harbor**, where Trivy scans it. **Renovate**
runs every hour and opens pull requests when new versions of what we pin (charts, images,
GitHub Actions) are released — including Harbor's move from rc1 to v2.16.0.

1. **GitHub:** create two fine-grained personal access tokens (who gets which permissions:
   platform-gitops runbook, Phase 9 step 1): `lab-arc` for sample-app and `lab-renovate` for
   platform-gitops + sample-app.
2. **Mac:** push the `phase-9-ci` branch in `platform-gitops`, open the PR, **don't merge yet**.
3. **Utility server:** seal the two tokens (the script checks they work first):
   ```bash
   cd ~/platform-gitops && git fetch && git checkout phase-9-ci && git pull
   ./scripts/seal-ci-secrets.sh
   git checkout main
   ```
4. **Mac:** add both sealed files to the branch (one `scp`) and push:
   ```bash
   cd ~/GitHub/platform-gitops && git checkout phase-9-ci
   scp -r admin@172.16.79.10:ci-sealed /tmp/
   cp /tmp/ci-sealed/github-token-sealedsecret.yaml components/arc-sample-app/manifests/
   cp /tmp/ci-sealed/renovate-token-sealedsecret.yaml components/renovate/manifests/
   rm -rf /tmp/ci-sealed
   git add components/*/manifests/*-sealedsecret.yaml
   git commit -m "Phase 9: sealed CI tokens" && git push
   ```
5. **GitHub:** once the PR shows that commit and CI is green, merge. Then the utility server:
   `kubectl -n argocd get applications` — `arc-controller`, `arc-sample-app`, `renovate`
   Synced + Healthy; sample-app → Settings → Actions → Runners lists `arc-sample-app`.
6. **Utility server:** create the Harbor project `sample-app` and a CI robot account
   (platform-gitops runbook, Phase 9 step 4); **GitHub:** save the robot's name and secret as
   sample-app's Actions secrets `HARBOR_USERNAME` / `HARBOR_PASSWORD`.
7. **Mac:** push sample-app: its workflow runs on `arc-sample-app`, builds and pushes
   `harbor.apps.lab.local/sample-app/sample-app:<sha>`. **Mac (Harbor):** the image is there,
   scanned.
8. **Utility server:** run Renovate once now and look for its PRs:
   ```bash
   kubectl -n renovate create job renovate-now --from=cronjob/renovate
   kubectl -n renovate logs -f job/renovate-now | grep -E 'Repository|PR|ERROR' | head -40
   ```
9. **Utility server:** `kubectl top nodes` while a build runs — workers still have headroom.

Done when: a push to sample-app builds in the cluster and lands in Harbor scanned, and
Renovate has opened its Dependency Dashboard and update PRs.

Lessons from the build: the Renovate token needs **Pull requests: Read and write**, or
Renovate pushes branches but opens no PRs; the first sample-app image had **47** fixable
vulnerabilities (Go 1.24's standard library), and merging Renovate's golang 1.27 PR brought
the rebuilt image down to **4** negligible ones — the whole loop working: Trivy finds it,
Renovate proposes the fix, CI builds it in the cluster, Harbor rescans; Renovate's chart
PRs (cert-manager, MetalLB) rolled out through Argo CD within minutes of merging; paste
Mac and utility-server commands into the right terminal (prompt `andrew:` vs `[admin@dns`).
Detailed runbook: [platform-gitops README → Phase 9](https://github.com/andrewsgitacc/platform-gitops#phase-9-runbook-ci).

Design choices: **ARC** (GitHub's own Kubernetes runners) with **ephemeral** runner pods, so
every job starts clean and nothing runs while idle; **rootless BuildKit** as a sidecar for
image builds instead of Docker-in-Docker (no privileged pods) or the archived Kaniko;
**personal access tokens** for ARC and Renovate (simpler than a GitHub App, but they expire
and are tied to your account — re-seal before expiry); a **robot account** limited to one
Harbor project for pushes; **self-hosted Renovate** deployed by Argo CD like everything else,
acting only on repos that opt in with a `renovate.json`.

### Phase 10 — Kargo

**Kargo** (https://kargo.apps.lab.local) promotes releases through stages. Every
sample-app image that CI pushes to Harbor becomes **Freight**; Kargo deploys it to **dev**
by itself, and a **Promote** click sends it on to **staging**, then **prod** — only Freight
that ran healthily in the stage before. What each stage runs lives in the
`sample-app-deploy` repo: Kargo renders the stage with the new image tag and commits it to
the branch `stage/<stage>`, which that stage's Argo CD Application deploys.
Phase 10b will promote Puppet code (the control repo's environment branches) the same way.

1. **GitHub:** create a fine-grained token `lab-kargo` — repositories `sample-app-deploy` and
   `puppet-control-repo`, **Contents: Read and write** (field by field: platform-gitops
   runbook, Phase 10 step 1).
2. **Mac:** in `sample-app-deploy`, push the `phase-10-kargo` branch, open the PR, merge once
   its `validate` check is green.
3. **Mac:** push the `phase-10-kargo` branch in `platform-gitops`, open the PR, **don't merge yet**.
4. **Utility server:** seal Kargo's secrets — asks for a new Kargo `admin` password, the
   token (checked first) and Harbor's `admin` password (creates a pull-only robot account):
   ```bash
   cd ~/platform-gitops && git fetch && git checkout phase-10-kargo && git pull
   ./scripts/seal-kargo-secrets.sh
   git checkout main
   ```
5. **Mac:** copy the sealed files to the branch (one `scp`, then a separate block):
   ```bash
   cd ~/GitHub/platform-gitops && git checkout phase-10-kargo
   scp -r admin@172.16.79.10:kargo-sealed /tmp/
   ```
   ```bash
   cp /tmp/kargo-sealed/kargo-api-sealedsecret.yaml components/kargo/manifests/
   cp /tmp/kargo-sealed/git-*.yaml /tmp/kargo-sealed/harbor-*.yaml kargo/sample-app/
   rm -rf /tmp/kargo-sealed
   git add components/kargo/manifests kargo/sample-app
   git commit -m "Phase 10: sealed Kargo secrets" && git push
   ```
6. **GitHub:** once the PR shows that commit and CI is green, merge. **Utility server:**
   `kubectl -n argocd get applications kargo kargo-sample-app keycloak` — Synced + Healthy;
   `kubectl -n sample-app get freight,promotions` — Freight found, dev promotion Succeeded.
7. **Mac:** `curl -k https://sample-app-dev.apps.lab.local` answers with `"environment":"dev"`.
8. **Mac:** https://kargo.apps.lab.local → SSO login (Keycloak user `admin`) → project
   sample-app → promote the Freight to staging, then prod; `curl -k` both URLs.
9. **Mac:** merge a small sample-app change: CI builds it, Kargo puts it in dev on its own.
10. **Utility server:** `kubectl top nodes` — workers still have headroom.

Done when: new sample-app images reach dev automatically, and staging/prod by a promotion
in the Kargo UI, with each stage's history in its `stage/*` branch.
Detailed runbook: [platform-gitops README → Phase 10](https://github.com/andrewsgitacc/platform-gitops#phase-10-runbook-kargo).

Lessons from the build: the first dev pod failed with **CreateContainerConfigError** —
distroless's `USER nonroot` is a name, so Kubernetes can't verify `runAsNonRoot`; giving the
pod (and now the image) the numeric UID 65532 fixed it; a change merged to
sample-app-deploy's `main` reaches a stage only at its **next promotion** — merge first,
then promote (re-promoting the same Freight is fine); a promotion with nothing new to
commit "succeeds" without changing anything; the first sync of the Kargo project takes a
minute while Kargo creates its namespace; a token pasted at a hidden prompt can arrive
mangled (HTTP 401) — test it first. The end-to-end loop worked with no clicks into dev:
merge in sample-app → CI in the cluster → Harbor scan → new Freight → dev, while staging and
prod stayed on the previous release until promoted.

Design choices: **rendered branches** (Kargo commits the fully rendered manifests per stage
to `stage/<stage>`) rather than Kargo editing `main`, so `main` only changes through
reviewed PRs and a stage's branch is exactly what it runs; stage Applications **without
automated sync**, so Kargo decides when a stage changes; auto-promotion **only into dev**;
images picked by **newest build** among the CI's short-SHA tags (no semver releases yet);
the Kargo pipeline itself declared in Git (`platform-gitops/kargo/`), not clicked together in
the UI; one **pull-only** Harbor robot account for Kargo and the stages' image pulls; no
Argo Rollouts, so no automated verification yet (Phase 11 candidate).

### Rebuilding the platform from scratch

On a freshly built cluster (Phase 1 step 5), the whole platform comes back with:

1. **Mac:** prepare the workers for Ceph:
   `cd k8s && ansible-playbook -i k8s_inventory.ini 08_prepare_ceph_nodes.yml -k -K`
   (time sync with the lab NTP server is already part of playbook 01)
2. **Mac:** copy the sealing key backup to the utility server:
   `scp ~/lab-secrets/sealed-secrets-key.yaml admin@172.16.79.10:`
3. **Utility server:** `cd ~/platform-gitops && git pull && ./scripts/install.sh` — installs
   every component's CRDs, then Sealed Secrets (restoring the key), then Argo CD
4. **Utility server:** Argo CD password and login (Phase 3 steps 2–3), then
   `kubectl apply -f bootstrap/root.yaml` — Argo CD installs everything else from Git,
   retrying until storage, CRDs and webhooks are ready (allow ~15–20 minutes)
5. **Utility server:** once cert-manager is up, `./scripts/export-lab-ca.sh`; set the Ceph
   dashboard password (Phase 5 step 5); once Keycloak is up, restart `argocd-server` and
   Grafana so they load the lab CA (Phase 7 step 5). The Keycloak secrets are already in Git
   (sealed with the restored key), so SSO comes back by itself; so are Harbor's.
   Harbor's robot accounts are in its database, so after a rebuild re-create them: CI's
   (Phase 9 step 6) and Kargo's (`./scripts/seal-kargo-secrets.sh --pipeline-only`, then
   commit the new sealed files).
6. **Mac:** once cert-manager is up, trust the new lab CA on the nodes (pulls from Harbor):
   `cd k8s && ansible-playbook -i k8s_inventory.ini 13_trust_lab_ca.yml -k -K`
7. **Utility server:** remove the Helm records `install.sh` left behind (Argo CD owns it all):
   ```bash
   helm list -A -o json | jq -r '.[] | "\(.namespace) \(.name)"' | while read -r ns name; do
     kubectl -n "$ns" delete secret -l owner=helm,name="$name"
   done
   ```

## Notes

- `.local` is reserved for mDNS (Bonjour). The resolver file makes it work on macOS,
  but if lookups are slow or flaky, the long-term fix is a domain like `lab.internal`
  (`.internal` is reserved for private networks).
- The Calico CNI is bootstrap, owned by Ansible. Everything from Phase 2 onwards is
  installed with Helm and, from Phase 3, managed by Argo CD.
- Troubleshooting: node and disk problems in [`k8s/README.md`](../k8s/README.md#troubleshooting);
  platform components in the [platform-gitops README](https://github.com/andrewsgitacc/platform-gitops#troubleshooting).

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
| 8 | Harbor | registry, database, Redis, Trivy scanner | ~19 GB | ~140 GB (images in Ceph) | 250 GB |
| 9 | CI | runner controller; build runners on demand (~2 GB each while building) | ~20–23 GB | ~160 GB | 250 GB |
| 10 | Kargo | controller, API | ~21–24 GB | ~160 GB | 250 GB |
| 11 | Hardening | Kyverno, Velero | ~22–25 GB | ~180 GB (backups) | 300 GB |

> **Watch the workers' memory** with `kubectl top nodes` after each phase. After Phase 5 the
> workers sat at ~30% (Ceph's sizes are cut down for the lab); after Phase 6 they're at ~59%
> (Prometheus alone is ~1.4 GB), and after Phase 7 still ~57% (Keycloak and its database
> add ~0.7 GB). The later phases will bring them towards the 30 GB, so check after Phase 8
> (Harbor) and add worker RAM before Phase 9 if they pass ~75%. **Watch the control planes too**: the API
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
| 8 | Harbor | ⏭️ next |
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
   (sealed with the restored key), so SSO comes back by itself
6. **Utility server:** remove the Helm records `install.sh` left behind (Argo CD owns it all):
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

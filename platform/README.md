# Platform lab

**Author:** Andrew Kyle — [LinkedIn](https://www.linkedin.com/in/andrew-kyle-1007591/)

A GitOps platform on the `k8s` lab cluster, built to look like a real infrastructure
environment: everything in GitHub, CI with GitHub Actions, CD with Argo CD and Kargo.

## Architecture

- **Cluster:** `labs/k8s` — kubeadm, 3 control planes + 3 workers, Calico, Ceph disks on the workers
- **DNS:** `labs/dns` — BIND; `apps.lab.local` is updated automatically by external-dns
- **CI:** GitHub Actions — PR checks on GitHub-hosted runners, image builds on self-hosted runners in the cluster
- **CD:** Argo CD deploys from Git; Kargo promotes dev → staging → prod
- **Utility server:** `dns.lab.local` doubles as the admin box — kubectl, helm, k9s and the cluster kubeconfig live there (`labs/admin`). Nothing is installed on the Mac; it only runs Ansible and the browser

## Repos

| Repo | Purpose |
|---|---|
| `labs` | VM/cluster build (Ansible), DNS, platform docs and runbooks |
| `platform-gitops` | Argo CD app-of-apps and Helm values for every platform component |
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
| **.100–.119** | **Reserved: MetalLB LoadBalancer IPs (Phase 2)** |
| .128–.254 | Fusion DHCP — never use for static IPs or MetalLB |

## Build order

| # | Phase | Status |
|---|---|---|
| 1 | Prep: Mac DNS resolver, `apps.lab.local` zone, admin tools on the utility server, cluster rebuild (v1.36, Calico, bigger workers, Ceph disks), new repos | ✅ done |
| 2 | Cluster foundation: MetalLB, Envoy Gateway, cert-manager, external-dns | 🚧 in progress |
| 3 | Argo CD (self-managed; GitOps from here) | |
| 4 | Sealed Secrets | |
| 5 | Rook-Ceph (block, file, S3 object) | |
| 6 | Observability: Prometheus, Grafana, Alertmanager, Loki, Alloy | |
| 7 | Keycloak SSO | |
| 8 | Harbor | |
| 9 | CI: ARC runners, sample-app pipeline, Renovate | |
| 10 | Kargo | |
| 11 | Hardening and day-2: Kyverno, Velero, alerts, k8s 1.36 → 1.37 upgrade, break/fix | |

## Phase 1 runbook

Ansible runs from the Mac, in the `labs` repo. Cluster commands run on the utility server.

### 1. Mac DNS resolver

```bash
./platform/workstation/setup_workstation.sh
```

Creates `/etc/resolver/lab.local` so the Mac (browser, ssh, Ansible) uses the lab DNS for
`*.lab.local`. Nothing is installed on the Mac.

Check: `dscacheutil -q host -a name k8s-api.lab.local` returns the control plane IPs.

### 2. DNS zone for external-dns

```bash
cd dns
ansible-playbook -i dns_inventory.ini add_apps_zone.yml -k -K
cd ..
```

Then run the verification in `dns/README.md` on the DNS server (`ssh admin@dns.lab.local`):
a signed update works, an unsigned one is refused.

### 3. Admin tools on the utility server

```bash
cd admin
ansible-playbook -i admin_inventory.ini install_admin_tools.yml -k -K
cd ..
```

### 4. Rebuild the cluster

This destroys and recreates all six k8s VMs (the cluster had no workloads).
Power off the Puppet and Jenkins VMs first to free RAM. Then run the playbooks
in `k8s/README.md` in order (01 → 06). Playbook 03 installs the kubeconfig on the
utility server.

Check, on the utility server:

```bash
ssh admin@dns.lab.local
kubectl get nodes -o wide      # 6 nodes Ready, v1.36.x
kubectl get tigerastatus       # calico, apiserver AVAILABLE=True
k9s                            # browse the cluster
```

Then run the `k8s/README.md` tests, especially **NetworkPolicy** and **Ceph disks on the workers**.

### 5. New repos

On the utility server (`gh` is installed there):

```bash
gh auth login        # once
gh repo create andrewsgitacc/platform-gitops   --public  --add-readme --description "GitOps config for the platform lab (Argo CD)"
gh repo create andrewsgitacc/sample-app        --private --add-readme --description "Demo app for the platform lab CI/CD"
gh repo create andrewsgitacc/sample-app-deploy --public  --add-readme --description "Environment config for sample-app, promoted by Kargo"
```

Or create them in the GitHub web UI, then clone them into `~/GitHub` on the Mac.

### Phase 1 done when

- [ ] `k8s-api.lab.local` resolves on the Mac without `@172.16.79.10`
- [ ] Signed nsupdate to `apps.lab.local` works, unsigned is refused
- [ ] kubectl, helm, k9s work on the utility server
- [ ] 6 nodes Ready on v1.36, Calico Available
- [ ] NetworkPolicy test blocks and allows as expected
- [ ] `/dev/nvme0n2` (100G, empty) on all 3 workers
- [ ] Three new repos exist
- [ ] `ansible-lint` GitHub Actions check green on the Phase 1 PR

## Phase 2: cluster foundation

Everything for this phase lives in
[platform-gitops](https://github.com/andrewsgitacc/platform-gitops); the step-by-step
runbook is in its README. In short, on the utility server:

| Step | Component | Result |
|---|---|---|
| 1 | MetalLB | LoadBalancer IPs from 172.16.79.100–.119; tested from the Mac on .119 |
| 2 | cert-manager | Internal `Lab Root CA` + `lab-ca` issuer; CA public cert trusted on the Mac |
| 3 | Envoy Gateway | `lab-gateway` on 172.16.79.100, HTTPS for `*.apps.lab.local` (auto-renewed wildcard cert) |
| 4 | external-dns | `<name>.apps.lab.local` records created/removed on dns.lab.local via signed RFC2136 updates |
| 5 | hello app | https://hello.apps.lab.local works in the Mac browser with a trusted certificate |

Design choices:

- **Envoy Gateway** rather than ingress-nginx (being retired) or Traefik: it implements the
  Kubernetes **Gateway API**, the standard that replaces Ingress.
- **One shared gateway** with a wildcard certificate. Apps only add an HTTPRoute; DNS and TLS follow.
- **The CA private key stays in the cluster.** Only its public certificate leaves, to be trusted.
- **Helm from the utility server for now.** The same chart versions, values and manifests are
  adopted by Argo CD in Phase 3 without reinstalling anything.

## Notes

- `.local` is reserved for mDNS (Bonjour). The resolver file makes it work on macOS,
  but if lookups are slow or flaky, the long-term fix is a domain like `lab.internal`
  (`.internal` is reserved for private networks).
- The Calico CNI is bootstrap, owned by Ansible. Everything from Phase 2 onwards is
  installed with Helm and, from Phase 3, managed by Argo CD.

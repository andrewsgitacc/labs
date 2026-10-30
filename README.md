# labs

**Author:** Andrew Kyle — [LinkedIn](https://www.linkedin.com/in/andrew-kyle-1007591/)

Infrastructure labs designed to run on an **Apple Silicon Mac** with **VMware Fusion**.
Every VM is cloned from a CentOS Stream 9 (aarch64) template and built with **Ansible**,
one lab per folder. Together they're building towards a realistic platform environment:
Kubernetes, GitOps, CI/CD, storage and observability, with everything in GitHub.

## Completed labs

| Lab | What it builds | Hosts |
|---|---|---|
| [`dns`](dns/) | BIND DNS for `lab.local`, plus a dynamic `apps.lab.local` zone for Kubernetes external-dns. Also the lab's **utility server** | `dns.lab.local` 172.16.79.10 |
| [`admin`](admin/) | Admin CLI tools on the utility server: kubectl, helm, k9s, stern, yq, jq, gh | `dns.lab.local` |
| [`k8s`](k8s/) | Kubernetes v1.36 with kubeadm: 3 control planes, 3 workers, Calico CNI (NetworkPolicies), 100 GB Ceph disk per worker | .21–.23, .31–.33 |
| [`jenkins`](jenkins/) | Jenkins CI server, configured as code (JCasC), jobs as code | `jenkins.lab.local` 172.16.79.60 |
| [`puppet`](puppet/) | OpenVox (Puppet) server + 2 agents; code in [puppet-control-repo](https://github.com/andrewsgitacc/puppet-control-repo), deployed with r10k | .70–.72 |

## Platform lab (in progress)

[`platform`](platform/) builds a GitOps platform on the `k8s` cluster, one phase at a time.
Full plan, architecture and runbooks: [`platform/README.md`](platform/README.md).

| # | Phase | What it adds | Status |
|---|---|---|---|
| 1 | Prep | Cluster rebuild (v1.36, Calico, bigger workers, Ceph disks), dynamic DNS zone, admin tools, new repos | ✅ Done |
| 2 | Cluster foundation | MetalLB, Envoy Gateway (Gateway API), cert-manager with an internal CA, external-dns | ✅ Done |
| 3 | Argo CD | GitOps: everything after this is deployed from Git | ⏭️ Next |
| 4 | Sealed Secrets | Encrypted secrets stored safely in Git | Planned |
| 5 | Rook-Ceph | Block, file and S3-compatible object storage | Planned |
| 6 | Observability | Prometheus, Grafana, Alertmanager, Loki, Alloy | Planned |
| 7 | Keycloak | Single sign-on for the platform UIs | Planned |
| 8 | Harbor | Container registry with Trivy image scanning | Planned |
| 9 | CI | GitHub Actions self-hosted runners in the cluster, sample-app pipeline, Renovate | Planned |
| 10 | Kargo | Promotion of releases dev → staging → prod | Planned |
| 11 | Hardening and day-2 | Kyverno policies, Velero backups + restore test, alerting, Kubernetes upgrade, break/fix | Planned |

Related repos (created in Phase 1, used from Phase 3):

- `platform-gitops` — Argo CD app-of-apps and Helm values for every platform component
- `sample-app` (private) — demo app and its CI pipeline
- `sample-app-deploy` — dev/staging/prod config promoted by Kargo

## Network

All labs share the VMware Fusion NAT network `172.16.79.0/24` and the `lab.local` domain.
The full IP plan is in [`platform/README.md`](platform/README.md) (section "IP plan").

## Requirements

- VMware Fusion with the `CentOS9aarch64` template (user `admin` with sudo, password `admin` — *lab only*)
- Ansible on the Mac, with the `community.general` and `ansible.posix` collections
- The `dns` lab built first: every other lab depends on it

## CI

- **GitHub Actions** ([`.github/workflows/ansible-lint.yml`](.github/workflows/ansible-lint.yml)) syntax-checks the `k8s`, `dns` and `admin` playbooks and runs `ansible-lint` on every pull request.
- **Jenkins** (`jenkins` lab) also runs the `k8s` and `puppet` pipelines from their `Jenkinsfile`s.

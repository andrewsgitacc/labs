# labs

**Author:** Andrew Kyle — [LinkedIn](https://www.linkedin.com/in/andrew-kyle-1007591/)

## Labs design to run on Apple Silicon Mac OS.

| Lab | What it builds |
|---|---|
| `dns` | BIND DNS server for `lab.local` (+ dynamic `apps.lab.local`). Also the lab's **utility server** |
| `admin` | Admin CLI tools (kubectl, helm, k9s...) on the utility server |
| `k8s` | 3 control plane + 3 worker kubeadm cluster with Calico |
| `jenkins` | Jenkins server with JCasC and jobs as code |
| `puppet` | OpenVox server + 2 agents, control repo in its own repo |
| `platform` | GitOps platform on the k8s cluster: Argo CD, Ceph, observability, Harbor, Kargo |

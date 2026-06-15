# k8s

**Author:** Andrew Kyle — [LinkedIn](https://www.linkedin.com/in/andrew-kyle-1007591/)

Deploys a 3-control-plane, 3-worker Kubernetes cluster on VMware Fusion using Ansible.

## Note

VMware Fusion uses NAT networking — you can't change vSwitch security policies and there's no vSphere console. Gratuitous ARP for floating VIPs doesn't work reliably, so keepalived/HAProxy is replaced with round-robin DNS pointing `k8s-api.lab.local` at both control plane nodes. The tradeoff: if one control node goes down, ~50% of requests will fail until you update DNS. Acceptable for a lab.

## Requirements

- VMware Fusion
- VM template: `CentOS9aarch64`
  - User account with sudo access: `admin`
  - Password: `admin` *(lab only)*
- Ansible (on Mac)
- DNS server deployed — see `labs/dns`

## Deployment

```bash
git clone git@github.com:andrewsgitacc/labs.git
cd k8s
```

Run playbooks in order:

```bash
# 1. Deploy and configure VMs
#    When prompted: enter admin password, root password, and select "I Copied It" if asked
ansible-playbook 01_configure_k8s_cluster.yml -k -K

# 2. Install k8s software on all nodes
ansible-playbook -i k8s_inventory.ini 02_install_k8s_software.yml -k -K

# 3. Initialise the control plane
ansible-playbook -i k8s_inventory.ini 03_init_control_plane.yml -k -K

# 4. Join worker and second control plane nodes
ansible-playbook -i k8s_inventory.ini 04_join_nodes.yml -k -K

# 5. Install Flannel CNI (VXLAN backend — Cilium has limitations on VMware Fusion)
ansible-playbook -i k8s_inventory.ini 05_install_flannel.yml -k -K

# 6. Configure firewall for CNI
#    Fixes kube-proxy ClusterIP failures caused by legacy xt_tables on CentOS Stream 9
ansible-playbook -i k8s_inventory.ini 06_configure_firewall_for_cni.yml -k -K
```

## Verification

SSH to a control node:

```bash
ssh -q -l admin "$(dig @172.16.79.10 k8s-api.lab.local +short | tail -1)"
```

### Check all nodes are Ready - run on the control node

```bash
kubectl get nodes -o wide
```

Expected output:

```
NAME                       STATUS   ROLES           AGE   VERSION    INTERNAL-IP    EXTERNAL-IP   OS-IMAGE          KERNEL-VERSION           CONTAINER-RUNTIME
k8s-control-01.lab.local   Ready    control-plane   12h   v1.32.13   172.16.79.21   <none>        CentOS Stream 9   5.14.0-710.el9.aarch64   containerd://2.2.4
k8s-control-02.lab.local   Ready    control-plane   11h   v1.32.13   172.16.79.22   <none>        CentOS Stream 9   5.14.0-710.el9.aarch64   containerd://2.2.4
k8s-control-03.lab.local   Ready    control-plane   11h   v1.32.13   172.16.79.23   <none>        CentOS Stream 9   5.14.0-710.el9.aarch64   containerd://2.2.4
k8s-worker-01.lab.local    Ready    <none>          11h   v1.32.13   172.16.79.31   <none>        CentOS Stream 9   5.14.0-710.el9.aarch64   containerd://2.2.4
k8s-worker-02.lab.local    Ready    <none>          11h   v1.32.13   172.16.79.32   <none>        CentOS Stream 9   5.14.0-710.el9.aarch64   containerd://2.2.4
k8s-worker-03.lab.local    Ready    <none>          11h   v1.32.13   172.16.79.33   <none>        CentOS Stream 9   5.14.0-710.el9.aarch64   containerd://2.2.4
```

## Tests

All tests run on a control node as `admin`.

### Basic cluster health

```bash
kubectl get nodes -o wide
kubectl get pods -n kube-system
kubectl cluster-info
```

### Deploy a simple pod and exec into it

```bash
kubectl run test-pod --image=nginx
kubectl get pod test-pod
kubectl wait --for=condition=ready pod/test-pod --timeout=60s
kubectl exec -it test-pod -- curl localhost
kubectl delete pod test-pod
```

### Pod scheduling across all workers

```bash
kubectl create deployment nginx --image=nginx --replicas=3
kubectl get pods -o wide   # should spread across worker nodes
kubectl delete deployment nginx
```

### Service and DNS resolution

```bash
kubectl create deployment nginx --image=nginx --replicas=2
kubectl expose deployment nginx --port=80
kubectl run curl-test --image=curlimages/curl --rm -it --restart=Never -- curl nginx
kubectl delete deployment nginx && kubectl delete service nginx
```

### Persistent storage (hostPath)

```bash
kubectl run storage-test --image=busybox --rm -it --restart=Never -- sh -c "echo hello > /tmp/test && cat /tmp/test"
```

### DNS test suite - run from Mac

```bash
control_server=`dig @172.16.79.10 k8s-api.lab.local +short | tail -1`
scp -q dns_test.sh admin@$control_server:
ssh -q -l admin $control_server bash dns_test.sh
```

### Rolling update

```bash
kubectl create deployment nginx --image=nginx:1.25
kubectl rollout status deployment/nginx
kubectl set image deployment/nginx nginx=nginx:1.26
kubectl rollout status deployment/nginx
kubectl rollout history deployment/nginx
kubectl delete deployment nginx
```

### Cross-pod networking (Flannel)

```bash
kubectl create deployment server --image=nginx
kubectl expose deployment server --port=80
kubectl run client --image=curlimages/curl --rm -it --restart=Never -- curl server
kubectl delete deployment server && kubectl delete service server
```

### NodePort

```bash
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --type=NodePort --port=80
kubectl get service nginx   # note the NodePort
NODEPORT=$(kubectl get service nginx | tail -1 | cut -d: -f2 | cut -d/ -f1)
curl http://172.16.79.31:$NODEPORT
curl http://172.16.79.32:$NODEPORT
curl http://172.16.79.33:$NODEPORT
kubectl delete deployment nginx && kubectl delete service nginx
```

### Flannel pod status and routes

```bash
kubectl get pods -n kube-flannel -o wide
kubectl logs -n kube-flannel -l app=flannel | tail -20

# Run from Mac — each node should have routes to other nodes' pod CIDRs
ssh -q -t admin@172.16.79.31 "ip route | grep 10.244"
```

### Resource limits

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: limited
spec:
  containers:
  - name: nginx
    image: nginx
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi
EOF
kubectl describe pod limited
kubectl delete pod limited
```

### etcd health

```bash
kubectl exec -n kube-system etcd-k8s-control-01.lab.local -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/peer.crt \
  --key=/etc/kubernetes/pki/etcd/peer.key \
  endpoint health
```

## HA Tests

### Control plane resilience

1. Shut down `k8s-control-02` — verify `kubectl` still works (round-robin will route ~50% of requests to the dead node until DNS settles; this is the known DNS round-robin limitation)
2. Shut down `k8s-control-01`, update `k8s-api.lab.local` to point only at `k8s-control-02` — verify cluster is still responsive
3. Bring both nodes back up — verify etcd re-syncs

### Worker node failure

```bash
# 1. Deploy workload
kubectl create deployment nginx --image=nginx --replicas=3
kubectl get pods -o wide   # note which nodes the pods land on

# 2. Cordon and drain worker-01
kubectl cordon k8s-worker-01.lab.local
kubectl drain k8s-worker-01.lab.local --ignore-daemonsets --delete-emptydir-data

# 3. Verify pods rescheduled onto the remaining two workers
kubectl get pods -o wide   # no pods should show k8s-worker-01 — all on worker-02/03

# 4. Verify the node shows SchedulingDisabled
kubectl get nodes

# 5. Bring worker-01 back
kubectl uncordon k8s-worker-01.lab.local

# 6. Verify it rejoins and is Ready
kubectl get nodes

# 7. Cleanup
kubectl delete deployment nginx
```

### Pod disruption budget - if you set "minAvailable: 2" on a 3-replica deployment, drain will only evict one pod at a time and wait for the replacement to be Ready before evicting the next one, keeping at least 2 healthy at all times.

```bash
# Deploy nginx with 3 replicas, kill pods one by one — ReplicaSet should recreate them
kubectl create deployment nginx --image=nginx --replicas=3
kubectl get pods -o wide   #Review the pods names creaetd
kubectl delete pod `kubectl get pods -o wide|tail -1|awk '{print $1}'`
kubectl get pods -o wide   #See that a pod is deleted and a new one has been created

# Apply a PDB and verify drain respects it
kubectl create pdb nginx-pdb --selector=app=nginx --min-available=2
kubectl get pods -o wide   #Review the pods names created - see that there are still 3 pods running
kubectl drain k8s-worker-01.lab.local --ignore-daemonsets   # should block while PDB is violated
# Delete them all
kubectl delete pdb nginx-pdb && kubectl delete deployment nginx
```

### etcd quorum

Need a min of 3 control nodes to maintain a quorum if a control node is lost. If quorum is lost, the API server goes read-only.

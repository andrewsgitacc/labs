#!/usr/bin/env bash
# DNS Test Suite for k8s lab cluster
# Run from the control node: bash dns_test.sh

set -uo pipefail

PASS="\033[0;32m✓\033[0m"
FAIL="\033[0;31m✗\033[0m"
INFO="\033[0;34m→\033[0m"
DNS_SERVER="172.16.79.10"

pass() { echo -e "$PASS $1"; }
fail() { echo -e "$FAIL $1"; FAILED=$((FAILED+1)); }
info() { echo -e "$INFO $1"; }

FAILED=0

# Run a one-shot busybox pod and capture its stdout via logs.
# Polls for Succeeded/Failed phase so we never read logs before the
# container actually runs (Pending also satisfies Ready=False, which
# is why kubectl wait --for=condition=Ready=False fired too early).
run_in_pod() {
  local name="$1"; shift
  kubectl run "$name" --image=busybox:1.36 --restart=Never -- "$@" >/dev/null 2>&1
  local phase i
  for i in $(seq 1 30); do
    phase=$(kubectl get pod "$name" -o jsonpath='{.status.phase}' 2>/dev/null)
    [[ "$phase" == "Succeeded" || "$phase" == "Failed" ]] && break
    sleep 1
  done
  kubectl logs "$name" 2>/dev/null
  kubectl delete pod "$name" --ignore-not-found >/dev/null 2>&1
}

echo "================================================"
echo " k8s Cluster DNS Test Suite"
echo "================================================"
echo ""

# ── 1. CoreDNS pod health ──────────────────────────
echo "[ 1 ] CoreDNS pod health"
COREDNS_PODS=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ') || COREDNS_PODS=0
if [[ "$COREDNS_PODS" -ge 2 ]]; then
  pass "$COREDNS_PODS CoreDNS pods running"
else
  fail "Expected ≥2 CoreDNS pods, found $COREDNS_PODS"
  kubectl get pods -n kube-system -l k8s-app=kube-dns
fi
echo ""

# ── 2. Lab DNS: k8s-api.lab.local round-robin ─────
echo "[ 2 ] Lab DNS — k8s-api.lab.local round-robin"
RESOLVED=$(dig @$DNS_SERVER k8s-api.lab.local +short | sort)
if echo "$RESOLVED" | grep -q "172.16.79.21" && echo "$RESOLVED" | grep -q "172.16.79.22"; then
  pass "k8s-api.lab.local resolves to both control plane IPs"
  echo "      $RESOLVED" | tr '\n' ' '
  echo ""
else
  fail "k8s-api.lab.local did not resolve to both 172.16.79.21 and 172.16.79.22"
  info "Got: $RESOLVED"
fi
echo ""

# ── 3. Cluster-internal: kubernetes service ────────
echo "[ 3 ] Cluster DNS — kubernetes.default.svc.cluster.local"
RESULT=$(run_in_pod dns-test-1 nslookup kubernetes.default.svc.cluster.local)
if echo "$RESULT" | grep -q "10.96.0.1"; then
  pass "kubernetes.default.svc.cluster.local resolves to 10.96.0.1"
elif echo "$RESULT" | grep -q "Address"; then
  pass "kubernetes.default.svc.cluster.local resolved (address returned)"
  info "$(echo "$RESULT" | grep 'Address' | tail -1)"
else
  fail "kubernetes.default.svc.cluster.local did not resolve"
  echo "$RESULT"
fi
echo ""

# ── 4. Service DNS: deploy nginx, resolve by name ──
echo "[ 4 ] Service DNS — deploy nginx, resolve from peer pod"
kubectl create deployment dns-nginx --image=nginx:stable-alpine --replicas=1 -o name 2>/dev/null || true
kubectl expose deployment dns-nginx --port=80 2>/dev/null || true
info "Waiting for dns-nginx pod to be ready..."
kubectl wait --for=condition=ready pod -l app=dns-nginx --timeout=60s -o name 2>/dev/null | head -1

SVC_RESULT=$(run_in_pod dns-test-2 nslookup dns-nginx)
if echo "$SVC_RESULT" | grep -q "Address"; then
  pass "Service 'dns-nginx' resolved by short name within cluster"
  info "$(echo "$SVC_RESULT" | grep 'Address' | tail -1)"
else
  fail "Service 'dns-nginx' did not resolve"
  echo "$SVC_RESULT"
fi

FQDN_RESULT=$(run_in_pod dns-test-3 nslookup dns-nginx.default.svc.cluster.local)
if echo "$FQDN_RESULT" | grep -q "Address"; then
  pass "Service resolved by FQDN (dns-nginx.default.svc.cluster.local)"
else
  fail "FQDN resolution failed for dns-nginx.default.svc.cluster.local"
fi
echo ""

# ── 5. External DNS from inside a pod ─────────────
echo "[ 5 ] External DNS — resolve google.com from within cluster"
EXT_RESULT=$(run_in_pod dns-test-4 nslookup google.com)
if echo "$EXT_RESULT" | grep -q "Address"; then
  pass "External DNS (google.com) resolves from within cluster"
else
  fail "External DNS failed — check CoreDNS upstream forwarder config"
  echo "$EXT_RESULT"
fi
echo ""

# ── 6. Reverse DNS for cluster nodes ──────────────
echo "[ 6 ] Reverse DNS — node IPs via lab DNS server"
for IP_HOST in "172.16.79.21:k8s-control-01" "172.16.79.22:k8s-control-02" "172.16.79.31:k8s-worker-01"; do
  IP="${IP_HOST%%:*}"
  EXPECTED="${IP_HOST##*:}"
  REV=$(dig @$DNS_SERVER -x "$IP" +short 2>/dev/null | sed 's/\.$//')
  if echo "$REV" | grep -qi "$EXPECTED"; then
    pass "Reverse DNS $IP → $REV"
  else
    fail "Reverse DNS $IP → '$REV' (expected $EXPECTED.lab.local)"
  fi
done
echo ""

# ── 7. Cross-namespace DNS ─────────────────────────
echo "[ 7 ] Cross-namespace DNS — resolve kube-dns service from default namespace"
NS_RESULT=$(run_in_pod dns-test-5 nslookup kube-dns.kube-system.svc.cluster.local)
if echo "$NS_RESULT" | grep -q "Address"; then
  pass "Cross-namespace: kube-dns.kube-system.svc.cluster.local resolved"
else
  fail "Cross-namespace DNS resolution failed"
  echo "$NS_RESULT"
fi
echo ""

# ── Cleanup ────────────────────────────────────────
echo "[ cleanup ] Removing test resources"
kubectl delete deployment dns-nginx --ignore-not-found 2>/dev/null
kubectl delete service dns-nginx --ignore-not-found 2>/dev/null
pass "Test resources removed"
echo ""

# ── Summary ───────────────────────────────────────
echo "================================================"
if [[ "$FAILED" -eq 0 ]]; then
  echo -e " $PASS All DNS tests passed"
else
  echo -e " $FAIL $FAILED test(s) failed — review output above"
fi
echo "================================================"
exit $FAILED

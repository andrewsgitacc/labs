#!/usr/bin/env bash
# Mac setup for the platform lab. Nothing is installed on the Mac: the admin
# CLI tools live on the utility server (dns.lab.local, see labs/admin).
#
# This only makes the Mac ask the lab DNS server (172.16.79.10) for *.lab.local,
# so the browser can open the lab UIs (Argo CD, Grafana, Harbor...) and ssh/ansible
# can use lab hostnames. macOS treats .local as Bonjour (mDNS) unless told otherwise.
#
# Usage: ./platform/workstation/setup_workstation.sh   (asks for your Mac password)
set -euo pipefail

LAB_DOMAIN="lab.local"
LAB_DNS="172.16.79.10"

echo "==> Pointing ${LAB_DOMAIN} at ${LAB_DNS}"
sudo mkdir -p /etc/resolver
printf 'nameserver %s\n' "${LAB_DNS}" | sudo tee "/etc/resolver/${LAB_DOMAIN}" >/dev/null

echo "==> Checking"
scutil --dns | grep -A2 "domain   : ${LAB_DOMAIN}" || true
dscacheutil -q host -a name "k8s-api.${LAB_DOMAIN}" || true
echo "To undo: sudo rm /etc/resolver/${LAB_DOMAIN}"

#!/usr/bin/env bash
# Set up the Mac as the admin workstation for the platform lab.
#   1. Installs the CLI tools in the Brewfile
#   2. Sends lab.local DNS lookups to the lab DNS server (172.16.79.10)
#
# Usage: ./platform/workstation/setup_workstation.sh   (asks for your Mac password for step 2)
set -euo pipefail

LAB_DOMAIN="lab.local"
LAB_DNS="172.16.79.10"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Installing CLI tools"
brew bundle --file "${SCRIPT_DIR}/Brewfile"

# macOS treats .local as Bonjour (mDNS). A resolver file makes it ask the lab
# DNS server for *.lab.local as well, so names like grafana.apps.lab.local work
# in the browser, kubectl and helm.
echo "==> Pointing ${LAB_DOMAIN} at ${LAB_DNS}"
sudo mkdir -p /etc/resolver
printf 'nameserver %s\n' "${LAB_DNS}" | sudo tee "/etc/resolver/${LAB_DOMAIN}" >/dev/null

echo "==> Checking"
scutil --dns | grep -A2 "domain   : ${LAB_DOMAIN}" || true
dscacheutil -q host -a name "k8s-api.${LAB_DOMAIN}" || true
echo "Done. kubectl version --client: $(kubectl version --client 2>/dev/null | head -1)"

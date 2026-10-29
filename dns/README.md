# DNS Lab

**Author:** Andrew Kyle — [LinkedIn](https://www.linkedin.com/in/andrew-kyle-1007591/)

Deploys a VM from template and installs BIND.

## Utility server

`dns.lab.local` is also the lab's **utility server**: it holds the platform admin CLI
tools (kubectl, helm, k9s...) and the cluster kubeconfig, installed by `labs/admin`.

In production DNS and admin tooling would be separate machines. They're combined here
because DNS is always running (every lab needs it), it saves a VM's worth of RAM, it
resolves `lab.local` natively, and it keeps tools and credentials off the Mac. The
trade-off is that access to this server means admin access to the cluster. Full
reasoning: [`admin/README.md`](../admin/README.md#why-the-dns-server-is-also-the-utility-server).

After rebuilding this VM, re-run `admin/install_admin_tools.yml` to put the tools back.

## Requirements

- VMware Fusion
- VM template: `CentOS9aarch64`
  - User account with sudo access: `admin`
  - Password: `admin` *(lab only — do not use in production)*
- Ansible

## Usage

```bash
git clone git@github.com:andrewsgitacc/labs.git
cd dns
ansible-playbook dns.yml -k -K
```

When prompted, enter the `admin` account password and root password (both `admin`).

# Verification - run on Mac
```bash
dig @172.16.79.10 k8s-api.lab.local +short
```

## Dynamic zone for Kubernetes (external-dns)

`apps.lab.local` is a separate zone that accepts dynamic updates (RFC2136) signed
with the TSIG key `externaldns-key`. external-dns in the platform cluster uses it to
create and remove records for apps (e.g. `grafana.apps.lab.local`). The main
`lab.local` zone stays static and Ansible-managed.

- Fresh builds: included automatically by `configure_dns_server.yml`.
- Existing server: add it in place with

```bash
cd dns
ansible-playbook -i dns_inventory.ini add_apps_zone.yml -k -K
```

The key is generated once on the server (`/etc/named/externaldns.key`) and a copy is
fetched to `dns/externaldns.key` on the Mac for the external-dns setup. That file is
git-ignored.

### Verification - run on the DNS server (`ssh admin@dns.lab.local`)

```bash
dig @172.16.79.10 apps.lab.local SOA +short

# Test a signed update and removal with the key
cat > /tmp/nsupdate.txt <<'EOT'
server 172.16.79.10
zone apps.lab.local
update add test.apps.lab.local 60 A 172.16.79.250
send
EOT
sudo nsupdate -k /etc/named/externaldns.key /tmp/nsupdate.txt
dig @172.16.79.10 test.apps.lab.local +short     # 172.16.79.250
sed -i 's/update add test.apps.lab.local 60 A 172.16.79.250/update delete test.apps.lab.local A/' /tmp/nsupdate.txt
sudo nsupdate -k /etc/named/externaldns.key /tmp/nsupdate.txt
dig @172.16.79.10 test.apps.lab.local +short     # (empty)

# An unsigned update must be refused
printf 'server 172.16.79.10\nzone apps.lab.local\nupdate add bad.apps.lab.local 60 A 1.2.3.4\nsend\n' | nsupdate   # REFUSED
```

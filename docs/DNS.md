# DNS Infrastructure

This document describes the Technitium DNS cluster deployment for the home lab.

## Overview

Two Technitium DNS servers run as LXC containers on Proxmox, providing:

- Authoritative DNS for `home.lewelly.com`
- Ad blocking (replacing Pi-hole)
- Automatic DNS record management via external-dns
- High availability with cluster replication

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  external-dns                                        │    │
│  │  - Watches Services, Ingresses, HTTPRoutes          │    │
│  │  - Creates/updates DNS records via RFC 2136         │    │
│  └──────────────────────┬──────────────────────────────┘    │
└─────────────────────────┼───────────────────────────────────┘
                          │ RFC 2136 + TSIG (external-dns key)
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  Technitium Cluster (v14)                                   │
│  ┌─────────────────────┐    ┌─────────────────────┐        │
│  │ ns1.home.lewelly.com│◄──►│ ns2.home.lewelly.com│        │
│  │   10.10.20.71       │    │   10.10.20.72       │        │
│  │   (taco)            │    │   (tamale)          │        │
│  └─────────────────────┘    └─────────────────────┘        │
│    Cluster sync via TSIG (cluster-catalog key)             │
└─────────────────────────────────────────────────────────────┘
```

## Servers

| Hostname     | IP Address  | DNS Name             | Proxmox Host | VM ID | Storage  |
| ------------ | ----------- | -------------------- | ------------ | ----- | -------- |
| technitium-1 | 10.10.20.71 | ns1.home.lewelly.com | taco         | 301   | Ceph RBD |
| technitium-2 | 10.10.20.72 | ns2.home.lewelly.com | tamale       | 302   | Ceph RBD |

Both containers use Ceph RBD storage for live migration capability between Proxmox hosts.

## Access

| Interface      | URL/Port                           |
| -------------- | ---------------------------------- |
| Web UI (HTTPS) | `https://10.10.20.71:53443`        |
| Web UI (HTTP)  | `http://10.10.20.71:5380`          |
| DNS            | `10.10.20.71:53`, `10.10.20.72:53` |

TLS certificates are automatically synced from Kubernetes (Let's Encrypt wildcard for `*.home.lewelly.com`).

## Zone Configuration

### Primary Zone: `home.lewelly.com`

- **Type**: Primary
- **Dynamic Updates**: Enabled with TSIG authentication
- **TSIG Key**: `external-dns` (HMAC-SHA256)

### Cluster Replication

Technitium v14 cluster feature handles automatic zone synchronization between nodes. Both servers maintain identical zone data without manual primary/secondary configuration.

**Cluster endpoints:**
- `https://ns1.home.lewelly.com:53443/`
- `https://ns2.home.lewelly.com:53443/`

A dedicated TSIG key (`cluster-catalog`) authenticates replication between nodes.

### Upstream DNS

Cloudflare DNS over HTTPS:
- `https://cloudflare-dns.com/dns-query` (1.1.1.1)
- `https://cloudflare-dns.com/dns-query` (1.0.0.1)

## External-DNS Integration

External-dns uses RFC 2136 (Dynamic DNS Updates) with TSIG authentication to manage records.

### Configuration

```yaml
provider:
  name: rfc2136
extraArgs:
  - --rfc2136-host=10.10.20.71
  - --rfc2136-port=53
  - --rfc2136-zone=home.lewelly.com
  - --rfc2136-tsig-secret-alg=hmac-sha256
  - --rfc2136-tsig-keyname=external-dns
```

### TSIG Secret

The shared secret is stored in `infrastructure/base/external-dns/tsig-secret.yaml` (SOPS encrypted).

To view the current secret:
```bash
sops -d infrastructure/base/external-dns/tsig-secret.yaml | grep tsig-secret
```

The same secret must be configured in Technitium under Settings > TSIG.

## TLS Certificate Sync

Certificates are pulled from Kubernetes and converted to PKCS#12 format for Technitium.

### How It Works

1. ServiceAccount in `technitium-system` namespace has RBAC to read the cert secret
2. Kubeconfig (SOPS encrypted) is deployed to `/etc/technitium/kubeconfig`
3. Cron job runs `/usr/local/bin/sync-tls-cert.sh` daily
4. Script fetches cert from K8s, creates `.pfx` file, restarts Technitium if changed

### Manual Sync

```bash
ssh root@10.10.20.71 /usr/local/bin/sync-tls-cert.sh
```

## Deployment

### Infrastructure

```bash
# LXC containers (Terraform)
cd tf && tofu apply -target=module.technitium_lxc

# Technitium installation (Ansible)
cd ansible && ansible-playbook playbooks/technitium.yml
```

### TLS Only

```bash
ansible-playbook playbooks/technitium.yml --tags tls
```

## Key Files

```
tf/
├── technitium.tf                    # LXC container definitions
└── modules/proxmox-lxc/             # LXC module

ansible/
├── playbooks/technitium.yml         # Main playbook
├── inventory/hosts.yml              # Inventory (technitium group)
└── roles/technitium/
    ├── tasks/
    │   ├── main.yml                 # Installation tasks
    │   └── tls.yml                  # TLS sync tasks
    ├── templates/
    │   ├── technitium-dns.service.j2
    │   └── sync-tls-cert.sh.j2
    ├── files/
    │   └── kubeconfig               # SOPS encrypted
    └── defaults/main.yml            # Default variables

infrastructure/
├── base/external-dns/
│   ├── external-dns.yaml            # RFC 2136 config
│   └── tsig-secret.yaml             # SOPS encrypted
└── base/technitium-rbac/
    └── rbac.yaml                    # K8s RBAC for cert access
```

## Troubleshooting

### Test Dynamic Updates

```bash
# Create test key file
cat > /tmp/tsig.conf << 'EOF'
key "external-dns" {
    algorithm hmac-sha256;
    secret "YOUR_SECRET_HERE";
};
EOF

# Test update
cat > /tmp/update.txt << 'EOF'
server 10.10.20.71
zone home.lewelly.com
update add test.home.lewelly.com 300 A 10.10.20.99
send
EOF

nsupdate -k /tmp/tsig.conf /tmp/update.txt
dig @10.10.20.71 test.home.lewelly.com A +short
```

### Check External-DNS Logs

```bash
kubectl logs -n external-dns deployment/external-dns -f
```

### Verify DNS Resolution

```bash
# Query specific records
dig @10.10.20.71 grafana.home.lewelly.com A +short

# Check zone SOA
dig @10.10.20.71 home.lewelly.com SOA +short
```

### Restart Technitium

```bash
ssh root@10.10.20.71 systemctl restart technitium-dns
```

## Ad Blocking

Ad blocking is configured via the Technitium blocklist feature. The cluster automatically syncs blocklists between nodes.

**Active blocklists:**

| List | URL |
|------|-----|
| Hagezi Pro | `https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/pro-onlydomains.txt` |
| StevenBlack (fakenews+gambling) | `https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling/hosts` |

To add/remove blocklists: Settings > Blocking > Block List URLs

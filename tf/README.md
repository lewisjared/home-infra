# OpenTofu Infrastructure for Proxmox

This directory contains terraform infrastructure code for managing VMs on the local Proxmox VE cluster.

## Prerequisites

### Required Tools

```bash
# OpenTofu
brew install opentofu

# Helm (for Cilium manifest generation)
brew install helm

# Talosctl (for cluster management)
brew install siderolabs/tap/talosctl
```

### Proxmox User Setup

A Terraform user with appropriate permissions must exist on the Proxmox cluster:

```bash
# On the Proxmox server
pveum role add TerraformProv -privs "Datastore.AllocateSpace Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt SDN.Use"
pveum user add terraform-prov@pve --password <password>
pveum aclmod / -user terraform-prov@pve -role TerraformProv
```

### Environment Variables

Set credentials in your shell or `.env` file (sourced before running tofu):

```bash
export PROXMOX_VE_ENDPOINT="https://pve.lewelly.com"
export PROXMOX_VE_USERNAME="terraform-prov@pve"
export PROXMOX_VE_PASSWORD="<password>"
```

### Network Prerequisites

1. **OPNsense VLAN 50** configured with:
   - Interface IP: 10.10.20.1/24
   - Firewall rules allowing intra-VLAN traffic

2. **Proxmox bridge** VLAN-awareness enabled:

   ```bash
   # In /etc/network/interfaces on each Proxmox node
   bridge-vlan-aware yes
   ```

## Quick Start

```bash
# 1. Source environment variables
source ../.env

# 2. Initialize OpenTofu
tofu init

# 3. Validate configuration
tofu validate

# 4. Preview changes
tofu plan -out=tfplan

# 5. Apply infrastructure
tofu apply tfplan

# 6. Use the cluster
export KUBECONFIG=output/kubeconfig
kubectl get nodes
```

## Directory Structure

```
tf/
├── versions.tf              # Provider version constraints
├── providers.tf             # Provider configuration
├── variables.tf             # Configurable variables
├── main.tf                  # Root module (cluster instantiation)
├── outputs.tf               # Output values
├── modules/
│   ├── proxmox-vm/         # Reusable VM module
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── talos-cluster/      # Talos Kubernetes cluster
│       ├── main.tf         # VM creation
│       ├── variables.tf
│       ├── outputs.tf
│       ├── image.tf        # Talos image factory
│       ├── secrets.tf      # Machine secrets
│       ├── config.tf       # Machine configuration
│       └── bootstrap.tf    # Cluster bootstrap
├── manifests/
│   └── cilium/
│       ├── cilium-values.yaml    # Helm values
│       └── cilium-install.yaml   # Generated manifest
└── output/                 # Generated configs (gitignored)
    ├── kubeconfig
    └── talosconfig
```

## Cluster Configuration

### Default Topology

| VM Name | Role | Proxmox Host | IP Address |
|---------|------|--------------|------------|
| talos-master-1 | Control Plane | churro | 10.10.20.11 |
| talos-master-2 | Control Plane | nacho | 10.10.20.12 |
| talos-master-3 | Control Plane | tamale | 10.10.20.13 |
| talos-worker-1 | Worker | nacho | 10.10.20.21 |
| talos-worker-2 | Worker | tamale | 10.10.20.22 |

### Customization

Override defaults in a `terraform.tfvars` file:

```hcl
# Custom cluster name
cluster_name = "my-cluster"

# Custom node resources
worker_cpu_cores = 16
worker_memory_mb = 32768
worker_disk_gb   = 100

# Custom node distribution
control_plane_nodes = {
  "cp-1" = {
    proxmox_node = "host1"
    ip_address   = "10.10.20.11"
    vm_id        = 201
  }
  # ...
}
```

## Operations

### Accessing the Cluster

```bash
# Kubernetes
export KUBECONFIG=output/kubeconfig
kubectl get nodes -o wide
kubectl get pods -A

# Talos
export TALOSCONFIG=output/talosconfig
talosctl health
talosctl get members
talosctl logs kubelet -n 10.50.0.11
```

### Updating Cilium

```bash
# Regenerate manifest with new version
helm template cilium cilium/cilium \
  --version 1.17.0 \
  --namespace kube-system \
  -f manifests/cilium/cilium-values.yaml > manifests/cilium/cilium-install.yaml

# Re-apply the cluster
tofu apply
```

### Upgrading Talos

```bash
# Update talos_version in variables.tf or tfvars
talos_version = "v1.10.0"

# Plan and apply
tofu plan -out=tfplan
tofu apply tfplan
```

### Destroying the Cluster

```bash
tofu destroy
```

## Troubleshooting

### VM Not Starting

Check Proxmox logs:

```bash
ssh root@<proxmox-node> journalctl -u pve-guests -f
```

### Talos Configuration Not Applied

Check Talos logs:

```bash
talosctl -n <ip> dmesg | tail -50
talosctl -n <ip> logs controller-runtime
```

### Network Connectivity Issues

1. Verify VLAN is configured on OPNsense
2. Check Proxmox bridge has `bridge-vlan-aware yes`
3. Test from within a VM: `talosctl -n <ip> netstat`

### Cilium Issues

```bash
kubectl -n kube-system get pods -l app.kubernetes.io/name=cilium
kubectl -n kube-system logs -l app.kubernetes.io/name=cilium-agent
```

## References

- [Talos Linux Documentation](https://www.talos.dev/)
- [bpg/proxmox Provider](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- [siderolabs/talos Provider](https://registry.terraform.io/providers/siderolabs/talos/latest/docs)
- [Cilium on Talos](https://www.talos.dev/v1.9/kubernetes-guides/network/deploying-cilium/)

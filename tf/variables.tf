# =============================================================================
# Proxmox Connection
# =============================================================================

variable "proxmox_endpoint" {
  type        = string
  description = "Proxmox VE API endpoint"
  default     = "https://10.10.10.10:8006"
}

variable "proxmox_insecure" {
  type        = bool
  description = "Skip TLS verification (use only for self-signed certs)"
  default     = true
}

variable "proxmox_ssh_user" {
  type        = string
  description = "SSH username for Proxmox nodes (used for file uploads)"
  default     = "root"
}

# =============================================================================
# Cluster Configuration
# =============================================================================

variable "cluster_name" {
  type        = string
  description = "Name of the Talos Kubernetes cluster"
  default     = "home-prod"
}

variable "cluster_endpoint" {
  type        = string
  description = "Kubernetes API endpoint (VIP or first control plane IP)"
  default     = "https://10.10.20.51:6443"
}

variable "kubeconfig_context_name" {
  type        = string
  description = "Context name in generated kubeconfig (defaults to admin@cluster_name)"
  default     = "home-prod"
}

variable "talos_version" {
  type        = string
  description = "Talos Linux version"
  # keep in sync with apps/production/core/tuppr/talos-upgrade.yaml -> spec.talos.version
  # renovate: datasource=docker depName=ghcr.io/siderolabs/installer
  default = "v1.12.8"
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version"
  # keep in sync with apps/production/core/tuppr/kubernetes-upgrade.yaml -> spec.kubernetes.version
  # renovate: datasource=docker depName=ghcr.io/siderolabs/kubelet
  default = "v1.35.4"
}

# =============================================================================
# Network Configuration
# =============================================================================

variable "network_gateway" {
  type        = string
  description = "Default gateway for Talos nodes"
  default     = "10.10.20.1"
}

variable "network_nameservers" {
  type        = list(string)
  description = "DNS nameservers"
  default     = ["10.10.20.1"]
  # description = "DNS nameservers (Technitium HA cluster)"
  # default     = ["10.10.20.71", "10.10.20.72"]
}

variable "network_vlan_id" {
  type        = number
  description = "VLAN ID for Talos network"
  default     = 20
}

variable "network_bridge" {
  type        = string
  description = "Proxmox network bridge"
  default     = "vmbr0"
}

variable "network_cidr" {
  type        = string
  description = "Network CIDR suffix (e.g., /24)"
  default     = "/24"
}

# =============================================================================
# VLAN Definitions
# =============================================================================

variable "vlans" {
  type = map(object({
    id      = number
    name    = string
    comment = string
  }))
  description = "VLAN definitions for Proxmox host networking"
  default = {
    "vlan10" = {
      id      = 10
      name    = "vlan10"
      comment = "Management network"
    }
    "vlan20" = {
      id      = 20
      name    = "vlan20"
      comment = "Infrastructure network (K8s, VMs)"
    }
    "vlan30" = {
      id      = 30
      name    = "vlan30"
      comment = "Storage network (isolated L2) for Ceph and NFS"
    }
    "vlan40" = {
      id      = 40
      name    = "vlan40"
      comment = "LAN network for trusted devices"
    }
    "vlan50" = {
      id      = 50
      name    = "vlan50"
      comment = "IOT network"
    }
    "vlan90" = {
      id      = 90
      name    = "vlan90"
      comment = "Guest network"
    }
  }
}

variable "ceph_vlan_id" {
  type        = number
  description = "VLAN ID for Ceph storage network (for Talos VM NICs)"
  default     = 30
}

# =============================================================================
# Proxmox Host Definitions
# =============================================================================

variable "proxmox_hosts" {
  type = map(object({
    default_interface = string # Default parent interface for VLANs (e.g., "vmbr0")
    vlans = map(object({
      ip        = string
      interface = optional(string) # Override interface for this VLAN (e.g., dedicated NIC for storage)
    }))
  }))
  description = "Proxmox host definitions with per-VLAN IP and optional interface override"
  default = {
    "churro" = {
      default_interface = "vmbr0"
      vlans = {
        "10" = { ip = "10.10.10.10/24" }
        "20" = { ip = "10.10.20.10/24" }
        "30" = { ip = "10.10.30.10/24" }
      }
    }
    "mole" = {
      default_interface = "vmbr0"
      vlans = {
        "10" = { ip = "10.10.10.11/24" }
        "20" = { ip = "10.10.20.11/24" }
        "30" = { ip = "10.10.30.11/24" }
      }
    }
    "taco" = {
      default_interface = "vmbr0"
      vlans = {
        "10" = { ip = "10.10.10.12/24" }
        "20" = { ip = "10.10.20.12/24" }
        "30" = { ip = "10.10.30.12/24" }
      }
    }
    "nacho" = {
      default_interface = "vmbr0"
      vlans = {
        "10" = { ip = "10.10.10.13/24" }
        "20" = { ip = "10.10.20.13/24" }
        "30" = { ip = "10.10.30.13/24" }
      }
    }
    "tamale" = {
      default_interface = "vmbr0"
      vlans = {
        "10" = { ip = "10.10.10.14/24" }
        "20" = { ip = "10.10.20.14/24" }
        "30" = { ip = "10.10.30.14/24" }
      }
    }
  }
}

# =============================================================================
# Talos Node Definitions
# =============================================================================

# Dual-role nodes: every node is a control-plane/etcd member that also runs workloads.
# One Talos VM per physical compute host.
variable "control_plane_nodes" {
  type = map(object({
    proxmox_node     = string
    ip_address       = string
    mac_address      = string
    ceph_ip_address  = optional(string) # IP on Ceph VLAN 30
    ceph_mac_address = optional(string) # MAC for Ceph NIC
    vm_id            = optional(number)
    cpu_cores        = number
    memory_mb        = number
    disk_gb          = number
    gpu_enabled      = optional(bool, false)        # Enable AMD iGPU passthrough
    node_labels      = optional(map(string), {})    # Extra Talos nodeLabels (durable across rebuilds)
    hostpci_devices = optional(list(object({
      device  = string
      mapping = optional(string)
      id      = optional(string)
      pcie    = optional(bool, true)
      rombar  = optional(bool, true)
      xvga    = optional(bool, false)
    })), [])
  }))
  description = "Node definitions"
  default = {
    "talos-master-1" = {
      proxmox_node     = "nacho"
      ip_address       = "10.10.20.51"
      mac_address      = "BC:24:11:20:01:51"
      ceph_ip_address  = "10.10.30.51"
      ceph_mac_address = "BC:24:11:30:01:51"
      vm_id            = 201
      # Host: 32 cores, 61942 MB.
      # Reserve ~2 cores and ~12 GB for PVE + Ceph MON/MGR/OSD (osd.2).
      cpu_cores       = 30
      memory_mb       = 52000
      disk_gb         = 100
      gpu_enabled     = true
      hostpci_devices = [{ device = "hostpci0", mapping = "igpu" }]
    }
    "talos-master-2" = {
      proxmox_node     = "tamale"
      ip_address       = "10.10.20.52"
      mac_address      = "BC:24:11:20:01:52"
      ceph_ip_address  = "10.10.30.52"
      ceph_mac_address = "BC:24:11:30:01:52"
      vm_id            = 202
      # Host: 32 cores, 61942 MB.
      # Reserve ~2 cores and ~12 GB for PVE + Ceph MON/MGR/OSD (osd.3).
      cpu_cores       = 30
      memory_mb       = 52000
      disk_gb         = 100
      gpu_enabled     = true
      hostpci_devices = [{ device = "hostpci0", mapping = "igpu" }]
    }
    "talos-master-3" = {
      proxmox_node     = "churro"
      ip_address       = "10.10.20.53"
      mac_address      = "BC:24:11:20:01:53"
      ceph_ip_address  = "10.10.30.53"
      ceph_mac_address = "BC:24:11:30:01:53"
      vm_id            = 203
      # Host: 16 cores, 93363 MB. Ceph MON only (no local OSD).
      # Reserve ~2 cores and ~10 GB for PVE + Ceph MON.
      cpu_cores = 14
      memory_mb = 83000
      disk_gb   = 100
      # esphome is pinned here (hostNetwork) so its source IP is predictable for
      # the OPNsense VLAN20->VLAN50 rule. See apps/production/apps/esphome.
      node_labels = { esphome = "true" }
    }
  }
}

variable "storage_pool" {
  type        = string
  description = "Proxmox storage pool for VM disks"
  default     = "local-lvm"
}

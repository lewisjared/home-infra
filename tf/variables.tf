# =============================================================================
# Proxmox Connection
# =============================================================================

variable "proxmox_endpoint" {
  type        = string
  description = "Proxmox VE API endpoint"
  default     = "https://pve.lewelly.com"
}

variable "proxmox_insecure" {
  type        = bool
  description = "Skip TLS verification (use only for self-signed certs)"
  default     = false
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
  default     = "v1.11.5"
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version"
  default     = "v1.34.2"
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
    default_interface = string  # Default parent interface for VLANs (e.g., "vmbr0")
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
      # Taco does not need VLAN 30 configured
      # This will help keep all VLAN traffic over the 10GbE NICs
      vlans = {
        "10" = { ip = "10.10.10.12/24" }
        "20" = { ip = "10.10.20.12/24" }
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

variable "control_plane_nodes" {
  type = map(object({
    proxmox_node     = string
    ip_address       = string
    mac_address      = string
    ceph_ip_address  = optional(string) # IP on Ceph VLAN 30
    ceph_mac_address = optional(string) # MAC for Ceph NIC
    vm_id            = optional(number)
    cpu_cores        = optional(number)
    memory_mb        = optional(number)
    disk_gb          = optional(number)
  }))
  description = "Control plane node definitions"
  default = {
    "talos-master-1" = {
      proxmox_node     = "nacho"
      ip_address       = "10.10.20.51"
      mac_address      = "BC:24:11:20:01:51"
      ceph_ip_address  = "10.10.30.51"
      ceph_mac_address = "BC:24:11:30:01:51"
      vm_id            = 201
    }
    "talos-master-2" = {
      proxmox_node     = "tamale"
      ip_address       = "10.10.20.52"
      mac_address      = "BC:24:11:20:01:52"
      ceph_ip_address  = "10.10.30.52"
      ceph_mac_address = "BC:24:11:30:01:52"
      vm_id            = 202
    }
    "talos-master-3" = {
      proxmox_node     = "churro"
      ip_address       = "10.10.20.53"
      mac_address      = "BC:24:11:20:01:53"
      ceph_ip_address  = "10.10.30.53"
      ceph_mac_address = "BC:24:11:30:01:53"
      vm_id            = 203
    }
  }
}

variable "worker_nodes" {
  type = map(object({
    proxmox_node     = string
    ip_address       = string
    mac_address      = string
    ceph_ip_address  = optional(string) # IP on Ceph VLAN 30
    ceph_mac_address = optional(string) # MAC for Ceph NIC
    vm_id            = optional(number)
    cpu_cores        = optional(number)
    memory_mb        = optional(number)
    disk_gb          = optional(number)
  }))
  description = "Worker node definitions"
  default = {
    "talos-worker-1" = {
      proxmox_node     = "nacho"
      ip_address       = "10.10.20.61"
      mac_address      = "BC:24:11:20:02:61"
      ceph_ip_address  = "10.10.30.61"
      ceph_mac_address = "BC:24:11:30:02:61"
      vm_id            = 211
    }
    "talos-worker-2" = {
      proxmox_node     = "tamale"
      ip_address       = "10.10.20.62"
      mac_address      = "BC:24:11:20:02:62"
      ceph_ip_address  = "10.10.30.62"
      ceph_mac_address = "BC:24:11:30:02:62"
      vm_id            = 212
    }
  }
}

# =============================================================================
# Default Resource Specifications
# =============================================================================

variable "controlplane_cpu_cores" {
  type        = number
  description = "Default CPU cores for control plane nodes"
  default     = 4
}

variable "controlplane_memory_mb" {
  type        = number
  description = "Default memory in MB for control plane nodes"
  default     = 4096
}

variable "controlplane_disk_gb" {
  type        = number
  description = "Default disk size in GB for control plane nodes"
  default     = 20
}

variable "worker_cpu_cores" {
  type        = number
  description = "Default CPU cores for worker nodes"
  default     = 8
}

variable "worker_memory_mb" {
  type        = number
  description = "Default memory in MB for worker nodes"
  default     = 16384
}

variable "worker_disk_gb" {
  type        = number
  description = "Default disk size in GB for worker nodes"
  default     = 50
}

variable "storage_pool" {
  type        = string
  description = "Proxmox storage pool for VM disks"
  default     = "local-lvm"
}

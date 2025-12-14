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
  default     = "talos-home"
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
# Node Definitions
# =============================================================================

variable "control_plane_nodes" {
  type = map(object({
    proxmox_node = string
    ip_address   = string
    mac_address  = string
    vm_id        = optional(number)
    cpu_cores    = optional(number)
    memory_mb    = optional(number)
    disk_gb      = optional(number)
  }))
  description = "Control plane node definitions"
  default = {

    "talos-master-1" = {
      proxmox_node = "nacho"
      ip_address   = "10.10.20.51"
      mac_address  = "BC:24:11:20:01:51"
      vm_id        = 201
    }
    "talos-master-2" = {
      proxmox_node = "tamale"
      ip_address   = "10.10.20.52"
      mac_address  = "BC:24:11:20:01:52"
      vm_id        = 202
    }
    "talos-master-3" = {
      proxmox_node = "churro"
      ip_address   = "10.10.20.53"
      mac_address  = "BC:24:11:20:01:53"
      vm_id        = 203
    }
  }
}

variable "worker_nodes" {
  type = map(object({
    proxmox_node = string
    ip_address   = string
    mac_address  = string
    vm_id        = optional(number)
    cpu_cores    = optional(number)
    memory_mb    = optional(number)
    disk_gb      = optional(number)
  }))
  description = "Worker node definitions"
  default = {
    "talos-worker-1" = {
      proxmox_node = "nacho"
      ip_address   = "10.10.20.61"
      mac_address  = "BC:24:11:20:02:61"
      vm_id        = 211
    }
    "talos-worker-2" = {
      proxmox_node = "tamale"
      ip_address   = "10.10.20.62"
      mac_address  = "BC:24:11:20:02:62"
      vm_id        = 212
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

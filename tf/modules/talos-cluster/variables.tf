variable "cluster_name" {
  type        = string
  description = "Name of the Talos cluster"
}

variable "kubeconfig_context_name" {
  type        = string
  description = "Context name to use in the generated kubeconfig"
  default     = null
}

variable "cluster_endpoint" {
  type        = string
  description = "Kubernetes API endpoint URL"
}

variable "talos_version" {
  type        = string
  description = "Talos Linux version"
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version"
}

variable "network_gateway" {
  type        = string
  description = "Network gateway IP"
}

variable "network_nameservers" {
  type        = list(string)
  description = "DNS nameservers"
}

variable "network_vlan_id" {
  type        = number
  description = "VLAN ID"
}

variable "network_bridge" {
  type        = string
  description = "Proxmox network bridge"
}

variable "network_cidr" {
  type        = string
  description = "Network CIDR suffix"
  default     = "/24"
}

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
}

variable "controlplane_cpu_cores" {
  type        = number
  description = "Default CPU cores for control plane"
}

variable "controlplane_memory_mb" {
  type        = number
  description = "Default memory for control plane"
}

variable "controlplane_disk_gb" {
  type        = number
  description = "Default disk size for control plane"
}

variable "worker_cpu_cores" {
  type        = number
  description = "Default CPU cores for workers"
}

variable "worker_memory_mb" {
  type        = number
  description = "Default memory for workers"
}

variable "worker_disk_gb" {
  type        = number
  description = "Default disk size for workers"
}

variable "storage_pool" {
  type        = string
  description = "Proxmox storage pool"
}

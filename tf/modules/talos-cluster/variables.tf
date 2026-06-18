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

# Ceph storage network configuration
variable "ceph_vlan_id" {
  type        = number
  description = "VLAN ID for Ceph storage network (null to disable)"
  default     = null
}

variable "ceph_cidr" {
  type        = string
  description = "CIDR suffix for Ceph network"
  default     = "/24"
}

# Dual-role nodes: every node is a control-plane/etcd member that also runs
# workloads (machine config sets allowSchedulingOnControlPlanes = true).
# Sizing is mandatory per node — there are no resource defaults.
variable "control_plane_nodes" {
  type = map(object({
    proxmox_node     = string
    ip_address       = string
    mac_address      = string
    ceph_ip_address  = optional(string) # IP on Ceph VLAN (e.g., "10.10.30.51")
    ceph_mac_address = optional(string) # MAC for Ceph NIC
    vm_id            = optional(number)
    cpu_cores        = number
    memory_mb        = number
    disk_gb          = number
    gpu_enabled      = optional(bool, false)     # Enable AMD iGPU passthrough
    node_labels      = optional(map(string), {}) # Extra Talos nodeLabels (durable across rebuilds)
    hostpci_devices = optional(list(object({
      device  = string
      mapping = optional(string)
      id      = optional(string)
      pcie    = optional(bool, true)
      rombar  = optional(bool, true)
      xvga    = optional(bool, false)
    })), [])
  }))
  description = "Dual-role control-plane/worker node definitions"
}

variable "storage_pool" {
  type        = string
  description = "Proxmox storage pool"
}

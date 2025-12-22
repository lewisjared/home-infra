variable "hostname" {
  type        = string
  description = "Container hostname"
}

variable "vm_id" {
  type        = number
  description = "Proxmox container ID"
  default     = null
}

variable "proxmox_node" {
  type        = string
  description = "Proxmox node to create container on"
}

variable "cpu_cores" {
  type        = number
  description = "Number of CPU cores"
  default     = 1
}

variable "memory_mb" {
  type        = number
  description = "Memory in MB"
  default     = 512
}

variable "swap_mb" {
  type        = number
  description = "Swap in MB"
  default     = 512
}

variable "disk_size_gb" {
  type        = number
  description = "Root disk size in GB"
  default     = 8
}

variable "storage_pool" {
  type        = string
  description = "Storage pool for container disk"
  default     = "local-lvm"
}

variable "template_file_id" {
  type        = string
  description = "LXC template file ID (e.g., local:vztmpl/debian-13-standard_13.0-1_amd64.tar.zst)"
}

variable "network_bridge" {
  type        = string
  description = "Network bridge"
  default     = "vmbr0"
}

variable "vlan_id" {
  type        = number
  description = "VLAN ID (null for untagged)"
  default     = null
}

variable "ip_address" {
  type        = string
  description = "Static IP address with CIDR (e.g., 10.10.20.71/24)"
}

variable "gateway" {
  type        = string
  description = "Default gateway IP address"
}

variable "dns_servers" {
  type        = list(string)
  description = "DNS server IP addresses"
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "dns_domain" {
  type        = string
  description = "DNS search domain"
  default     = null
}

variable "unprivileged" {
  type        = bool
  description = "Run as unprivileged container"
  default     = true
}

variable "on_boot" {
  type        = bool
  description = "Start container on host boot"
  default     = true
}

variable "started" {
  type        = bool
  description = "Start container after creation"
  default     = true
}

variable "tags" {
  type        = list(string)
  description = "Tags to apply to container"
  default     = []
}

variable "description" {
  type        = string
  description = "Container description"
  default     = "Managed by OpenTofu"
}

variable "ssh_public_keys" {
  type        = list(string)
  description = "SSH public keys for root user"
  default     = []
}

variable "name" {
  type        = string
  description = "VM name"
}

variable "vm_id" {
  type        = number
  description = "Proxmox VM ID"
  default     = null
}

variable "proxmox_node" {
  type        = string
  description = "Proxmox node to create VM on"
}

variable "cpu_cores" {
  type        = number
  description = "Number of CPU cores"
  default     = 2
}

variable "memory_mb" {
  type        = number
  description = "Memory in MB"
  default     = 2048
}

variable "disk_size_gb" {
  type        = number
  description = "Boot disk size in GB"
  default     = 20
}

variable "storage_pool" {
  type        = string
  description = "Storage pool for disks"
  default     = "local-lvm"
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

variable "boot_disk_image_id" {
  type        = string
  description = "Disk image ID to import for boot"
}

variable "machine_type" {
  type        = string
  description = "QEMU machine type"
  default     = "q35"
}

variable "bios_type" {
  type        = string
  description = "BIOS type (seabios or ovmf)"
  default     = "seabios"
}

variable "qemu_agent" {
  type        = bool
  description = "Enable QEMU guest agent"
  default     = true
}

variable "on_boot" {
  type        = bool
  description = "Start VM on host boot"
  default     = true
}

variable "started" {
  type        = bool
  description = "Start VM after creation"
  default     = true
}

variable "tags" {
  type        = list(string)
  description = "Tags to apply to VM"
  default     = []
}

variable "description" {
  type        = string
  description = "VM description"
  default     = "Managed by OpenTofu"
}

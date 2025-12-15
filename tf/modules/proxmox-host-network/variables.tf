# =============================================================================
# Proxmox Host VLAN Configuration
# =============================================================================

variable "vlans" {
  type = map(object({
    id      = number
    name    = string
    comment = string
  }))
  description = "VLAN definitions to create on each host"
}

variable "proxmox_hosts" {
  type = map(object({
    default_interface = string  # Default parent interface for VLANs
    vlans = map(object({
      ip        = string
      interface = optional(string) # Override interface for this VLAN
    }))
  }))
  description = "Proxmox host definitions with per-VLAN IP and optional interface override"
}

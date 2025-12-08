output "vm_id" {
  description = "The VM ID"
  value       = proxmox_virtual_environment_vm.this.vm_id
}

output "name" {
  description = "The VM name"
  value       = proxmox_virtual_environment_vm.this.name
}

output "ipv4_address" {
  description = "The primary IPv4 address (from QEMU agent)"
  value       = try(proxmox_virtual_environment_vm.this.ipv4_addresses[1][0], null)
}

output "mac_address" {
  description = "The MAC address of the first network interface"
  value       = proxmox_virtual_environment_vm.this.network_device[0].mac_address
}

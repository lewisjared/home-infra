output "container_id" {
  description = "The Proxmox container ID"
  value       = proxmox_virtual_environment_container.this.vm_id
}

output "hostname" {
  description = "The container hostname"
  value       = var.hostname
}

output "ip_address" {
  description = "The container IP address (without CIDR)"
  value       = split("/", var.ip_address)[0]
}

output "kubeconfig" {
  description = "Kubeconfig for kubectl access"
  value       = module.talos_cluster.kubeconfig
  sensitive   = true
}

output "talosconfig" {
  description = "Talosconfig for talosctl access"
  value       = module.talos_cluster.talosconfig
  sensitive   = true
}

output "node_ips" {
  description = "Talos node IP addresses"
  value       = module.talos_cluster.node_ips
}

output "node_vm_ids" {
  description = "Talos node VM IDs"
  value       = module.talos_cluster.node_vm_ids
}

output "proxmox_vlan_interfaces" {
  description = "VLAN interfaces on Proxmox hosts"
  value       = module.proxmox_host_network.vlan_interfaces_by_host
}

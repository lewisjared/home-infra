output "kubeconfig" {
  description = "Kubeconfig for kubectl access"
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "talosconfig" {
  description = "Talosconfig for talosctl access"
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "node_ips" {
  description = "Talos node IP addresses"
  value       = { for k, v in var.control_plane_nodes : k => v.ip_address }
}

output "node_vm_ids" {
  description = "Talos node VM IDs"
  value       = { for k, v in module.controlplane_vms : k => v.vm_id }
}

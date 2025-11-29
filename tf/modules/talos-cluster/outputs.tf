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

output "control_plane_ips" {
  description = "Control plane node IP addresses"
  value       = { for k, v in var.control_plane_nodes : k => v.ip_address }
}

output "worker_ips" {
  description = "Worker node IP addresses"
  value       = { for k, v in var.worker_nodes : k => v.ip_address }
}

output "control_plane_vm_ids" {
  description = "Control plane VM IDs"
  value       = { for k, v in module.controlplane_vms : k => v.vm_id }
}

output "worker_vm_ids" {
  description = "Worker VM IDs"
  value       = { for k, v in module.worker_vms : k => v.vm_id }
}

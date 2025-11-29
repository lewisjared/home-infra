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

output "control_plane_ips" {
  description = "Control plane node IP addresses"
  value       = module.talos_cluster.control_plane_ips
}

output "worker_ips" {
  description = "Worker node IP addresses"
  value       = module.talos_cluster.worker_ips
}

output "control_plane_vm_ids" {
  description = "Control plane VM IDs"
  value       = module.talos_cluster.control_plane_vm_ids
}

output "worker_vm_ids" {
  description = "Worker VM IDs"
  value       = module.talos_cluster.worker_vm_ids
}

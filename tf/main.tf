# Talos Kubernetes Cluster on Proxmox VE
module "talos_cluster" {
  source = "./modules/talos-cluster"

  # Cluster configuration
  cluster_name            = var.cluster_name
  cluster_endpoint        = var.cluster_endpoint
  kubeconfig_context_name = var.kubeconfig_context_name
  talos_version           = var.talos_version
  kubernetes_version      = var.kubernetes_version

  # Network configuration
  network_gateway     = var.network_gateway
  network_nameservers = var.network_nameservers
  network_vlan_id     = var.network_vlan_id
  network_bridge      = var.network_bridge
  network_cidr        = var.network_cidr

  # Node definitions
  control_plane_nodes = var.control_plane_nodes
  worker_nodes        = var.worker_nodes

  # Resource specifications
  controlplane_cpu_cores = var.controlplane_cpu_cores
  controlplane_memory_mb = var.controlplane_memory_mb
  controlplane_disk_gb   = var.controlplane_disk_gb
  worker_cpu_cores       = var.worker_cpu_cores
  worker_memory_mb       = var.worker_memory_mb
  worker_disk_gb         = var.worker_disk_gb
  storage_pool           = var.storage_pool
}

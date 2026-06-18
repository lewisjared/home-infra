# =============================================================================
# Proxmox Host Network Configuration (VLANs 10, 20, 30)
# =============================================================================
module "proxmox_host_network" {
  source = "./modules/proxmox-host-network"

  vlans         = var.vlans
  proxmox_hosts = var.proxmox_hosts
}

# =============================================================================
# Talos Kubernetes Cluster on Proxmox VE
# =============================================================================
module "talos_cluster" {
  source = "./modules/talos-cluster"

  # Cluster configuration
  cluster_name            = var.cluster_name
  cluster_endpoint        = var.cluster_endpoint
  kubeconfig_context_name = var.kubeconfig_context_name
  talos_version           = var.talos_version
  kubernetes_version      = var.kubernetes_version

  # Primary network configuration (Kubernetes - VLAN 20)
  network_gateway     = var.network_gateway
  network_nameservers = var.network_nameservers
  network_vlan_id     = var.network_vlan_id
  network_bridge      = var.network_bridge
  network_cidr        = var.network_cidr

  # Ceph storage network configuration (VLAN 30)
  ceph_vlan_id = var.ceph_vlan_id
  ceph_cidr    = var.network_cidr # Same /24 CIDR for VLAN 30

  # Node definitions
  control_plane_nodes = var.control_plane_nodes
  storage_pool        = var.storage_pool
}

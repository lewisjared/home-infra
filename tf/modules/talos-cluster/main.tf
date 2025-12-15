# Create control plane VMs
module "controlplane_vms" {
  source   = "../proxmox-vm"
  for_each = var.control_plane_nodes

  name         = each.key
  vm_id        = each.value.vm_id
  proxmox_node = each.value.proxmox_node

  cpu_cores    = coalesce(each.value.cpu_cores, var.controlplane_cpu_cores)
  memory_mb    = coalesce(each.value.memory_mb, var.controlplane_memory_mb)
  disk_size_gb = coalesce(each.value.disk_gb, var.controlplane_disk_gb)
  storage_pool = var.storage_pool

  # Primary NIC - Kubernetes network
  network_bridge = var.network_bridge
  vlan_id        = var.network_vlan_id
  mac_address    = each.value.mac_address

  # Secondary NIC - Ceph storage network
  ceph_vlan_id     = var.ceph_vlan_id
  ceph_mac_address = each.value.ceph_mac_address

  iso_file_id = proxmox_virtual_environment_download_file.talos_iso[each.value.proxmox_node].id

  qemu_agent  = true
  on_boot     = true
  started     = true
  tags        = ["talos", "kubernetes", "controlplane"]
  description = "Talos Kubernetes control plane - Managed by OpenTofu"
}

# Create worker VMs
module "worker_vms" {
  source   = "../proxmox-vm"
  for_each = var.worker_nodes

  name         = each.key
  vm_id        = each.value.vm_id
  proxmox_node = each.value.proxmox_node

  cpu_cores    = coalesce(each.value.cpu_cores, var.worker_cpu_cores)
  memory_mb    = coalesce(each.value.memory_mb, var.worker_memory_mb)
  disk_size_gb = coalesce(each.value.disk_gb, var.worker_disk_gb)
  storage_pool = var.storage_pool

  # Primary NIC - Kubernetes network
  network_bridge = var.network_bridge
  vlan_id        = var.network_vlan_id
  mac_address    = each.value.mac_address

  # Secondary NIC - Ceph storage network
  ceph_vlan_id     = var.ceph_vlan_id
  ceph_mac_address = each.value.ceph_mac_address

  iso_file_id = proxmox_virtual_environment_download_file.talos_iso[each.value.proxmox_node].id

  qemu_agent  = true
  on_boot     = true
  started     = true
  tags        = ["talos", "kubernetes", "worker"]
  description = "Talos Kubernetes worker - Managed by OpenTofu"
}

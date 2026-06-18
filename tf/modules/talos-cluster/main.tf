# Create the dual-role Talos VMs (one per physical compute host)
module "controlplane_vms" {
  source   = "../proxmox-vm"
  for_each = var.control_plane_nodes

  name         = each.key
  vm_id        = each.value.vm_id
  proxmox_node = each.value.proxmox_node

  cpu_cores    = each.value.cpu_cores
  memory_mb    = each.value.memory_mb
  disk_size_gb = each.value.disk_gb
  storage_pool = var.storage_pool

  # Primary NIC - Kubernetes network
  network_bridge = var.network_bridge
  vlan_id        = var.network_vlan_id
  mac_address    = each.value.mac_address

  # Secondary NIC - Ceph storage network
  ceph_vlan_id     = var.ceph_vlan_id
  ceph_mac_address = each.value.ceph_mac_address

  iso_file_id = proxmox_download_file.talos_iso[each.value.proxmox_node].id

  # GPU passthrough needs OVMF/UEFI for correct 64-bit BAR mapping;
  # SeaBIOS mis-maps the iGPU aperture and amdgpu panics on boot.
  bios_type = each.value.gpu_enabled ? "ovmf" : "seabios"

  # PCI passthrough (e.g., iGPU for hardware encoding)
  hostpci_devices = each.value.hostpci_devices

  qemu_agent  = true
  on_boot     = true
  started     = true
  tags        = ["talos", "kubernetes", "controlplane"]
  description = "Talos node - Managed by OpenTofu"
}

resource "proxmox_virtual_environment_vm" "this" {
  name        = var.name
  description = var.description
  tags        = var.tags

  node_name = var.proxmox_node
  vm_id     = var.vm_id

  machine = var.machine_type
  bios    = var.bios_type
  on_boot = var.on_boot
  started = var.started

  # Graceful shutdown for Talos
  stop_on_destroy = true

  # Boot from disk first, not network
  boot_order = ["scsi0"]

  agent {
    enabled = var.qemu_agent
  }

  cpu {
    cores = var.cpu_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.memory_mb
  }

  # Boot disk from image
  disk {
    datastore_id = var.storage_pool
    file_id      = var.boot_disk_image_id
    interface    = "scsi0"
    iothread     = true
    discard      = "on"
    size         = var.disk_size_gb
    ssd          = true
  }

  network_device {
    bridge  = var.network_bridge
    vlan_id = var.vlan_id
    model   = "virtio"
  }

  # SCSI controller
  scsi_hardware = "virtio-scsi-single"

  operating_system {
    type = "l26"
  }

  # Serial console for Talos
  serial_device {}

  lifecycle {
    ignore_changes = [
      disk[0].file_id,
    ]
  }
}

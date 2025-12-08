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

  # Boot from CD-ROM first (for initial install), then disk
  boot_order = [ "scsi0", "ide2",]

  agent {
    enabled = var.qemu_agent
  }

  cpu {
    cores = var.cpu_cores
    type  = "host"
  }

  memory {
    dedicated = var.memory_mb
  }

  # CD-ROM with Talos ISO
  cdrom {
    file_id   = var.iso_file_id
    interface = "ide2"
  }

  # Empty disk for Talos installation
  disk {
    datastore_id = var.storage_pool
    interface    = "scsi0"
    iothread     = true
    discard      = "on"
    size         = var.disk_size_gb
    ssd          = true
    file_format  = "raw"
  }

  network_device {
    bridge      = var.network_bridge
    vlan_id     = var.vlan_id
    model       = "virtio"
    mac_address = var.mac_address
  }

  # SCSI controller
  scsi_hardware = "virtio-scsi-single"

  operating_system {
    type = "l26"
  }

  # Serial console for Talos
  serial_device {}
}

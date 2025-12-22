resource "proxmox_virtual_environment_container" "this" {
  node_name   = var.proxmox_node
  vm_id       = var.vm_id
  description = var.description
  tags        = var.tags

  unprivileged = var.unprivileged
  start_on_boot = var.on_boot
  started      = var.started

  operating_system {
    template_file_id = var.template_file_id
    type             = "debian"
  }

  cpu {
    cores = var.cpu_cores
  }

  memory {
    dedicated = var.memory_mb
    swap      = var.swap_mb
  }

  disk {
    datastore_id = var.storage_pool
    size         = var.disk_size_gb
  }

  network_interface {
    name     = "eth0"
    bridge   = var.network_bridge
    vlan_id  = var.vlan_id
    firewall = false
  }

  initialization {
    hostname = var.hostname

    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
      domain  = var.dns_domain
    }

    user_account {
      keys = var.ssh_public_keys
    }
  }

  lifecycle {
    ignore_changes = [
      # Ignore changes to started state to prevent unnecessary restarts
      started,
    ]
  }
}

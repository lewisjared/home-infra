# Fetch QEMU guest agent extension version
data "talos_image_factory_extensions_versions" "this" {
  talos_version = var.talos_version
  filters = {
    names = ["qemu-guest-agent"]
  }
}

# Create schematic with QEMU guest agent for Proxmox integration
resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = data.talos_image_factory_extensions_versions.this.extensions_info[*].name
      }
    }
  })
}

# Get image URLs from Talos Image Factory
data "talos_image_factory_urls" "this" {
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "nocloud"
  architecture  = "amd64"
}

# Get unique list of Proxmox nodes that need the image
locals {
  proxmox_nodes = toset(distinct(concat(
    [for node in var.control_plane_nodes : node.proxmox_node],
    [for node in var.worker_nodes : node.proxmox_node]
  )))
}

# Download Talos image to each Proxmox node
resource "proxmox_virtual_environment_download_file" "talos_image" {
  for_each = local.proxmox_nodes

  content_type = "iso"
  datastore_id = "local"
  node_name    = each.key
  url          = data.talos_image_factory_urls.this.urls.disk_image
  file_name    = "talos-${var.talos_version}-nocloud-amd64.img"
  overwrite    = false
}

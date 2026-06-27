# Create schematic with QEMU guest agent and AMD GPU support.
# AMD ROCm on Ryzen iGPUs needs the firmware/ucode extension as well as the
# amdgpu extension. Bake the GPU memory tuning into the boot assets so it works
# for Talos v1.12 UKI-style boots and future node reinstalls/upgrades.
resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      extraKernelArgs = [
        # Let ROCm map a larger slice of host RAM as GPU-accessible GTT/TTM
        # memory for iGPU compute workloads. Values are in MiB/pages.
        "amdgpu.gttsize=49152",     # 48 GiB GTT on the 52 GiB GPU nodes
        "ttm.pages_limit=12582912", # 48 GiB / 4 KiB pages
      ]
      systemExtensions = {
        officialExtensions = [
          "siderolabs/qemu-guest-agent",
          "siderolabs/amd-ucode",
          "siderolabs/amdgpu",
          "siderolabs/iscsi-tools",
          "siderolabs/util-linux-tools",
        ]
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
  proxmox_nodes = toset([for node in var.control_plane_nodes : node.proxmox_node])
}

# Download Talos ISO to each Proxmox node
resource "proxmox_download_file" "talos_iso" {
  for_each = local.proxmox_nodes

  content_type = "iso"
  datastore_id = "local"
  node_name    = each.key
  url          = data.talos_image_factory_urls.this.urls.iso
  file_name    = "talos-${var.talos_version}-${talos_image_factory_schematic.this.id}-nocloud-amd64.iso"
  overwrite    = false
}

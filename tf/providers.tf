provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = var.proxmox_insecure

  # API credentials sourced from environment variables:
  # PROXMOX_VE_USERNAME - e.g., "terraform-prov@pve"
  # PROXMOX_VE_PASSWORD - the user password

  # SSH is required for disk import operations
  ssh {
    agent    = true
    username = "root"
  }
}

provider "talos" {}

provider "local" {}

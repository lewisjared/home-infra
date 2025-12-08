provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = var.proxmox_insecure

  # API credentials sourced from environment variables:
  # Option 1 - API Token (recommended, has full permissions):
  #   PROXMOX_VE_API_TOKEN="root@pam!terraform=xxxxx"
  #
  # Option 2 - Username/Password:
  #   PROXMOX_VE_USERNAME="terraform-prov@pve"
  #   PROXMOX_VE_PASSWORD="password"

  # SSH is required for disk import operations
  ssh {
    agent    = true
    username = "root"
  }
}

provider "talos" {}

provider "local" {}

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      version = "0.93.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.10.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.7.0"
    }
  }
}

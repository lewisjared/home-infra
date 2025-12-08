terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      version = "0.89.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.7.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.5.0"
    }
  }
}

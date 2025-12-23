# =============================================================================
# Technitium DNS HA Cluster
# =============================================================================
# Deploys a 2-node Technitium DNS cluster for:
# - Authoritative DNS for home.lewelly.com
# - Local DNS overrides for lewelly.com
# - Ad blocking (replacing Pi-hole)
# - External-dns integration via RFC 2136
# =============================================================================

# -----------------------------------------------------------------------------
# LXC Template Download
# -----------------------------------------------------------------------------
# Download Debian 13 (trixie) LXC template to nodes that will host Technitium containers
# Each node needs its own copy of the template

locals {
  technitium_proxmox_nodes = toset(["taco", "tamale"])
  debian_lxc_template_url  = "http://download.proxmox.com/images/system/debian-13-standard_13.1-2_amd64.tar.zst"
  debian_lxc_template_name = "debian-13-standard_13.1-2_amd64.tar.zst"
}

resource "proxmox_virtual_environment_download_file" "debian_lxc_template" {
  for_each = local.technitium_proxmox_nodes

  content_type = "vztmpl"
  datastore_id = "local"
  node_name    = each.key
  url          = local.debian_lxc_template_url
  file_name    = local.debian_lxc_template_name
  overwrite    = false
}

# -----------------------------------------------------------------------------
# Technitium DNS Containers
# -----------------------------------------------------------------------------

variable "technitium_nodes" {
  type = map(object({
    proxmox_node = string
    ip_address   = string
    vm_id        = number
  }))
  description = "Technitium DNS container definitions"
  default = {
    "technitium-1" = {
      proxmox_node = "taco"
      ip_address   = "10.10.20.71/24"
      vm_id        = 301
    }
    "technitium-2" = {
      proxmox_node = "tamale"
      ip_address   = "10.10.20.72/24"
      vm_id        = 302
    }
  }
}

variable "technitium_ssh_public_keys" {
  type        = list(string)
  description = "SSH public keys for Technitium container root access"
  default     = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK4zH1OrC8hroHDjHYOsmOkIALw3+a9yzXK6QeRLxx8y jared.lewis@climate-resource.com",
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC6GbS2U0RBZKpCIX9Z+762qXw8LOgBau9xW4uOd2dXviE/VmjNnHH9TjZZJTiAhxCLJK+chyf1v9Ycf8RR55MDeHF1jNUSLg7KDnI6DkWbcEUPqPwOI/gDR8JsGZKU5WyaPHuQr79dnfE7ae2XypZ8qMozFnJXqlOyeSlVoTunsUXqFgcqVtzBws8Hc+rM1F8mtlvMSm/pLAqW2bdZ6Z70UU+CZku+lQQ+tBEXGg7HuMz2jqPa9u96Ke3ypJJJjQHuomNw77HUlMo4/m8DrqQCqeUgJaFOn8tOt+uusfiQWp1uwsxt9Nz0YHC4eHksHeaOXg46IeYuD6PMHIA+7W+pTci5peN/BUhDNU4VEOwAC7KNg/5EnM+jYTJ1sHeRje7VYWqbk/iK4BHSS0tW3LK0katQjdJOALsPyLl5v5KkB+dEFvn/zos5sp01/5p4Mb02gpGEVpd6HQV1SiMyBFbPCTdWm4+s0fsjtNwXerw8jMTynPQt3ANbskqJimJeZUDwJ10yJ5oe27mcFnDtKczyrzJL6xGZepYwXZ11nuhKBTv2vxhkVE+N/DrlvnvUyo1U1XXJTC6DevsxBJzVj86wcR2Em0gScHTWnhyMwgfotrL2Joimqd3sx3fumpaIssxG3DIM3MhBjCaoOj3nFk/VchNi81ACLL4lsAvn3Be58Q== jared@Jareds-Laptop.localdomain"
  ]
}

module "technitium_lxc" {
  for_each = var.technitium_nodes
  source   = "./modules/proxmox-lxc"

  hostname         = each.key
  proxmox_node     = each.value.proxmox_node
  ip_address       = each.value.ip_address
  vm_id            = each.value.vm_id
  template_file_id = proxmox_virtual_environment_download_file.debian_lxc_template[each.value.proxmox_node].id

  # Network configuration - VLAN 20 (Infrastructure)
  vlan_id = 20
  gateway = "10.10.20.1"

  # Use Ceph RBD storage for HA (allows live migration)
  storage_pool = "proxmox-vms"

  # Resource allocation
  cpu_cores    = 2
  memory_mb    = 1024
  swap_mb      = 512
  disk_size_gb = 8

  # DNS - use self after initial setup, fallback to gateway
  dns_servers = ["10.10.20.1"]
  dns_domain  = "home.lewelly.com"

  # Container settings
  unprivileged    = true
  on_boot         = true
  started         = true
  ssh_public_keys = var.technitium_ssh_public_keys

  tags        = ["dns", "technitium", "infrastructure"]
  description = "Technitium DNS Server - Managed by OpenTofu"
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "technitium_ips" {
  description = "IP addresses of Technitium DNS containers"
  value = {
    for name, container in module.technitium_lxc : name => container.ip_address
  }
}

output "technitium_container_ids" {
  description = "Proxmox container IDs for Technitium DNS"
  value = {
    for name, container in module.technitium_lxc : name => container.container_id
  }
}

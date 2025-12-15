# =============================================================================
# Proxmox Host VLAN Network Configuration
# =============================================================================
# Creates VLAN interfaces on Proxmox hosts for each defined VLAN.
# Each host gets a VLAN interface with the specified IP address.

locals {
  # Flatten hosts x VLANs into a map for for_each
  # Key format: "hostname-vlanid" (e.g., "churro-10")
  host_vlans = merge([
    for host_name, host in var.proxmox_hosts : {
      for vlan_key, vlan in var.vlans : "${host_name}-${vlan.id}" => {
        host_name = host_name
        # Use per-VLAN interface override if specified, otherwise use host default
        interface = coalesce(
          try(host.vlans[tostring(vlan.id)].interface, null),
          host.default_interface
        )
        vlan_id   = vlan.id
        vlan_name = vlan.name
        comment   = vlan.comment
        address   = try(host.vlans[tostring(vlan.id)].ip, null)
      }
      if try(host.vlans[tostring(vlan.id)].ip, null) != null
    }
  ]...)
}

resource "proxmox_virtual_environment_network_linux_vlan" "host_vlan" {
  for_each = local.host_vlans

  node_name = each.value.host_name
  name      = each.value.vlan_name
  interface = each.value.interface
  vlan      = each.value.vlan_id
  address   = each.value.address
  autostart = true
  comment   = each.value.comment
}

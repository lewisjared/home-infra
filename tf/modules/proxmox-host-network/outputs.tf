# =============================================================================
# Outputs
# =============================================================================

output "vlan_interfaces" {
  description = "Created VLAN interfaces on Proxmox hosts"
  value = {
    for key, vlan in proxmox_virtual_environment_network_linux_vlan.host_vlan : key => {
      host    = vlan.node_name
      name    = vlan.name
      vlan_id = vlan.vlan
      address = vlan.address
    }
  }
}

output "vlan_interfaces_by_host" {
  description = "VLAN interfaces grouped by host"
  value = {
    for host_name in distinct([for v in proxmox_virtual_environment_network_linux_vlan.host_vlan : v.node_name]) :
    host_name => {
      for key, vlan in proxmox_virtual_environment_network_linux_vlan.host_vlan :
      "vlan${vlan.vlan}" => {
        name    = vlan.name
        address = vlan.address
      }
      if vlan.node_name == host_name
    }
  }
}

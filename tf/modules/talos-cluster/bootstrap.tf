# Apply machine configuration to control plane nodes
resource "talos_machine_configuration_apply" "controlplane" {
  for_each   = var.control_plane_nodes
  depends_on = [module.controlplane_vms]

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane[each.key].machine_configuration
  node                        = each.value.ip_address
  endpoint                    = each.value.ip_address

  timeouts = {
    create = "10m"
  }
}

# Apply machine configuration to worker nodes
resource "talos_machine_configuration_apply" "worker" {
  for_each   = var.worker_nodes
  depends_on = [module.worker_vms]

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker[each.key].machine_configuration
  node                        = each.value.ip_address
  endpoint                    = each.value.ip_address

  timeouts = {
    create = "10m"
  }
}

# Bootstrap the cluster on the first control plane node
resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.controlplane]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = values(var.control_plane_nodes)[0].ip_address
  endpoint             = values(var.control_plane_nodes)[0].ip_address

  timeouts = {
    create = "10m"
  }
}

# Retrieve kubeconfig after cluster bootstrap
resource "talos_cluster_kubeconfig" "this" {
  depends_on = [
    talos_machine_bootstrap.this,
    talos_machine_configuration_apply.worker
  ]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = values(var.control_plane_nodes)[0].ip_address
  endpoint             = values(var.control_plane_nodes)[0].ip_address

  timeouts = {
    create = "5m"
  }
}

# Write kubeconfig to local file
resource "local_sensitive_file" "kubeconfig" {
  content         = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename        = "${path.root}/output/kubeconfig"
  file_permission = "0600"
}

# Write talosconfig to local file
resource "local_sensitive_file" "talosconfig" {
  content         = data.talos_client_configuration.this.talos_config
  filename        = "${path.root}/output/talosconfig"
  file_permission = "0600"
}

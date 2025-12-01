# Load Cilium manifest for inline deployment
locals {
  cilium_manifest = file("${path.module}/../../manifests/cilium/cilium-install.yaml")

  # Common patches applied to all nodes
  common_patches = [
    yamlencode({
      machine = {
        network = {
          nameservers = var.network_nameservers
        }
        features = {
          kubePrism = {
            enabled = true
            port    = 7445
          }
        }
      }
    })
  ]

  # Control plane specific patches
  controlplane_patches = concat(local.common_patches, [
    # Disable default CNI and kube-proxy for Cilium
    yamlencode({
      cluster = {
        network = {
          cni = { name = "none" }
        }
        proxy = { disabled = true }
        allowSchedulingOnControlPlanes = true
      }
    }),
    # Include Cilium as inline manifest
    yamlencode({
      cluster = {
        inlineManifests = [
          {
            name     = "cilium"
            contents = local.cilium_manifest
          }
        ]
      }
    })
  ])

  # Worker specific patches
  worker_patches = local.common_patches
}

# Generate control plane machine configuration
data "talos_machine_configuration" "controlplane" {
  for_each = var.control_plane_nodes

  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  config_patches = concat(local.controlplane_patches, [
    yamlencode({
      machine = {
        network = {
          hostname = each.key
          interfaces = [{
            interface = "eth0"
            addresses = ["${each.value.ip_address}${var.network_cidr}"]
            routes = [{
              network = "0.0.0.0/0"
              gateway = var.network_gateway
            }]
          }]
        }
        install = {
          disk  = "/dev/sda"
          image = data.talos_image_factory_urls.this.urls.installer
        }
      }
    })
  ])
}

# Generate worker machine configuration
data "talos_machine_configuration" "worker" {
  for_each = var.worker_nodes

  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  config_patches = concat(local.worker_patches, [
    yamlencode({
      machine = {
        network = {
          hostname = each.key
          interfaces = [{
            interface = "eth0"
            addresses = ["${each.value.ip_address}${var.network_cidr}"]
            routes = [{
              network = "0.0.0.0/0"
              gateway = var.network_gateway
            }]
          }]
        }
        install = {
          disk  = "/dev/sda"
          image = data.talos_image_factory_urls.this.urls.installer
        }
      }
    })
  ])
}

# Generate talosconfig for CLI access
data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [for node in var.control_plane_nodes : node.ip_address]
  nodes = concat(
    [for node in var.control_plane_nodes : node.ip_address],
    [for node in var.worker_nodes : node.ip_address]
  )
}

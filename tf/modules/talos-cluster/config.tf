# Load manifests for inline deployment
locals {
  cilium_manifest = file("${path.module}/../../manifests/cilium/cilium-install.yaml")

  # Gateway API CRDs fetched from GitHub at bootstrap
  # Using experimental channel because Cilium 1.18 requires TLSRoute CRD
  # See: https://github.com/cilium/cilium/issues/38420
  gateway_api_version  = "v1.2.0"
  gateway_api_crds_url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/${local.gateway_api_version}/experimental-install.yaml"

  # Registries proxied by the in-cluster Spegel P2P image cache
  spegel_mirror_registries = [
    "docker.io",
    "ghcr.io",
    "quay.io",
    "gcr.io",
    "registry.k8s.io",
    "public.ecr.aws",
    "mcr.microsoft.com",
  ]

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
        registries = {
          mirrors = {
            for reg in local.spegel_mirror_registries : reg => {
              endpoints    = ["http://127.0.0.1:29999"]
              overridePath = true
            }
          }
        }
        # Spegel requires containerd to keep unpacked layer blobs so peers
        # can serve them.
        # Talos defaults discard_unpacked_layers = true.
        files = [
          {
            op      = "create"
            path    = "/etc/cri/conf.d/20-customization.part"
            content = <<-EOT
              [plugins."io.containerd.cri.v1.images"]
                discard_unpacked_layers = false
            EOT
          },
        ]
        # Kubelet image GC — defaults (85%/80%)
        kubelet = {
          extraConfig = {
            imageGCHighThresholdPercent = 75
            imageGCLowThresholdPercent  = 65
          }
          # Bind-mount the host paths the iscsi-tools extension populates
          # into the kubelet's mount namespace so CSI node DaemonSets
          # (democratic-csi) can hostPath-mount /etc/iscsi and /var/lib/iscsi.
          # Without these, kubelet's view of /etc/iscsi is overlay-masked
          # and hostPath.type=Directory checks fail.
          extraMounts = [
            {
              destination = "/etc/iscsi"
              type        = "bind"
              source      = "/etc/iscsi"
              options     = ["bind", "rshared", "rw"]
            },
            {
              destination = "/var/lib/iscsi"
              type        = "bind"
              source      = "/var/lib/iscsi"
              options     = ["bind", "rshared", "rw"]
            },
          ]
        }
      }
    })
  ]

  # Control plane specific patches
  controlplane_patches = concat(local.common_patches, [
    # Enable Kubernetes Talos API Access for tuppr (upgrade controller)
    yamlencode({
      machine = {
        features = {
          kubernetesTalosAPIAccess = {
            enabled                     = true
            allowedRoles                = ["os:admin"]
            allowedKubernetesNamespaces = ["system-upgrade"]
          }
        }
      }
    }),
    # Disable default CNI and kube-proxy for Cilium
    yamlencode({
      cluster = {
        network = {
          cni = { name = "none" }
        }
        proxy                          = { disabled = true }
        allowSchedulingOnControlPlanes = true
      }
    }),
    # Gateway API CRDs fetched from GitHub URL at bootstrap
    yamlencode({
      cluster = {
        extraManifests = [
          local.gateway_api_crds_url
        ]
      }
    }),
    # Cilium CNI as inline manifest (templated with our Helm values)
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

  # GPU patch - applied only to nodes with gpu_enabled = true
  gpu_patch = yamlencode({
    machine = {
      kernel = {
        modules = [
          { name = "amdgpu" },
          { name = "drm" }
        ]
      }
      nodeLabels = {
        "gpu" = "amd-igpu"
      }
    }
  })
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

  config_patches = concat(
    local.controlplane_patches,
    # GPU patch - only for nodes with gpu_enabled
    each.value.gpu_enabled ? [local.gpu_patch] : [],
    [
      # Talos v1.12 requires hostname via the dedicated HostnameConfig
      # document; setting machine.network.hostname alongside it (or on its
      # own) trips "static hostname is already set in v1alpha1 config".
      yamlencode({
        apiVersion = "v1alpha1"
        kind       = "HostnameConfig"
        hostname   = each.key
        auto       = "off"
      }),
      yamlencode({
        machine = {
          network = {
            interfaces = concat(
              # eth0 - Primary NIC (Kubernetes network)
              [{
                interface = "eth0"
                addresses = ["${each.value.ip_address}${var.network_cidr}"]
                routes = [{
                  network = "0.0.0.0/0"
                  gateway = var.network_gateway
                }]
              }],
              # eth1 - Secondary NIC (Ceph storage network) - only if configured
              each.value.ceph_ip_address != null ? [{
                interface = "eth1"
                addresses = ["${each.value.ceph_ip_address}${var.ceph_cidr}"]
                # No routes - isolated L2 storage network
              }] : []
            )
          }
          install = {
            disk  = "/dev/sda"
            image = data.talos_image_factory_urls.this.urls.installer
          }
        }
      })
    ]
  )
}

# Generate talosconfig for CLI access
data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [for node in var.control_plane_nodes : node.ip_address]
  nodes                = [for node in var.control_plane_nodes : node.ip_address]
}

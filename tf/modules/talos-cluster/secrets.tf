# Generate machine secrets for the cluster
resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains the infrastructure-as-code for a personal home lab built on a Proxmox cluster.
A Talos Kubernetes cluster runs on VMs across the compute nodes, managed via Terraform.
The repository uses **Flux CD** as the GitOps continuous deployment system, making the repository the source of truth for cluster state.

## Essential Commands

### Validation

```bash
make validate
```

Validates all YAML files, Flux manifests, and Kustomize overlays. This is equivalent to running:

```bash
bash scripts/validate.sh
```

Run this before committing changes to ensure manifests are valid.

### Monitoring Flux Sync

```bash
make watch
```

Continuously watch Flux Kustomization resources and their sync status. Useful for monitoring deployments.

### Manual Kustomize Build (for debugging)

```bash
kustomize build apps/production/core
kustomize build apps/production/apps
```

Builds the complete manifest from a kustomization. Useful for debugging template expansion.

### Flux CLI Operations

```bash
flux get kustomizations          # List all Flux Kustomization resources
flux get helmreleases            # List all Helm releases managed by Flux
flux reconcile kustomization     # Force a manual sync of a specific kustomization
```

## Architecture

### GitOps Structure

The repository is organized into two main directories:

**1. `/clusters/production/`** - Flux CD Kustomization definitions

- 6 Flux Kustomizations organized by category
- Defines deployment order via `dependsOn` relationships
- Flux uses these to continuously reconcile cluster state with the repository

**2. `/apps/production/`** - All deployable components organized by category

| Category         | Purpose                    | Components                                                                                          |
| ---------------- | -------------------------- | --------------------------------------------------------------------------------------------------- |
| `cert-manager/`  | TLS certificate management | cert-manager HelmRelease                                                                            |
| `core/`          | Foundation services        | cert-issuers, cilium-gateway, external-dns, metrics-server, pull-secrets, technitium-rbac, reloader |
| `storage/`       | Distributed storage        | rook-ceph operator, ceph-cluster (external)                                                         |
| `security/`      | Authentication             | authelia                                                                                            |
| `monitoring/`    | Observability stack        | Prometheus, Grafana, Loki, Tempo, Alloy, network-policies, hubble-ui                                |
| `apps/`          | User applications          | homepage, podinfo, media stack                                                                      |
| `apps/disabled/` | Inactive apps              | home-assistant, kubernetes-dashboard, headlamp                                                      |

### Flux Kustomization Dependencies

```raw
cert-manager (no deps)
    └── core (depends: cert-manager)
        ├── storage (depends: core)
        ├── security (depends: core, storage)
        ├── monitoring (depends: core, storage)
        └── apps (depends: core, storage, security)
```

### Key Technical Patterns

**Templating**: Uses Kustomize for composition within each category

**Package Management**: External packages (cert-manager, ingress-nginx) are managed via Helm charts, integrated with Flux via HelmRelease resources

**Secrets Management**: Uses SOPS (Secrets Operations) with PGP encryption:

- `.sops.yaml` defines encryption rules
- Files matching `(infrastructure|clusters|apps)/.*.yaml` have their `data` and `stringData` fields encrypted
- kubeconfig file has `client-key-data` field encrypted
- Decryption happens in the cluster via Flux's SOPS integration (requires PGP private key)

**Validation**: Three-layer validation approach:

- yq: Basic YAML syntax validation
- kubeconform: Kubernetes manifest schema validation against Flux CRD schemas
- kustomize build: Validates Kustomize overlay compilation
- Secrets are skipped during validation (SOPS fields would fail)

## Important Development Notes

### Before Committing

Always run `make validate` before committing changes. Invalid manifests will fail Flux reconciliation.

### Working with Secrets

- Encrypted fields are stored in files but appear plaintext in the cluster
- Use `sops` CLI to edit encrypted files: `sops path/to/file.yaml`
- New secrets in apps/clusters directories are automatically encrypted on save if configured in `.sops.yaml`
- The kubeconfig file has its PEM private key encrypted

### Adding New Applications

1. Create app directory in `apps/production/apps/your-app/`
2. Add kustomization.yaml listing your resources
3. Reference in `apps/production/apps/kustomization.yaml`
4. Run validation before committing

To enable a disabled app, move it from `apps/production/apps/disabled/` to `apps/production/apps/` and add to the kustomization.

### App-Template Pattern for Simple Containers

For deploying Docker containers without a dedicated Helm chart,
use the [bjw-s/app-template](https://github.com/bjw-s-labs/helm-charts) chart.
The media apps use this pattern.

**Shared OCI Repository** (defined in `apps/production/apps/media/oci-repository.yaml`):

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: app-template
  namespace: flux-system
spec:
  url: oci://ghcr.io/bjw-s-labs/helm/app-template
  ref:
    tag: 4.5.0
```

**Example HelmRelease** (see `apps/production/apps/media/radarr/helmrelease.yaml`):

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: radarr
  namespace: media
spec:
  chartRef:
    kind: OCIRepository
    name: app-template
    namespace: flux-system
  values:
    controllers:
      main:
        containers:
          main:
            image:
              repository: ghcr.io/home-operations/radarr
              tag: 5.28.0@sha256:...
            env:
              TZ: Australia/Melbourne
            probes:
              liveness: &probes
                enabled: true
                custom: true
                spec:
                  httpGet:
                    path: /ping
                    port: &port 7878
              readiness: *probes
            resources:
              requests:
                cpu: 10m
                memory: 256Mi
              limits:
                memory: 2Gi

    service:
      main:
        controller: main
        ports:
          http:
            port: *port

    persistence:
      config:
        type: persistentVolumeClaim
        storageClass: rook-ceph-block
        size: 5Gi
      data:
        existingClaim: media-library
```

Key features: single chart for all apps, YAML anchors for DRY config, pinned image digests, shared PVCs.

### Adding Infrastructure Components

1. Determine the appropriate category (core, storage, security, monitoring)
2. Create definitions in `apps/production/<category>/component-name/`
3. Reference in the category's `kustomization.yaml`
4. Ensure SOPS encryption rules are appropriate for any secrets

### Monitoring Stack Details

The monitoring stack (`/apps/production/monitoring/`) includes:

- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization and dashboards
- **Loki**: Log aggregation
- **Tempo**: Distributed tracing
- **Alloy**: Metrics collection agent (replaces Prometheus agent)
- **AlertManager**: Alert routing and notification
- Network policies enforce separation between monitoring components

## Tools and Prerequisites

For local validation and development:

- **yq** v4.34+: YAML processing and validation
- **kustomize** v5.3+: Kubernetes manifest templating
- **kubeconform** v0.6+: Kubernetes manifest schema validation
- **sops**: For encrypting/decrypting secrets
- **flux**: Flux CLI for cluster operations
- **kubectl**: For cluster interaction

Install via package manager or from upstream releases.

## Repository Configuration

- **`.sops.yaml`**: Encryption rules for PGP-based secret management
- **`Makefile`**: Simple make targets for common operations
- **`.github/`**: Currently empty, available for GitHub Actions/automation
- **`kubeconfig`**: Encrypted Kubernetes config (client-key-data encrypted)

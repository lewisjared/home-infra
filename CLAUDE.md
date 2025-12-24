# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains the infrastructure-as-code for a personal home lab built on a Proxmox cluster. A Talos Kubernetes cluster runs on VMs across the compute nodes, managed via Terraform. The repository uses **Flux CD** as the GitOps continuous deployment system, making the repository the source of truth for cluster state.

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
kustomize build apps/home/
kustomize build clusters/home/
```

Builds the complete manifest from a kustomization overlay. Useful for debugging template expansion.

### Flux CLI Operations

```bash
flux get kustomizations          # List all Flux Kustomization resources
flux get helmreleases            # List all Helm releases managed by Flux
flux reconcile kustomization     # Force a manual sync of a specific kustomization
```

## Architecture

### GitOps Structure

The repository is organized into three main directories:

**1. `/clusters/home/`** - Flux CD Kustomization definitions

- Defines which Kustomize overlays and Helm releases should be deployed
- Each `.yaml` file represents a Flux Kustomization resource
- Flux uses these to continuously reconcile cluster state with the repository

**2. `/infrastructure/`** - Core infrastructure components

- `cert-manager/`: TLS certificate management (Let's Encrypt integration)
- `external-dns/`: Automatic DNS updates to Cloudflare
- `ingress-nginx/`: Ingress controller for HTTP(S) routing
- `monitoring/`: Complete observability stack (Prometheus, Grafana, Loki, Tempo, Alloy, AlertManager)
- `rook-ceph/`: Distributed storage via Ceph with Rook operator
- `pull-secrets/`: Docker image pull secrets for private registries

**3. `/apps/home/`** - User applications

- `base/`: Base Kustomize definitions for apps
- `home/`: Home environment-specific overlays
- Applications include Home Assistant, Podinfo (test app), and others

### Key Technical Patterns

**Templating**: Uses Kustomize for templating, composition, and environment-specific overlays (base → home overlay pattern)

**Package Management**: External packages (cert-manager, ingress-nginx) are managed via Helm charts, integrated with Flux via HelmRelease resources

**Secrets Management**: Uses SOPS (Secrets Operations) with PGP encryption:

- `.sops.yaml` defines encryption rules
- Files matching `(infrastructure|clusters)/.*.yaml` have their `data` and `stringData` fields encrypted
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
- New secrets in infrastructure/clusters directories are automatically encrypted on save if configured in `.sops.yaml`
- The kubeconfig file has its PEM private key encrypted

### Adding New Applications

1. Create base definitions in `apps/base/your-app/`
2. Add kustomization overlay in `apps/home/`
3. Reference in `clusters/home/app.yaml` via a Flux Kustomization resource
4. Run validation before committing

### Adding Infrastructure Components

1. Create definitions in `infrastructure/component-name/`
2. Create Flux Kustomization in `clusters/home/component-name.yaml`
3. Reference in `clusters/home/` kustomization.yaml if needed
4. Ensure SOPS encryption rules are appropriate for any secrets

### Monitoring Stack Details

The monitoring infrastructure (`/infrastructure/monitoring/`) includes:

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

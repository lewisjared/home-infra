# CLAUDE.md

Infrastructure as code for a home lab: a Talos Kubernetes cluster on Proxmox VMs (Terraform in `tf/`),
reconciled from this repository by Flux CD.

## Commands

```bash
make validate   # yq, kubeconform and kustomize build (scripts/validate.sh). Run before committing.
make watch      # watch Flux Kustomization sync status
make ctx-prod   # switch kubectl to the home-prod context
kustomize build apps/production/<category>   # debug a single overlay
```

## Layout

- `clusters/production/`: Flux Kustomizations per category, ordered by `dependsOn`.
  The mermaid diagram in README.md is the authoritative dependency graph.
- `apps/production/<category>/`: the components
  (bootstrap, core, storage, database, security, monitoring, apps).
- `components/`: shared Kustomize components (alerts, volsync).
- `docs/`: runbooks (backups, postgres restore, DNS, Cilium, OIDC).

## Secrets

- SOPS with PGP (`.sops.yaml`): `data` and `stringData` are encrypted in any YAML
  under `infrastructure/`, `clusters/` or `apps/`.
- Edit encrypted files in place with `sops path/to/file.yaml`. Never commit a decrypted secret.
- Flux decrypts in the cluster. Validation skips Secrets.

## Adding things

- New app: create `apps/production/apps/<app>/` with a `kustomization.yaml`
  and list it in `apps/production/apps/kustomization.yaml`.
- New infrastructure component: same pattern under the matching category.
- A new Helm repository must also be added to `helmfile.yaml`, because validation installs repos from it.
- Plain containers without their own chart use bjw-s `app-template` via the shared OCIRepository in
  `apps/production/apps/media/oci-repository.yaml`. Copy `apps/production/apps/media/radarr/helmrelease.yaml`:
  pinned image digests, YAML anchors for probes and ports.

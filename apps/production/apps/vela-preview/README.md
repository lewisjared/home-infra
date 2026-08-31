# vela-preview

RBAC and GitHub feedback wiring for the vela repo's Flux Operator ResourceSet PR previews.
The ResourceSet/ResourceSetInputProvider themselves live in the vela repo at
`deploy/flux-preview` (applied by the `vela-preview` Kustomization; see `../vela/ks.yaml`).
This directory only holds the cluster-specific pieces the vela repo can't
know about.

## Contents

- `rbac.yaml` — the scoped `vela-preview` ServiceAccount/ClusterRole/
  ClusterRoleBinding the ResourceSet impersonates when applying per-PR
  resources.
- `provider.yaml` — a `notification.toolkit.fluxcd.io` `Provider`
  (`type: github`) pointed at `https://github.com/lewisjared/vela`, used to
  post commit statuses.
- `alert.yaml` — an `Alert` wired to that Provider, watching every
  `Kustomization` labelled `vela.dev/preview: "true"` in `flux-system`
  (i.e. every per-PR `vela-pr-<n>` Kustomization the ResourceSet renders).
  `eventSeverity: info` so a healthy reconcile posts a success status too,
  not just failures — this makes deploy success/failure visible as a commit
  status (`kustomization/vela-pr-<n>`) on the PR's head SHA.
- `github-token-secret.yaml` — SOPS-encrypted secret consumed by the Provider above.

## Operator step

**Mint a fine-grained GitHub PAT** scoped to `lewisjared/vela` with
commit-status write access (Repository permissions → Commit statuses: Read and write),
and re-encrypt `github-token-secret.yaml`'s `token` key
with `sops -e -i`.

## Deferred: immediate reconcile nudge

The original design added a `notification.toolkit.fluxcd.io` `Receiver` so an
in-cluster caller could force the `vela-preview-prs`
`ResourceSetInputProvider` to reconcile right after a preview image is pushed,
rather than waiting for its poll interval.
That is not possible with a GOTK `Receiver`:
its `spec.resources[].kind` schema only accepts core Flux source/GOTK kinds
(`GitRepository`, `Kustomization`, `ImagePolicy`, …),
not the flux-operator `ResourceSetInputProvider` CRD.
The `Receiver` was dropped rather than shipped invalid.

The RSIP already polls every 1 minute (vela `deploy/flux-preview`, tightened in vela #396), so discovery latency is bounded without a nudge.
If a true push-triggered reconcile is wanted later, the flux-operator-native
path is to annotate the RSIP with `reconcile.fluxcd.io/requestedAt` from an
in-cluster actor with RBAC on the object — a different mechanism from a GOTK
`Receiver`, tracked as a follow-up.

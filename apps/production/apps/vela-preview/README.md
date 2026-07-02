# vela-preview

RBAC and GitHub feedback wiring for the vela repo's Flux Operator
ResourceSet PR previews.
The ResourceSet/ResourceSetInputProvider themselves live in the vela repo at
`deploy/flux-preview` (applied by the `vela-preview` Kustomization; see
`../vela/ks.yaml`).
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
- `receiver.yaml` — a `Receiver` that lets an in-cluster caller nudge
  `vela-preview-prs` (the `ResourceSetInputProvider` in the vela repo) to
  reconcile immediately instead of waiting for its poll interval. See the
  comments in `receiver.yaml` for how to read the generated webhook path and
  why GitHub itself can never call it directly (no public ingress here).
- `github-token-secret.yaml` / `webhook-token-secret.yaml` — SOPS-encrypted
  secrets consumed by the Provider and Receiver above.

## Operator steps

1. **Mint a fine-grained GitHub PAT** scoped to `lewisjared/vela` with
   commit-status write access (Repository permissions → Commit statuses:
   Read and write), and re-encrypt `github-token-secret.yaml`'s `token` key
   with `sops -e -i`.
2. **Create a webhook token** (any sufficiently random string, e.g.
   `openssl rand -hex 20`) and re-encrypt `webhook-token-secret.yaml`'s
   `token` key with `sops -e -i`. This does not need to match anything on
   GitHub's side — it only authenticates in-cluster callers of the Receiver.

## vela-side follow-up

Add a step to vela's `docker-build.yml` (after the image push, on the
in-cluster arc runner) that nudges the Receiver so the preview picks up the
new tag without waiting for the next poll:

```yaml
- name: Nudge preview reconcile
  if: github.event_name == 'pull_request'
  run: |
    curl -fsS -X POST \
      -H "X-Hub-Signature-256: sha256=$(printf '%s' "$PAYLOAD" | openssl dgst -sha256 -hmac "$WEBHOOK_TOKEN" | sed 's/^.* //')" \
      -d "$PAYLOAD" \
      "http://webhook-receiver.flux-system.svc.cluster.local<path>"
```

Read `<path>` from the Receiver's status once it's applied:

```shell
kubectl get receiver vela-preview-github -n flux-system \
  -o jsonpath='{.status.webhookPath}'
```

This only works from a runner that can reach the cluster's internal service
network (the in-cluster arc runner), not GitHub-hosted runners.

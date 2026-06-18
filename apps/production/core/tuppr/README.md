# tuppr — Talos & Kubernetes upgrade runbook

[tuppr](https://github.com/home-operations/tuppr) (the Talos UPgrade contRoller)
turns Talos OS and Kubernetes version bumps into GitOps PRs:
it watches a `TalosUpgrade` / `KubernetesUpgrade` custom resource and,
when the target version is ahead of what a node runs,
rolls the upgrade out **one node at a time**, gating on etcd and node health.

## What's in this directory

- `tuppr.yaml` — HelmRelease for the controller (chart `0.1.6`, namespace `system-upgrade`) and its `HelmRepository`.
- `namespace.yaml` — the `system-upgrade` namespace.
- `talos-upgrade.yaml` — `TalosUpgrade/cluster`, the GitOps source of truth for the **Talos OS** version.
- `kubernetes-upgrade.yaml` — `KubernetesUpgrade/kubernetes`, the GitOps source of truth for the **Kubernetes** version.

Both CRs are **cluster-scoped**, which is why this directory's
`kustomization.yaml` deliberately has **no `namespace:` transformer**
(it would otherwise stamp a namespace onto them).

## How tuppr picks the installer image (why no annotations are needed)

Verified against the tuppr `0.1.6` controller source:
for each node tuppr reads the live `machine.install.image`
— Terraform sets this to
`factory.talos.dev/nocloud-installer/<schematic>:<version>` —
keeps the repository (the `nocloud-installer` flavor **and** the extensions
schematic) and substitutes **only** the version tag with `spec.talos.version`.

A built-in guard refuses to proceed if the node's running schematic isn't
embedded in that install image,
so the baked-in extensions
(`qemu-guest-agent`, `amdgpu`, `iscsi-tools`, `util-linux-tools`)
cannot be silently dropped on upgrade.
Because the schematic is preserved automatically,
**no per-node `factory-url` / `schematic` annotations are required** for a routine
version bump.

## Version sources of truth — keep these in sync

- **Talos** — `talos_version` in `tf/variables.tf` ↔ `spec.talos.version` in `talos-upgrade.yaml`.
- **Kubernetes** — `kubernetes_version` in `tf/variables.tf` ↔ `spec.kubernetes.version` in `kubernetes-upgrade.yaml`.

Terraform drives `machine.install.image` and the Image Factory ISO — the version a
node provisions at when it is **rebuilt**. The tuppr CR drives the **rolling upgrade
of already-running nodes**. Bump both together so a rebuilt node doesn't land on a
stale version.

The CRs are committed at the **current** versions, so reconciling them is a no-op
until you bump a version. The bump is the upgrade trigger.

## Routine upgrade procedure

> Do **one** kind of upgrade at a time. tuppr serialises Talos vs Kubernetes
> upgrades, but keep them in **separate PRs**: Talos first, let it settle, then
> Kubernetes. Never skip Talos minor versions.

### Preflight (every upgrade)

```sh
export TALOSCONFIG="$PWD/tf/output/talosconfig"
export KUBECONFIG="$PWD/tf/output/kubeconfig"

# All nodes Ready, none already cordoned/upgrading
kubectl get nodes -o wide

# etcd healthy on all three members
talosctl -n 10.10.20.51,10.10.20.52,10.10.20.53 service etcd

# Take an etcd snapshot first — three nodes means three etcd members; one bad
# reboot away from a quorum scare.
talosctl -n 10.10.20.51 etcd snapshot etcd-pre-upgrade.db
```

### Talos OS upgrade

1. Choose the next Talos version (one minor at a time).
2. Bump `talos_version` in `tf/variables.tf`, then from `tf/`:

   ```sh
   tofu plan    # regenerates the schematic data, installer URL and ISO download
   tofu apply
   ```

   This keeps `machine.install.image` and the downloaded ISO consistent for any
   future **node rebuild**. It does **not** upgrade a running OS by itself — only
   tuppr (or `talosctl upgrade`) re-images a running node.
   Apply the refreshed machine config so the install image label matches:

   ```sh
   bash scripts/apply-talos-configs.sh
   ```

3. Bump `spec.talos.version` in `talos-upgrade.yaml` to the **same** version.
4. Open a PR, review, merge. Flux applies the CR; tuppr rolls it out node by node.
5. Watch the rollout (see below).

### Kubernetes upgrade

1. Bump `kubernetes_version` in `tf/variables.tf` and `tofu apply` (provisioning
   default; no reboot).
2. Bump `spec.kubernetes.version` in `kubernetes-upgrade.yaml` to the same value.
3. PR → merge → watch. tuppr runs the in-place k8s upgrade from an elected
   control-plane node (no node reboots).

## Watching a rollout

```sh
export KUBECONFIG="$PWD/tf/output/kubeconfig"

# tuppr's own view (status, current node, history)
kubectl -n system-upgrade get talosupgrade,kubernetesupgrade
kubectl get talosupgrade cluster -o yaml | yq '.status'

# Node-level signal: tuppr taints outdated nodes
#   tuppr.home-operations.com/outdated  (PreferNoSchedule)
# and labels the node it is actively upgrading
#   tuppr.home-operations.com/upgrading=true
kubectl get nodes -L tuppr.home-operations.com/upgrading -w

# Controller logs
kubectl -n system-upgrade logs deploy/tuppr -f

# Flux side
flux get kustomizations core
flux reconcile kustomization core --with-source

# Confirm the running versions afterwards
talosctl -n 10.10.20.51,10.10.20.52,10.10.20.53 version
kubectl get nodes -o wide   # KERNEL/VERSION columns
```

## Suspend, retry, abort

```sh
# Pause an in-flight upgrade (controller stops picking up new nodes)
kubectl annotate talosupgrade cluster tuppr.home-operations.com/suspend="true"

# Resume
kubectl annotate talosupgrade cluster tuppr.home-operations.com/suspend-

# Retry after a failed node
kubectl annotate talosupgrade cluster tuppr.home-operations.com/reset="$(date)"
```

## Guardrails specific to this cluster

- **3 nodes = 3 etcd members.** `parallelism: 1` and `policy.force: false` (etcd
  health gating) are set in `talos-upgrade.yaml` and must stay that way — never let
  two members reboot together.
- **Don't upgrade during the dual-role collapse migration** (`tf/MIGRATION.md`):
  two disruptive operations at once is how you lose quorum.
- **Changing extensions / the schematic** (not just the version) is **not** a
  routine bump: the running node still reports the old schematic, so tuppr's guard
  will refuse. That path needs the `tuppr.home-operations.com/factory-url` +
  `tuppr.home-operations.com/schematic` node annotations (or a manual
  `talosctl upgrade`). See the upstream README before attempting it.

## How CRD ordering is handled

The `TalosUpgrade`/`KubernetesUpgrade` CRDs are installed by the tuppr HelmRelease
(`crds: Create` / `CreateReplace`). The `core` Flux Kustomization
(`clusters/production/core.yaml`) health-checks the `tuppr` Deployment, and Flux
retries any CR that briefly races ahead of its CRD — the same pattern this repo
uses for cert-manager and its issuers.

## Pinned-version note

We run chart `0.1.6`, which still accepts the legacy top-level `spec.drain` block.
These CRs use the forward-compatible `spec.policy.nodrain` form instead, so a bump
to `0.2.0` (which removes `spec.drain`) needs no CR change here.

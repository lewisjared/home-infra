# Migration: collapse master/worker split into 3 dual-role nodes

One-time runbook for the change that deletes the `worker_nodes` pool and folds its
capabilities (iGPU passthrough, sizing) into the three control-plane nodes, leaving
**one dual-role Talos VM per physical compute host**.

> **Why a runbook and not just `tofu apply`.**
> The committed desired-state is correct, but a naive single `tofu apply` is unsafe:
>
> 1. **etcd quorum.** All three nodes keep their `talos-master-*` keys but change
>    cpu/mem/disk (and master-1/2 also flip bios → OVMF and gain a `hostpci` device).
>    Terraform acts on the `for_each` instances concurrently (default `-parallelism=10`)
>    with no ordering between them — rebooting/replacing 2+ etcd members at once loses
>    quorum and takes the control plane down.
> 2. **GPU contention.** master-1 (nacho) and master-2 (tamale) claim the `igpu` mapped
>    device that worker-1 / worker-2 still hold at plan time. With no dependency forcing
>    the worker destroy first, Proxmox errors `device is already in use`.
> 3. **Replacement.** The bios seabios→OVMF flip + new EFI/hostpci on master-1/2 likely
>    forces VM **replacement** (fresh disk → the etcd member is wiped and must re-join),
>    not an in-place reboot. Two replaced members + one survivor = permanent quorum loss
>    if done together.
>
> Phase 1 (destroy workers first) frees the iGPUs → fixes (2).
> Phase 2 (one master at a time, health-gated) → fixes (1) and (3).

All commands run from `tf/`. `talosctl`/`kubectl` use the generated
`tf/output/talosconfig` and `tf/output/kubeconfig`.

```sh
export TALOSCONFIG="$PWD/output/talosconfig"
export KUBECONFIG="$PWD/output/kubeconfig"
```

## Node map

| Node               | Host   | k8s IP      | vm_id | iGPU                | role after         |
| ------------------ | ------ | ----------- | ----- | ------------------- | ------------------ |
| talos-master-1     | nacho  | 10.10.20.51 | 201   | yes (from worker-1) | dual-role, OVMF    |
| talos-master-2     | tamale | 10.10.20.52 | 202   | yes (from worker-2) | dual-role, OVMF    |
| talos-master-3     | churro | 10.10.20.53 | 203   | no                  | dual-role, SeaBIOS |
| ~~talos-worker-1~~ | nacho  | 10.10.20.61 | 211   | —                   | **destroyed**      |
| ~~talos-worker-2~~ | tamale | 10.10.20.62 | 212   | —                   | **destroyed**      |
| ~~talos-worker-3~~ | churro | 10.10.20.63 | 213   | —                   | **destroyed**      |

## Phase 0 — Pre-flight

```sh
# Cluster is green and etcd is healthy (expect 3 members, all on .51/.52/.53)
kubectl get nodes -o wide
talosctl -n 10.10.20.51 etcd members
talosctl -n 10.10.20.51 health --wait-timeout=5m

# Back up etcd before touching control-plane VMs.
talosctl -n 10.10.20.51 etcd snapshot etcd-backup-pre-collapse.db

# Confirm the plan matches expectations: 3 worker VMs to destroy,
# 3 master VMs updated/replaced. Read the create/replace markers.
tofu plan
```

If master-1/2 show `-/+ destroy and then create replacement` (not in-place update),
treat Phase 2 as a node rebuild — that is already what the steps below assume.

## Phase 1 — Drain and destroy the worker pool (frees the iGPUs)

```sh
# Move workloads off the workers; the dual-role masters already allow scheduling
# (allowSchedulingOnControlPlanes = true), so pods reschedule onto them.
for n in talos-worker-1 talos-worker-2 talos-worker-3; do
  kubectl drain "$n" --ignore-daemonsets --delete-emptydir-data --timeout=10m
done

# Destroy ONLY the worker VMs. They are already removed from config, so a targeted
# destroy isolates them from the master changes and releases the igpu mappings on
# nacho and tamale.
tofu destroy \
  -target='module.talos_cluster.module.worker_vms["talos-worker-1"]' \
  -target='module.talos_cluster.module.worker_vms["talos-worker-2"]' \
  -target='module.talos_cluster.module.worker_vms["talos-worker-3"]'

# Remove the now-gone nodes from the cluster.
for n in talos-worker-1 talos-worker-2 talos-worker-3; do
  kubectl delete node "$n" --ignore-not-found
done

# Sanity: etcd still 3 members (workers were never etcd), GPUs now free in Proxmox.
talosctl -n 10.10.20.51 etcd members
```

## Phase 2 — Migrate masters ONE AT A TIME

Strict serialization is the safeguard against quorum loss: never let more than one control-plane node be down.
After each node, wait for **3 healthy etcd members** before starting the next.

Repeat this block for `talos-master-1`, then `talos-master-2`, then `talos-master-3`
(IPs .51, .52, .53). Use `-parallelism=1` and target both the VM and its config-apply.

```sh
NODE=talos-master-1 ; IP=10.10.20.51   # then -2/.52, then -3/.53

# Cordon + drain the node we're about to disrupt.
kubectl cordon  "$NODE"
kubectl drain   "$NODE" --ignore-daemonsets --delete-emptydir-data --timeout=10m

# Apply just this node's VM + machine config. Resizes it, and for master-1/2 flips
# bios→OVMF, adds the EFI disk, and attaches the freed iGPU.
tofu apply -parallelism=1 \
  -target="module.talos_cluster.module.controlplane_vms[\"$NODE\"]" \
  -target="module.talos_cluster.talos_machine_configuration_apply.controlplane[\"$NODE\"]"

# If the VM was REPLACED (fresh disk), the member left etcd; let it re-bootstrap and
# rejoin. Wait until etcd reports 3 healthy members again BEFORE moving on.
talosctl -n 10.10.20.51 etcd members
talosctl -n "$IP" health --wait-timeout=10m
kubectl uncordon "$NODE"
kubectl get nodes -o wide   # node Ready before continuing
```

> If `tofu plan` showed an in-place update (reboot) rather than a replacement, the same
> steps apply — the node just reboots instead of rebuilding, and rejoins etcd faster.

## Phase 3 — Reconcile and verify

```sh
# Final full apply: removes the leftover worker data sources / config-apply /
# local_file state entries and confirms zero drift. Should report "No changes".
tofu apply

kubectl get nodes -o wide                       # 3 Ready nodes, all dual-role
talosctl -n 10.10.20.51 etcd members            # 3 members, all healthy
kubectl get nodes -l gpu=amd-igpu               # master-1 and master-2 labelled
talosctl -n 10.10.20.51 health --wait-timeout=5m
```

## Rollback

- A failed `tofu apply` on a single master leaves the other two up (quorum intact).
  Re-run the Phase 2 block for that node, or `talosctl -n <ip> reset` and let it rejoin.
- Worst case (etcd quorum lost): recover from the Phase 0 snapshot with
  `talosctl -n <ip> bootstrap --recover-from etcd-backup-pre-collapse.db`.
- The destroyed workers are reproducible from git history if the collapse is abandoned
  (`git revert`/checkout the pre-collapse `tf/variables.tf` and `tofu apply`).

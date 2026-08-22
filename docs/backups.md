# Backup System

This document describes the PVC backup system used to protect
persistent application data in the Kubernetes cluster.

## Overview

The backup system uses [VolSync](https://volsync.readthedocs.io/)
with the [Kopia](https://kopia.io/) backend to create daily snapshots
of application PersistentVolumeClaims (PVCs). Backups are written over
NFS to the TrueNAS server at `10.10.20.20`.

This covers **persistent data only**. Cluster configuration (manifests,
Helm values, secrets) is the source of truth in this Git repository and
is recovered by Flux CD during a rebuild.

## Components

### VolSync Operator

- **Namespace:** `volsync-system`
- **Image:** `ghcr.io/perfectra1n/volsync:v0.17.11`
  (perfectra1n fork with Kopia support)
- **Helm chart:**
  `oci://ghcr.io/home-operations/charts-mirror/volsync-perfectra1n`
  (v0.18.5)
- **Deployed by:** Flux, via `apps/production/core/volsync/`

### Snapshot Controller

- **Namespace:** `snapshot-controller`
- **Helm chart:**
  `oci://ghcr.io/piraeusdatastore/helm-charts/snapshot-controller`
  (v5.0.3)
- **Purpose:** Provides the Kubernetes VolumeSnapshot API, used by
  VolSync to create point-in-time snapshots before running a backup
- **Deployed by:** Flux, via
  `apps/production/core/snapshot-controller/`

### VolumeSnapshotClass

- **Name:** `csi-ceph-blockpool`
- **Driver:** `rook-ceph.rbd.csi.ceph.com`
- **Defined in:**
  `apps/production/storage/ceph-cluster/volumesnapshotclass.yaml`

## Backup Configuration

Each backed-up application has a `replicationsource.yaml` that defines
its VolSync ReplicationSource. All share the same configuration pattern:

| Setting        | Value                                           |
| -------------- | ----------------------------------------------- |
| Schedule       | `0 16 * * *` (daily at 16:00 UTC / 02:00 AEST)  |
| Backend        | Kopia                                           |
| Compression    | `zstd-fastest`                                  |
| Copy method    | `Snapshot` (Ceph RBD volume snapshot)           |
| Parallelism    | 2                                               |
| Retention      | 7 daily snapshots                               |
| Storage class  | `rook-ceph-block`                               |
| Snapshot class | `csi-ceph-blockpool`                            |
| Destination    | NFS: `10.10.20.20:/mnt/tank/backups/k8s`        |

### Backup Flow

1. The cron trigger fires at 16:00 UTC
2. VolSync creates a VolumeSnapshot of the source PVC via the
   Ceph CSI driver
3. A mover pod mounts the snapshot (read-only) and the NFS repository
4. Kopia deduplicates, compresses, and writes the backup to the
   NFS target
5. The temporary snapshot is cleaned up

Applications continue running uninterrupted because the backup reads
from the snapshot, not the live PVC.

## Backed-Up Applications

### Media namespace (8 apps)

| App         | PVC                  | UID/GID | Manifest                                   |
| ----------- | -------------------- | ------- | ------------------------------------------ |
| Jellyfin    | `jellyfin-config`    | 3000    | `media/jellyfin/replicationsource.yaml`    |
| qBittorrent | `qbittorrent-config` | 3000    | `media/qbittorrent/replicationsource.yaml` |
| Radarr      | `radarr`             | 3000    | `media/radarr/replicationsource.yaml`      |
| Sonarr      | `sonarr`             | 3000    | `media/sonarr/replicationsource.yaml`      |
| Bazarr      | `bazarr`             | 3000    | `media/bazarr/replicationsource.yaml`      |
| Prowlarr    | `prowlarr`           | 3000    | `media/prowlarr/replicationsource.yaml`    |
| SABnzbd     | `sabnzbd`            | 3000    | `media/sabnzbd/replicationsource.yaml`     |
| Jellyseerr  | `jellyseerr`         | 3000    | `media/jellyseerr/replicationsource.yaml`  |

All manifest paths are relative to `apps/production/apps/`.

### Security namespace (1 app)

| App      | PVC        | UID/GID | Manifest                                                   |
| -------- | ---------- | ------- | ---------------------------------------------------------- |
| Authelia | `authelia` | 8000    | `apps/production/security/authelia/replicationsource.yaml` |

## Secrets

Each namespace with backups has a `volsync-secret` Kubernetes Secret
containing Kopia repository credentials (`KOPIA_PASSWORD`,
`KOPIA_REPOSITORY`). These are SOPS-encrypted at rest:

- `apps/production/apps/media/volsync-secret.yaml`
- `apps/production/security/authelia/volsync-secret.yaml`

All media apps share a single Kopia repository (and therefore a single
secret), enabling cross-app deduplication.

## Monitoring

A Grafana dashboard ("VolSync Backups") is deployed via the Grafana
Operator CRD at:
`apps/production/monitoring/grafana/instance/volsync-dashboard.yaml`

### Dashboard panels

#### Backup Status

- **Sync Status** (`volsync_volume_out_of_sync`):
  Shows "Out of Sync" (red) when a backup is stale.
- **Missed Intervals** (`volsync_missed_intervals_total`):
  Yellow at 1 missed, red at 3+.

#### Backup Duration

- **Sync Duration** (`volsync_sync_duration_seconds`):
  Yellow above 5 min, red above 10 min.

#### Kopia Repository

- **Repository Connectivity**
  (`volsync_kopia_repository_connectivity`):
  "Disconnected" (red) means NFS or repo issue.
- **Retention Compliance**
  (`volsync_kopia_retention_compliance`):
  "Non-Compliant" means the retention policy is not met.
- **Cache Size** (`volsync_kopia_cache_size_bytes`):
  Trend monitoring only.

#### Errors

- **Snapshot Creation Failures**
  (`volsync_kopia_snapshot_creation_failure_total`):
  Any non-zero value in last 24h.
- **Operation Failures**
  (`volsync_kopia_operation_failure_total`):
  Any non-zero value in last 24h.

## Flux Dependency Chain

Backups depend on several layers being deployed in order:

```text
cert-manager
  └── core (volsync, snapshot-controller)
        └── storage (rook-ceph, VolumeSnapshotClass)
              ├── apps (media ReplicationSources)
              └── security (authelia ReplicationSource)
```

## Adding Backups to a New Application

1. Create a `replicationsource.yaml` in the app's directory.
   Use an existing one as a template
   (e.g., `apps/production/apps/media/radarr/replicationsource.yaml`).

2. Update the metadata (`name`, `namespace`) and `sourcePVC` to
   match the app.

3. Set the `moverSecurityContext` to match the UID/GID the app
   runs as.

4. If the app is in a new namespace that doesn't already have a
   `volsync-secret`, create one:

   ```bash
   sops apps/production/<category>/<app>/volsync-secret.yaml
   ```

   It needs `KOPIA_PASSWORD` and `KOPIA_REPOSITORY` in `stringData`.
   For apps sharing an existing Kopia repository (e.g., all media
   apps), reuse the same credentials.

5. Add the new files to the app's `kustomization.yaml`.

6. Run `make validate` before committing.

## Disaster Recovery

### Single app data loss

Restore the PVC from the Kopia repository. VolSync supports
ReplicationDestination resources for restoring data into a new or
existing PVC.

### Full cluster rebuild

1. Flux reconciles all manifests from this repository
   (cluster config recovery)
2. SOPS decrypts secrets using the PGP key
3. VolSync operator starts and processes ReplicationSource resources
4. To restore data, create ReplicationDestination resources targeting
   the Kopia repository on NFS

### What is NOT backed up by VolSync

- The shared `media-library` PVC (large media files) -- relies on
  TrueNAS-level protection
- PostgreSQL databases -- rely on Ceph redundancy (consider adding
  WAL-based backups)

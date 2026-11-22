# Backups

Cluster configuration is not backed up here.
It lives in this repository and Flux rebuilds it.
This page covers the data that git cannot recreate.

## Layers

| Layer                | Protects                                      | Lands on                                   | Retention                                                                          |
| -------------------- | --------------------------------------------- | ------------------------------------------ | ---------------------------------------------------------------------------------- |
| VolSync              | App PVCs on Ceph                              | `tank/backups/k8s` on mole                 | 30 daily, 6 monthly                                                                |
| CloudNativePG barman | Postgres, with WAL for point-in-time recovery | `tank/backups/k8s/postgres-barman` on mole | 30 days                                                                            |
| ZFS snapshots        | Immich photos and the backup datasets         | mole                                       | see [the snapshot tasks](../truenas/offsite-backup/README.md#1-zfs-snapshot-tasks) |
| Offsite              | Photos and everything in `tank/backups/k8s`   | Backblaze B2 EU Central                    | 30 daily, 8 weekly, 12 monthly                                                     |

So the Immich library, the Immich database and all app state each exist live, as local snapshots on mole,
and as an encrypted offsite copy.
The offsite leg is documented in [truenas/offsite-backup/README.md](../truenas/offsite-backup/README.md).

### Deliberately not backed up

- `tank/media`, because it can be downloaded again.
- climate-ref, vela and the runner caches, because they are work data or rebuildable.
- `tank/backups/timemachine`, because the laptop has its own offsite backup.
- Prometheus, Loki and Tempo data, because it is high-churn and the dashboards are in git.

## VolSync

VolSync (perfectra1n fork with Kopia, `apps/production/core/volsync/`) snapshots each PVC through the
`csi-ceph-blockpool` VolumeSnapshotClass and writes it with Kopia to `10.10.20.20:/mnt/tank/backups/k8s`.
It runs daily at 16:00 UTC, which is 02:00 or 03:00 in Melbourne depending on daylight saving.

Most apps get their ReplicationSource from the shared component `components/volsync`.
The app's Flux Kustomization (`ks.yaml`) lists the component and sets substitutions:

| Variable                       | Default  | Meaning                               |
| ------------------------------ | -------- | ------------------------------------- |
| `APP`                          | none     | ReplicationSource name and PVC name   |
| `VOLSYNC_CLAIM`                | `${APP}` | PVC name when it differs from the app |
| `VOLSYNC_PUID`, `VOLSYNC_PGID` | 3000     | User and group the mover runs as      |

Authelia keeps its own `apps/production/security/authelia/replicationsource.yaml`.

Backed up today:

| Namespace        | ReplicationSources                                                                                                              |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `media`          | bazarr, calibre-web-automated, jellyfin-config, jellyseerr, prowlarr, qbittorrent-config, radarr, sabnzbd, sonarr, tdarr-config |
| `authelia`       | authelia                                                                                                                        |
| `hermes`         | hermes                                                                                                                          |
| `home-assistant` | home-assistant                                                                                                                  |
| `openviking`     | openviking                                                                                                                      |
| `unifi`          | unifi                                                                                                                           |

Check the live list with `kubectl get replicationsource -A`.

### Adding an app

1. Add `../../../../../components/volsync` (adjusted for depth) to `components` in the app's `ks.yaml`.
2. Set `APP` under `postBuild.substitute`, plus `VOLSYNC_CLAIM` and the IDs when the defaults do not fit.
3. If the namespace has no `volsync-secret` yet, create one with `sops`.
   It needs `KOPIA_PASSWORD` and `KOPIA_REPOSITORY`.
   Apps in one namespace share a repository, so they deduplicate against each other.
4. Run `make validate`.

### Monitoring

The "VolSync Backups" Grafana dashboard (`apps/production/monitoring/grafana/instance/volsync-dashboard.yaml`)
shows sync status, missed intervals, duration, repository connectivity and Kopia errors.

## Postgres

Both CNPG clusters archive WAL continuously and take a daily base backup through the s3proxy in the
`database` namespace, which stores it on the `postgres-barman` NFS volume.

| Cluster               | Base backup (UTC) |
| --------------------- | ----------------- |
| `postgres` (date-jar) | 03:00             |
| `immich-postgres`     | 03:30             |

A file-level copy of a running database is not a backup, so this is the only path for database recovery.
See [postgres-restore.md](postgres-restore.md).

## Restoring

- One app: create a VolSync ReplicationDestination against the namespace's `volsync-secret`
  and point the PVC at it.
- One database: follow [postgres-restore.md](postgres-restore.md).
- A file from yesterday on mole: copy it out of `<dataset>/.zfs/snapshot/<name>/`.
- mole lost: restore `tank/photos` and `tank/backups/k8s` from B2 first, see
  [Restoring with mole gone](../truenas/offsite-backup/README.md#restoring-with-mole-gone).
  Then rebuild the cluster with Flux and restore apps and databases as above.

A rebuild also needs the SOPS PGP key and the B2 credentials, which live in the password manager.

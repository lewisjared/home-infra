# PostgreSQL restore

The shared production `postgres` CNPG cluster is backed up to the retained
TrueNAS NFS directory mounted by the internal S3Proxy. Date Jar uses the
`date_jar` database in that shared cluster; this runbook validates restoring
Date Jar from the shared-cluster backup. SeaweedFS is deliberately not used for
this disaster-recovery path because it shares the Ceph failure domain.

## Storage prerequisite

Before the first backup, create an isolated directory on TrueNAS and grant it to
the UID/GID used by the S3Proxy (`1000:1000`):

```sh
mkdir -p /mnt/tank/backups/k8s/postgres-barman
chown 1000:1000 /mnt/tank/backups/k8s/postgres-barman
chmod 0700 /mnt/tank/backups/k8s/postgres-barman
```

The export must be reachable as `10.10.20.20:/mnt/tank/backups/k8s` and the
Kubernetes PV mounts only the `postgres-barman` subdirectory. The S3Proxy init
container creates the `postgres-barman` bucket inside that mount. Do not reuse
this directory for another backup repository. Keep the underlying TrueNAS
dataset encrypted at rest; S3Proxy provides authenticated S3 access but does
not add client-side backup encryption.

## Isolated restore

1. Confirm the most recent WAL archive and base backup in the `postgres-barman`
   repository and record the target recovery time.
2. Stop Date Jar and create a separate, isolated CNPG cluster (for example,
   `postgres-restore`) in the `database-restore` namespace. Never point the
   restore at the production `postgres` Service or production PVCs.
3. Configure the isolated cluster's `bootstrap.recovery` with the same internal
   S3Proxy endpoint, the shared-cluster Barman destination
   (`s3://postgres-barman/postgres`), and the S3 credentials stored in the
   cluster's secret manager. Select the required backup or recovery target.
4. Wait for CNPG recovery to report healthy, then validate the restored
   `date_jar` database and application migrations using read-only checks.
5. Export any required data from the isolated cluster. Promote it to production
   only after an explicit change review; do not alter production resources as
   part of the restore test.

Keep the production backup repository and credentials unchanged during a test.
If the NFS share or S3Proxy is unavailable, fix that prerequisite before retrying
recovery rather than switching to SeaweedFS.

## Quarterly drill

Run an isolated restore at least quarterly and after any CNPG, S3Proxy, or
TrueNAS storage change. Record the backup timestamp, recovery duration, WAL
continuity, row-level validation results, and the operator who performed the
drill. Remove the isolated cluster and temporary resources only after the
record is complete.

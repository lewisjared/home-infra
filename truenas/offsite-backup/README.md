# Offsite backup: mole to Backblaze B2

Kopia runs as a TrueNAS custom app on mole.
Each night it snapshots the newest `daily-*` ZFS snapshot of each source into a Kopia repository in B2 EU Central.
It reads the ZFS snapshot, never the live tree, so every upload is one consistent point in time.

| Source             | Mounted at     | What it holds                                                                                  |
| ------------------ | -------------- | ---------------------------------------------------------------------------------------------- |
| `tank/photos`      | `/data/photos` | Immich originals. `thumbs/` and `encoded-video/` are excluded because Immich regenerates them. |
| `tank/backups/k8s` | `/data/k8s`    | The VolSync Kopia repository and the CNPG barman archive, including the Immich database.       |

Protection on the B2 side:

- Kopia encrypts client-side, so B2 only ever holds ciphertext.
- Every object carries a 30-day GOVERNANCE Object Lock, and daily full maintenance extends it.
  The app's key has no `bypassGovernance`, so a compromised mole cannot erase the last 30 days.
- Retention is 30 daily, 8 weekly and 12 monthly snapshots.

## Schedule

| Time                   | What                                                                                              |
| ---------------------- | ------------------------------------------------------------------------------------------------- |
| 02:00                  | TrueNAS takes the `daily-*` snapshot of `tank/photos`.                                            |
| 03:00                  | TrueNAS takes the `daily-*` snapshot of `tank/backups/k8s`, after VolSync finishes.               |
| 04:00                  | The app snapshots both sources to B2, then runs Kopia full maintenance. A failure retries hourly. |
| 15th, after the backup | The drill reads 2% of file contents back from B2 and checks their hashes.                         |

The app refuses a ZFS snapshot older than 36 hours, so a stopped snapshot task shows up as a failed backup.

## Monitoring

The `metrics` container serves `http://10.10.20.20:9851/metrics`, scraped by the Prometheus job `offsite-backup`.
Alerts live in the `offsite-backup-alerts` group of `apps/production/monitoring/prometheus/alerting-rules.yaml`:

- `OffsiteBackupStale` fires when a source has not reached B2 for 36 hours.
- `OffsiteBackupMissing` fires when there are no metrics at all.
- `OffsiteBackupMaintenanceFailing` fires when full maintenance has not succeeded for two days, because it extends the locks.
- `OffsiteBackupDrillFailed` fires when the drill fails or has not passed for 40 days.

## Setup

### 1. ZFS snapshot tasks

In TrueNAS, under Data Protection, add these periodic snapshot tasks.
Kopia selects snapshots by the `daily-` prefix, so the naming schemas matter.

| Dataset            | Naming schema            | Schedule           | Keep      |
| ------------------ | ------------------------ | ------------------ | --------- |
| `tank/photos`      | `hourly-%Y-%m-%d_%H-%M`  | every hour         | 2 days    |
| `tank/photos`      | `daily-%Y-%m-%d_%H-%M`   | daily 02:00        | 30 days   |
| `tank/photos`      | `weekly-%Y-%m-%d_%H-%M`  | Sunday 02:00       | 8 weeks   |
| `tank/photos`      | `monthly-%Y-%m-%d_%H-%M` | 1st of month 02:00 | 12 months |
| `tank/backups/k8s` | `daily-%Y-%m-%d_%H-%M`   | daily 03:00        | 14 days   |

Then delete the old `auto-%Y-%m-%d_%H-%M` task on `tank/photos`.
Its last few `auto-*` snapshots are no longer managed, so remove them by hand once the new tasks have run for a while.

### 2. B2 bucket and key

The B2 region is fixed per account at sign-up, so the account itself must be in EU Central.

1. Create a private bucket with Object Lock enabled.
   Object Lock can only be switched on when the bucket is created.
   Leave the bucket's default retention unset, because Kopia sets retention on each object.
2. Create an application key restricted to that bucket, without `bypassGovernance`.
   With the B2 CLI:

   ```bash
   b2 key create --bucket <bucket> offsite-mole \
     listBuckets,listFiles,readFiles,writeFiles,deleteFiles,readBucketRetentions,readFileRetentions,writeFileRetentions
   ```

3. Generate a repository password with `openssl rand -base64 33`.
4. Save the bucket name, key ID, application key and repository password in the password manager,
   next to the SOPS PGP key.
   Nothing in B2 can be read without them.

### 3. Host directories

From the repository root on the laptop:

```bash
scp truenas/offsite-backup/offsite-backup.sh truenas/offsite-backup/kopia.env.example jared@10.10.20.20:/tmp/
```

Then in a TrueNAS shell:

```bash
sudo mkdir -p /mnt/tank/backups/offsite/{scripts,config,cache,logs,state,metrics}
sudo chmod 700 /mnt/tank/backups/offsite
sudo install -m 755 /tmp/offsite-backup.sh /mnt/tank/backups/offsite/scripts/
sudo install -m 600 /tmp/kopia.env.example /mnt/tank/backups/offsite/kopia.env
sudo nano /mnt/tank/backups/offsite/kopia.env
```

Fill in `kopia.env` with the values from step 2.
Check that `B2_ENDPOINT` matches the endpoint on the bucket's details page.

### 4. Install the app

In TrueNAS, open Apps, then Discover Apps, then Custom App, then Install via YAML.
Name it `offsite-backup` and paste `compose.yaml`.

The app starts and waits for a repository, logging a retry every 10 minutes.

### 5. Create the repository

```bash
sudo docker exec offsite-backup /scripts/offsite-backup.sh init
sudo docker restart offsite-backup
sudo docker logs -f offsite-backup
```

`init` creates the locked repository and applies the policies. It is safe to run again.
After the restart, the loop starts the first backup straight away if it is past 04:00.
The first upload is about 60 GB, so expect it to take hours.

If the log says a snapshot directory `is empty, check the bind mount propagation`,
the ZFS automount is not reaching the container. This is the one part that could not be tested off mole.

### 6. Check it

```bash
curl -s http://10.10.20.20:9851/metrics
sudo docker exec offsite-backup kopia snapshot list --all
```

Restore one real photo and compare it with the ZFS snapshot it came from:

```bash
sudo docker exec offsite-backup kopia ls -r <root-id> | grep library/ | head
sudo docker exec offsite-backup kopia restore <root-id>/library/<path> /tmp/check
sudo docker exec offsite-backup sh -c 'sha256sum /tmp/check /data/photos/.zfs/snapshot/<daily-name>/library/<path>'
```

The root ID is in the `kopia snapshot list` output.
Run the drill by hand once with `sudo docker exec offsite-backup /scripts/offsite-backup.sh drill`.

## Restoring with mole gone

Install Kopia anywhere and take the four values from the password manager:

```bash
export KOPIA_PASSWORD=<repository password>
kopia repository connect s3 --bucket=<bucket> --endpoint=s3.eu-central-003.backblazeb2.com \
  --prefix=mole/ --access-key=<key id> --secret-access-key=<application key>
kopia snapshot list --all
kopia restore <photos snapshot id> /restore/photos
kopia restore <k8s snapshot id> /restore/k8s
```

`/restore/photos` goes back to `tank/photos`, owned by 3000:3000.
`/restore/k8s` goes back to `tank/backups/k8s`.
From there, VolSync restores app PVCs and CNPG recovers the databases, see [docs/backups.md](../../docs/backups.md).

## Changing things

- Retention: `kopia policy set --global --keep-daily=...` inside the container.
- Lock period: `kopia repository set-parameters --retention-mode=GOVERNANCE --retention-period=<days>d`.
  Keep it well above the daily full maintenance that extends it.
- Script changes: copy the new `offsite-backup.sh` to `/mnt/tank/backups/offsite/scripts/` and restart the app.
- Deleting the repository: locked objects cannot be removed for 30 days without a key that has `bypassGovernance`.

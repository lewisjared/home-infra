# Climate REF - Kubernetes Deployment

Full CMIP6 ensemble evaluation using Climate REF on local Kubernetes with NFS-backed persistent storage.

## Architecture

```text
                    +-----------------+
                    |   Flower UI     |
                    | :5555 (Authelia)|
                    +--------+--------+
                             |
+------------+     +---------+---------+     +------------+
| esgpull    |     |   Orchestrator    |     | Dragonfly  |
| CronJob    |     |   (Celery beat)   |     | (broker)   |
| daily 02:00|     +---+-----+-----+--+     +------------+
+-----+------+         |     |     |
      |           +----+  +--+--+  +----+
      |           | ESM | | PMP |  |ILAMB|   <- Celery workers
      |           +--+--+ +--+--+  +--+--+
      |              |       |        |
+-----v--------------v-------v--------v-----+
|              NFS (10.10.20.20)             |
|  /mnt/tank/climate-ref/                    |
|    cmip6/   - CMIP6 model data (5Ti)      |
|    obs/     - Observation data (100Gi)     |
|    state/   - DB, conda envs, results     |
|    esgpull/ - esgpull config + DB          |
+--------------------------------------------+

+------------------+
| ref-ingest-solve |
| CronJob          |
| daily 06:00      |
+------------------+
```

## Prerequisites

1. NFS server at `10.10.20.20` with exports under `/mnt/tank/climate-ref/`
2. Flux CD managing the cluster
3. Traefik ingress with Gateway API support
4. Authelia for authentication

## NFS Setup

Create the required directories on the NFS server:

```bash
ssh 10.10.20.20
mkdir -p /mnt/tank/climate-ref/{cmip6,obs,state,esgpull}
chown -R 1000:1000 /mnt/tank/climate-ref/
```

Ensure the NFS export allows read/write from the cluster nodes:

```bash
# /etc/exports (example)
/mnt/tank/climate-ref 10.10.20.0/24(rw,sync,no_subtree_check,no_root_squash)
```

## Deployment

Push to the Git repo. Flux reconciles automatically:

```bash
git add apps/production/apps/climate-ref/
git commit -m "climate-ref: add NFS storage, esgpull sync, and ingest jobs"
git push
```

Verify reconciliation:

```bash
flux get kustomization apps
kubectl -n climate-ref get pvc
kubectl -n climate-ref get pods
```

## Initial Setup (One-Time)

### 1. Verify PVCs are bound

```bash
kubectl -n climate-ref get pvc
# All PVCs should show STATUS=Bound
```

### 2. Set up providers

```bash
kubectl -n climate-ref exec -it deploy/climate-ref-orchestrator -- ref config list
kubectl -n climate-ref exec -it deploy/climate-ref-orchestrator -- ref providers setup
```

This creates conda environments for ESMValTool and PMP, and fetches reference/observation data.

### 3. Initialize esgpull queries

Create a one-off job from the CronJob and exec into it to run the query setup script:

```bash
# Create the init job
kubectl -n climate-ref create job esgpull-init --from=cronjob/esgpull-sync

# Wait for it to start, then exec in
kubectl -n climate-ref wait --for=condition=ready pod -l job-name=esgpull-init --timeout=120s
kubectl -n climate-ref exec -it job/esgpull-init -- sh

# Inside the pod, run the query setup
export PYTHONPATH=/tools/lib:$PYTHONPATH
export PATH=/tools/bin:/tools/lib/bin:$PATH
sh /queries/setup-queries.sh

# Verify queries were added
esgpull search --all

# Exit and let the job complete normally (it will run update + download)
exit
```

Alternatively, mount the ConfigMap in the CronJob and run the script directly. The queries persist in the esgpull NFS volume.

### 4. Trigger first sync manually

```bash
kubectl -n climate-ref create job --from=cronjob/esgpull-sync manual-sync-$(date +%s)
```

### 5. Trigger first ingest manually

After some CMIP6 data has been downloaded:

```bash
kubectl -n climate-ref create job --from=cronjob/ref-ingest-solve manual-ingest-$(date +%s)
```

## Monitoring

### Flower UI

Available at `https://climate-ref.home.lewelly.com` (protected by Authelia).

Shows Celery task queues, worker status, and task results.

### Check execution status

```bash
kubectl -n climate-ref exec deploy/climate-ref-orchestrator -- ref executions list-groups
```

### View logs

```bash
# Orchestrator
kubectl -n climate-ref logs deploy/climate-ref-orchestrator

# Workers
kubectl -n climate-ref logs deploy/climate-ref-esmvaltool
kubectl -n climate-ref logs deploy/climate-ref-pmp
kubectl -n climate-ref logs deploy/climate-ref-ilamb

# esgpull sync job
kubectl -n climate-ref logs job/esgpull-sync-<id>

# Ingest job
kubectl -n climate-ref logs job/ref-ingest-solve-<id>
```

## Manual Operations

### Trigger esgpull sync

```bash
kubectl -n climate-ref create job --from=cronjob/esgpull-sync manual-sync-$(date +%s)
```

### Trigger ingest + solve

```bash
kubectl -n climate-ref create job --from=cronjob/ref-ingest-solve manual-ingest-$(date +%s)
```

### Check disk usage

```bash
ssh 10.10.20.20 du -sh /mnt/tank/climate-ref/*
```

## Data Volume Estimates

| Volume  | Estimated Size | Contents                                         |
|---------|----------------|--------------------------------------------------|
| cmip6   | 1-5 TB         | Full CMIP6 ensemble (all models, all members)    |
| obs     | 10-50 GB       | Observation and reference datasets               |
| state   | 5-20 GB        | SQLite DB, conda environments, diagnostic results|
| esgpull | <100 MB        | esgpull configuration and tracking database      |

## CronJob Schedule

| Job                | Schedule        | Purpose                                 |
|--------------------|-----------------|---------------------------------------- |
| `esgpull-sync`     | Daily 02:00 UTC | Sync CMIP6 data from ESGF               |
| `ref-ingest-solve` | Daily 06:00 UTC | Ingest new data and trigger evaluations |

## Troubleshooting

### NFS permission errors

Ensure the NFS directories are owned by UID/GID 1000:

```bash
ssh 10.10.20.20 chown -R 1000:1000 /mnt/tank/climate-ref/
```

### PVCs stuck in Pending

Check if the PV exists and the storageClassName matches:

```bash
kubectl get pv | grep climate-ref
kubectl -n climate-ref describe pvc <name>
```

### Conda environment creation fails

ESMValTool and PMP require conda environments. If setup fails:

```bash
kubectl -n climate-ref exec -it deploy/climate-ref-orchestrator -- \
  ref providers setup --provider esmvaltool
```

Check that the state volume has enough space and that conda can write to it.

### SQLite locking errors

SQLite on NFS can have locking issues under concurrent access. If you see
`database is locked` errors, consider:

1. Ensuring only one writer at a time (the CronJobs use `concurrencyPolicy: Forbid`)
2. Setting `PRAGMA journal_mode=WAL` in the REF configuration
3. Migrating to PostgreSQL for production workloads

### esgpull download failures

ESGF nodes can be unreliable. The CronJob will retry daily. Check logs:

```bash
kubectl -n climate-ref logs job/<esgpull-job-name>
```

You can also configure fallback nodes in the esgpull config:

```bash
kubectl -n climate-ref exec -it job/<esgpull-job-name> -- \
  esgpull config api.index_node esgf-data.dkrz.de
```

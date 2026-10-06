# Climate REF

A test-bed for the [climate-ref-aft](https://github.com/Climate-REF/climate-ref-aft) Helm chart.
It runs the CMIP7 Assessment Fast Track providers (ESMValTool, PMP and ILAMB) against the local CMIP6 archive.

The chart does almost everything.
This directory adds the NFS volumes, the Authelia middleware, the ESGF fetch cronjob and a Grafana dashboard.

## Layout

| Path                        | What it is                                                     |
| --------------------------- | -------------------------------------------------------------- |
| `helmrelease.yaml`          | The chart and its values                                       |
| `middleware.yaml`           | Authelia forward-auth, attached to the chart's HTTPRoutes      |
| `pvc/`                      | Static NFS volumes for state (`/ref`), CMIP6 and observations  |
| `esgpull/`                  | Daily `esgf-fetch` cronjob that downloads CMIP6 data from ESGF |
| `monitoring/dashboard.yaml` | Grafana dashboard over the Flower and Dragonfly metrics        |
| `testbed.sh`                | Bring up, bootstrap, solve, watch, verify and tear down        |

## How it fits together

- The API serves the frontend at `climate-ref.home.lewelly.com`.
  Flower is at `flower.climate-ref.home.lewelly.com`. Both sit behind Authelia.
- Dragonfly is the Celery broker. It has no volume, so a restart drops the queues.
- The orchestrator consumes the default queue and copies results into `/ref/results`.
- Each provider has its own worker Deployment.
  KEDA scales it from zero on the length of its queue, and holds a busy worker up through Flower's running task count.
  Workers scale back to zero five minutes after the last task finishes.
- A pre-install hook runs `ref db migrate`.
  The database is SQLite under `/ref/db`.

| Mount         | Volume                  | NFS path                                  | Access                                            |
| ------------- | ----------------------- | ----------------------------------------- | ------------------------------------------------- |
| `/ref`        | `climate-ref-state-csi` | `10.10.30.20:/mnt/fast/climate-ref`       | Read-write, read-only on the API except `/ref/db` |
| `/data/cmip6` | `climate-ref-cmip6-csi` | `10.10.30.20:/mnt/tank/climate-ref/cmip6` | Read-only                                         |
| `/data/obs`   | `climate-ref-obs-csi`   | `10.10.30.20:/mnt/tank/climate-ref/obs`   | Read-only, read-write on the orchestrator         |

`/ref` holds the database, results, scratch, logs, the conda environments (`/ref/software`) and the reference data cache (`/ref/cache`).
obs4REF lives at `/data/obs/obs4REF`, so it survives a teardown.

## Test-bed

Run everything from the repository root with the home cluster as the current context.

```bash
apps/production/apps/climate-ref/testbed.sh e2e
```

`e2e` runs these steps in order. Each one also runs on its own.

| Step                  | What it does                                                                                              |
| --------------------- | --------------------------------------------------------------------------------------------------------- |
| `up`                  | Resumes the Flux Kustomization and waits for the release                                                  |
| `bootstrap`           | `ref providers setup`, restarts the API, fetches obs4REF if missing, ingests obs4REF and CMIP6            |
| `solve [smoke\|wide]` | Queues executions and returns                                                                             |
| `watch`               | Prints queue length, running executions and worker replicas until everything is back at zero              |
| `verify`              | Fails unless each provider has a success, nothing failed, queued or running, and the API lists executions |

`solve smoke` queues one quick diagnostic per provider and takes a few minutes.
`solve wide` queues one execution per diagnostic.
It pushes every worker pool to its maximum, but ESMValTool executions can run for hours.
Extra arguments go straight to `ref solve`, for example `solve smoke --dataset-filter source_id=ACCESS-ESM1-5`.

Set `CMIP6_PATH` to ingest part of the archive, for example `CMIP6_PATH=/data/cmip6/CMIP/CSIRO`.

`status` prints one snapshot of the pods, autoscalers, queues and executions.

`verify` checks every execution in the database, not only the latest solve.
Run `down` first for a result that covers one solve alone.

### Tear down

```bash
apps/production/apps/climate-ref/testbed.sh down
```

This suspends the Flux Kustomization, uninstalls the release and wipes the database, results, scratch and logs.
It keeps the conda environments and the reference data cache, so the next `bootstrap` takes minutes rather than hours.
`down --purge` wipes those too, which makes the next `bootstrap` a true first install.
The CMIP6 archive and obs4REF are never touched.
It refuses to wipe while any pod still mounts the state volume, including jobs outside the release.

The Kustomization stays suspended until `up`.

## Manual operations

```bash
alias ref-orch="kubectl -n climate-ref exec deploy/climate-ref-orchestrator -c orchestrator --"
ref-orch ref executions list-groups --not-successful
ref-orch ref executions inspect <execution id>
ref-orch ref doctor
kubectl -n climate-ref create job --from=cronjob/esgf-fetch manual-fetch-$(date +%s)
```

The upstream runbooks cover the rest:
[bootstrap a deployment](https://github.com/Climate-REF/climate-ref-aft/blob/main/docs/runbooks/bootstrap-a-deployment.md)
and [run and triage a solve](https://github.com/Climate-REF/climate-ref-aft/blob/main/docs/runbooks/run-and-triage-a-solve.md).

## Upgrades

Bump the tag on the `OCIRepository` in `helmrelease.yaml`.
The chart pins the API and worker images, so they move with it.
Upgrade between solves, because every worker restarts and in-flight executions run again.
Run `testbed.sh bootstrap` afterwards, because `ref providers setup` must rerun after an update.

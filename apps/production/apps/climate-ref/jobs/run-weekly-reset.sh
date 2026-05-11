#!/bin/sh
# Weekly full reset: wipe REF state config dir (DB + caches), keep
# /ref/software (conda envs are expensive to rebuild), then re-init the
# database, re-register providers and re-fetch obs4REF / NFS datasets.
#
# No solve happens here -- the periodic ingest+solve cron picks up the
# unsolved diagnostics a few executions at a time across the week.
set -eu

CONFIG_DIR=${REF_CONFIGURATION:-/ref/home_2026-05-11}

echo "=== Wiping state dir ${CONFIG_DIR} (preserving /ref/software) ==="
rm -rf "${CONFIG_DIR}"
mkdir -p "${CONFIG_DIR}"

echo "=== ref db migrate ==="
ref db migrate

echo "=== ref providers setup (skip env build + skip validate) ==="
ref providers setup --skip-data --skip-validate

echo "=== Fetching obs4REF observation cache ==="
ref datasets fetch-data --registry obs4ref

echo "=== Ingesting CMIP6 from /data/cmip6 ==="
ref -v datasets ingest --source-type cmip6 /data/cmip6

echo "=== Ingesting obs4mips ==="
ref -v datasets ingest --source-type obs4mips "${CONFIG_DIR}/cache/climate_ref/obs4REF"

echo "=== Scaling climate-ref-api + climate-ref-orchestrator back to 1 ==="
kubectl -n climate-ref scale deploy climate-ref-api climate-ref-orchestrator --replicas=1

echo "=== Reset complete. Periodic ingest+solve cron will drive the workers. ==="

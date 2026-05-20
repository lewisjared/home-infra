#!/bin/sh
# Weekly full reset: wipe REF state config dir (DB + caches), keep
# /ref/software (conda envs are expensive to rebuild), then re-init the
# database, re-register providers and re-ingest CMIP6 + obs4mips.
#
# obs4REF cache lives on a separate PVC (climate-ref-obs-csi, mounted at
# /data/obs) so it survives the wipe. Only re-fetch when that PVC is empty,
# which in practice means new clusters or PVC replacement.
#
# No solve happens here -- the periodic ingest+solve cron picks up the
# unsolved diagnostics a few executions at a time across the week.
set -eu

CONFIG_DIR=${REF_CONFIGURATION:-/ref/home_2026-05-11}
OBS4REF_CACHE=/data/obs/obs4REF

echo "=== Wiping state dir ${CONFIG_DIR} (preserving /ref/software) ==="
rm -rf "${CONFIG_DIR}"
mkdir -p "${CONFIG_DIR}"

echo "=== ref db migrate ==="
ref db migrate

echo "=== ref providers setup ==="
# Full setup: builds conda envs, fetches each provider's reference registry
# (esmvaltool OBS Tier 2, ilamb GPP/WECANN etc.) into the obs PVC pooch
# cache at $XDG_CACHE_HOME/climate_ref/<provider>, and validates. Required
# for diagnostics to find their reference observations -- without it,
# esmvaltool fails with "No data sources found for project 'OBS'" and ilamb
# hits FileNotFoundError on its reference netCDFs.
ref providers setup

if [ ! -d "${OBS4REF_CACHE}" ] || [ -z "$(ls -A "${OBS4REF_CACHE}" 2>/dev/null)" ]; then
    echo "=== obs4REF cache missing at ${OBS4REF_CACHE} -- fetching ==="
    ref datasets fetch-data --registry obs4ref --output-directory "${OBS4REF_CACHE}"
else
    echo "=== obs4REF cache present at ${OBS4REF_CACHE} -- skipping fetch ==="
fi

echo "=== Ingesting CMIP6 from /data/cmip6 ==="
# --chunk-size streams the catalog in directory-aligned batches so peak
# memory is bounded by chunk_size, not the full archive size (REF v0.14.1+).
ref -v datasets ingest --source-type cmip6 --chunk-size 1000 /data/cmip6

echo "=== Ingesting obs4mips from ${OBS4REF_CACHE} ==="
ref -v datasets ingest --source-type obs4mips "${OBS4REF_CACHE}"

echo "=== Scaling climate-ref-api + climate-ref-orchestrator back to 1 ==="
kubectl -n climate-ref scale deploy climate-ref-api climate-ref-orchestrator --replicas=1

echo "=== Reset complete. Periodic ingest+solve cron will drive the workers. ==="

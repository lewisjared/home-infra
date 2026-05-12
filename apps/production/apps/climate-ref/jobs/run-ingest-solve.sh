#!/bin/sh
# Periodic ingest + capped solve. Picks up any new ESGF data dropped on the
# CMIP6 NFS volume and enqueues at most one new execution per diagnostic per
# run (matches the upstream `tests/integration/test_cmip7_aft.py` test
# pattern). Every diagnostic is exercised each tick while the per-diagnostic
# backlog drains gradually across the week.
#
# obs4mips bootstrap: weekly-reset is normally the only path that populates
# obs4mips. If the on-disk cache is gone -- e.g. after a state-dir rename or
# manual DB rebuild -- the solver sees an empty obs4mips catalog and every
# diagnostic skips for the whole week. Re-fetch + re-ingest here so the
# periodic cron can recover without waiting for Sunday.
set -eu

CONFIG_DIR=${REF_CONFIGURATION:-/ref/home_2026-05-11}
OBS4REF_CACHE="${CONFIG_DIR}/cache/climate_ref/obs4REF"

if [ ! -d "${OBS4REF_CACHE}" ] || [ -z "$(ls -A "${OBS4REF_CACHE}" 2>/dev/null)" ]; then
    echo "=== obs4REF cache missing at ${OBS4REF_CACHE} -- bootstrapping ==="
    ref datasets fetch-data --registry obs4ref
    echo "=== Ingesting obs4mips from ${OBS4REF_CACHE} ==="
    ref -v datasets ingest --source-type obs4mips "${OBS4REF_CACHE}"
else
    echo "=== obs4REF cache present at ${OBS4REF_CACHE} -- skipping bootstrap ==="
fi

echo "=== Ingesting CMIP6 from /data/cmip6 ==="
ref -v datasets ingest --source-type cmip6 /data/cmip6

echo "=== Solving (cap: one new execution per diagnostic) ==="
ref -v solve --timeout 0 --one-per-diagnostic

echo "=== Done ==="

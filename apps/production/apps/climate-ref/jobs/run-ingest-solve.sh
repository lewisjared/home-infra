#!/bin/sh
# Periodic ingest + capped solve. Picks up any new ESGF data dropped on the
# CMIP6 NFS volume and enqueues at most one new execution per diagnostic per
# run (matches the upstream `tests/integration/test_cmip7_aft.py` test
# pattern). Every diagnostic is exercised each tick while the per-diagnostic
# backlog drains gradually across the week.
#
# obs4REF lives on its own PVC (climate-ref-obs-csi, mounted at /data/obs)
# rather than the REF state PVC so it survives state-dir wipes / renames.
# The bootstrap step only fires the first time the obs PVC is empty, which
# in practice means new clusters or PVC replacement.
set -eu

OBS4REF_CACHE=/data/obs/obs4REF

if [ ! -d "${OBS4REF_CACHE}" ] || [ -z "$(ls -A "${OBS4REF_CACHE}" 2>/dev/null)" ]; then
    echo "=== obs4REF cache missing at ${OBS4REF_CACHE} -- bootstrapping ==="
    ref datasets fetch-data --registry obs4ref --output-directory "${OBS4REF_CACHE}"
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

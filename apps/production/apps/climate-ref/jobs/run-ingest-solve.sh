#!/bin/sh
# Periodic ingest + capped solve.
# Picks up any new CMIP6 datasets and enqueues at most one new execution per diagnostic.
# Every diagnostic is exercised each tick while the per-diagnostic
# backlog drains gradually across the week.
#
# obs4REF lives on its own PVC (climate-ref-obs-csi, mounted at /data/obs)
# rather than the REF state PVC so it survives state-dir wipes / renames.
set -eu

OBS4REF_CACHE=/data/obs/obs4REF

 echo "=== obs4REF cache missing at ${OBS4REF_CACHE} -- bootstrapping ==="
ref datasets fetch-data --registry obs4ref --output-directory "${OBS4REF_CACHE}"

echo "=== Ingesting obs4mips from ${OBS4REF_CACHE} ==="
ref -v datasets ingest --source-type obs4mips "${OBS4REF_CACHE}"


echo "=== Ingesting CMIP6 from /data/cmip6 ==="
ref -v datasets ingest --source-type cmip6 /data/cmip6

echo "=== Solving (cap: one new execution per diagnostic) ==="
ref -v solve --timeout 0 --one-per-diagnostic

echo "=== Done ==="

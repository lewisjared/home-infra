#!/bin/sh
# Periodic ingest + capped solve. Picks up any new ESGF data dropped on the
# CMIP6 NFS volume and enqueues at most one new execution per diagnostic per
# run (matches the upstream `tests/integration/test_cmip7_aft.py` test
# pattern). Every diagnostic is exercised each tick while the per-diagnostic
# backlog drains gradually across the week.
set -eu

echo "=== Ingesting CMIP6 from /data/cmip6 ==="
ref -v datasets ingest --source-type cmip6 /data/cmip6

echo "=== Solving (cap: one new execution per diagnostic) ==="
ref -v solve --timeout 0 --one-per-diagnostic

echo "=== Done ==="

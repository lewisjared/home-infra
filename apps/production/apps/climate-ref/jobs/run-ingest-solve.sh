#!/bin/sh
# Periodic ingest + capped solve. Picks up any new ESGF data dropped on the
# CMIP6 NFS volume and enqueues at most one new execution per provider per
# run, so the weekly reset's backlog is drained gradually instead of all at
# once.
set -eu

echo "=== Ingesting CMIP6 from /data/cmip6 ==="
ref -v datasets ingest --source-type cmip6 /data/cmip6

echo "=== Solving (cap: one new execution per provider) ==="
ref -v solve --timeout 0 --one-per-provider

echo "=== Done ==="

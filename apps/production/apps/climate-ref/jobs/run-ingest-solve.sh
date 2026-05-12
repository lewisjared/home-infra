#!/bin/sh
# Periodic ingest + capped solve. Picks up any new ESGF data dropped on the
# CMIP6 NFS volume and enqueues at most one new execution per diagnostic per
# run (matches the upstream `tests/integration/test_cmip7_aft.py` test
# pattern). Every diagnostic is exercised each tick while the per-diagnostic
# backlog drains gradually across the week.
#
# Hardening notes:
# - `ref datasets ingest` currently exits 0 even when a malformed file aborts
#   the whole scan (Climate-REF/climate-ref#668). We grep the log for the
#   upstream-known "Error ingesting datasets" marker and fail loudly.
# - The weekly-reset cron is what normally populates obs4mips. If the cache
#   is missing -- e.g. after a state-dir rename or a manual DB rebuild -- the
#   solver sees an empty obs4mips catalog and every diagnostic skips for the
#   whole week. Bootstrap it here when the on-disk cache is gone so the
#   periodic cron can recover without waiting for Sunday.
set -eu

CONFIG_DIR=${REF_CONFIGURATION:-/ref/home_2026-05-11}
OBS4REF_CACHE="${CONFIG_DIR}/cache/climate_ref/obs4REF"
INGEST_LOG=/tmp/ingest.log

ingest_with_check() {
    src=$1
    path=$2
    echo "=== Ingesting ${src} from ${path} ==="
    : > "${INGEST_LOG}"
    ref -v datasets ingest --source-type "${src}" "${path}" 2>&1 | tee "${INGEST_LOG}"
    if grep -q "Error ingesting datasets" "${INGEST_LOG}"; then
        echo "FATAL: ingest logged 'Error ingesting datasets' (Climate-REF/climate-ref#668)"
        exit 1
    fi
}

if [ ! -d "${OBS4REF_CACHE}" ] || [ -z "$(ls -A "${OBS4REF_CACHE}" 2>/dev/null)" ]; then
    echo "=== obs4REF cache missing at ${OBS4REF_CACHE} -- bootstrapping ==="
    ref datasets fetch-data --registry obs4ref
    ingest_with_check obs4mips "${OBS4REF_CACHE}"
else
    echo "=== obs4REF cache present at ${OBS4REF_CACHE} -- skipping bootstrap ==="
fi

ingest_with_check cmip6 /data/cmip6

echo "=== Solving (cap: one new execution per diagnostic) ==="
ref -v solve --timeout 0 --one-per-diagnostic

echo "=== Done ==="

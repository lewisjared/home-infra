#!/bin/sh
set -e

export HOME=/tmp
export PYTHONPATH=/tools/lib:$PYTHONPATH
export PATH=/tools/bin:/tools/lib/bin:$PATH

# Configure intake-esgf to download into the CMIP6 NFS volume
mkdir -p /tmp/.config/intake-esgf
cat > /tmp/.config/intake-esgf/conf.yaml <<CONF
local_cache:
  - /data/cmip6
confirm_download: false
break_on_error: false
num_threads: 20
CONF

echo "=== intake-esgf configuration ==="
cat /tmp/.config/intake-esgf/conf.yaml

echo "=== fetching ESGF datasets ==="
python /scripts/fetch-esgf.py

echo "=== fetch complete ==="

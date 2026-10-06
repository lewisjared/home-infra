#!/usr/bin/env bash
# Climate REF test-bed: bring the deployment up, bootstrap it, solve, watch KEDA, verify and tear down.
# See README.md in this directory.
set -euo pipefail

NS=climate-ref
WORKERS="esmvaltool pmp ilamb"
CMIP6_PATH=${CMIP6_PATH:-/data/cmip6}
OBS4REF_PATH=/data/obs/obs4REF
WATCH_INTERVAL=${WATCH_INTERVAL:-30}
WATCH_TIMEOUT=${WATCH_TIMEOUT:-28800}
WIPE_IMAGE=busybox:1.37.0@sha256:bdf57e528e45e4433820e045b29b4597825a1c9e38353532d90a01445013f82e

log() { printf '\n=== %s ===\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
orch() { kubectl -n "$NS" exec -i deploy/climate-ref-orchestrator -c orchestrator -- "$@"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [args]

  up                 Resume Flux and wait for the release to be ready
  bootstrap          Set up providers, ingest obs4REF and CMIP6 (CMIP6_PATH=$CMIP6_PATH)
  solve [mode] ...   Queue executions and return. Extra args go to 'ref solve'.
                       smoke  one execution per provider from three quick diagnostics (default)
                       wide   one execution per diagnostic, enough to push KEDA to its maximum
  watch              Follow queues, executions and worker replicas until the workers scale back to zero
  verify             Fail unless every worker provider has a success and nothing failed or is running
  status             One snapshot of pods, autoscalers, queues and executions
  e2e [mode]         up, bootstrap, solve, watch and verify in one go
  down [--purge]     Uninstall and wipe the database, results, scratch and logs.
                     --purge also wipes the conda environments and the reference data cache.
EOF
}

# Prints {"queues": {name: length}, "executions": {provider: {running, failed, successful, not_started}}}.
state() {
  orch python - <<'EOF'
import json
import os

import redis
from climate_ref.config import Config
from climate_ref.database import Database
from climate_ref.results import Reader

broker = redis.Redis.from_url(os.environ["CELERY_BROKER_URL"])
# Celery queues are the only list keys in the broker.
queues = {k.decode(): broker.llen(k) for k in broker.scan_iter() if broker.type(k) == b"list"}

database = Database.from_config(Config.default(), run_migrations=False, read_only=True)
executions = {}
for row in Reader(database).executions.statistics():
    totals = executions.setdefault(row.provider, dict.fromkeys(("running", "failed", "successful", "not_started"), 0))
    for key in totals:
        totals[key] += getattr(row, key)

print(json.dumps({"queues": queues, "executions": executions}))
EOF
}

replicas() {
  local r
  r=$(kubectl -n "$NS" get deploy "climate-ref-$1" -o jsonpath='{.status.replicas}')
  echo "${r:-0}"
}

cmd_up() {
  log "Resuming Flux"
  flux resume kustomization climate-ref -n flux-system --timeout=20m
  kubectl -n "$NS" rollout status deploy/climate-ref-orchestrator --timeout=10m
}

cmd_bootstrap() {
  log "Setting up providers"
  orch ref providers setup
  orch ref providers setup --validate-only

  log "Restarting the API so it loads the provider environments"
  kubectl -n "$NS" rollout restart deploy/climate-ref-api
  kubectl -n "$NS" rollout status deploy/climate-ref-api --timeout=10m

  if orch sh -c "[ -n \"\$(ls -A $OBS4REF_PATH 2>/dev/null)\" ]"; then
    log "obs4REF already fetched to $OBS4REF_PATH"
  else
    log "Fetching obs4REF to $OBS4REF_PATH"
    orch ref datasets fetch-data --registry obs4ref --output-directory "$OBS4REF_PATH"
  fi

  log "Ingesting obs4REF"
  orch ref datasets ingest --source-type obs4ref "$OBS4REF_PATH"

  log "Ingesting CMIP6 from $CMIP6_PATH"
  orch ref datasets ingest --source-type cmip6 --chunk-size 500 "$CMIP6_PATH"
  orch ref datasets stats

  log "Doctor"
  orch ref doctor || echo "Doctor reported findings. Diagnostics it names will not run."
}

cmd_solve() {
  local mode=${1:-smoke}
  if [ $# -gt 0 ]; then shift; fi
  case $mode in
    smoke)
      log "Solving: one execution per provider"
      orch ref solve --no-wait --one-per-provider \
        --diagnostic global-mean-timeseries --diagnostic annual-cycle --diagnostic gpp-wecann "$@"
      ;;
    wide)
      log "Solving: one execution per diagnostic"
      orch ref solve --no-wait --one-per-diagnostic "$@"
      ;;
    *) die "unknown solve mode '$mode', expected smoke or wide" ;;
  esac
}

cmd_watch() {
  local start=$SECONDS saw_work=0 snapshot queued running line idle w r peak
  for w in $WORKERS; do printf -v "peak_$w" 0; done
  log "Watching every ${WATCH_INTERVAL}s, until the workers are back at zero"
  while :; do
    snapshot=$(state)
    queued=$(jq '[.queues[]] | add // 0' <<<"$snapshot")
    running=$(jq '[.executions[].running] | add // 0' <<<"$snapshot")
    line="$(date +%H:%M:%S) queued=$queued running=$running |"
    idle=1
    for w in $WORKERS; do
      r=$(replicas "$w")
      peak="peak_$w"
      if [ "$r" -gt "${!peak}" ]; then printf -v "peak_$w" '%s' "$r"; fi
      if [ "$r" -gt 0 ]; then idle=0; fi
      line+=" $w=$r"
    done
    echo "$line"
    if [ "$queued" -gt 0 ] || [ "$running" -gt 0 ] || [ "$idle" -eq 0 ]; then saw_work=1; fi
    if [ "$saw_work" -eq 1 ] && [ "$queued" -eq 0 ] && [ "$running" -eq 0 ] && [ "$idle" -eq 1 ]; then
      log "Drained and scaled to zero after $(( (SECONDS - start) / 60 )) min"
      for w in $WORKERS; do peak="peak_$w"; echo "$w peaked at ${!peak} replica(s)"; done
      return 0
    fi
    [ $(( SECONDS - start )) -lt "$WATCH_TIMEOUT" ] || die "still busy after ${WATCH_TIMEOUT}s"
    sleep "$WATCH_INTERVAL"
  done
}

cmd_verify() {
  local snapshot failed=0 w n
  log "Executions"
  orch ref executions stats
  snapshot=$(state)

  n=$(jq '[.executions[].running] | add // 0' <<<"$snapshot")
  [ "$n" -eq 0 ] || { echo "FAIL: $n execution(s) still running"; failed=1; }
  n=$(jq '[.executions[].failed] | add // 0' <<<"$snapshot")
  if [ "$n" -gt 0 ]; then
    echo "FAIL: $n execution group(s) failed"
    orch ref executions list-groups --not-successful
    failed=1
  fi
  for w in $WORKERS; do
    n=$(jq --arg p "$w" '.executions[$p].successful // 0' <<<"$snapshot")
    [ "$n" -gt 0 ] || { echo "FAIL: no successful $w execution"; failed=1; }
  done

  log "API"
  orch python - <<'EOF' || failed=1
import json
import urllib.request

base = "http://climate-ref-api/api/v1"
urllib.request.urlopen(f"{base}/utils/health-check/", timeout=30)
body = json.load(urllib.request.urlopen(f"{base}/executions/", timeout=30))
if isinstance(body, dict):
    count = body.get("count", len(body.get("results") or body.get("data") or []))
else:
    count = len(body)
print(f"API is healthy and lists {count} execution(s)")
if not count:
    raise SystemExit("FAIL: the API lists no executions")
EOF

  [ "$failed" -eq 0 ] || die "verification failed"
  log "PASS"
}

cmd_status() {
  kubectl -n "$NS" get pods,scaledobjects
  state | jq .
}

cmd_down() {
  local wipe='rm -rf /ref/db /ref/results /ref/scratch /ref/log'
  if [ "${1:-}" = --purge ]; then
    wipe='find /ref -mindepth 1 -maxdepth 1 -exec rm -rf {} +'
  fi

  log "Suspending Flux"
  flux suspend kustomization climate-ref -n flux-system

  log "Uninstalling the release"
  kubectl -n "$NS" delete helmrelease climate-ref --ignore-not-found --wait --timeout=10m
  # Workers get hours of grace to finish a task, which a teardown does not want to wait for.
  kubectl -n "$NS" delete pod -l app.kubernetes.io/instance=climate-ref --ignore-not-found --grace-period=0 --force
  kubectl -n "$NS" wait pod -l app.kubernetes.io/instance=climate-ref --for=delete --timeout=5m 2>/dev/null || true

  log "Wiping state: $wipe"
  kubectl -n "$NS" run climate-ref-wipe --rm -i --restart=Never --image="$WIPE_IMAGE" --overrides="$(cat <<EOF
{
  "spec": {
    "securityContext": {"runAsUser": 1000, "runAsGroup": 1000, "runAsNonRoot": true, "seccompProfile": {"type": "RuntimeDefault"}},
    "containers": [{
      "name": "wipe",
      "image": "$WIPE_IMAGE",
      "command": ["sh", "-c", "$wipe && ls -la /ref"],
      "securityContext": {"allowPrivilegeEscalation": false, "capabilities": {"drop": ["ALL"]}},
      "volumeMounts": [{"name": "ref", "mountPath": "/ref"}]
    }],
    "volumes": [{"name": "ref", "persistentVolumeClaim": {"claimName": "climate-ref-state-csi"}}]
  }
}
EOF
)"

  log "Torn down. Flux stays suspended until '$(basename "$0") up'"
}

case ${1:-} in
  up) cmd_up ;;
  bootstrap) cmd_bootstrap ;;
  solve) shift; cmd_solve "$@" ;;
  watch) cmd_watch ;;
  verify) cmd_verify ;;
  status) cmd_status ;;
  e2e) shift; cmd_up; cmd_bootstrap; cmd_solve "$@"; cmd_watch; cmd_verify ;;
  down) shift; cmd_down "$@" ;;
  *) usage; exit 1 ;;
esac

#!/usr/bin/env bash
# Pushes the newest daily ZFS snapshot of each source to a Kopia repository in Backblaze B2.
#
# Modes:
#   run      long-running scheduler: backup daily after BACKUP_HOUR, drill monthly on DRILL_DAY
#   init     create or connect the repository and apply policies (idempotent)
#   backup   snapshot every source once, then run due maintenance
#   drill    read a sample of file contents back from B2 and check their hashes
# Kopia also calls this script as the before-snapshot-root action, detected through KOPIA_ACTION.
set -euo pipefail

SOURCES=(/data/photos /data/k8s)
SNAPSHOT_PREFIX=${SNAPSHOT_PREFIX:-daily-}
MAX_SNAPSHOT_AGE_HOURS=${MAX_SNAPSHOT_AGE_HOURS:-36}
BACKUP_HOUR=${BACKUP_HOUR:-4}
DRILL_DAY=${DRILL_DAY:-15}
DRILL_VERIFY_PERCENT=${DRILL_VERIFY_PERCENT:-2}
B2_ENDPOINT=${B2_ENDPOINT:-s3.eu-central-003.backblazeb2.com}
B2_PREFIX=${B2_PREFIX:-mole/}
# Must stay at least one day longer than the full maintenance interval (24h).
RETENTION_PERIOD=${RETENTION_PERIOD:-30d}
STATE_DIR=${STATE_DIR:-/state}
METRICS_FILE=${METRICS_FILE:-/metrics/metrics}

log() { printf '%s %s\n' "$(date -Iseconds)" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

write_state() {
  printf '%s\n' "$2" >"$STATE_DIR/$1.tmp"
  mv "$STATE_DIR/$1.tmp" "$STATE_DIR/$1"
}

read_state() { cat "$STATE_DIR/$1" 2>/dev/null || true; }

render_metrics() {
  local out="$METRICS_FILE.tmp" src name value
  {
    echo '# HELP offsite_backup_last_success_timestamp_seconds Last successful Kopia snapshot of a source.'
    echo '# TYPE offsite_backup_last_success_timestamp_seconds gauge'
    for src in "${SOURCES[@]}"; do
      name=$(basename "$src")
      value=$(read_state "success_$name")
      [[ -n $value ]] && echo "offsite_backup_last_success_timestamp_seconds{source=\"$name\"} $value"
    done
    echo '# HELP offsite_backup_last_run_success Whether the last snapshot attempt of a source succeeded.'
    echo '# TYPE offsite_backup_last_run_success gauge'
    for src in "${SOURCES[@]}"; do
      name=$(basename "$src")
      value=$(read_state "result_$name")
      [[ -n $value ]] && echo "offsite_backup_last_run_success{source=\"$name\"} $value"
    done
    for name in maintenance drill; do
      value=$(read_state "success_$name")
      if [[ -n $value ]]; then
        echo "# TYPE offsite_backup_${name}_last_success_timestamp_seconds gauge"
        echo "offsite_backup_${name}_last_success_timestamp_seconds $value"
      fi
      value=$(read_state "result_$name")
      if [[ -n $value ]]; then
        echo "# TYPE offsite_backup_${name}_last_run_success gauge"
        echo "offsite_backup_${name}_last_run_success $value"
      fi
    done
  } >"$out"
  mv "$out" "$METRICS_FILE"
}

s3_flags() {
  : "${B2_BUCKET:?B2_BUCKET is not set}" "${B2_KEY_ID:?B2_KEY_ID is not set}"
  : "${B2_APPLICATION_KEY:?B2_APPLICATION_KEY is not set}" "${KOPIA_PASSWORD:?KOPIA_PASSWORD is not set}"
  printf '%s\n' \
    "--bucket=$B2_BUCKET" "--endpoint=$B2_ENDPOINT" "--prefix=$B2_PREFIX" \
    "--access-key=$B2_KEY_ID" "--secret-access-key=$B2_APPLICATION_KEY"
  [[ ${B2_DISABLE_TLS:-false} == true ]] && echo --disable-tls
  return 0
}

connect() {
  kopia repository status >/dev/null 2>&1 && return 0
  local flags
  mapfile -t flags < <(s3_flags)
  kopia repository connect s3 "${flags[@]}" \
    --override-hostname=mole --override-username=offsite --enable-actions
}

# Prints KOPIA_SNAPSHOT_PATH so Kopia reads the newest daily ZFS snapshot instead of the live tree.
resolve_snapshot() {
  local src=${KOPIA_SOURCE_PATH:?} dir latest stamp taken age_hours path
  dir="$src/.zfs/snapshot"
  latest=$(find "$dir" -mindepth 1 -maxdepth 1 -name "${SNAPSHOT_PREFIX}*" -printf '%f\n' | sort | tail -n 1)
  [[ -n $latest ]] || die "no ${SNAPSHOT_PREFIX}* snapshot in $dir"

  # Naming schema is <prefix>%Y-%m-%d_%H-%M.
  stamp=${latest#"$SNAPSHOT_PREFIX"}
  taken=$(date -d "${stamp%_*} $(tr - : <<<"${stamp#*_}")" +%s) || die "cannot parse snapshot name $latest"
  age_hours=$((($(date +%s) - taken) / 3600))
  ((age_hours <= MAX_SNAPSHOT_AGE_HOURS)) || die "$latest is ${age_hours}h old, check the TrueNAS snapshot task"

  path="$dir/$latest"
  # An empty listing means the ZFS automount did not propagate into the container.
  [[ -n $(ls -A "$path") ]] || die "$path is empty, check the bind mount propagation"
  log "snapshotting $path for $src"
  echo "KOPIA_SNAPSHOT_PATH=$path"
}

init() {
  local flags
  mapfile -t flags < <(s3_flags)
  if ! connect 2>/dev/null; then
    log "creating repository in $B2_BUCKET/$B2_PREFIX"
    kopia repository create s3 "${flags[@]}" \
      --retention-mode=GOVERNANCE --retention-period="$RETENTION_PERIOD" \
      --override-hostname=mole --override-username=offsite
    kopia repository disconnect
    connect
  fi

  kopia policy set --global --compression=zstd-fastest \
    --keep-latest=7 --keep-hourly=0 --keep-daily=30 --keep-weekly=8 --keep-monthly=12 --keep-annual=0
  kopia policy set /data/photos --add-ignore=/thumbs --add-ignore=/encoded-video
  for src in "${SOURCES[@]}"; do
    kopia policy set "$src" \
      --before-snapshot-root-action=/scripts/offsite-backup.sh --action-command-mode=essential
  done
  kopia maintenance set --owner=me --enable-full=true --full-interval=24h --extend-object-locks=true
  log "repository ready"
}

backup() {
  local rc=0 src name
  connect
  for src in "${SOURCES[@]}"; do
    name=$(basename "$src")
    if kopia snapshot create "$src"; then
      write_state "success_$name" "$(date +%s)"
      write_state "result_$name" 1
    else
      log "snapshot of $src failed"
      write_state "result_$name" 0
      rc=1
    fi
  done
  if kopia maintenance run; then
    write_state success_maintenance "$(date +%s)"
    write_state result_maintenance 1
  else
    log "maintenance failed"
    write_state result_maintenance 0
    rc=1
  fi
  render_metrics
  return "$rc"
}

drill() {
  local rc=0
  connect
  if kopia snapshot verify --verify-files-percent="$DRILL_VERIFY_PERCENT" --file-parallelism=4; then
    write_state success_drill "$(date +%s)"
    write_state result_drill 1
  else
    write_state result_drill 0
    rc=1
  fi
  render_metrics
  return "$rc"
}

run() {
  mkdir -p "$STATE_DIR" "$(dirname "$METRICS_FILE")"
  render_metrics
  until connect; do
    log "cannot connect to the repository, run init first. Retrying in 10 minutes."
    sleep 600
  done

  local today hour month last_attempt
  while true; do
    today=$(date +%F)
    hour=$((10#$(date +%H)))
    month=$(date +%Y-%m)
    last_attempt=$(read_state last_attempt)
    last_attempt=${last_attempt:-0}

    if [[ $(read_state backup_date) != "$today" ]] && ((hour >= BACKUP_HOUR)) &&
      (($(date +%s) - last_attempt >= 3600)); then
      write_state last_attempt "$(date +%s)"
      log "starting backup"
      if backup; then
        write_state backup_date "$today"
        log "backup finished"
      else
        log "backup failed, retrying in an hour"
      fi
    fi

    if (($(date +%-d) == DRILL_DAY)) && [[ $(read_state backup_date) == "$today" ]] &&
      [[ $(read_state drill_month) != "$month" ]]; then
      log "starting restore drill"
      if drill; then log "drill passed"; else log "drill failed"; fi
      write_state drill_month "$month"
    fi

    sleep 600
  done
}

if [[ ${KOPIA_ACTION:-} == before-snapshot-root ]]; then
  resolve_snapshot
  exit 0
fi

case ${1:-run} in
  run) run ;;
  init) init ;;
  backup) backup ;;
  drill) drill ;;
  *) die "unknown mode: $1" ;;
esac

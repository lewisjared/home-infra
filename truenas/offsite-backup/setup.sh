#!/usr/bin/env bash
# Sets up the offsite backup on mole: snapshot tasks, host directories, env file, app and repository.
# Run as root from a copy of this directory.
# Safe to run again: it creates what is missing and updates the script and app.
set -euo pipefail

BASE=/mnt/tank/backups/offsite
APP=offsite-backup
SRC=$(cd "$(dirname "$0")" && pwd)

log() { printf '==> %s\n' "$*"; }

[[ $EUID -eq 0 ]] || { echo "run as root: sudo bash $0" >&2; exit 1; }

# dataset naming_schema lifetime_value lifetime_unit minute hour dom dow
TASKS=(
  "tank/photos hourly-%Y-%m-%d_%H-%M 2 DAY 0 * * *"
  "tank/photos daily-%Y-%m-%d_%H-%M 30 DAY 0 2 * *"
  "tank/photos weekly-%Y-%m-%d_%H-%M 8 WEEK 0 2 * sun"
  "tank/photos monthly-%Y-%m-%d_%H-%M 12 MONTH 0 2 1 *"
  "tank/backups/k8s daily-%Y-%m-%d_%H-%M 14 DAY 0 3 * *"
)

snapshot_tasks() {
  local spec dataset schema value unit minute hour dom dow filter
  for spec in "${TASKS[@]}"; do
    read -r dataset schema value unit minute hour dom dow <<<"$spec"
    filter=$(jq -nc --arg d "$dataset" --arg s "$schema" '[["dataset","=",$d],["naming_schema","=",$s]]')
    if [[ $(midclt call pool.snapshottask.query "$filter" | jq length) -gt 0 ]]; then
      log "snapshot task $dataset $schema exists"
      continue
    fi
    midclt call pool.snapshottask.create "$(jq -nc \
      --arg d "$dataset" --arg s "$schema" --argjson v "$value" --arg u "$unit" \
      --arg mi "$minute" --arg h "$hour" --arg dom "$dom" --arg dow "$dow" \
      '{dataset: $d, naming_schema: $s, lifetime_value: $v, lifetime_unit: $u, recursive: false,
        schedule: {minute: $mi, hour: $h, dom: $dom, month: "*", dow: $dow}}')" >/dev/null
    log "created snapshot task $dataset $schema"
  done

  local id
  for id in $(midclt call pool.snapshottask.query \
    '[["dataset","=","tank/photos"],["naming_schema","^","auto-"]]' | jq '.[].id'); do
    midclt call pool.snapshottask.delete "$id" >/dev/null
    log "deleted old auto- snapshot task $id"
  done
}

host_files() {
  mkdir -p "$BASE"/{scripts,config,cache,logs,state,metrics}
  chmod 700 "$BASE"
  install -m 755 "$SRC/offsite-backup.sh" "$BASE/scripts/"
  log "installed $BASE/scripts/offsite-backup.sh"

  if [[ -s $BASE/kopia.env ]]; then
    log "keeping existing $BASE/kopia.env"
    return
  fi
  local bucket key_id app_key password endpoint
  read -rp "B2 bucket name: " bucket
  read -rp "B2 S3 endpoint [s3.eu-central-003.backblazeb2.com]: " endpoint
  read -rp "B2 key ID: " key_id
  read -rsp "B2 application key: " app_key && echo
  read -rsp "Kopia repository password (blank to generate): " password && echo
  if [[ -z $password ]]; then
    password=$(openssl rand -base64 33)
    printf '\nGenerated repository password, save it in the password manager now:\n\n  %s\n\n' "$password"
    read -rp "Press enter once it is saved. "
  fi
  umask 077
  cat >"$BASE/kopia.env" <<EOF
B2_BUCKET=$bucket
B2_ENDPOINT=${endpoint:-s3.eu-central-003.backblazeb2.com}
B2_KEY_ID=$key_id
B2_APPLICATION_KEY=$app_key
KOPIA_PASSWORD=$password
EOF
  log "wrote $BASE/kopia.env"
}

app() {
  local compose
  compose=$(jq -Rs . <"$SRC/compose.yaml")
  if [[ $(midclt call app.query "[[\"name\",\"=\",\"$APP\"]]" | jq length) -gt 0 ]]; then
    midclt call -j app.update "$APP" "{\"custom_compose_config_string\": $compose}" >/dev/null
    log "updated app $APP"
  else
    midclt call -j app.create \
      "{\"custom_app\": true, \"app_name\": \"$APP\", \"custom_compose_config_string\": $compose}" >/dev/null
    log "created app $APP"
  fi
}

repository() {
  for _ in $(seq 30); do
    [[ $(docker inspect -f '{{.State.Running}}' "$APP" 2>/dev/null) == true ]] && break
    sleep 2
  done
  docker exec "$APP" /scripts/offsite-backup.sh init
  docker restart "$APP" >/dev/null
  log "repository ready, app restarted"
}

snapshot_tasks
host_files
app
repository

log "metrics:"
sleep 3
curl -fsS http://127.0.0.1:9851/metrics || echo "(no metrics yet)"
log "follow the first backup with: sudo docker logs -f $APP"

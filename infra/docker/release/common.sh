#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
release_root=$(cd -- "$script_dir/../../.." && pwd -P)
: "${CURRENT_ROOT:?Set CURRENT_ROOT to the absolute path of the currently deployed source}"
: "${TRANSFER_DIR:?Set TRANSFER_DIR to the absolute directory with release archives and manifest}"
current_root=$(cd -- "$CURRENT_ROOT" && pwd -P)
transfer_dir=$(cd -- "$TRANSFER_DIR" && pwd -P)
current_env=${CURRENT_ENV:-$current_root/infra/docker/.env}
manifest=$transfer_dir/RELEASE_MANIFEST.json
fail() { printf '%s\n' "$*" >&2; exit 1; }
manifest_value() {
  python3 - "$manifest" "$1" <<'PY'
import json, sys
v=json.load(open(sys.argv[1],encoding='utf-8-sig'))[sys.argv[2]]
if isinstance(v,bool): print(str(v).lower())
else: print(v)
PY
}
require_tools() {
  command -v python3 >/dev/null || fail 'Python 3 is required.'
  command -v docker >/dev/null || fail 'Docker Engine is required.'
  docker compose version >/dev/null 2>&1 || fail 'Docker Compose v2 is required.'
  docker info >/dev/null 2>&1 || fail 'Docker Engine connection unavailable.'
}
load_images() {
  export TAMREEDY_API_IMAGE TAMREEDY_WORKER_IMAGE TAMREEDY_ADMIN_IMAGE
  TAMREEDY_API_IMAGE=$(manifest_value apiImageTag)
  TAMREEDY_WORKER_IMAGE=$(manifest_value workerImageTag)
  TAMREEDY_ADMIN_IMAGE=$(manifest_value adminImageTag)
  [[ $TAMREEDY_API_IMAGE =~ ^tamreedy-api:rc3-[a-f0-9]{7,40}$ && $TAMREEDY_WORKER_IMAGE =~ ^tamreedy-worker:rc3-[a-f0-9]{7,40}$ && $TAMREEDY_ADMIN_IMAGE =~ ^tamreedy-admin:rc3-[a-f0-9]{7,40}$ ]] || fail 'Invalid release image tags.'
}
old_compose() {
  local args=(-p tamreedy --env-file "$current_env" -f "$current_root/infra/docker/docker-compose.prod.yml")
  if [[ -n ${CURRENT_OVERRIDE:-} ]]; then args+=(-f "$CURRENT_OVERRIDE"); fi
  docker compose "${args[@]}" "$@"
}
release_compose() {
  docker compose -p tamreedy --env-file "$current_env"     -f "$release_root/infra/docker/docker-compose.prod.yml" -f "$script_dir/images.override.yml" "$@"
}
use_current_mounts() {
  # Existing external credentials and certificates are reused in place.
  if [[ -z ${FCM_SERVICE_ACCOUNT_HOST_FILE:-} ]]; then
    local fcm_source
    fcm_source=$(old_compose config --format json 2>/dev/null | python3 -c 'import json,sys; s=json.load(sys.stdin)["services"]["worker"]; dst=s.get("environment",{}).get("FCM_SERVICE_ACCOUNT_FILE"); print(next((v["source"] for v in s.get("volumes",[]) if v.get("target")==dst),""))')
    export FCM_SERVICE_ACCOUNT_HOST_FILE="${fcm_source:-$current_root/infra/docker/secrets/fcm.json}"
  fi
  if [[ -z ${TURN_TLS_DIR:-} ]]; then
    local turn_source
    turn_source=$(old_compose config --format json 2>/dev/null | python3 -c 'import json,sys; s=json.load(sys.stdin)["services"].get("coturn",{}); print(next((v["source"] for v in s.get("volumes",[]) if v.get("target")=="/run/secrets/tls"),""))')
    if [[ -n $turn_source ]]; then export TURN_TLS_DIR="$turn_source"; fi
  fi
}
postgres_query() {
  old_compose exec -T db psql -X -qAt -v ON_ERROR_STOP=1 -U tamreedy -d tamreedy "$@"
}
assert_quiescent() {
  local in_progress
  in_progress=$(postgres_query -c "SELECT count(*) FROM care_requests WHERE status IN ('ASSIGNED','EN_ROUTE','ARRIVED','IN_SERVICE','ESCALATED')")
  [[ $in_progress == 0 ]] || fail 'Active or escalated requests must be resolved before the update.'
}
assert_paused() {
  [[ $(postgres_query -c "SELECT value->>'accepting' FROM app_settings WHERE key='orders'") == false ]] || fail 'Pause new orders in the existing admin dashboard before updating.'
}
capture_migrations() {
  postgres_query -c 'SELECT name FROM schema_migrations ORDER BY name COLLATE "C"'
}

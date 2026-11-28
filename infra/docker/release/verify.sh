#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/common.sh"
require_tools
load_images
use_current_mounts
for service in api worker admin; do
  id=$(release_compose ps -q "$service")
  [[ $id =~ ^[a-f0-9]+$ && $(docker inspect --format '{{.State.Running}}' "$id") == true ]] || fail "Service unavailable: $service"
  case $service in api) expected=$TAMREEDY_API_IMAGE;; worker) expected=$TAMREEDY_WORKER_IMAGE;; admin) expected=$TAMREEDY_ADMIN_IMAGE;; esac
  [[ $(docker inspect --format '{{.Image}}' "$id") == "$(docker image inspect --format '{{.Id}}' "$expected")" ]] || fail "Unexpected $service image."
done
release_compose exec -T db pg_isready -U tamreedy -d tamreedy >/dev/null
release_compose exec -T redis sh -c 'REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli ping' | grep -qx PONG
capture_migrations | python3 "$script_dir/release-checks.py" migrations "$manifest"
base=${VERIFY_API_URL:-}
if [[ -z $base ]]; then
  address=$(release_compose port api 3000)
  [[ $address =~ :([0-9]+)$ ]] || fail 'Cannot resolve local API port.'
  base="http://127.0.0.1:${BASH_REMATCH[1]}"
fi
for path in /health /health/ready /v1/capabilities; do
  for ((attempt=1; attempt<=30; attempt++)); do
    if response=$(curl --silent --show-error --fail --max-time 5 "${base%/}$path" 2>/dev/null); then break; fi
    response=; sleep 2
  done
  [[ -n $response ]] || fail "API check failed: $path"
  printf '%s' "$response" | python3 "$script_dir/release-checks.py" response "$path"
done
admin_address=$(release_compose port admin 80)
[[ $admin_address =~ :([0-9]+)$ ]] || fail 'Cannot resolve local Admin Web port.'
curl --silent --show-error --fail --max-time 5 "http://127.0.0.1:${BASH_REMATCH[1]}/" > /dev/null
printf '%s\n' 'API, Worker, Admin Web, PostgreSQL, Redis, release images and readiness verified.'

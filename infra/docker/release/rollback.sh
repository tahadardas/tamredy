#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/common.sh"
require_tools
: "${BACKUP_DIR:?Set BACKUP_DIR to the restricted backup of this update}"
[[ ${CONFIRM_MAINTENANCE_WINDOW:-} == tamreedy-rc3 ]] || fail 'Maintenance window confirmation required.'
[[ -s $BACKUP_DIR/applied-migrations.txt && -s $BACKUP_DIR/current-images.txt && -s $BACKUP_DIR/previous-release.json && -s $BACKUP_DIR/current-root.txt ]] || fail 'Previous release/schema evidence missing. An approved restoration plan is required.'
[[ $(<"$BACKUP_DIR/current-root.txt") == "$current_root" ]] || fail 'Backup does not belong to the provided previous release.'
exec 9>"$current_root/.tamreedy-deployment.lock"
flock -n 9 || fail 'Another release operation is running.'
# Without an explicitly certified compatibility window, only an identical schema is eligible.
[[ $(capture_migrations) == "$(cat -- "$BACKUP_DIR/applied-migrations.txt")" ]] || fail 'Applied migrations changed. Stop and obtain an approved recovery plan; no database restoration was performed.'
assert_paused
assert_quiescent
rollback_override=$(mktemp)
trap 'rm -f -- "$rollback_override"' EXIT
printf 'services:\n' > "$rollback_override"
for service in api worker admin; do
  image=$(awk -v service="$service" '$1==service {print $2}' "$BACKUP_DIR/current-images.txt")
  [[ $image =~ ^tamreedy-${service}:rollback-[a-f0-9]{16}$ ]] || fail "Invalid saved rollback image: $service"
  docker image inspect "$image" >/dev/null
  printf '  %s:\n    image: %s\n' "$service" "$image" >> "$rollback_override"
  [[ $service != api ]] || printf '  migrate:\n    image: %s\n' "$image" >> "$rollback_override"
done
local_args=(-p tamreedy --env-file "$current_env" -f "$current_root/infra/docker/docker-compose.prod.yml")
if [[ -n ${CURRENT_OVERRIDE:-} ]]; then local_args+=(-f "$CURRENT_OVERRIDE"); fi
local_args+=(-f "$rollback_override")
for service in api worker admin; do docker compose "${local_args[@]}" up -d --no-build --no-deps "$service"; done
printf '%s\n' 'Previous images started. Verify the previous release health/readiness before resuming orders.'

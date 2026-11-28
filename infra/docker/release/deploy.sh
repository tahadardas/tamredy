#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/common.sh"
mode=${1:-source}
[[ $mode == source || $mode == prebuilt ]] || fail 'Usage: deploy.sh source|prebuilt'
: "${BACKUP_DIR:?Set BACKUP_DIR to a new restricted backup directory}"
[[ ${CONFIRM_MAINTENANCE_WINDOW:-} == tamreedy-rc3 ]] || fail 'Set CONFIRM_MAINTENANCE_WINDOW=tamreedy-rc3 after arranging a maintenance window.'
bash "$script_dir/preflight.sh"
load_images
use_current_mounts
exec 9>"$current_root/.tamreedy-deployment.lock"
flock -n 9 || fail 'Another release operation is running.'
assert_paused
assert_quiescent
if [[ $mode == source ]]; then
  for service in migrate worker admin; do COMPOSE_PARALLEL_LIMIT=1 release_compose build "$service"; done
else
  [[ $(manifest_value prebuiltImagesAvailable) == true ]] || fail 'No prebuilt Docker image archive declared in this release.'
  image_archive=$transfer_dir/server-images/tamreedy-images-linux.tar.gz
  [[ -s $image_archive ]] || fail 'Prebuilt image archive missing.'
  gzip -dc -- "$image_archive" | docker load
fi
for image in "$TAMREEDY_API_IMAGE" "$TAMREEDY_WORKER_IMAGE" "$TAMREEDY_ADMIN_IMAGE"; do
  [[ $(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$image") == "$(docker version --format '{{.Server.Os}}/{{.Server.Arch}}')" ]] || fail 'Image architecture does not match Docker host.'
done
assert_paused
assert_quiescent
before_migration=true
restart_if_safe() {
  local status=$?
  if [[ $status != 0 && $before_migration == true ]]; then
    old_compose start api worker admin || true
    printf '%s\n' 'Update stopped before migrations. Check the previous services before resuming orders.' >&2
  fi
}
trap restart_if_safe EXIT
old_compose stop worker api admin
# Close the last-write race after stopping application writers and before taking the consistent backup.
assert_quiescent
bash "$script_dir/backup.sh"
before_migration=false
release_compose run --rm --no-deps migrate
# --no-deps preserves existing PostgreSQL, Redis and Coturn containers and volumes.
for service in api worker admin; do release_compose up -d --no-build --no-deps "$service"; done
bash "$script_dir/verify.sh"
install -m 600 -- "$manifest" "$release_root/RELEASE_MANIFEST.json"
printf '%s\n' 'All checks passed. Review readiness and resume orders through the admin dashboard when authorized.'

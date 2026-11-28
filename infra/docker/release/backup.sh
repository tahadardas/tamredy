#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/common.sh"
require_tools
: "${BACKUP_DIR:?Set BACKUP_DIR to the absolute path of a new restricted backup directory}"
[[ $BACKUP_DIR = /* ]] || fail 'BACKUP_DIR must be absolute.'
mkdir -m 700 -- "$BACKUP_DIR"
[[ $(df -Pk "$BACKUP_DIR" | awk 'END{print $4}') -ge 1048576 ]] || fail 'Less than 1 GiB available at backup destination.'
old_compose exec -T db pg_dump -U tamreedy -d tamreedy -Fc > "$BACKUP_DIR/postgresql.dump"
old_compose exec -T db pg_restore --list < "$BACKUP_DIR/postgresql.dump" > "$BACKUP_DIR/postgresql.contents.txt"
api_id=$(old_compose ps -aq api)
[[ $api_id =~ ^[a-f0-9]+$ ]] || fail 'Expected one existing API container for the encrypted uploads backup.'
# docker cp reads the encrypted volume even while the current API container is stopped.
docker cp "$api_id:/data/uploads/." - | gzip -c > "$BACKUP_DIR/encrypted-uploads.tar.gz"
tar -tzf "$BACKUP_DIR/encrypted-uploads.tar.gz" > /dev/null
capture_migrations > "$BACKUP_DIR/applied-migrations.txt"
for service in api worker admin; do
  id=$(old_compose ps -aq "$service")
  [[ $id =~ ^[a-f0-9]+$ ]] || fail "Missing existing $service container."
  image=$(docker inspect --format '{{.Image}}' "$id")
  [[ $image =~ ^sha256:[a-f0-9]{64}$ ]] || fail "Could not resolve current $service image."
  # Retain a unique immutable rollback alias without pruning any existing image.
  alias="tamreedy-${service}:rollback-${image:7:16}"
  docker image tag "$image" "$alias"
  printf '%s %s %s\n' "$service" "$alias" "$(docker inspect --format '{{.Config.Image}}' "$id")"
done > "$BACKUP_DIR/current-images.txt"
if [[ -s $current_root/RELEASE_MANIFEST.json ]]; then
  cp -- "$current_root/RELEASE_MANIFEST.json" "$BACKUP_DIR/previous-release.json"
elif [[ -n ${CURRENT_MANIFEST:-} && -s $CURRENT_MANIFEST ]]; then
  cp -- "$CURRENT_MANIFEST" "$BACKUP_DIR/previous-release.json"
else
  # Older releases may not have shipped a manifest. Record observed images,
  # preserving the unknown source commit rather than inferring it from a tag.
  python3 - "$BACKUP_DIR" <<'PY'
import json,sys
from pathlib import Path
backup=Path(sys.argv[1])
images=[dict(zip(('service','retainedImage','observedImage'), line.split()))
        for line in (backup/'current-images.txt').read_text().splitlines()]
with (backup/'previous-release.json').open('x',encoding='utf-8') as out:
    json.dump({'sourceCommit': None, 'observedImages': images,
               'appliedMigrations': (backup/'applied-migrations.txt').read_text().splitlines()}, out, indent=2)
    out.write('\n')
PY
fi
printf '%s\n' "$current_root" > "$BACKUP_DIR/current-root.txt"
if [[ ${BACKUP_ENV:-false} == true ]]; then install -m 600 -- "$current_env" "$BACKUP_DIR/runtime.env"; fi
cp -- "$manifest" "$BACKUP_DIR/target-release.json"
(cd -- "$BACKUP_DIR" && sha256sum -- postgresql.dump encrypted-uploads.tar.gz applied-migrations.txt current-images.txt previous-release.json > backup-sha256s.txt)
printf 'readable\n' > "$BACKUP_DIR/backup-status.txt"
printf '%s\n' 'Backup archives are readable. A separate restore exercise is required to establish restorability.'

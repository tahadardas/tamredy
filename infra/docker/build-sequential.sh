#!/usr/bin/env bash
# Build only; startup is an explicit release operation.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
compose=(docker compose -p tamreedy -f "$root/infra/docker/docker-compose.prod.yml" --env-file "${CURRENT_ENV:-$root/infra/docker/.env}")
for service in migrate worker admin; do
  COMPOSE_PARALLEL_LIMIT=1 "${compose[@]}" build "$service"
done

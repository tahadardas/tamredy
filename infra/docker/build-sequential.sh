#!/usr/bin/env bash
# Builds the images ONE AT A TIME (low memory), then starts the stack. Run from the project folder (the one that contains `infra`).
set -euo pipefail
C="docker compose -f infra/docker/docker-compose.prod.yml --env-file infra/docker/.env"
echo "== memory =="; free -h | sed -n 1,3p; echo "== disk =="; df -h / | tail -1
for s in migrate worker admin; do
  echo "== building $s (one at a time) =="
  COMPOSE_PARALLEL_LIMIT=1 $C build "$s"
  docker image prune -f >/dev/null
  sleep 5
done
echo "== starting =="
$C up -d
$C ps

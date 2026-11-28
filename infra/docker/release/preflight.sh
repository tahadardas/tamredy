#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/common.sh"
require_tools
[[ $(uname -s) == Linux ]] || fail 'This release runs on Linux.'
[[ $release_root != "$current_root" ]] || fail 'Extract the package outside the currently deployed directory.'
[[ -s $current_env && -s $current_root/infra/docker/docker-compose.prod.yml && -s $manifest && -s $transfer_dir/SHA256SUMS.txt ]] || fail 'Current deployment or release manifest/checksums missing.'
for cmd in sha256sum tar gzip flock curl; do command -v "$cmd" >/dev/null || fail "Missing command: $cmd"; done
load_images
use_current_mounts
case $(uname -m) in x86_64) arch=linux/amd64;; aarch64|arm64) arch=linux/arm64;; *) fail 'Unsupported Linux architecture.';; esac
wanted=$(manifest_value serverArchitecture)
[[ $wanted == "$arch" || $wanted == source-build ]] || fail 'Release architecture does not match server.'
[[ $(docker version --format '{{.Server.Os}}/{{.Server.Arch}}') == "$arch" ]] || fail 'Docker daemon architecture does not match this server.'
ram_kib=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
disk_kib=$(df -Pk "$release_root" | awk 'END{print $4}')
[[ $ram_kib -ge 1048576 && $disk_kib -ge 2097152 ]] || fail 'Less than 1 GiB RAM or 2 GiB free release storage.'
[[ -n $(old_compose ps -q db) && -n $(old_compose ps -q redis) ]] || fail 'Existing tamreedy database and Redis containers are required.'
api_id=$(old_compose ps -aq api)
[[ $api_id =~ ^[a-f0-9]+$ ]] || fail 'Expected exactly one existing API container.'
uploads=$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/data/uploads"}}{{.Name}}{{end}}{{end}}' "$api_id")
[[ -n $uploads ]] || fail 'Existing encrypted uploads volume was not found.'
python3 "$script_dir/release-checks.py" bundle "$manifest" "$release_root" "$transfer_dir"
{ release_compose config --format json 2>/dev/null || fail 'Invalid production Compose configuration.'; } | python3 "$script_dir/release-checks.py" compose "$uploads"
printf 'Preflight passed (%s, %s KiB total RAM, %s KiB release disk available).\n' "$arch" "$ram_kib" "$disk_kib"

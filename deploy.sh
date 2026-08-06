#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

test -f deploy/.env
git pull --ff-only
export GIT_COMMIT="$(git rev-parse --short HEAD)"

docker compose --env-file deploy/.env config >/dev/null
docker compose --env-file deploy/.env build
docker compose --env-file deploy/.env up -d
docker compose --env-file deploy/.env ps
curl --fail --silent --show-error http://127.0.0.1:8081/api/health

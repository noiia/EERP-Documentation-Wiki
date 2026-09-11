#!/usr/bin/env bash
# Pull the latest published docs image and restart the service.
# Run this on the deploy server, from the repo checkout (compose.yaml must
# be in the same directory). Wire it to a `git pull` + this script on a
# schedule/webhook if you want deploys to follow pushes to main automatically.
set -euo pipefail
cd "$(dirname "$0")"

docker compose pull
docker compose up -d

#!/usr/bin/env bash
# Build the miner image. Extra args pass through to "docker compose build".
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose build "$@"

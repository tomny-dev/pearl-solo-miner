#!/usr/bin/env bash
# Stop and remove the miner container.
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose down "$@"
echo "Miner stopped."

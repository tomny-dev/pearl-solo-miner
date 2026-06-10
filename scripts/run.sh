#!/usr/bin/env bash
# Start the miner in the background. Requires a populated .env file.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -f .env ]; then
  echo "No .env found. Run: cp .env.example .env  and set PRL_WALLET first." >&2
  exit 1
fi
docker compose up -d "$@"
echo "Miner started. Follow logs with: ./scripts/logs.sh"

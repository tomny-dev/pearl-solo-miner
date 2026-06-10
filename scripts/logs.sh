#!/usr/bin/env bash
# Follow the miner logs (Ctrl-C to stop following; the miner keeps running).
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose logs -f --tail=200 "$@"

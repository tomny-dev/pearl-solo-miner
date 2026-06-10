#!/usr/bin/env bash
# Entrypoint: validate configuration, log a safe summary, then exec lpminer.
# All configuration comes from environment variables only (see .env.example).
set -euo pipefail

TAG="[pearl-solo-miner]"

log()  { printf '%s %s\n' "$TAG" "$*"; }
die()  { printf '%s ERROR: %s\n' "$TAG" "$*" >&2; exit 1; }

# Mask a wallet so logs never reveal the full address.
# Shows the first 6 and last 4 characters, e.g. solo:p…wxyz
redact() {
  local w="$1"
  local n=${#w}
  if (( n <= 12 )); then
    printf '***'
  else
    printf '%s…%s' "${w:0:6}" "${w: -4}"
  fi
}

# ---- Startup validation -----------------------------------------------------

[ -n "${PRL_WALLET:-}" ] || die "PRL_WALLET is not set. Pass -e PRL_WALLET=prl1... or set it in .env."

# Sensible LuckyPool defaults so PRL_WALLET is the only strictly-required value
# (these mirror .env.example, so running the prebuilt image with just
# -e PRL_WALLET=... works without a .env file).
WORKER_NAME="${WORKER_NAME:-rig01}"
POOL_HOST="${POOL_HOST:-pearl-ca1.luckypool.io}"
POOL_PORT="${POOL_PORT:-3360}"
POOL="${POOL_HOST}:${POOL_PORT}"

# Solo mode: default ON. Prefixes the wallet with solo: for LuckyPool.
SOLO_MODE="${SOLO_MODE:-true}"
WALLET_FOR_POOL="$PRL_WALLET"
SOLO_ENABLED="no"
case "${SOLO_MODE,,}" in
  1|true|yes|on)
    SOLO_ENABLED="yes"
    case "$PRL_WALLET" in
      solo:*) WALLET_FOR_POOL="$PRL_WALLET" ;;        # already prefixed, leave as-is
      *)      WALLET_FOR_POOL="solo:${PRL_WALLET}" ;; # add the solo: prefix
    esac
    ;;
esac

# GPU visibility check (nvidia-smi is injected by the NVIDIA Container Toolkit).
command -v nvidia-smi >/dev/null 2>&1 \
  || die "nvidia-smi not found. Ensure the NVIDIA runtime is active and NVIDIA_DRIVER_CAPABILITIES includes 'utility'."
if ! GPU_LIST="$(nvidia-smi -L 2>/dev/null)" || [ -z "$GPU_LIST" ]; then
  die "No NVIDIA GPU visible inside the container. Check the NVIDIA Container Toolkit and your GPU_COUNT (or device_ids) setting in docker-compose.yml."
fi

# Locate the miner binary (tarball may unpack into a versioned subdirectory).
# Prefer the exact name, then a versioned 'lpminer-*'; sort for deterministic pick.
MINER_BIN="${MINER_BIN:-}"
[ -n "$MINER_BIN" ] || MINER_BIN="$(command -v lpminer || true)"
[ -n "$MINER_BIN" ] || MINER_BIN="$(find /opt/lpminer -maxdepth 4 -type f -name lpminer -perm -u+x 2>/dev/null | sort | head -n1 || true)"
[ -n "$MINER_BIN" ] || MINER_BIN="$(find /opt/lpminer -maxdepth 4 -type f -name 'lpminer-*' -perm -u+x 2>/dev/null | sort | head -n1 || true)"
[ -n "$MINER_BIN" ] || die "lpminer binary not found under /opt/lpminer."
[ -x "$MINER_BIN" ] || die "lpminer binary at $MINER_BIN is not executable."

MINER_PASSWORD="${MINER_PASSWORD:-x}"
MINER_DEVICES="${MINER_DEVICES:-}"

# Build the lpminer command. lpminer (exfer branch) uses a phase flag
# (--pearl-mine) plus --pool / --wallet / --worker. The wallet carries the
# optional solo: prefix; --password and --algo are accepted but ignored.
cmd=( "$MINER_BIN" --pearl-mine
      --pool "$POOL"
      --wallet "$WALLET_FOR_POOL"
      --worker "$WORKER_NAME"
      --password "$MINER_PASSWORD" )
# Restrict to specific exposed GPUs if requested (default: lpminer uses all).
[ -n "$MINER_DEVICES" ] && cmd+=( --devices "$MINER_DEVICES" )
# Append any extra raw args (intentionally word-split).
if [ -n "${MINER_EXTRA_ARGS:-}" ]; then
  # shellcheck disable=SC2206
  cmd+=( ${MINER_EXTRA_ARGS} )
fi

# ---- Safe startup summary ---------------------------------------------------

log "=================================================="
log " Pearl (PRL) miner  -  LuckyPool / lpminer"
log "=================================================="
log "Pool endpoint : ${POOL}"
log "Worker name   : ${WORKER_NAME}"
log "Solo mode     : ${SOLO_ENABLED}"
log "Miner binary  : ${MINER_BIN}"
log "GPU devices   : ${MINER_DEVICES:-all (exposed to container)}"
log "GPU visible   :"
while IFS= read -r line; do log "   ${line}"; done <<< "$GPU_LIST"
# Password and any free-form extra args are masked here so secrets never hit the logs.
log "Command       : ${MINER_BIN} --pearl-mine --pool ${POOL} --wallet $(redact "$WALLET_FOR_POOL") --worker ${WORKER_NAME} --password ***${MINER_DEVICES:+ --devices ${MINER_DEVICES}}${MINER_EXTRA_ARGS:+ [+ extra args]}"
log "=================================================="
if [ "$SOLO_ENABLED" = "yes" ]; then
  log "WARNING: Solo mining is lottery-style. You may earn ZERO PRL for days or"
  log "         weeks. A reward only arrives when this rig finds a whole block."
fi

# Use the writable data volume as the working directory if available.
if [ -d /data ] && [ -w /data ]; then
  cd /data
fi

# Exec so lpminer becomes PID 1 and receives SIGTERM on container stop.
exec "${cmd[@]}"

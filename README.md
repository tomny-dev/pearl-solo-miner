# Pearl (PRL) Miner — Dockerized, NVIDIA GPU

[![build-and-push](https://github.com/tomny-dev/pearl-solo-miner/actions/workflows/build.yml/badge.svg)](https://github.com/tomny-dev/pearl-solo-miner/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A small, hardened Docker wrapper for mining **Pearl (PRL)** on NVIDIA GPUs with
**LuckyPool's `lpminer`**. Solo or pool mining, one or many GPUs, on Linux,
Windows (Docker Desktop + WSL2), or macOS. All config is via environment
variables — nothing sensitive is baked into the image.

> ⚠️ **Solo mining is lottery-style.** You only get paid when *your* rig finds a
> whole block, so you may mine for days with zero PRL. For steady, proportional
> payouts set `SOLO_MODE=false`.

---

## Quick start

```bash
cp .env.example .env        # 1. create your config
# 2. edit .env: set PRL_WALLET to your Pearl address (prl1…)
docker compose up -d        # 3. build + start, detached   (or: ./scripts/run.sh)
docker compose logs -f      # 4. watch it mine             (or: ./scripts/logs.sh)
docker compose down         # 5. stop                      (or: ./scripts/stop.sh)
```

Only **`PRL_WALLET`** is required — your Pearl payout address (`prl1…`),
**without** a `solo:` prefix (`SOLO_MODE` adds it for you). Everything else in
`.env` has a working default.

> Compose is the recommended path: `docker compose up -d` builds the image the
> first time, then runs the miner with **all security hardening applied for you**
> (read-only root filesystem, dropped capabilities, `no-new-privileges`, GPU
> reservation, and an always-open stdin). You never type a volume, tmpfs, or
> security flag.

> 🔒 Your real values live in `.env`, which is git-ignored. **Never commit
> `.env`** — only `.env.example` belongs in git.

---

## Prerequisites

Docker + Docker Compose v2, an NVIDIA GPU, and a recent NVIDIA driver. GPU
passthrough setup differs per OS:

- **Linux** — install the **NVIDIA Container Toolkit**, then
  `sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker`.
- **Windows** — Docker Desktop with the **WSL2 backend** + the NVIDIA Windows
  driver (Game Ready / Studio). Do **not** install a driver inside WSL.
- **macOS** — NVIDIA passthrough isn't available; you can build the image but
  not mine.

Verify the GPU reaches containers (works the same on Linux/Windows):

```bash
docker run --rm --gpus all nvidia/cuda:12.8.1-base-ubuntu24.04 nvidia-smi
```

If that lists your GPU, you're ready.

---

## Configuration

Edit `.env` (copied from `.env.example`):

| Variable           | Required | Default                      | Purpose |
|--------------------|----------|------------------------------|---------|
| `PRL_WALLET`       | yes      | —                            | Your Pearl payout address (no `solo:` prefix). |
| `WORKER_NAME`      | no       | `rig01`                      | Label for this rig on the dashboard. |
| `SOLO_MODE`        | no       | `true`                       | `true` = solo (adds `solo:`); `false` = shared pool. |
| `GPU_COUNT`        | no       | `1`                          | GPUs to use: `1`, `2`, … or `all`. |
| `POOL_HOST`        | yes      | `pearl-ca1.luckypool.io`     | Pool stratum host (North America). |
| `POOL_PORT`        | yes      | `3360`                       | Difficulty port: `3360` low / `3361` mid / `3362` high. |
| `MINER_DEVICES`    | no       | all exposed                  | Restrict to specific GPUs, e.g. `0` or `0,1`. |
| `MINER_EXTRA_ARGS` | no       | —                            | Extra raw flags for `lpminer`. |
| `LPMINER_URL`      | no       | Linux `lpminer-0.1.9.tar.gz` | Build-time download URL (must be the Linux `.tar.gz`). |
| `CUDA_IMAGE_TAG`   | no       | `12.8.1-runtime-ubuntu24.04` | Build arg (set in `.env` or `--build-arg`): CUDA base image. |

> Rarely-needed knobs (`MINER_PASSWORD`, `CUDA_FORCE_PTX_JIT`) have safe defaults
> and aren't in `.env.example`; see [Troubleshooting](#troubleshooting).

The resulting command (password and extra args are masked in logs):

```
lpminer --pearl-mine --pool <POOL_HOST>:<POOL_PORT> --wallet [solo:]<WALLET> --worker <WORKER> [--devices <MINER_DEVICES>] [extra]
```

### GPU selection

`GPU_COUNT` uses the *first N* GPUs (cross-platform via Compose device
reservations). To pin *specific* cards, edit `docker-compose.yml`: comment out
the `count:` line and uncomment `device_ids:` (e.g. `["1"]` or `["0","2"]`).
`lpminer` uses all GPUs the container can see; `MINER_DEVICES` narrows that.

### Pool difficulty port

Match the port to your hashrate (too-high difficulty = long gaps between shares):

| Port   | Difficulty | Good for                        |
|--------|------------|----------------------------------|
| `3360` | ~2M (low)  | rigs under ~500 TH/s (default)   |
| `3361` | ~4M (mid)  | mid-size rigs                    |
| `3362` | ~8M (high) | large rigs / farms               |

Confirm current hosts/ports on the pool's getting-started page — they can change.

---

## What you'll see

On startup the entrypoint validates config and prints a safe summary (the wallet
is redacted to first-6/last-4, and the password/extra args are masked):

```
[pearl-solo-miner] Pool endpoint : pearl-ca1.luckypool.io:3360
[pearl-solo-miner] Worker name   : rig01
[pearl-solo-miner] Solo mode     : yes
[pearl-solo-miner] Miner binary  : /opt/lpminer/lpminer/lpminer
[pearl-solo-miner] GPU devices   : all (exposed to container)
[pearl-solo-miner] GPU visible   :
[pearl-solo-miner]    GPU 0: NVIDIA GeForce RTX 4090 (UUID: GPU-....)
[pearl-solo-miner] Command       : .../lpminer --pearl-mine --pool pearl-ca1.luckypool.io:3360 --wallet solo:p…wxyz --worker rig01 --password ***
```

**Worker stats:** open <https://pearl.luckypool.io/> and look up your PRL
address, then find your worker by `WORKER_NAME`. In solo mode the wrapper logs
in as `solo:<address>`, so use the pool's solo view (or search the `solo:`-prefixed
address) — searching the bare address may show only shared-pool stats.

---

## Security hardening

The **Compose path** (`docker compose up -d`) applies full runtime hardening —
none of which you type yourself:

- **Non-root** runtime user (`miner`, UID 10001) — baked into the image, so it
  applies however you run it.
- **Read-only root filesystem**, **`cap_drop: ALL`**, **`no-new-privileges`**.
- Writable scratch via `tmpfs /tmp` and a named `miner_data` volume at `/data`
  (also `HOME` and the CUDA JIT cache).

The minimal `docker run` in [Prebuilt image](#prebuilt-image-ghcr) skips the
read-only/capability hardening for cross-shell simplicity (the image is still
non-root); use Compose when you want the full set.

---

## Prebuilt image (GHCR)

Prefer not to build? Pull the published image and run it (swap in your
`owner/repo` if you forked). You still need a `.env` next to where you run this —
`cp .env.example .env` and set `PRL_WALLET` first.

This **one command is identical in PowerShell, CMD, and Git Bash** — it has no
mount paths, so there's nothing for any shell to rewrite (no per-shell variants):

```bash
docker run -di --name pearl-solo-miner --gpus all --env-file .env --restart unless-stopped ghcr.io/tomny-dev/pearl-solo-miner:latest
```

Then `docker logs -f pearl-solo-miner` to watch, `docker stop pearl-solo-miner` to stop.

- **`-di` is required:** `lpminer` reads stdin and exits on EOF when detached.
- Pick GPUs with `--gpus all` / `--gpus 2` / `--gpus '"device=0,2"'`.

> This minimal command trades away the runtime hardening for cross-shell
> simplicity: the root filesystem is writable (not read-only) and capabilities
> aren't dropped — though the image still runs as the non-root `miner` user.
> **For the fully hardened setup, use Compose** (`docker compose up -d`), which
> keeps the read-only root fs, `cap_drop: ALL`, `no-new-privileges`, and a named
> `miner_data` volume — and never asks you to type a mount path either.

---

## Troubleshooting

**No GPU detected** (`nvidia-smi not found` / `No NVIDIA GPU visible`)
- Linux: the Container Toolkit isn't active — re-run `nvidia-ctk runtime configure` + restart Docker.
- Windows: ensure Docker Desktop uses the WSL2 backend and the NVIDIA Windows driver is installed.
- Test the host: `docker run --rm --gpus all nvidia/cuda:12.8.1-base-ubuntu24.04 nvidia-smi`.
- Wrong/too few cards: check `GPU_COUNT` (or `device_ids`) against `nvidia-smi -L`.

**RTX 50-series (Blackwell / `sm_120`): `illegal memory access` crash loop**
lpminer enables the card then the GPU compute faults — usually an environment
issue, not missing Blackwell support. Try, in order:
1. Newer CUDA base: `docker compose build --build-arg CUDA_IMAGE_TAG=12.9.1-runtime-ubuntu24.04` (or `13.0.2-...`), then `up -d`.
2. Add `CUDA_FORCE_PTX_JIT=1` to `.env` and restart.
3. On Docker Desktop/WSL2, bleeding-edge `sm_120` kernels can fault even when fine on bare-metal Linux — not fixable from the container.

Isolate it (GPU self-test, no pool): `docker run --rm -it --gpus all --entrypoint /opt/lpminer/lpminer/lpminer pearl-solo-miner:latest --pearl-bench`

**Container keeps restarting**
- Logs end right at `commands  s (stats), q (quit)`: lpminer hit stdin EOF and quit. Compose sets `stdin_open: true`; with `docker run` use `-di`.
- Otherwise read the first `ERROR:` line — the entrypoint reports missing wallet/worker/pool/GPU/binary. A missing `.env` is the usual cause.

**Shares accepted but no payout** — expected for solo (you're paid only on a block). Confirm your address; use `SOLO_MODE=false` for steady payouts.

**Rejected / stale shares** — usually network latency; pick the closest `POOL_HOST` (`pearl-ca1`/`pearl-ca2` for NA) and check the host clock. Unstable overclocks also cause rejects.

**High temperature / power** — cap power on the host: `sudo nvidia-smi -i 0 -pl 300` (watts). Keep sustained temps under ~80–85 °C.

---

## License

[MIT](LICENSE). This wrapper doesn't endorse any pool — verify the operator and
current endpoints yourself before mining.

# Pearl (PRL) Miner — Dockerized, NVIDIA GPU

A small, hardened Docker wrapper for mining Pearl (PRL) on NVIDIA GPUs using
**LuckyPool's `lpminer`**. Supports **solo or normal pool mining**, **one or
many GPUs**, and runs on **Linux, Windows (Docker Desktop + WSL2) and macOS**.

- `lpminer` is downloaded at build time from the official LuckyPool URL
  (configurable via `LPMINER_URL`).
- All runtime settings — wallet, worker, pool, GPU count, mining mode — come
  from environment variables. Nothing sensitive is baked into the image.
- Defaults target a **LuckyPool North America** server on a **low-difficulty
  port** suitable for rigs **under ~500 TH/s**, in **solo** mode.

> ⚠️ **Solo mining is lottery-style.** You only get paid when *your* rig finds a
> whole block. You may mine for **days or weeks and earn zero PRL**. If you want
> steady, proportional payouts instead, set `SOLO_MODE=false` to mine the normal
> shared pool.

---

## Repository layout

```
.
├── Dockerfile             # CUDA base, downloads lpminer, non-root user
├── docker-compose.yml     # GPU selection + security hardening
├── .env.example           # all configuration (copy to .env)
├── .gitignore             # keeps your real .env out of git
├── start.sh               # validation, safe logging, exec lpminer
├── README.md
├── scripts/
│   ├── build.sh           # docker compose build
│   ├── run.sh             # docker compose up -d
│   ├── logs.sh            # docker compose logs -f
│   └── stop.sh            # docker compose down
└── .github/workflows/
    └── build.yml          # CI: build + push image to GHCR
```

> 🔒 **Public repo note:** your real settings live in `.env`, which is
> git-ignored. **Never commit `.env`** — only `.env.example` (with empty
> `PRL_WALLET`) belongs in git.

---

## Prerequisites

All platforms need Docker + Docker Compose v2, an NVIDIA GPU, and a recent
NVIDIA driver. The GPU-passthrough setup differs slightly per OS.

### Linux

Install the **NVIDIA Container Toolkit** so containers can see the GPU:

```bash
# Add the repository (Debian/Ubuntu)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit

# Register the NVIDIA runtime with Docker and restart it
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# Verify the GPU is visible to containers
sudo docker run --rm --gpus all nvidia/cuda:12.8.1-base-ubuntu24.04 nvidia-smi
```

### Windows (Docker Desktop + WSL2)

- **Windows 10/11 with WSL2** enabled.
- The normal **NVIDIA Windows driver** (Game Ready / Studio) — recent versions
  include CUDA-on-WSL support. ⚠️ Do **not** install a driver *inside* WSL; the
  Windows driver is shared into WSL automatically.
- **Docker Desktop** with the **WSL2 backend** (Settings → General → "Use the
  WSL 2 based engine"). No `nvidia-ctk` step is needed — GPU support is built in.

Verify the GPU reaches containers (PowerShell):

```powershell
docker run --rm --gpus all nvidia/cuda:12.8.1-base-ubuntu24.04 nvidia-smi
```

### macOS

NVIDIA GPU passthrough is **not available** on macOS (no supported NVIDIA driver
path through Docker Desktop). You can build/inspect the image, but actual mining
requires a Linux or Windows host with an NVIDIA GPU.

If the verify command lists your GPU(s), you're ready. The Compose file uses the
cross-platform device-reservation form, so the same `docker compose` commands
work on Linux and Windows.

---

## Quick start

```bash
# 1. Copy the example config and edit it
cp .env.example .env

# 2. Set at least your wallet (and pick a worker name)
#    PRL_WALLET=prl1your_real_pearl_address
#    WORKER_NAME=rig01

# 3. Choose how many GPUs to use (1, 2, ... or all) and the mining mode
#    GPU_COUNT=1
#    SOLO_MODE=true   # set to false for normal shared pool mining

# 4. Build the image (downloads lpminer)
./scripts/build.sh

# 5. Start mining
./scripts/run.sh

# 6. Watch the logs
./scripts/logs.sh

# 7. Stop when you're done
./scripts/stop.sh
```

### Setting `PRL_WALLET`

Edit `.env` and set your Pearl payout address. **Do not** add the `solo:` prefix
yourself — with `SOLO_MODE=true` (the default) the wrapper prefixes it for you:

```
PRL_WALLET=prl1qxyz...your_address...
```

### Solo vs. normal pool mining

Set `SOLO_MODE` in `.env`:

```
SOLO_MODE=true    # SOLO: wallet prefixed with solo:, you win whole blocks (lottery)
SOLO_MODE=false   # normal shared pool: steady, proportional payouts
```

The wrapper adds the `solo:` prefix automatically when solo is on — never put it
in `PRL_WALLET` yourself.

### Choosing how many / which GPUs

GPU selection uses Compose's cross-platform device reservation, so the same
config works on Linux and Windows. Set `GPU_COUNT` in `.env`:

```
GPU_COUNT=1     # one GPU (default)
GPU_COUNT=2     # two GPUs
GPU_COUNT=all   # every GPU in the machine
```

Run `nvidia-smi -L` (Linux/PowerShell) to see how your cards are numbered.

**Pinning specific cards** — `GPU_COUNT` takes the *first N* GPUs. To choose
*which* physical cards (e.g. only GPU 1, or GPUs 0 and 2), edit
`docker-compose.yml`: comment out the `count:` line and uncomment `device_ids:`,
then list them — `device_ids: ["1"]` or `device_ids: ["0","2"]`.

> **Multi-GPU note:** `lpminer` uses all GPUs the container can see. If you want
> per-GPU tuning or to limit which exposed GPUs it mines on, pass miner flags via
> `MINER_EXTRA_ARGS`.

### Checking logs

```bash
./scripts/logs.sh          # follow live output
docker compose logs --tail=200
```

On startup you'll see a summary like:

```
[pearl-solo-miner] Pool endpoint : pearl-ca1.luckypool.io:3360
[pearl-solo-miner] Worker name   : rig01
[pearl-solo-miner] Solo mode     : yes
[pearl-solo-miner] GPU visible   :
[pearl-solo-miner]    GPU 0: NVIDIA GeForce RTX 4090 (UUID: GPU-....)
[pearl-solo-miner] Command       : .../lpminer pearl solo:p…wxyz.rig01 pearl-ca1.luckypool.io:3360 x
```

The wallet is **always redacted** in logs (first 6 / last 4 characters only).

### Stopping

```bash
./scripts/stop.sh
```

### Finding your worker stats on the pool dashboard

1. Go to the LuckyPool Pearl dashboard: <https://pearl.luckypool.io/>
2. Paste your **full PRL wallet address** into the search/lookup box.
   - For solo mining, look it up **with** the `solo:` prefix if the dashboard
     distinguishes solo vs. shared workers.
3. Find your worker by the `WORKER_NAME` you set (e.g. `rig01`).
4. There you can see accepted shares, hashrate, and any pending balance/payout.

---

## Configuration reference

| Variable          | Required | Default                          | Purpose |
|-------------------|----------|----------------------------------|---------|
| `PRL_WALLET`      | yes      | —                                | Your Pearl payout address (no `solo:` prefix). |
| `WORKER_NAME`     | yes      | `rig01`                          | Label for this rig on the dashboard. |
| `POOL_HOST`       | yes      | `pearl-ca1.luckypool.io`         | Pool stratum host (North America). |
| `POOL_PORT`       | yes      | `3360`                           | Difficulty port (3360 low / 3361 mid / 3362 high). |
| `SOLO_MODE`       | no       | `true`                           | `true` = solo (prefix `solo:`); `false` = normal pool. |
| `GPU_COUNT`       | no       | `1`                              | Number of GPUs to use (`1`, `2`, … or `all`). |
| `MINER_DEVICES`   | no       | all exposed                      | GPUs lpminer mines on, e.g. `0` or `0,1`. Empty = all. |
| `MINER_EXTRA_ARGS`| no       | —                                | Extra raw args for `lpminer`. |
| `LPMINER_URL`     | no       | Linux `lpminer-0.1.9.tar.gz`     | Build-time download URL. Must be the Linux `.tar.gz`. |
| `CUDA_IMAGE_TAG`  | no       | `12.8.1-runtime-ubuntu24.04`     | Build arg only; advanced — try a newer CUDA for RTX 50-series. |

> Advanced/rare knobs (`MINER_PASSWORD`, `CUDA_FORCE_PTX_JIT`) have sensible
> defaults and aren't in `.env.example`; see Troubleshooting if you need them.

Resulting miner command (wallet redacted in logs):

```
lpminer --pearl-mine --pool <POOL_HOST>:<POOL_PORT> --wallet <solo:WALLET> --worker <WORKER> [--devices <MINER_DEVICES>] [MINER_EXTRA_ARGS]
```

---

## Security hardening

The compose file applies hardening that is compatible with the NVIDIA runtime:

- **Runs as a non-root user** (`miner`, UID 10001) created in the image.
- **`no-new-privileges:true`** — the process can't gain privileges via setuid.
- **`cap_drop: ALL`** — no Linux capabilities; mining needs none.
- **`read_only: true`** — the root filesystem is mounted read-only.

### Why a read-only root filesystem *is* used (with writable scratch)

`read_only: true` is enabled. Because the miner may still need scratch space
(temp files, a small runtime cache), two writable mounts are provided instead of
making the whole filesystem writable:

- `tmpfs: /tmp` — in-memory temp, wiped on restart.
- a named volume `miner_data` mounted at `/data` (the working directory).

If a future `lpminer` version needs to write somewhere outside `/tmp` or `/data`
and fails under read-only mode, either add another `tmpfs`/volume for that path,
or temporarily set `read_only: false` in `docker-compose.yml`.

---

## Pool difficulty / port guidance

Pick the port that matches your hashrate so the pool sends appropriately sized
work (too-high difficulty on a small rig means long gaps between shares):

| Port  | Difficulty | Good for                |
|-------|-----------|--------------------------|
| 3360  | ~2M (low) | rigs under ~500 TH/s (default) |
| 3361  | ~4M (mid) | mid-size rigs            |
| 3362  | ~8M (high)| large rigs / farms       |

Always confirm the **current** hosts and ports on the pool's getting-started
page — pools occasionally change them.

---

## Troubleshooting

### No GPU detected
- `nvidia-smi not found` or `No NVIDIA GPU visible`:
  - **Linux:** the NVIDIA Container Toolkit isn't active. Re-run the install
    steps, then `sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker`.
  - **Windows:** ensure Docker Desktop uses the WSL2 backend and the NVIDIA
    Windows driver is installed (not a driver inside WSL).
- Test the host directly:
  `docker run --rm --gpus all nvidia/cuda:12.8.1-base-ubuntu24.04 nvidia-smi`.
- Wrong / too few cards: check `GPU_COUNT` (or the `device_ids` block) against
  `nvidia-smi -L`.
- The Compose `deploy.devices` block must keep `utility` in `capabilities` so
  `nvidia-smi` is injected.

### RTX 50-series (Blackwell / `sm_120`): "illegal memory access" crash loop
- Symptom: startup is clean (GPU detected, pool `authorize: ok`, a job arrives),
  then immediately:
  ```
  pearl_harness: kernel launch: an illegal memory access was encountered
  GPU #0 worker exited rc=1; disabling device for this session
  all GPU workers exited; stopping session
  ```
  followed by a restart loop.
- Note: lpminer **enables** the `sm_120` card (so the binary *does* know
  Blackwell), then the compute faults — usually an **execution / environment**
  issue, not "no Blackwell support". Things to try, in order:
  1. **Newer CUDA runtime.** Rebuild on a newer base image:
     `docker compose build --build-arg CUDA_IMAGE_TAG=12.9.1-runtime-ubuntu24.04 && docker compose up -d`
     (or `13.0.2-runtime-ubuntu24.04`).
  2. **Force PTX JIT.** Add `CUDA_FORCE_PTX_JIT=1` to your `.env` and restart.
     (A writable JIT cache is already configured in the image.)
  3. **WSL2 limitation.** On Docker Desktop (Windows), bleeding-edge `sm_120`
     kernels can fault under WSL2 even when fine on bare-metal Linux — this can't
     be fixed from inside the container. If 1–2 don't help, run lpminer natively
     on Windows, or on a bare-metal Linux host.
- Isolate it (GPU self-test, no pool). If this crashes too, the cause is the
  CUDA/WSL2 environment, not your pool/config:
  `docker run --rm -it --gpus all --entrypoint /opt/lpminer/lpminer/lpminer pearl-solo-miner:latest --pearl-bench`
- **Stop the loop** anytime with `docker compose down`.

### Shares accepted but no payout yet
- **This is expected for solo mining.** Accepted shares only prove your rig is
  working; payment comes **only when you find a block**, which is rare and random.
- Check the pool's minimum payout threshold and confirm your address is correct.
- Switch `SOLO_MODE=false` if you'd rather have steady proportional payouts.

### Wrong pool difficulty port
- Symptom: very few or no shares submitted, long idle gaps. Your rig may be on a
  port whose difficulty is too high. Lower `POOL_PORT` (e.g. to `3360`).
- Conversely, a huge farm on a low-diff port can flood the pool — move up.

### Rejected / stale shares
- A few stale shares are normal. A high rate usually means **network latency** —
  switch to the closest region (`POOL_HOST`), e.g. `pearl-ca1` / `pearl-ca2` for
  North America.
- Check the host clock is accurate (`timedatectl`).
- Unstable overclocks also cause rejects — back off OC/undervolt settings.

### Container keeps restarting
- **Logs end right after `commands  s (stats), q (quit)`** with no error: lpminer
  read EOF on a closed stdin and quit cleanly, and the restart policy relaunched
  it. Keep stdin open — Compose already sets `stdin_open: true`; with `docker run`
  use `-di` instead of `-d`.
- `./scripts/logs.sh` and read the first error line. The entrypoint validates
  config and prints a clear `ERROR:` for missing `PRL_WALLET`, `WORKER_NAME`,
  pool endpoint, GPU, or miner binary.
- A missing/empty `.env`, or a bad `LPMINER_URL` at build time, are common causes.
- `restart: unless-stopped` will loop a misconfigured container — fix the error,
  then `./scripts/stop.sh && ./scripts/run.sh`.

### High temperature / power usage
- Mining runs the GPU at full load. Ensure good airflow and monitor with
  `nvidia-smi -l 5` (or `watch -n5 nvidia-smi`) on the host.
- Set a power cap on the host (persists for the card):
  `sudo nvidia-smi -i 0 -pl 300` (watts; pick a safe value for your card).
- Set a thermal limit / fan curve, and pass any miner-specific limits via
  `MINER_EXTRA_ARGS`.
- If temps exceed ~80–85 °C sustained, reduce the power limit or improve cooling.

---

## Continuous integration / prebuilt image (GHCR)

A GitHub Actions workflow ([`.github/workflows/build.yml`](.github/workflows/build.yml))
builds the image and publishes it to the **GitHub Container Registry (GHCR)**.

- **Pull requests** build the image only (a smoke test — nothing is pushed).
- **Pushes to `main`** publish `:latest` and `:main` plus a commit-SHA tag.
- **Version tags** like `v1.2.3` publish `:1.2.3`, `:1.2`, and `:latest`.
- A **manual run** (`workflow_dispatch`) lets you override `LPMINER_URL`.

It uses the built-in `GITHUB_TOKEN` (no extra secrets) and the repo's
`packages: write` permission, so it works out of the box once the repo is on
GitHub.

### Make the published package public

By default the GHCR package is private. To let anyone pull it:
**GitHub → your repo → Packages → the package → Package settings → Change
visibility → Public.**

### Run from the prebuilt image instead of building locally

Images are published to `ghcr.io/tomny-dev/pearl-solo-miner` (if you forked the
repo, swap in your own lowercase `owner/repo`). The `--gpus` flag works the same
on Linux and Windows (Docker Desktop).

**Linux / macOS shells:**

```bash
docker pull ghcr.io/tomny-dev/pearl-solo-miner:latest

docker run -di --name pearl-solo-miner \
  --gpus all \
  --env-file .env \
  --read-only --tmpfs /tmp -v miner_data:/data \
  --security-opt no-new-privileges:true --cap-drop ALL \
  --restart unless-stopped \
  ghcr.io/tomny-dev/pearl-solo-miner:latest
```

**Windows (PowerShell):**

```powershell
docker pull ghcr.io/tomny-dev/pearl-solo-miner:latest

docker run -di --name pearl-solo-miner `
  --gpus all `
  --env-file .env `
  --read-only --tmpfs /tmp -v miner_data:/data `
  --security-opt no-new-privileges:true --cap-drop ALL `
  --restart unless-stopped `
  ghcr.io/tomny-dev/pearl-solo-miner:latest
```

> Note the **`-di`** (not `-d`): lpminer reads stdin for its `s`/`q` commands and
> quits on EOF, so it needs stdin held open (`-i`) to run detached. Compose does
> this via `stdin_open: true`.

**Choosing GPUs with `docker run`:**

```
--gpus all                 # every GPU
--gpus 2                   # the first two GPUs
--gpus '"device=0"'        # only GPU 0   (quote exactly like this)
--gpus '"device=0,2"'      # GPUs 0 and 2
```

Or point Compose at the published image (works on every OS). Set the service
`image:` to `ghcr.io/tomny-dev/pearl-solo-miner:latest` in `docker-compose.yml`, then:

```bash
docker compose pull
docker compose up -d
```

---

## Notes

- `lpminer` is fetched from `LPMINER_URL` at **build time**. Re-run
  `./scripts/build.sh` after changing the version.
- Comments in the shell/YAML/.env files use single-line comments only (no block
  comments), per project convention. (`//` is not a valid comment character in
  these formats, so the standard `#` is used.)
- This wrapper does not endorse any pool; verify the operator and current
  endpoints yourself before mining.

# Pearl (PRL) Solo-Pool Miner — Dockerized, NVIDIA GPU

A small, hardened Docker wrapper for **solo mining Pearl (PRL)** on a single
NVIDIA GPU using **LuckyPool's `lpminer`**.

- `lpminer` is downloaded at build time from the official LuckyPool URL
  (configurable via `LPMINER_URL`).
- All runtime settings — wallet, worker, pool, GPU, solo mode — come from
  environment variables. Nothing sensitive is baked into the image.
- Defaults target a **LuckyPool North America** server on a **low-difficulty
  port** suitable for rigs **under ~500 TH/s**.

> ⚠️ **Solo mining is lottery-style.** You only get paid when *your* rig finds a
> whole block. You may mine for **days or weeks and earn zero PRL**. If you want
> steady, proportional payouts instead, set `SOLO_MODE=false` to mine the normal
> shared pool.

---

## Repository layout

```
.
├── Dockerfile             # CUDA base, downloads lpminer, non-root user
├── docker-compose.yml     # single-GPU pinning + security hardening
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

- A Linux host with an NVIDIA GPU and a recent NVIDIA driver.
- Docker Engine + Docker Compose v2.
- The **NVIDIA Container Toolkit** (so containers can see the GPU).

### Install the NVIDIA Container Toolkit

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

If that last command lists your GPU, you're ready.

---

## Quick start

```bash
# 1. Copy the example config and edit it
cp .env.example .env

# 2. Set at least your wallet (and pick a worker name)
#    PRL_WALLET=prl1your_real_pearl_address
#    WORKER_NAME=rig01

# 3. Choose which physical GPU to use (0 = first card, 1 = second card)
#    GPU_ID=0

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

### Choosing GPU 0 or GPU 1

Set `GPU_ID` in `.env`. This pins the container to exactly **one** physical card
via `NVIDIA_VISIBLE_DEVICES`:

```
GPU_ID=0   # first GPU
GPU_ID=1   # second GPU
```

Run `nvidia-smi -L` on the host to see how your cards are numbered. To run a
second card at the same time, copy the project to another folder, set `GPU_ID=1`
and a different `WORKER_NAME` and `container_name`, then start it separately.

> Alternative: the compose file includes a commented `deploy.devices` block that
> pins the same single GPU using `device_ids` instead of the nvidia runtime —
> use it if your Docker is set up for CDI rather than `runtime: nvidia`.

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
| `SOLO_MODE`       | no       | `true`                           | `true` prefixes wallet with `solo:`. |
| `GPU_ID`          | no       | `0`                              | Physical GPU index (0 or 1). |
| `MINER_PASSWORD`  | no       | `x`                              | Stratum password field. |
| `MINER_EXTRA_ARGS`| no       | —                                | Extra raw args for `lpminer`. |
| `LPMINER_URL`     | no       | official `lpminer-0.1.9.tar.gz`  | Build-time download URL/version. |

Resulting miner command (wallet redacted in logs):

```
lpminer pearl <solo:WALLET>.<WORKER> <POOL_HOST>:<POOL_PORT> <MINER_PASSWORD> [MINER_EXTRA_ARGS]
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
- `nvidia-smi not found` or `No NVIDIA GPU visible`: the NVIDIA Container Toolkit
  isn't active. Re-run the install steps, then
  `sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker`.
- Test the host directly:
  `docker run --rm --gpus all nvidia/cuda:12.8.1-base-ubuntu24.04 nvidia-smi`.
- Wrong card: check `GPU_ID` against `nvidia-smi -L`.
- Using the `deploy.devices` block? Make sure `capabilities` includes `utility`
  so `nvidia-smi` is injected.

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

Replace `<owner>/<repo>` with your GitHub path (lowercase). Pull, then run with
your `.env`:

```bash
docker pull ghcr.io/<owner>/<repo>:latest

docker run -d --name pearl-solo-miner \
  --runtime=nvidia \
  -e NVIDIA_VISIBLE_DEVICES=0 \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility \
  --env-file .env \
  --read-only --tmpfs /tmp -v miner_data:/data \
  --security-opt no-new-privileges:true --cap-drop ALL \
  --restart unless-stopped \
  ghcr.io/<owner>/<repo>:latest
```

Or point Compose at the published image by adding `image:` to the service and
skipping the local build:

```bash
# Use the registry image without rebuilding
docker compose pull
docker compose up -d
```

(For `docker compose pull` to fetch GHCR rather than build, set the service
`image:` to `ghcr.io/<owner>/<repo>:latest` in `docker-compose.yml`.)

---

## Notes

- `lpminer` is fetched from `LPMINER_URL` at **build time**. Re-run
  `./scripts/build.sh` after changing the version.
- Comments in the shell/YAML/.env files use single-line comments only (no block
  comments), per project convention. (`//` is not a valid comment character in
  these formats, so the standard `#` is used.)
- This wrapper does not endorse any pool; verify the operator and current
  endpoints yourself before mining.

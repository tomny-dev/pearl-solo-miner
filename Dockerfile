# syntax=docker/dockerfile:1
# Pearl (PRL) solo-pool miner for NVIDIA GPUs using LuckyPool lpminer.

# CUDA base image tag is a build arg so you can try a newer CUDA runtime for
# bleeding-edge GPUs (e.g. RTX 50-series / sm_120):
#   docker compose build --build-arg CUDA_IMAGE_TAG=13.0.1-runtime-ubuntu24.04
ARG CUDA_IMAGE_TAG=12.8.1-runtime-ubuntu24.04
FROM nvidia/cuda:${CUDA_IMAGE_TAG}

# lpminer download URL is configurable at build time so you can pin/upgrade
# without editing the Dockerfile:  docker compose build --build-arg LPMINER_URL=...
# Use the Linux .tar.gz build (the .zip is a Windows-only binary and will not
# run inside this Linux image).
ARG LPMINER_URL=https://pearl.luckypool.io/lpminer/lpminer-0.1.9.tar.gz

# Fixed UID/GID for the non-root runtime user (and the writable /data volume).
ARG MINER_UID=10001
ARG MINER_GID=10001

ENV DEBIAN_FRONTEND=noninteractive \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    CUDA_CACHE_PATH=/tmp/.nv \
    HOME=/data

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates tar unzip wget \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/lpminer

# Download and unpack lpminer. Handles .tar.gz and .zip; the archive type is
# detected from the URL with any ?query/#fragment stripped.
RUN wget -qO /tmp/lpminer.archive "${LPMINER_URL}" \
 && url_path="${LPMINER_URL%%[?#]*}" \
 && case "${url_path}" in \
      *.zip)          unzip -q /tmp/lpminer.archive -d /opt/lpminer ;; \
      *.tar.gz|*.tgz) tar -xzf /tmp/lpminer.archive -C /opt/lpminer ;; \
      *) echo "Unsupported archive type: ${LPMINER_URL}" >&2; exit 1 ;; \
    esac \
 && rm -f /tmp/lpminer.archive \
 && find /opt/lpminer -type f \( -name lpminer -o -name 'lpminer-*' \) -exec chmod +x {} \;

COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

# Create an unprivileged user and a writable data dir for any runtime cache.
# The named volume mounted at /data inherits this ownership on first use.
RUN groupadd -g "${MINER_GID}" miner \
 && useradd -u "${MINER_UID}" -g "${MINER_GID}" -M -s /usr/sbin/nologin miner \
 && mkdir -p /data \
 && chown -R miner:miner /data /opt/lpminer

USER miner
WORKDIR /data

ENTRYPOINT ["/usr/local/bin/start.sh"]

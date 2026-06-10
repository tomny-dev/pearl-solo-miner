# syntax=docker/dockerfile:1
# Pearl (PRL) solo-pool miner for NVIDIA GPUs using LuckyPool lpminer.

FROM nvidia/cuda:12.8.1-runtime-ubuntu24.04

# lpminer download URL is configurable at build time so you can pin/upgrade
# without editing the Dockerfile:  docker compose build --build-arg LPMINER_URL=...
ARG LPMINER_URL=https://pearl.luckypool.io/lpminer/lpminer-0.1.9.tar.gz

# Fixed UID/GID for the non-root runtime user (and the writable /data volume).
ARG MINER_UID=10001
ARG MINER_GID=10001

ENV DEBIAN_FRONTEND=noninteractive \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates tar wget \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/lpminer

# Download and unpack lpminer at build time from the official LuckyPool URL.
RUN wget -qO /tmp/lpminer.tar.gz "${LPMINER_URL}" \
 && tar -xzf /tmp/lpminer.tar.gz -C /opt/lpminer \
 && rm -f /tmp/lpminer.tar.gz \
 && find /opt/lpminer -type f -name 'lpminer*' -exec chmod +x {} \;

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

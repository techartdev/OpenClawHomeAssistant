ARG BUILD_FROM=ghcr.io/hassio-addons/base:14.0.2
FROM ${BUILD_FROM}

# Base image is Alpine (HA add-ons base). It may only provide Node 18.x.
# Clawdbot requires Node 20+, so we install a Node 20 musl build directly.
ARG NODE_VERSION=20.11.1

RUN apk add --no-cache \
    bash \
    git \
    openssh-client \
    ca-certificates \
    tzdata \
    jq \
    curl \
    tar \
    xz \
    libstdc++ \
    libgcc

RUN set -euo pipefail; \
  arch=$(uname -m); \
  if [ "$arch" != "x86_64" ]; then echo "Unsupported arch: $arch"; exit 1; fi; \
  url="https://unofficial-builds.nodejs.org/download/release/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64-musl.tar.xz"; \
  echo "Downloading Node.js $NODE_VERSION (musl) from $url"; \
  curl -fsSL "$url" -o /tmp/node.tar.xz; \
  mkdir -p /usr/local; \
  tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1; \
  rm -f /tmp/node.tar.xz; \
  node -v; npm -v

# Install clawdbot globally
RUN npm config set fund false && npm config set audit false \
 && npm install -g clawdbot

COPY run.sh /run.sh
RUN chmod +x /run.sh

CMD [ "/run.sh" ]

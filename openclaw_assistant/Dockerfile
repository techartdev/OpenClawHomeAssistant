ARG BUILD_FROM=ghcr.io/hassio-addons/base:14.0.2
FROM ${BUILD_FROM}

# Base image is Alpine (HA add-ons base). It may only provide Node 18.x.
# OpenClaw requires Node 20+, so we install a Node 20 musl build directly.
ARG NODE_VERSION=22.12.0

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
    libgcc \
    libatomic \
    file \
    pax-utils \
    python3 \
    nginx \
    ttyd

# Install Node.js 22+ (musl build) from unofficial builds.
# Router/base image Alpine may ship an older libstdc++; we pull a newer libstdc++ from edge to satisfy Node's C++ symbols.
RUN set -eu; \
  arch=$(uname -m); \
  if [ "$arch" != "x86_64" ]; then echo "Unsupported arch: $arch"; exit 1; fi; \
  url="https://unofficial-builds.nodejs.org/download/release/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64-musl.tar.xz"; \
  echo "Downloading Node.js $NODE_VERSION (musl) from $url"; \
  curl -fsSL "$url" -o /tmp/node.tar.xz; \
  mkdir -p /usr/local; \
  tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1; \
  rm -f /tmp/node.tar.xz; \
  echo "Upgrading libstdc++/libgcc/libatomic from Alpine edge for Node compatibility"; \
  apk add --no-cache --upgrade \
    --repository=https://dl-cdn.alpinelinux.org/alpine/edge/main \
    --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community \
    libstdc++ libgcc libatomic; \
  /usr/local/bin/node -v; /usr/local/bin/npm -v

# Install OpenClaw globally
RUN npm config set fund false && npm config set audit false \
 && npm install -g openclaw@2026.1.29

COPY run.sh /run.sh
COPY nginx.conf.tpl /etc/nginx/nginx.conf.tpl
RUN chmod +x /run.sh \
 && mkdir -p /run/nginx

CMD [ "/run.sh" ]

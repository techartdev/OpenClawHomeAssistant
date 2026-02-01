ARG BUILD_FROM
FROM ${BUILD_FROM}

# Base image is Debian Bookworm (glibc). This avoids musl-related native module issues
# that occur on Alpine (e.g. clipboard, node-llama-cpp).

# Install base packages (without nodejs/npm - we'll get Node 22 from NodeSource)
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    git \
    openssh-client \
    ca-certificates \
    tzdata \
    jq \
    curl \
    tar \
    xz-utils \
    file \
    python3 \
    nginx \
    gnupg \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Install Node.js 22 LTS from NodeSource (Debian Bookworm ships Node 18, but OpenClaw requires 20+)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
 && apt-get install -y nodejs \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Install ttyd (web terminal) - not in Debian repos, download binary
# Docker TARGETARCH: amd64, arm64, arm/v7 → ttyd filenames: x86_64, aarch64, armhf
ARG TARGETARCH
RUN ARCH=$(echo ${TARGETARCH:-$(dpkg --print-architecture)} | sed 's|arm64|aarch64|;s|arm/v7|armhf|;s|armv7|armhf|;s|amd64|x86_64|') \
 && echo "Downloading ttyd for arch: ${ARCH}" \
 && curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.${ARCH}" -o /usr/local/bin/ttyd \
 && chmod +x /usr/local/bin/ttyd

RUN node -v && npm -v

# Install OpenClaw globally
RUN npm config set fund false && npm config set audit false \
 && npm install -g openclaw@2026.1.30

COPY run.sh /run.sh
COPY nginx.conf.tpl /etc/nginx/nginx.conf.tpl
COPY landing.html.tpl /etc/nginx/landing.html.tpl
RUN chmod +x /run.sh \
 && mkdir -p /run/nginx

CMD [ "/run.sh" ]

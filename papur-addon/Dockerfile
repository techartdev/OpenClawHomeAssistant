ARG BUILD_FROM=ghcr.io/hassio-addons/base:14.0.2
FROM ${BUILD_FROM}

# Base image is Alpine. Install Node.js 20+ + git so we can install clawdbot.
# On HA base images, `nodejs` may be 18.x; use `nodejs-current` for 20+.
RUN apk add --no-cache \
    nodejs-current \
    npm \
    git \
    bash \
    openssh-client \
    ca-certificates \
    tzdata \
    jq

# Install clawdbot globally
RUN npm config set fund false && npm config set audit false \
 && npm install -g clawdbot

COPY run.sh /run.sh
RUN chmod +x /run.sh

CMD [ "/run.sh" ]

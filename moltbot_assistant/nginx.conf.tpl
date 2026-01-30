worker_processes  1;

# Log to stderr/stdout (container-friendly)
error_log /dev/stderr notice;

events { worker_connections 1024; }

http {
  include       /etc/nginx/mime.types;
  default_type  application/octet-stream;

  # Log to stdout/stderr (container-friendly)
  access_log /dev/stdout;
  error_log  /dev/stderr notice;

  sendfile        on;
  keepalive_timeout  65;

  # Ingress note: keep redirects relative so we stay under HA Ingress.

  server {
    listen 8099;

    # Web terminal (ttyd)
    location /terminal/ {
      proxy_pass http://127.0.0.1:7681/;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $remote_addr;
      proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Gateway UI
    # IMPORTANT: We must not redirect to an absolute "/..." path because Home Assistant Ingress
    # strips the ingress prefix before forwarding to the add-on. An absolute Location would jump
    # out of ingress (to the HA host root). So we use a *relative* redirect.

    # Only redirect the root document to add token in the browser URL.
    # NOTE: Home Assistant Ingress can expose the add-on at a path like:
    #   /hassio/ingress/<slug>
    # which may not end in a slash. Some clients compute relative URLs (including WS)
    # incorrectly if the URL doesn't end in '/'. HA often provides the original ingress
    # path via X-Ingress-Path; if present, redirect to that path with a trailing slash.
    location = / {
      if ($arg_token = "") {
        # Force a trailing slash via a relative redirect.
        # This avoids absolute /hassio/... redirects that can confuse HA ingress routing.
        return 302 ./?token=__GATEWAY_TOKEN__;
      }

      proxy_pass http://127.0.0.1:18789;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $remote_addr;
      proxy_set_header X-Forwarded-Proto $scheme;
    }

    # WebSocket endpoint compatibility:
    # Some clients/UIs assume a dedicated /ws path. The gateway websocket endpoint
    # itself is at /, so we map /ws -> / when proxying.
    location /ws {
      proxy_pass http://127.0.0.1:18789/;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $remote_addr;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_read_timeout 3600s;
      proxy_send_timeout 3600s;
    }

    # Everything else (assets, api, etc.) just proxy through.
    location / {
      proxy_pass http://127.0.0.1:18789;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $remote_addr;
      proxy_set_header X-Forwarded-Proto $scheme;
    }
  }
}

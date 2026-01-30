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
    location = / {
      if ($arg_token = "") {
        # Force a trailing slash via a relative redirect.
        return 302 ./?token=__GATEWAY_TOKEN__;
      }

      # Proxy the gateway UI.
      proxy_pass http://127.0.0.1:18789;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $remote_addr;
      proxy_set_header X-Forwarded-Proto $scheme;

      # Inject the correct WS URL when running behind HA Ingress.
      # HA provides a per-session ingress proxy path in X-Ingress-Path (usually /api/hassio_ingress/<token>).
      # The UI loaded at /hassio/ingress/<slug> cannot be used as a WS endpoint on some setups,
      # but /api/hassio_ingress/<token> *can* proxy websocket upgrades.
      #
      # We inject a small script to override the UI's saved websocket URL to:
      #   wss://<host><x-ingress-path>/
      # so the browser connects same-origin + through HA's ingress proxy.
      proxy_set_header Accept-Encoding "";
      sub_filter_types text/html;
      sub_filter_once on;
      sub_filter '</head>' '<script>(function(){try{var p="__INGRESS_PATH__"; if(p && p!=="__INGRESS_PATH__"){ var ws=(location.protocol==="https:"?"wss://":"ws://")+location.host+p+"/"; try{var k="clawdbot.control.settings.v1"; var s=localStorage.getItem(k); var o=s?JSON.parse(s):{}; o.url=ws; localStorage.setItem(k, JSON.stringify(o));}catch(e){} } }catch(e){} })();</script></head>';
      sub_filter '__INGRESS_PATH__' "$http_x_ingress_path";
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

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
    # ttyd base-path is configured as /terminal (no trailing slash).
    # Some clients will hit /terminal first, so redirect to /terminal/.
    location = /terminal {
      return 302 /terminal/;
    }

    # Proxy everything under /terminal/ (including websocket /terminal/ws)
    location ^~ /terminal/ {
      # IMPORTANT: no trailing slash in proxy_pass so nginx preserves the full URI
      proxy_pass http://127.0.0.1:7681;
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

    # Landing page (shown inside HA Ingress)
    # - Shows the web terminal (if enabled)
    # - Provides a button to open the Gateway Web UI in a separate tab (not embedded)
    location = / {
      default_type text/html;

      # NOTE: __GATEWAY_PUBLIC_URL__ is configured via add-on option gateway_public_url.
      # We keep it flexible because the right URL depends on how the user exposes HA/gateway
      # (Nabu Casa, DuckDNS, LAN, etc.).

      return 200 '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
      <title>OpenClaw Assistant</title>
      <style>
        body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Cantarell,Noto Sans,sans-serif;margin:0;padding:16px;background:#0b0f14;color:#e6edf3}
        a,button{font:inherit}
        .card{max-width:1100px;margin:0 auto;background:#111827;border:1px solid #1f2937;border-radius:12px;padding:16px}
        .row{display:flex;gap:12px;flex-wrap:wrap;align-items:center}
        .btn{background:#2563eb;color:white;border:0;border-radius:10px;padding:10px 14px;cursor:pointer;text-decoration:none;display:inline-block}
        .btn.secondary{background:#334155}
        .muted{color:#9ca3af;font-size:14px}
        .term{margin-top:14px;height:70vh;min-height:420px;border:1px solid #1f2937;border-radius:10px;overflow:hidden}
        iframe{width:100%;height:100%;border:0;background:black}
        code{background:#0b1220;padding:2px 6px;border-radius:6px}
      </style>
      </head><body>
        <div class="card">
          <h2 style="margin:0 0 8px 0">OpenClaw Assistant</h2>
          <div class="row" style="margin-bottom:6px">
            <a class="btn" href="__GATEWAY_PUBLIC_URL____GW_PUBLIC_URL_PATH__?token=__GATEWAY_TOKEN__" target="_blank" rel="noopener noreferrer">Open Gateway Web UI</a>
            <a class="btn secondary" href="./terminal/" target="_self">Open Terminal (full page)</a>
          </div>
          <div class="muted">
            Tip: The gateway UI is intentionally opened outside of Ingress to avoid websocket/proxy issues.
            Configure <code>gateway_public_url</code> in the add-on options.
          </div>
          <div class="term">
            <iframe src="./terminal/" title="Terminal"></iframe>
          </div>
        </div>
      </body></html>';
    }

    # (Optional) Gateway UI via ingress has been intentionally removed.
    # See landing page link that opens the gateway in a separate tab.

    # Everything else: 404
    location / {
      return 404;
    }
  }
}

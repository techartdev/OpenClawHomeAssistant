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
    # Served as a real HTML file to avoid fragile quoting inside nginx.conf.
    location = / {
      root /etc/nginx/html;
      default_type text/html;
      try_files /index.html =404;
    }

    # (Optional) Gateway UI via ingress has been intentionally removed.
    # See landing page link that opens the gateway in a separate tab.

    # Everything else: 404
    location / {
      return 404;
    }
  }
}

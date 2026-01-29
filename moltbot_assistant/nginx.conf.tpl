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
    # Ensure the browser URL includes token=... (Clawdbot UI expects it client-side).
    location / {
      if ($arg_token = "") {
        return 302 $scheme://$host$request_uri?token=__GATEWAY_TOKEN__;
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
  }
}

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

  # Inject gateway token server-side. Token is substituted into this template at runtime.
  map $args $args_with_token {
    ""      "token=__GATEWAY_TOKEN__";
    default "$args&token=__GATEWAY_TOKEN__";
  }

  server {
    listen 8099;

    # Web terminal (ttyd)
    location /terminal/ {
      proxy_pass http://127.0.0.1:7681/;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host $host;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Everything else -> Clawdbot gateway UI (websocket capable)
    location / {
      proxy_pass http://127.0.0.1:18789$uri?$args_with_token;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host $host;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
    }
  }
}

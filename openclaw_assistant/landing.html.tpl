<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
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
</head>
<body>
  <div class="card">
    <h2 style="margin:0 0 8px 0">OpenClaw Assistant</h2>

    <div class="row" style="margin-bottom:6px">
      <a class="btn" id="gwbtn" href="__GATEWAY_PUBLIC_URL____GW_PUBLIC_URL_PATH__?token=__GATEWAY_TOKEN__" target="_blank" rel="noopener noreferrer">Open Gateway Web UI</a>
      <a class="btn secondary" href="./terminal/" target="_self">Open Terminal (full page)</a>
    </div>

    <div class="muted">
      Tip: The gateway UI is intentionally opened outside of Ingress to avoid websocket/proxy issues.
      Set <code>gateway_public_url</code> in the add-on options.
    </div>

    <div class="muted" style="margin-top:8px">
      If the Gateway UI says <b>Unauthorized</b>, you need the token. In the terminal run:
      <code>openclaw config get gateway.auth.token</code>
    </div>

    <div class="term">
      <iframe src="./terminal/" title="Terminal"></iframe>
    </div>
  </div>
</body>
</html>

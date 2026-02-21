# Security Risks & Disclaimer

This document outlines the security risks associated with running the OpenClaw Assistant Home Assistant add-on and provides best practices for safe usage.

**By installing and using this add-on, you acknowledge and accept the risks described below.**

---

## Disclaimer

This add-on is provided **"AS IS"**, without warranty of any kind, under the [MIT License](LICENSE).

The authors and contributors of this add-on are **not responsible** for any damage, data loss, security breach, unauthorized access, financial loss, or any other harm that may occur as a result of installing, configuring, or using this add-on. This includes but is not limited to:

- Unintended actions performed by the AI agent
- Exposure of sensitive data (tokens, credentials, personal information)
- Unauthorized access to your Home Assistant instance or network
- Damage to smart home devices or connected systems
- Actions taken by third-party skills or integrations

**You use this add-on entirely at your own risk.**

---

## Understanding the Risks

### 1. Autonomous AI Agent

OpenClaw is an **agentic AI assistant** — it can plan, reason, and execute actions autonomously. Unlike a simple chatbot, it can:

- Execute shell commands on the add-on container
- Control smart home devices (if integrated with Assist pipeline or HA long-lived access token)
- Read and write files
- Make HTTP requests to external services
- Install and run third-party skills

**Risk**: If the agent is manipulated (e.g., via prompt injection from a malicious webpage or document), it could perform unintended actions within its permissions.

**Mitigation**: Review what entities you expose to the Assist pipeline. Only expose devices you're comfortable with the AI controlling.

### 2. Network Exposure

When `gateway_bind_mode` is set to `lan`, the gateway is accessible to **all devices on your local network**. When exposed to the internet (via port forwarding or reverse proxy), it becomes accessible to **anyone**.

When `gateway_bind_mode` is set to `tailnet`, the gateway is exposed only on your Tailscale network. This significantly reduces exposure compared with `lan`, but all authenticated tailnet peers can still reach it.

**Risks**:
- Unauthorized users could interact with your AI agent
- API tokens could be intercepted over plain HTTP
- The gateway endpoint could be discovered by network scanners

**Mitigations**:
- Use HTTPS whenever possible (reverse proxy with TLS)
- Never expose the gateway port directly to the internet without authentication and encryption
- Use `gateway_bind_mode: loopback` if you only need local access
- Prefer `gateway_bind_mode: tailnet` over `lan` when you need remote/private-network access
- Keep your gateway auth token secret

### 3. Plain HTTP Authentication (`allow_insecure_auth`)

Enabling `allow_insecure_auth` transmits authentication tokens over **unencrypted HTTP**. On a trusted home network this is generally acceptable, but:

**Risks**:
- Anyone on your network can intercept the token
- If your Wi-Fi is compromised, the token is exposed
- The token grants full access to the gateway

**Mitigations**:
- Only enable on trusted networks
- Never enable when the gateway is exposed to the internet
- Rotate your gateway token periodically: `openclaw config set gateway.auth.token <new-token>`

### 4. Home Assistant Token

The `homeassistant_token` option stores a **long-lived access token** that grants broad access to your Home Assistant instance. This is extremely powerful — it can control devices, read state, trigger automations, and more.

**Risks**:
- If the container is compromised, the attacker gains full HA access
- Skills or scripts running inside the add-on have access to this token
- The token does not expire unless manually revoked

**Mitigations**:
- Only provide this token if skills specifically require it
- Create a dedicated HA user with limited permissions for this token
- Revoke and regenerate the token if you suspect compromise
- Monitor your HA logs for unexpected API activity

### 5. Third-Party Skills & Supply Chain

OpenClaw supports installing skills from the community (ClawHub) and via npm. These are **third-party code** running inside the add-on container.

**Risks**:
- Malicious skills could exfiltrate data, install backdoors, or perform harmful actions
- Skills have access to the same permissions as the OpenClaw process
- Compromised npm packages could affect your installation
- [Security researchers have already found malicious skills](https://thehackernews.com/2026/02/researchers-find-341-malicious-clawhub.html) published to ClawHub

**Mitigations**:
- Only install skills from trusted sources
- Review skill code before installing when possible
- Monitor the add-on logs for unexpected activity
- Keep the add-on updated to get security patches

### 6. Router SSH Access

The `router_ssh_*` options allow the add-on to SSH into your router or network devices. This grants **direct access to your network infrastructure**.

**Risks**:
- A compromised add-on could reconfigure your router
- Firewall rules could be modified
- Network traffic could be intercepted or redirected

**Mitigations**:
- Use a dedicated SSH key with minimal permissions
- Restrict the SSH user's capabilities on the router (read-only if possible)
- Only enable if you have a specific use case that requires it, and only if you understand the risks very well

### 7. Browser Automation (Chromium)

The bundled Chromium runs with `noSandbox` (required in Docker). This reduces browser-level security isolation.

**Risks**:
- A malicious webpage could potentially escape the browser sandbox
- Automated browsing could expose session cookies or credentials
- Browser automation skills could visit unintended websites

**Mitigations**:
- Only use browser automation with trusted skills
- Do not use it to log into sensitive accounts
- The container itself provides some isolation from the host

### 8. Prompt Injection

AI agents that process external content (web pages, documents, emails) are vulnerable to **prompt injection** — hidden instructions that manipulate the agent's behavior.

**Risks**:
- A webpage or document could contain hidden instructions that cause the agent to perform unintended actions
- Data exfiltration through crafted prompts
- Actions performed on behalf of an attacker

**Mitigations**:
- Be cautious about what content you ask the agent to process
- Review agent actions in the logs
- Limit the entities and services exposed to the agent

---

## Best Practices Summary

| Practice | Priority |
|---|---|
| Use HTTPS for remote access | High |
| Keep `gateway_bind_mode: loopback` unless network access is needed | High |
| Prefer `gateway_bind_mode: tailnet` over `lan` for remote/private access | High |
| Only install skills from trusted sources | High |
| Review exposed entities in Assist pipeline | High |
| Keep the add-on updated | High |
| Use a dedicated HA user for the `homeassistant_token` | Medium |
| Monitor add-on logs regularly | Medium |
| Rotate gateway tokens periodically | Medium |
| Restrict router SSH user permissions | Medium |
| Back up your configuration regularly | Low |

---

## Reporting Security Issues

If you discover a security vulnerability in this add-on, please report it responsibly by opening a private security advisory on GitHub rather than a public issue.

---

*This document does not constitute legal advice. Consult a qualified professional for legal guidance specific to your situation.*

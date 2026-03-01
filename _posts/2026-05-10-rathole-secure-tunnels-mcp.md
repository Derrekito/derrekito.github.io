---
title: "Exposing Local Services Securely with Rathole: SSH, Ollama, and MCP Behind NAT"
date: 2026-05-10 10:00:00 -0700
categories: [Networking, Security]
tags: [rathole, tunneling, ssh, ollama, mcp, nginx, websocket, nat]
---

This post describes a method to securely expose local services (SSH, Ollama, MCP servers) through NAT using rathole reverse tunnels, nginx WebSocket proxying, and token-based authentication.

## Problem Statement

Services running on machines behind NAT often require remote access:

- **SSH** to home desktops or lab servers
- **Ollama** API for remote LLM inference
- **MCP servers** for Claude Code integrations
- **Development servers** requiring access from any location

Traditional solutions present various limitations:

| Approach | Limitation |
|----------|----------|
| Port forwarding | Requires router access, static IP, direct port exposure |
| ngrok/Cloudflare Tunnel | Third-party dependency, traffic inspection concerns |
| WireGuard VPN | Both ends require configuration, excessive for single services |
| SSH reverse tunnel | Fragile, requires keepalive configuration, one tunnel per service |

**Rathole** addresses these limitations: a fast, secure, Rust-based tunnel that multiplexes services over a single WebSocket connection with per-service authentication.

## Architecture

```text
┌──────────────────┐           ┌──────────────────┐          ┌──────────────────┐
│ Your Laptop      │           │ VPS (Public IP)  │          │ Home Machine     │
│                  │           │                  │          │ (Behind NAT)     │
│ ssh -p 2222      │──────────▶│ nginx :443       │          │                  │
│ localhost        │   TLS     │   │              │◀─────────│ rathole client   │
│                  │           │   ▼              │ WebSocket│                  │
│ curl localhost:  │           │ rathole :8443    │          │ ┌──────────────┐ │
│ 11434/api/...    │           │   │              │          │ │ sshd :22     │ │
│                  │           │   ├── :2222 ─────┼──────────│ │ ollama:11434 │ │
│                  │           │   └── :11434 ────┼──────────│ │ mcp :3000    │ │
└──────────────────┘           └──────────────────┘          └──────────────────┘
```

**Data flow:**
1. Client connects to `localhost:2222` (SSH) or `localhost:11434` (Ollama)
2. Traffic routes to VPS nginx over TLS
3. nginx proxies WebSocket to rathole server
4. rathole forwards to the appropriate client tunnel
5. Home machine receives traffic on local service

## Components

### 1. VPS Server

A small VPS (1 vCPU, 512MB RAM sufficient) running:

- **nginx**: TLS termination, WebSocket proxying, decoy responses
- **rathole server**: Accepts client connections, multiplexes services
- **certbot**: Let's Encrypt certificates

### 2. Home Machine (Client)

- **rathole client**: Maintains persistent connection to server
- **Local services**: SSH, Ollama, MCP servers, etc.

## Server Setup

### Install Dependencies

```bash
# Arch Linux
pacman -S nginx certbot certbot-nginx

# Download rathole
curl -LO https://github.com/rapiz1/rathole/releases/download/v0.5.0/rathole-x86_64-unknown-linux-gnu.zip
unzip rathole-*.zip
mv rathole /usr/local/bin/
chmod +x /usr/local/bin/rathole
```

### Rathole Server Configuration

Create `/etc/rathole/server.toml`:

```toml
[server]
bind_addr = "127.0.0.1:8443"

[server.transport]
type = "websocket"

[server.transport.websocket]
tls = false  # TLS handled by nginx

# SSH tunnel
[server.services.ssh]
token = "generate-a-strong-random-token-here"
bind_addr = "127.0.0.1:2222"

# Ollama API tunnel
[server.services.ollama]
token = "another-strong-random-token"
bind_addr = "127.0.0.1:11434"

# MCP server tunnel
[server.services.mcp]
token = "yet-another-strong-token"
bind_addr = "127.0.0.1:3000"
```

Generate secure tokens:

```bash
# Generate random tokens
openssl rand -hex 32  # For each service
```

### Nginx Configuration

Create `/etc/nginx/nginx.conf`:

```nginx
worker_processes auto;
error_log /var/log/nginx/error.log warn;

events {
    worker_connections 1024;
}

http {
    # Detect WebSocket upgrades
    map $http_upgrade $connection_upgrade {
        default upgrade;
        '' close;
    }

    map $http_upgrade $is_websocket {
        default 0;
        ~*^websocket$ 1;
    }

    upstream rathole {
        server 127.0.0.1:8443;
    }

    # HTTP -> HTTPS redirect
    server {
        listen 80;
        server_name your-domain.com;
        return 301 https://$host$request_uri;
    }

    # Main HTTPS server
    server {
        listen 443 ssl;
        server_name your-domain.com;

        # TLS (certbot will fill these in)
        ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;

        # Security headers
        add_header Strict-Transport-Security "max-age=31536000" always;
        server_tokens off;

        # Root: serve decoy for non-WebSocket, proxy WebSocket to rathole
        location = / {
            # Non-WebSocket requests get a decoy response
            if ($is_websocket = 0) {
                add_header Content-Type application/json;
                return 200 '{"status":"ok","version":"1.0.0"}';
            }

            # WebSocket requests go to rathole
            proxy_pass http://rathole;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_set_header Host $host;
            proxy_read_timeout 86400;
            proxy_send_timeout 86400;
        }

        # Health check
        location /health {
            return 200 '{"status":"healthy"}';
            add_header Content-Type application/json;
        }
    }
}
```

### Systemd Service for Server

Create `/etc/systemd/system/rathole-server.service`:

```ini
[Unit]
Description=Rathole Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/rathole /etc/rathole/server.toml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Obtain TLS Certificate

```bash
certbot --nginx -d your-domain.com
```

### Start Services

```bash
systemctl enable --now rathole-server nginx
```

## Client Setup

### Rathole Client Configuration

Create `/etc/rathole/client.toml` on the home machine:

```toml
[client]
remote_addr = "wss://your-domain.com/"

[client.transport]
type = "websocket"

# SSH - expose local SSH
[client.services.ssh]
token = "same-token-as-server-ssh"
local_addr = "127.0.0.1:22"

# Ollama - expose local Ollama API
[client.services.ollama]
token = "same-token-as-server-ollama"
local_addr = "127.0.0.1:11434"

# MCP - expose local MCP server
[client.services.mcp]
token = "same-token-as-server-mcp"
local_addr = "127.0.0.1:3000"
```

### Systemd Service for Client

Create `/etc/systemd/system/rathole-client.service`:

```ini
[Unit]
Description=Rathole Client
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/rathole /etc/rathole/client.toml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Start the service:

```bash
systemctl enable --now rathole-client
```

## Accessing Services

Once connected, home services are accessible through the VPS:

### SSH

```bash
# From anywhere
ssh -p 2222 your-user@your-domain.com

# Or via localhost if another tunnel/VPN to the VPS exists
ssh -p 2222 your-user@localhost
```

### Ollama API

```bash
# Direct API call
curl https://your-domain.com:11434/api/tags

# Or configure MCP/Claude Code to use the tunnel
# In MCP config, point to localhost:11434 (if port-forwarded)
```

### SSH Port Forwarding for Local Access

To access services on `localhost`:

```bash
# Create local forwards through the VPS
ssh -L 11434:localhost:11434 -L 3000:localhost:3000 user@your-domain.com

# Now localhost:11434 reaches home Ollama
curl localhost:11434/api/tags
```

## Security Hardening

### Token Rotation

Rotate tokens periodically without downtime:

**Server-side rotation script** (`/usr/local/bin/rotate-rathole-tokens.sh`):

```bash
#!/bin/bash
set -euo pipefail

CONFIG="/etc/rathole/server.toml"
PENDING="/etc/rathole/pending-tokens.json"

# Generate new tokens
new_ssh=$(openssl rand -hex 32)
new_ollama=$(openssl rand -hex 32)

# Save pending tokens for clients to fetch
cat > "$PENDING" << EOF
{
  "ssh": "$new_ssh",
  "ollama": "$new_ollama",
  "valid_until": "$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

chmod 600 "$PENDING"

echo "New tokens staged in $PENDING"
echo "Clients should sync within 5 minutes."
echo "Run 'finalize-rathole-rotation.sh' after clients update."
```

**Client-side sync** (runs via systemd timer):

```bash
#!/bin/bash
# Fetch new tokens from server API and update local config

SERVER_URL="https://your-domain.com/api/v1/config"
API_KEY=$(cat /etc/rathole/rotation.key)
CLIENT_CONF="/etc/rathole/client.toml"

# Fetch pending tokens
response=$(curl -s -H "X-Api-Key: $API_KEY" "$SERVER_URL")

if [[ -z "$response" ]]; then
    exit 0  # No pending rotation
fi

# Parse and update tokens in config
new_ssh=$(echo "$response" | jq -r '.ssh // empty')
if [[ -n "$new_ssh" ]]; then
    sed -i "s/^token = .*/token = \"$new_ssh\"/" "$CLIENT_CONF"
    systemctl restart rathole-client
fi
```

### Fail2ban Integration

Block brute-force attempts on tunneled SSH:

```ini
# /etc/fail2ban/jail.d/rathole-ssh.conf
[rathole-ssh]
enabled = true
port = 2222
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
```

### Geo-blocking

Restrict connections to specific countries:

```bash
# Using ipset + iptables
ipset create allowed_countries hash:net

# Add country IP ranges
curl -s https://www.ipdeny.com/ipblocks/data/countries/us.zone | \
    while read cidr; do ipset add allowed_countries $cidr; done

# Block non-matching IPs
iptables -A INPUT -p tcp --dport 443 -m set ! --match-set allowed_countries src -j DROP
```

## MCP Integration

### Claude Code with Remote Ollama

Configure Claude Code to use the tunneled Ollama:

```json
{
  "mcpServers": {
    "ollama": {
      "command": "npx",
      "args": ["-y", "@anthropic/mcp-ollama"],
      "env": {
        "OLLAMA_HOST": "http://localhost:11434"
      }
    }
  }
}
```

Then SSH with port forwarding:

```bash
ssh -L 11434:localhost:11434 user@your-domain.com
```

This configuration enables Claude Code to use home GPU resources for Ollama inference.

### Remote MCP Servers

Run MCP servers on the home machine and access them through the tunnel:

```bash
# Home machine: Start MCP server
npx @anthropic/mcp-filesystem --root /path/to/files --port 3000

# Laptop: Forward the port
ssh -L 3000:localhost:3000 user@your-domain.com
```

## Monitoring

### Status Script

Check active tunnel connections:

```bash
#!/bin/bash
echo "=== Rathole Tunnel Status ==="

for svc in "ssh:2222" "ollama:11434" "mcp:3000"; do
    name=${svc%%:*}
    port=${svc##*:}

    count=$(ss -tn sport = :$port 2>/dev/null | grep -c ESTAB || echo 0)

    if [[ $count -gt 0 ]]; then
        echo "  $name (:$port): $count active connections"
    else
        echo "  $name (:$port): idle"
    fi
done
```

### Systemd Journal

```bash
# Server logs
journalctl -u rathole-server -f

# Client logs
journalctl -u rathole-client -f
```

## Comparison with Alternatives

| Feature | Rathole | ngrok | Cloudflare Tunnel | SSH -R |
|---------|---------|-------|-------------------|--------|
| Self-hosted | Yes | No | No | Yes |
| Multiple services | Yes | Limited free | Yes | Manual |
| WebSocket transport | Yes | Yes | Yes | No |
| Per-service auth | Yes | No | Yes | No |
| Resource usage | Minimal | N/A | N/A | Minimal |
| TLS termination | Flexible | Forced | Forced | N/A |
| Open source | Yes | No | No | Yes |

## Troubleshooting

### Client Connection Failure

```bash
# Check client logs
journalctl -u rathole-client -n 50

# Verify WebSocket connectivity
curl -v -H "Upgrade: websocket" -H "Connection: upgrade" \
    https://your-domain.com/
```

### Inaccessible Services

```bash
# Check server is listening
ss -tlnp | grep rathole

# Verify service binding
ss -tlnp | grep 2222  # Should show rathole
```

### Token Mismatch

```bash
# Server and client tokens MUST match exactly
# Check for trailing whitespace or newlines
cat /etc/rathole/server.toml | grep token
cat /etc/rathole/client.toml | grep token
```

## Conclusion

Rathole provides a robust, self-hosted solution for exposing services behind NAT:

- **Single connection**: All services multiplex over one WebSocket
- **Per-service tokens**: Granular authentication
- **TLS via nginx**: Industry-standard security
- **Low overhead**: Written in Rust, minimal resource usage
- **Decoy responses**: Non-WebSocket requests receive innocuous JSON

This setup is suitable for:
- Remote access to home lab services
- Running MCP servers on powerful home hardware
- Accessing Ollama from any location
- SSH access without exposing port 22 directly to the internet

The key design principle: nginx handles TLS and presents a normal-looking API endpoint externally, while WebSocket connections pass through to rathole. Scanners observe a JSON API; legitimate clients access a tunnel.

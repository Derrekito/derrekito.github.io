---
title: "Building a Unified Local Development Environment"
date: 2026-07-26 10:00:00 -0700
categories: [Development, Infrastructure]
tags: [development, caddy, dns, docker, automation]
---

A complete local development environment integrating a service dashboard, reverse proxy, local DNS, and port allocation scheme. All services become accessible from any network device via friendly URLs.

## Motivation

Local development environments tend toward entropy. Services accumulate across arbitrary ports—a blog preview on 4000, an API on 5000, Docker Compose stacks spanning 8000-8999. Port assignments become difficult to track. Mobile testing requires remembering workstation IP addresses. Mixed HTTP/HTTPS requirements trigger browser security warnings.

These friction points impose cognitive overhead. Context switching between port numbers and IP addresses interrupts development flow. Demonstrating work-in-progress to colleagues requires explanation of access methods. Testing across devices—mobile, tablet, secondary machines—becomes unnecessarily complex.

## Benefits

| Baseline | With Unified Environment |
|----------|--------------------------|
| `192.168.1.51:4000` | `blog.lan` |
| Undocumented port assignments | Centralized dashboard |
| Mobile devices cannot reach dev servers | Network-wide accessibility |
| Mixed HTTP/HTTPS protocols | Consistent HTTPS |
| Manual service startup | Dashboard-driven control |
| Ad-hoc port selection | Documented allocation scheme |

## Limitations

**Initial configuration overhead.** The system requires Caddy installation, DNS entry management, and dashboard deployment.

**Infrastructure prerequisites.** Operating a reverse proxy and managing DNS records assumes familiarity with these technologies.

**pfSense dependency.** The DNS configuration targets pfSense with Unbound. Alternative routers require different approaches; `/etc/hosts` serves as a fallback.

**Complexity proportional to scale.** Single-service workflows gain little from this infrastructure.

## Architecture Overview

```text
┌─────────────────────────────────────────────────────────────────┐
│                     Local Network (192.168.1.0/24)              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐         ┌──────────────────────────────────┐ │
│  │   pfSense    │         │       Workstation (darknova)     │ │
│  │              │  DNS    │          192.168.1.51            │ │
│  │  Unbound DNS ├────────►│                                  │ │
│  │              │         │  ┌────────────────────────────┐  │ │
│  │ *.lan → .51  │         │  │         Caddy :80/:443     │  │ │
│  └──────────────┘         │  │      Reverse Proxy         │  │ │
│                           │  └─────────────┬──────────────┘  │ │
│  ┌──────────────┐         │                │                 │ │
│  │   Laptop     │  HTTPS  │  ┌─────────────┼──────────────┐  │ │
│  │              ├─────────┼─►│             ▼              │  │ │
│  │ dashboard.lan│         │  │  ┌───────────────────────┐ │  │ │
│  └──────────────┘         │  │  │ Dashboard :9000       │ │  │ │
│                           │  │  │ Jekyll    :4000       │ │  │ │
│  ┌──────────────┐         │  │  │ Vite      :5173       │ │  │ │
│  │   Phone      │         │  │  │ Docker    :8000-8999  │ │  │ │
│  │              │         │  │  └───────────────────────┘ │  │ │
│  │  blog.lan    │         │  │       Local Services       │  │ │
│  └──────────────┘         │  └────────────────────────────┘  │ │
│                           └──────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Port Allocation Scheme

Stop the chaos of random port numbers. Adopt a scheme:

| Range | Purpose | Examples |
|-------|---------|----------|
| 3000-3099 | Frontend dev servers | React, Vue, Svelte |
| 4000-4099 | Static site generators | Jekyll, Hugo, Zola |
| 5000-5199 | Backend APIs, Vite | FastAPI, Express |
| 5678 | n8n (workflow automation) | - |
| 6379 | Redis | - |
| 7474, 7687 | Neo4j | Browser, Bolt |
| 8000-8099 | Standalone projects | Docs, tools |
| 8100-8999 | Large project (Docker) | Microservices |
| 9000 | Services dashboard | - |
| 11434-11435 | Ollama (local/tunneled) | - |
| 27017 | MongoDB | - |

This mapping should be documented in a team wiki or a `LOCAL_SERVICES.md` file in the home directory.

## Component 1: Services Dashboard

A Python web app that shows all running services with start/stop controls.

**Files:**
```text
~/projects/local-dashboard/
├── server.py       # Dashboard server
└── services.json   # Service definitions
```

**Key features:**
- Detects running services by port or process pattern
- Start services with nohup (survives terminal close)
- Stop by sending SIGTERM
- Docker Compose integration
- Auto-refresh every 10 seconds

See [Part 1: Local Dev Dashboard](/posts/local-dev-dashboard-python/) for the full implementation.

## Component 2: Caddy Reverse Proxy

Routes friendly domains to local ports with automatic HTTPS.

**Config:** `/etc/caddy/conf.d/local-dev.caddyfile`

```text
# Local-only (.localhost - automatic HTTPS)
dashboard.localhost {
    reverse_proxy localhost:9000
}

blog.localhost {
    reverse_proxy localhost:4000
}

# Network-wide (.lan - internal TLS)
dashboard.lan {
    tls internal
    reverse_proxy localhost:9000
}

blog.lan {
    tls internal
    reverse_proxy localhost:4000
}
```

**Why both?**
- `.localhost` works immediately, no DNS needed
- `.lan` accessible from other devices on the local network

See [Part 2: Caddy and Local DNS](/posts/caddy-local-dns-dev-environment/) for setup details.

## Component 3: Local DNS

pfSense Unbound resolves `*.lan` to the development workstation.

**Config:** `/var/unbound/local_services.conf` (on pfSense)

```text
server:
local-zone: "lan." static
local-data: "dashboard.lan. A 192.168.1.51"
local-data: "blog.lan. A 192.168.1.51"
local-data: "app.lan. A 192.168.1.51"
```

All devices on the local network automatically use pfSense for DNS, eliminating per-device configuration.

## Component 4: Firewall Rules

Allow HTTP/HTTPS from the LAN:

```bash
# UFW
sudo ufw allow from 192.168.1.0/24 to any port 80 proto tcp
sudo ufw allow from 192.168.1.0/24 to any port 443 proto tcp
```

## Adding a New Project: Complete Workflow

Let's add a new project called "my-api" running on port 5000.

### Step 1: Add to Dashboard Config

Edit `~/projects/local-dashboard/services.json`:

```json
{
  "name": "My API",
  "domain": "api.lan",
  "port": 5000,
  "directory": "/home/user/projects/my-api",
  "start_cmd": "python3 -m uvicorn main:app --host 0.0.0.0 --port 5000",
  "process_match": "uvicorn.*5000"
}
```

### Step 2: Add DNS Entry

```bash
ssh root@192.168.1.1 'echo "local-data: \"api.lan. A 192.168.1.51\"" >> /var/unbound/local_services.conf'
ssh root@192.168.1.1 "pfSsh.php playback svc restart unbound"
```

### Step 3: Add Caddy Config

Edit `/etc/caddy/conf.d/local-dev.caddyfile`:

```text
api.localhost {
    reverse_proxy localhost:5000
}

api.lan {
    tls internal
    reverse_proxy localhost:5000
}
```

Reload:
```bash
sudo systemctl reload caddy
```

### Step 4: Verify

```bash
# DNS
dig +short api.lan

# Local access
curl -sk https://api.localhost/

# Network access (from another device)
curl -sk https://api.lan/
```

## Quick Reference Card

Create `~/LOCAL_SERVICES.md`:

```markdown
# Local Development Services

## Dashboard
- Local: https://dashboard.localhost
- Network: https://dashboard.lan

## Services
| Name | Local | Network | Port |
|------|-------|---------|------|
| Blog | blog.localhost | blog.lan | 4000 |
| Frontend | app.localhost | app.lan | 5173 |
| API | api.localhost | api.lan | 5000 |

## Management Commands

# Start dashboard
cd ~/projects/local-dashboard && python3 server.py

# Add DNS entry
ssh root@192.168.1.1 'echo "local-data: \"new.lan. A 192.168.1.51\"" >> /var/unbound/local_services.conf && pfSsh.php playback svc restart unbound'

# Reload Caddy
sudo systemctl reload caddy

# Check what's on a port
ss -tlnp | grep :5000
```

## Automation Script

Create a helper script for adding new services:

```bash
#!/bin/bash
# add-service.sh - Add a new service to the dev environment

NAME="$1"
PORT="$2"
IP="${3:-192.168.1.51}"

if [[ -z "$NAME" || -z "$PORT" ]]; then
    echo "Usage: $0 <name> <port> [ip]"
    echo "Example: $0 myapp 3000"
    exit 1
fi

DOMAIN="${NAME}.lan"

echo "Adding service: $NAME on port $PORT"

# Add DNS
echo "Adding DNS entry..."
ssh root@192.168.1.1 "echo 'local-data: \"${DOMAIN}. A ${IP}\"' >> /var/unbound/local_services.conf && pfSsh.php playback svc restart unbound"

# Add Caddy config
echo "Adding Caddy config..."
sudo tee -a /etc/caddy/conf.d/local-dev.caddyfile > /dev/null << EOF

${NAME}.localhost {
    reverse_proxy localhost:${PORT}
}

${DOMAIN} {
    tls internal
    reverse_proxy localhost:${PORT}
}
EOF

# Reload Caddy
echo "Reloading Caddy..."
sudo systemctl reload caddy

# Verify
echo ""
echo "Verifying..."
dig +short "$DOMAIN"
echo ""
echo "Done! Access at:"
echo "  Local:   https://${NAME}.localhost"
echo "  Network: https://${DOMAIN}"
```

Usage:
```bash
chmod +x add-service.sh
./add-service.sh myapp 3000
```

## Troubleshooting Checklist

### Service not accessible locally
1. Is the service running? `ss -tlnp | grep :PORT`
2. Is Caddy running? `systemctl status caddy`
3. Is the Caddy config valid? `sudo caddy validate`

### Service not accessible from network
1. Does DNS resolve? `dig +short name.lan @192.168.1.1`
2. Is the firewall open? `sudo ufw status`
3. Is Caddy listening on all interfaces? `ss -tlnp | grep caddy`

### Certificate warnings
Expected for `.lan` domains. Either:
- Accept the warning
- Install Caddy's root CA on client devices

## Benefits

This setup provides:

1. **Single source of truth** - Dashboard shows everything
2. **Memorable URLs** - `blog.lan` instead of `192.168.1.51:4000`
3. **Network access** - Preview from phone, tablet, other machines
4. **HTTPS everywhere** - Even for local development
5. **Easy onboarding** - New project? Three commands.
6. **Organized ports** - No more "what's on 8080?"

## What's Next?

Consider adding:
- **Systemd service** for the dashboard (auto-start on boot)
- **Traefik labels** for Docker services (auto-discovery)
- **mkcert** for trusted local certificates
- **Tailscale** for access outside the home network

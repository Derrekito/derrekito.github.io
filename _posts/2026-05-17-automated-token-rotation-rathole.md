---
title: "Automated Token Rotation for Rathole Tunnels"
date: 2026-05-17 10:00:00 -0700
categories: [Security, Automation]
tags: [rathole, token-rotation, systemd, nginx, bash, security]
---

This post presents a zero-downtime token rotation system for rathole tunnels: the server generates new tokens, clients pull them automatically, and the server finalizes after a grace period. No manual configuration editing on remote machines is required.

## Problem Statement

The [previous post](/posts/rathole-secure-tunnels-mcp/) described rathole tunnel setup with per-service authentication tokens. However, tokens should rotate periodically for several reasons:

- **Credential hygiene**: Limit exposure window if a token leaks
- **Compliance**: Some environments require regular rotation
- **Access revocation**: Remove a client by excluding it from the next rotation

Manual rotation is labor-intensive:
1. Generate new tokens on the server
2. SSH into each client machine
3. Edit configs, paste new tokens
4. Restart services
5. Verify no typographical errors occurred

With multiple clients behind NAT (the primary rathole use case), this becomes a significant maintenance burden.

## Proposed Solution: Pull-Based Rotation

```text
┌──────────────────────────────────────────────────────────────────────┐
│                         Rotation Timeline                            │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  T+0         T+5min        T+10min       T+15min                    │
│   │            │             │             │                         │
│   ▼            ▼             ▼             ▼                         │
│  ┌────┐     ┌────┐        ┌────┐       ┌────────┐                   │
│  │Init│     │Sync│        │Sync│       │Finalize│                   │
│  └────┘     └────┘        └────┘       └────────┘                   │
│                                                                      │
│  Server:    Client A:     Client B:    Server:                      │
│  Generate   Pulls new     Pulls new    Apply new tokens             │
│  new tokens tokens        tokens       Restart rathole              │
│  Stage in   Updates       Updates      Clients reconnect            │
│  pending    local config  local config with new tokens              │
│  file                                                                │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

**Key design principle**: Clients poll the server for pending rotations. The server does not push anything—it serves a file. After a grace period, the server applies the new tokens and restarts. Clients reconnect automatically with their already-updated tokens.

## Architecture

### Components

| Location | Component | Purpose |
|----------|-----------|---------|
| Server | `rotate-rathole-tokens.sh` | Generate tokens, stage for clients |
| Server | `finalize-rathole-rotation.sh` | Apply tokens to config, restart |
| Server | nginx `/api/v1/config` | Serve pending tokens to clients |
| Server | `rotation.key` | Pre-shared key for API auth |
| Client | `rathole-token-sync.sh` | Poll server, update local config |
| Client | `rathole-token-sync.timer` | Run sync every 5 minutes |

### Security Model

- **Pre-shared key**: Clients authenticate to the API with a rotation key
- **HTTPS only**: Tokens never traverse the network in plaintext
- **Root-only access**: Scripts and keys are mode 600/700
- **Validation**: Tokens verified as 64-char hex before applying
- **Backups**: Server configs backed up before each rotation

## Server Setup

### 1. Rotation Initiation Script

`/usr/local/bin/rotate-rathole-tokens.sh`:

```bash
#!/bin/bash
# Initiate rathole token rotation
# Generates new tokens, serves them for clients to pull,
# then finalizes after a grace period
set -euo pipefail

RATHOLE_CONF="/etc/rathole/server.toml"
PENDING_FILE="/etc/rathole/pending-tokens.json"
BACKUP_DIR="/etc/rathole/backups"
GRACE_MINUTES="${1:-15}"

if [[ $EUID -ne 0 ]]; then
    echo "Error: Must run as root"
    exit 1
fi

# Validate grace period
if [[ ! "$GRACE_MINUTES" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: Grace period must be a positive integer"
    exit 1
fi

# Check if rotation already pending
if [[ -f "$PENDING_FILE" ]]; then
    echo "ERROR: A rotation is already pending!"
    echo "Run 'sudo finalize-rathole-rotation.sh' to apply it"
    echo "or 'sudo rm $PENDING_FILE' to cancel."
    exit 1
fi

# Backup current config
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
cp "$RATHOLE_CONF" "$BACKUP_DIR/server.toml.$(date +%Y%m%d_%H%M%S)"

# Prune old backups
find "$BACKUP_DIR" -name 'server.toml.*' -mtime +30 -delete 2>/dev/null || true

# Generate new tokens (one per service)
SSH_TOKEN=$(openssl rand -hex 32)
OLLAMA_TOKEN=$(openssl rand -hex 32)
MCP_TOKEN=$(openssl rand -hex 32)

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
FINALIZE_AT=$(date -u -d "+${GRACE_MINUTES} minutes" +%Y-%m-%dT%H:%M:%SZ)

# Write pending tokens (clients will pull this)
cat > "$PENDING_FILE" << EOF
{
  "generated": "$TIMESTAMP",
  "finalize_at": "$FINALIZE_AT",
  "tokens": {
    "ssh": "$SSH_TOKEN",
    "ollama": "$OLLAMA_TOKEN",
    "mcp": "$MCP_TOKEN"
  }
}
EOF
chmod 600 "$PENDING_FILE"

# Schedule finalization
systemd-run --on-active="${GRACE_MINUTES}m" \
    --unit=rathole-finalize \
    --description="Finalize rathole token rotation" \
    /usr/local/bin/finalize-rathole-rotation.sh

echo ""
echo "=== Rathole Token Rotation Initiated ==="
echo ""
echo "New tokens staged. Clients will sync within 5 minutes."
echo "Finalization scheduled: $FINALIZE_AT UTC"
echo ""
echo "To cancel: sudo rm $PENDING_FILE && sudo systemctl stop rathole-finalize.timer"
echo "To finalize now: sudo finalize-rathole-rotation.sh"
```

### 2. Finalization Script

`/usr/local/bin/finalize-rathole-rotation.sh`:

```bash
#!/bin/bash
# Apply pending tokens to server config and restart
set -euo pipefail

RATHOLE_CONF="/etc/rathole/server.toml"
PENDING_FILE="/etc/rathole/pending-tokens.json"

if [[ $EUID -ne 0 ]]; then
    echo "Error: Must run as root"
    exit 1
fi

if [[ ! -f "$PENDING_FILE" ]]; then
    echo "No pending rotation."
    exit 0
fi

# Security checks
file_owner=$(stat -c '%u' "$PENDING_FILE")
file_perms=$(stat -c '%a' "$PENDING_FILE")

if [[ "$file_owner" != "0" ]]; then
    echo "ERROR: $PENDING_FILE not owned by root"
    exit 1
fi

if [[ "$file_perms" != "600" ]]; then
    echo "ERROR: Unsafe permissions on $PENDING_FILE"
    exit 1
fi

# Parse tokens
SSH_TOKEN=$(grep -o '"ssh": "[^"]*"' "$PENDING_FILE" | cut -d'"' -f4)
OLLAMA_TOKEN=$(grep -o '"ollama": "[^"]*"' "$PENDING_FILE" | cut -d'"' -f4)
MCP_TOKEN=$(grep -o '"mcp": "[^"]*"' "$PENDING_FILE" | cut -d'"' -f4)

# Validate tokens are 64-char hex
hex_re='^[0-9a-f]{64}$'
for name in SSH_TOKEN OLLAMA_TOKEN MCP_TOKEN; do
    val="${!name}"
    if [[ ! "$val" =~ $hex_re ]]; then
        echo "ERROR: $name is not valid 64-char hex"
        exit 1
    fi
done

# Backup and update config
BACKUP="${RATHOLE_CONF}.pre-rotation"
cp "$RATHOLE_CONF" "$BACKUP"

# Use awk for safe replacement (handles special chars)
awk -v ssh="$SSH_TOKEN" -v ollama="$OLLAMA_TOKEN" -v mcp="$MCP_TOKEN" '
    /^\[server\.services\.ssh\]$/    { section="ssh" }
    /^\[server\.services\.ollama\]$/ { section="ollama" }
    /^\[server\.services\.mcp\]$/    { section="mcp" }
    /^token = / {
        if (section == "ssh")     { print "token = \"" ssh "\""; next }
        if (section == "ollama")  { print "token = \"" ollama "\""; next }
        if (section == "mcp")     { print "token = \"" mcp "\""; next }
    }
    { print }
' "$BACKUP" > "$RATHOLE_CONF"

# Verify replacement
if ! grep -q "$SSH_TOKEN" "$RATHOLE_CONF"; then
    echo "ERROR: Replacement failed, restoring backup"
    cp "$BACKUP" "$RATHOLE_CONF"
    exit 1
fi

# Restart server
systemctl restart rathole-server

# Cleanup
rm -f "$PENDING_FILE" "$BACKUP"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) - Token rotation finalized" | \
    tee -a /var/log/rathole-rotation.log
```

### 3. Nginx API Endpoint

Add to the nginx config (inside the `server` block):

```nginx
# Token rotation API - clients pull pending tokens
location = /api/v1/config {
    default_type application/json;

    # Authenticate with pre-shared key
    if ($http_x_api_key != "YOUR_ROTATION_KEY_HERE") {
        return 403 '{"error":"forbidden"}';
    }

    # No pending rotation
    if (!-f /etc/rathole/pending-tokens.json) {
        return 200 '{"status":"no_pending_rotation"}';
    }

    # Serve pending tokens
    alias /etc/rathole/pending-tokens.json;
}
```

Generate the rotation key:

```bash
openssl rand -hex 32 > /etc/rathole/rotation.key
chmod 600 /etc/rathole/rotation.key

# Put the same value in nginx config
cat /etc/rathole/rotation.key
```

## Client Setup

### 1. Token Sync Script

`/usr/local/bin/rathole-token-sync.sh`:

```bash
#!/bin/bash
# Poll server for token rotation and apply new tokens
set -euo pipefail

# --- CONFIGURE PER CLIENT ---
SERVER_URL="https://your-domain.com/api/v1/config"
ROTATION_KEY_FILE="/etc/rathole/rotation.key"
CLIENT_CONF="/etc/rathole/client.toml"
SERVICE_NAMES="ssh ollama"  # Services this client exposes
# ----------------------------

LOG="/var/log/rathole-token-sync.log"
log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $1" >> "$LOG"; }

if [[ $EUID -ne 0 ]]; then
    exit 1
fi

if [[ ! -f "$ROTATION_KEY_FILE" ]]; then
    log "ERROR: Rotation key not found"
    exit 1
fi

ROTATION_KEY=$(cat "$ROTATION_KEY_FILE")

# Check for pending rotation
PENDING_FILE=$(mktemp)
trap 'rm -f "$PENDING_FILE"' EXIT

HTTP_CODE=$(curl -s -o "$PENDING_FILE" -w "%{http_code}" \
    -H "X-Api-Key: $ROTATION_KEY" \
    "$SERVER_URL" 2>/dev/null || echo "000")

# Handle responses
case "$HTTP_CODE" in
    000) log "WARN: Could not reach server"; exit 0 ;;
    403|404) exit 0 ;;  # No access or no endpoint
    200) ;;  # Continue processing
    *) log "WARN: HTTP $HTTP_CODE"; exit 0 ;;
esac

# Check if it's a "no rotation" response
if grep -q "no_pending_rotation" "$PENDING_FILE"; then
    exit 0
fi

# Function to replace token in specific service section
replace_token() {
    local svc="$1" token="$2" conf="$3"
    awk -v svc="$svc" -v token="$token" '
        /^\[client\.services\./ {
            match($0, /\[client\.services\.([^\]]+)\]/, m)
            section = m[1]
        }
        /^\[/ && !/^\[client\.services\./ { section = "" }
        /^token = / && section == svc {
            print "token = \"" token "\""
            next
        }
        { print }
    ' "$conf"
}

# Process each service
UPDATED=""
cp "$CLIENT_CONF" "$CLIENT_CONF.bak"
WORKING="$CLIENT_CONF.bak"

for svc in $SERVICE_NAMES; do
    new_token=$(grep -o "\"$svc\": \"[^\"]*\"" "$PENDING_FILE" | cut -d'"' -f4)
    [[ -z "$new_token" ]] && continue

    # Get current token
    current=$(awk -v svc="$svc" '
        /^\[client\.services\./ { match($0, /\[client\.services\.([^\]]+)\]/, m); section = m[1] }
        /^\[/ && !/^\[client\.services\./ { section = "" }
        /^token = / && section == svc { gsub(/^token = "|"$/, ""); print; exit }
    ' "$WORKING")

    [[ "$new_token" == "$current" ]] && continue

    # Apply new token
    replace_token "$svc" "$new_token" "$WORKING" > "$CLIENT_CONF.tmp"
    mv "$CLIENT_CONF.tmp" "$WORKING"
    UPDATED="$UPDATED $svc"
done

if [[ -z "$UPDATED" ]]; then
    mv "$CLIENT_CONF.bak" "$CLIENT_CONF"
    exit 0
fi

mv "$WORKING" "$CLIENT_CONF"
log "Tokens updated:$UPDATED"
```

### 2. Systemd Timer

`/etc/systemd/system/rathole-token-sync.timer`:

```ini
[Unit]
Description=Check for rathole token rotation

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
```

`/etc/systemd/system/rathole-token-sync.service`:

```ini
[Unit]
Description=Rathole token sync

[Service]
Type=oneshot
ExecStart=/usr/local/bin/rathole-token-sync.sh
```

Enable:

```bash
systemctl daemon-reload
systemctl enable --now rathole-token-sync.timer
```

### 3. Client Installer

Package everything for deployment to new clients:

```bash
#!/bin/bash
# install.sh - Run on each client machine
set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "Run with sudo"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Find client config
CLIENT_CONF=$(find /etc -name '*.toml' -exec grep -l '\[client\]' {} \; 2>/dev/null | head -1)
[[ -z "$CLIENT_CONF" ]] && read -rp "Path to client.toml: " CLIENT_CONF

# Detect services
SERVICES=$(grep '^\[client\.services\.' "$CLIENT_CONF" | \
    sed 's/\[client\.services\.\(.*\)\]/\1/' | tr '\n' ' ')
echo "Detected services: $SERVICES"

# Install
mkdir -p /etc/rathole
cp "$SCRIPT_DIR/rotation.key" /etc/rathole/
chmod 600 /etc/rathole/rotation.key

cp "$SCRIPT_DIR/rathole-token-sync.sh" /usr/local/bin/
chmod 700 /usr/local/bin/rathole-token-sync.sh

# Configure script
sed -i "s|^CLIENT_CONF=.*|CLIENT_CONF=\"$CLIENT_CONF\"|" \
    /usr/local/bin/rathole-token-sync.sh
sed -i "s|^SERVICE_NAMES=.*|SERVICE_NAMES=\"$SERVICES\"|" \
    /usr/local/bin/rathole-token-sync.sh

cp "$SCRIPT_DIR"/*.service "$SCRIPT_DIR"/*.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now rathole-token-sync.timer

echo "Done. Timer runs every 5 minutes."
```

## Usage

### Initiate Rotation

```bash
# Default 15 minute grace period
sudo rotate-rathole-tokens.sh

# Custom grace period
sudo rotate-rathole-tokens.sh 30
```

Output:

```text
=== Rathole Token Rotation Initiated ===

New tokens staged. Clients will sync within 5 minutes.
Finalization scheduled: 2026-05-17T18:15:00Z UTC

To cancel: sudo rm /etc/rathole/pending-tokens.json
To finalize now: sudo finalize-rathole-rotation.sh
```

### Check Status

```bash
# Is rotation pending?
sudo ls /etc/rathole/pending-tokens.json

# When does it finalize?
sudo cat /etc/rathole/pending-tokens.json | jq .finalize_at

# Check scheduled finalization
systemctl list-timers | grep rathole
```

### Cancel Rotation

```bash
sudo rm /etc/rathole/pending-tokens.json
sudo systemctl stop rathole-finalize.timer
```

### Force Immediate Finalization

```bash
sudo finalize-rathole-rotation.sh
```

### View Rotation History

```bash
cat /var/log/rathole-rotation.log
```

## Monitoring

### Client Sync Status

On each client:

```bash
# Last sync attempt
tail -5 /var/log/rathole-token-sync.log

# Timer status
systemctl status rathole-token-sync.timer
```

### Server-Side Verification

After finalization, verify clients reconnected:

```bash
# Check rathole connections
ss -tn sport = :8443 | grep ESTAB

# Check service ports
for port in 2222 11434 3000; do
    count=$(ss -tn sport = :$port | grep -c ESTAB || echo 0)
    echo "Port $port: $count connections"
done
```

## Troubleshooting

### Client Not Syncing

```bash
# Test API manually
curl -s -H "X-Api-Key: $(cat /etc/rathole/rotation.key)" \
    https://your-domain.com/api/v1/config

# Check timer is running
systemctl status rathole-token-sync.timer

# Run sync manually
sudo /usr/local/bin/rathole-token-sync.sh
cat /var/log/rathole-token-sync.log
```

### Token Mismatch After Rotation

```bash
# Server tokens
sudo grep '^token' /etc/rathole/server.toml

# Client tokens
sudo grep '^token' /etc/rathole/client.toml

# They should match for each service
```

### Restore From Backup

```bash
# List backups
ls -la /etc/rathole/backups/

# Restore
sudo cp /etc/rathole/backups/server.toml.YYYYMMDD_HHMMSS \
    /etc/rathole/server.toml
sudo systemctl restart rathole-server
```

## Security Considerations

### Rotation Key Protection

The rotation key grants the ability to read new tokens. Proper protection is essential:

```bash
# Server
chmod 600 /etc/rathole/rotation.key
chown root:root /etc/rathole/rotation.key

# Clients
chmod 600 /etc/rathole/rotation.key
chown root:root /etc/rathole/rotation.key
```

### Network Security

- API endpoint is HTTPS only (via nginx TLS)
- Key transmitted in header, not URL
- Pending tokens file has 600 permissions

### Audit Trail

```bash
# Rotation log
tail /var/log/rathole-rotation.log

# Backups show rotation history
ls -la /etc/rathole/backups/
```

## Automation: Scheduled Rotation

Rotate weekly with a cron job:

```bash
# /etc/cron.d/rathole-rotation
0 3 * * 0 root /usr/local/bin/rotate-rathole-tokens.sh 30
```

This rotates every Sunday at 3 AM with a 30-minute grace period.

## Comparison: Push vs Pull

| Aspect | Push (SSH to clients) | Pull (clients poll) |
|--------|----------------------|---------------------|
| NAT traversal | Requires jump host | Works natively |
| Client availability | Must be online during push | Can be offline |
| Complexity | SSH keys, expect scripts | Simple HTTP polling |
| Failure mode | Partial rotation possible | Atomic per-client |
| Scaling | O(n) SSH connections | O(1) server work |

Pull-based rotation is superior for NAT-heavy environments where clients may be intermittently available.

## Conclusion

Automated token rotation removes the operational burden of credential management:

- **Zero manual intervention**: Initiate rotation, no further action required
- **Grace period**: Clients have time to sync before cutover
- **Atomic updates**: Each client updates independently
- **Audit trail**: Logs and backups for compliance
- **Simple recovery**: Restore from backup if needed

The system is intentionally simple—bash scripts, systemd timers, nginx serving a JSON file. No databases, no message queues, no external dependencies beyond those already running for rathole itself.

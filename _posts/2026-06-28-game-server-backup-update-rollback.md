---
title: "Game Server Backup and Update Scripts with Automatic Rollback"
date: 2026-06-28 10:00:00 -0700
categories: [Gaming, Automation]
tags: [game-server, backup, vintage-story, minecraft, systemd, bash]
---

Automated backup and update scripts for self-hosted game servers: Vintage Story and Minecraft implementations featuring retention policies, integrity checks, systemd integration, and automatic rollback on failed updates.

## Problem Statement

Self-hosted game servers require:

- **Regular backups**: World data must be preserved
- **Retention policy**: Disk space management through backup rotation
- **Safe updates**: Pre-update backups with rollback on failure
- **Automation**: Scheduled backups without manual intervention

## Part 1: Generic Backup Script

A template applicable to any game server:

```bash
#!/bin/bash
# game_backup.sh - Backup game server data with retention
set -euo pipefail

# =============================================================================
# Configuration (override via environment)
# =============================================================================

DATA_DIR="${DATA_DIR:?ERROR: DATA_DIR not set}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/gameserver}"
PREFIX="${PREFIX:-gamedata}"
RETENTION="${RETENTION:-14}"  # Keep last N backups
COMPRESS="${COMPRESS:-true}"

# =============================================================================
# Main
# =============================================================================

# Ensure backup directory exists
install -d -m 0755 "$BACKUP_DIR"

# Create timestamped archive
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

if [[ "$COMPRESS" == "true" ]]; then
    ARCHIVE="${BACKUP_DIR}/${PREFIX}_${TIMESTAMP}.tar.gz"
    echo "Creating compressed backup: $ARCHIVE"
    tar -C "$DATA_DIR" -czf "$ARCHIVE" .
else
    ARCHIVE="${BACKUP_DIR}/${PREFIX}_${TIMESTAMP}.tar"
    echo "Creating backup: $ARCHIVE"
    tar -C "$DATA_DIR" -cf "$ARCHIVE" .
fi

# Set permissions
chmod 0640 "$ARCHIVE"

# Verify archive integrity
echo "Verifying archive..."
if ! tar -tf "$ARCHIVE" >/dev/null 2>&1; then
    echo "ERROR: Archive verification failed!"
    rm -f "$ARCHIVE"
    exit 1
fi

# Show size
SIZE=$(du -h "$ARCHIVE" | cut -f1)
echo "Backup complete: $ARCHIVE ($SIZE)"

# Retention: delete oldest backups beyond limit
PATTERN="${BACKUP_DIR}/${PREFIX}_*.tar*"
BACKUP_COUNT=$(ls -1 $PATTERN 2>/dev/null | wc -l)

if [[ $BACKUP_COUNT -gt $RETENTION ]]; then
    echo "Applying retention policy (keeping $RETENTION)..."
    ls -1t $PATTERN | tail -n +$((RETENTION + 1)) | xargs -r rm -f
    echo "Deleted $((BACKUP_COUNT - RETENTION)) old backups"
fi

echo "Backups retained: $(ls -1 $PATTERN 2>/dev/null | wc -l)"
```

### Usage

```bash
# Vintage Story
DATA_DIR=/var/vintagestory/data PREFIX=vsdata ./game_backup.sh

# Minecraft
DATA_DIR=/srv/minecraft/world PREFIX=mcworld ./game_backup.sh

# Custom retention
DATA_DIR=/var/gamedata RETENTION=30 ./game_backup.sh
```

---

## Part 2: Vintage Story Server

### Backup Script

`/usr/local/bin/vs_backup.sh`:

```bash
#!/bin/bash
# vs_backup.sh - Vintage Story server backup
set -euo pipefail

DATA_DIR="/var/vintagestory/data"
BACKUP_DIR="/var/backups/vintagestory"
RETENTION=14

install -d -m 0755 "$BACKUP_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ARCHIVE="${BACKUP_DIR}/vsdata_${TIMESTAMP}.tar.gz"

echo "[$(date)] Starting Vintage Story backup"

# Create archive
tar -C "$DATA_DIR" -czf "$ARCHIVE" .
chmod 0640 "$ARCHIVE"

# Verify
if ! tar -tzf "$ARCHIVE" >/dev/null 2>&1; then
    echo "ERROR: Archive corrupt"
    rm -f "$ARCHIVE"
    exit 1
fi

echo "Backup: $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"

# Retention
ls -1t "${BACKUP_DIR}"/vsdata_*.tar.gz 2>/dev/null | \
    tail -n +$((RETENTION + 1)) | \
    xargs -r rm -f

echo "[$(date)] Backup complete"
```

### Update Script with Rollback

`/usr/local/bin/vs_update.sh`:

```bash
#!/bin/bash
# vs_update.sh - Update Vintage Story server with automatic rollback
set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

VS_USER="vintagestory"
VS_SERVER_DIR="/srv/vintagestory/server"
VS_DATA_DIR="/var/vintagestory/data"
VS_BACKUP_DIR="/srv/vintagestory"
SERVICE_NAME="vintagestory.service"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
die()       { log_error "$1"; exit 1; }

BACKUP_PATH=""

# =============================================================================
# Pre-flight checks
# =============================================================================

preflight() {
    [[ $EUID -eq 0 ]] || die "Must run as root"
    id "$VS_USER" &>/dev/null || die "User '$VS_USER' not found"
    [[ -d "$VS_SERVER_DIR" ]] || die "Server not found: $VS_SERVER_DIR"
    [[ -d "$VS_DATA_DIR" ]] || die "Data dir not found: $VS_DATA_DIR"
    log_ok "Pre-flight checks passed"
}

# =============================================================================
# Tarball validation
# =============================================================================

validate_tarball() {
    local tarball="$1"
    [[ -f "$tarball" ]] || die "File not found: $tarball"
    [[ "$tarball" == *.tar.gz ]] || die "Expected .tar.gz file"

    if ! tar -tzf "$tarball" | grep -q "VintagestoryServer.dll"; then
        die "Invalid archive (missing VintagestoryServer.dll)"
    fi
    log_ok "Tarball validated"
}

extract_version() {
    basename "$1" | sed -E 's/vs_server_linux-x64_([0-9.]+)\.tar\.gz/\1/'
}

# =============================================================================
# Server control
# =============================================================================

server_running() {
    pgrep -u "$VS_USER" -f "VintagestoryServer.dll" &>/dev/null
}

stop_server() {
    log_info "Stopping server..."

    if ! server_running; then
        log_info "Server not running"
        return 0
    fi

    systemctl stop "$SERVICE_NAME" 2>/dev/null || \
        pkill -SIGINT -u "$VS_USER" -f "VintagestoryServer.dll"

    # Wait for graceful shutdown
    local retries=30
    while server_running && ((retries-- > 0)); do
        sleep 1
    done

    if server_running; then
        log_warn "Force killing..."
        pkill -SIGKILL -u "$VS_USER" -f "VintagestoryServer.dll" || true
        sleep 2
    fi

    server_running && die "Failed to stop server"
    log_ok "Server stopped"
}

start_server() {
    log_info "Starting server..."
    systemctl start "$SERVICE_NAME"
    sleep 3

    if systemctl is-active "$SERVICE_NAME" &>/dev/null; then
        log_ok "Server started"
        return 0
    else
        log_error "Server failed to start"
        return 1
    fi
}

# =============================================================================
# Backup and update
# =============================================================================

backup_server() {
    BACKUP_PATH="${VS_BACKUP_DIR}/server.backup.$(date +%Y%m%d_%H%M%S)"
    log_info "Creating backup: $BACKUP_PATH"
    cp -a "$VS_SERVER_DIR" "$BACKUP_PATH"
    chown -R "${VS_USER}:${VS_USER}" "$BACKUP_PATH"
    log_ok "Backup created"
}

update_server() {
    local tarball="$1"
    local version
    version=$(extract_version "$tarball")

    log_info "Updating to version: $version"

    # Clear server directory and extract new files
    find "$VS_SERVER_DIR" -mindepth 1 -delete
    tar -xzf "$tarball" -C "$VS_SERVER_DIR"

    # Configure paths in server.sh
    sed -i \
        -e "s|^USERNAME=.*|USERNAME='${VS_USER}'|" \
        -e "s|^VSPATH=.*|VSPATH='${VS_SERVER_DIR}'|" \
        -e "s|^DATAPATH=.*|DATAPATH='${VS_DATA_DIR}'|" \
        "$VS_SERVER_DIR/server.sh"

    # Fix permissions
    chown -R "${VS_USER}:${VS_USER}" "$VS_SERVER_DIR"
    chmod +x "$VS_SERVER_DIR/server.sh"

    log_ok "Updated to $version"
}

rollback() {
    log_error "Update failed! Rolling back..."

    if [[ -z "$BACKUP_PATH" || ! -d "$BACKUP_PATH" ]]; then
        die "No backup available for rollback!"
    fi

    rm -rf "$VS_SERVER_DIR"
    mv "$BACKUP_PATH" "$VS_SERVER_DIR"

    log_info "Restored from backup, attempting to start..."
    start_server || true

    die "Rolled back to previous version"
}

# =============================================================================
# Main
# =============================================================================

main() {
    local tarball="${1:-}"

    echo "╔════════════════════════════════════════════╗"
    echo "║   Vintage Story Server Update Script       ║"
    echo "╚════════════════════════════════════════════╝"
    echo

    # Get tarball path
    if [[ -z "$tarball" ]]; then
        echo "Download from: https://account.vintagestory.at/"
        echo
        read -rp "Path to server tarball: " tarball
        [[ -n "$tarball" ]] || die "No tarball specified"
    fi

    # Resolve to absolute path
    tarball=$(realpath "$tarball") || die "Invalid path"

    # Validate
    preflight
    validate_tarball "$tarball"

    local version
    version=$(extract_version "$tarball")

    echo
    echo "  Server directory: $VS_SERVER_DIR"
    echo "  Data directory:   $VS_DATA_DIR"
    echo "  New version:      $version"
    echo
    read -rp "Proceed with update? (y/N): " confirm
    [[ "${confirm,,}" == "y" ]] || die "Cancelled"
    echo

    # Execute update
    stop_server
    backup_server

    if ! update_server "$tarball"; then
        rollback
    fi

    if ! start_server; then
        rollback
    fi

    echo
    log_ok "Update complete!"
    echo
    echo "  Backup:  $BACKUP_PATH"
    echo "  Logs:    journalctl -u $SERVICE_NAME -f"
    echo "  Console: screen -r vintagestory (if using screen)"
}

main "$@"
```

### Systemd Service

`/etc/systemd/system/vintagestory.service`:

```ini
[Unit]
Description=Vintage Story Dedicated Server
After=network-online.target
Wants=network-online.target

[Service]
User=vintagestory
Group=vintagestory
WorkingDirectory=/srv/vintagestory/server

ExecStart=/usr/bin/dotnet VintagestoryServer.dll --dataPath /var/vintagestory/data

Type=simple
Restart=always
RestartSec=5s
KillSignal=SIGINT
TimeoutStopSec=90s

# Logging
StandardOutput=journal
StandardError=journal

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadWritePaths=/var/vintagestory /srv/vintagestory/server

[Install]
WantedBy=multi-user.target
```

### Backup Timer

`/etc/systemd/system/vs-backup.service`:

```ini
[Unit]
Description=Vintage Story backup

[Service]
Type=oneshot
ExecStart=/usr/local/bin/vs_backup.sh
```

`/etc/systemd/system/vs-backup.timer`:

```ini
[Unit]
Description=Daily Vintage Story backup at 4am

[Timer]
OnCalendar=*-*-* 04:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

Enable the timer:

```bash
sudo systemctl enable --now vs-backup.timer
```

---

## Part 3: Minecraft Server

### Server Management Script

`/usr/local/bin/mc_server.sh`:

```bash
#!/bin/bash
# mc_server.sh - Minecraft server management with tmux
set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SESSION="${MC_SESSION:-minecraft}"
SERVER_DIR="${MC_SERVER_DIR:-/srv/minecraft}"
JAR="${MC_JAR:-server.jar}"
JVM_ARGS="${MC_JVM_ARGS:--Xmx4G -Xms2G}"
BACKUP_DIR="${MC_BACKUP_DIR:-/var/backups/minecraft}"
RETENTION="${MC_RETENTION:-14}"

# =============================================================================
# Commands
# =============================================================================

start_server() {
    cd "$SERVER_DIR" || exit 1

    if tmux has-session -t "$SESSION" 2>/dev/null; then
        echo "Server already running in session '$SESSION'"
        echo "Attach: tmux attach -t $SESSION"
        exit 0
    fi

    echo "Starting Minecraft server..."
    tmux new-session -d -s "$SESSION"
    tmux send-keys -t "$SESSION" "java $JVM_ARGS -jar $JAR nogui" C-m

    sleep 3
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        echo "Server started in tmux session '$SESSION'"
        echo "Attach: tmux attach -t $SESSION"
    else
        echo "ERROR: Server failed to start"
        exit 1
    fi
}

stop_server() {
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
        echo "Server not running"
        return 0
    fi

    echo "Sending stop command..."
    tmux send-keys -t "$SESSION" "stop" C-m

    # Wait for graceful shutdown
    local retries=60
    while tmux has-session -t "$SESSION" 2>/dev/null && ((retries-- > 0)); do
        sleep 1
    done

    if tmux has-session -t "$SESSION" 2>/dev/null; then
        echo "Force killing session..."
        tmux kill-session -t "$SESSION"
    fi

    echo "Server stopped"
}

status_server() {
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        echo "Server: RUNNING"
        echo "Session: $SESSION"
        echo "Attach: tmux attach -t $SESSION"
    else
        echo "Server: STOPPED"
    fi
}

send_command() {
    local cmd="$*"
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
        echo "Server not running"
        exit 1
    fi
    tmux send-keys -t "$SESSION" "$cmd" C-m
    echo "Sent: $cmd"
}

backup_server() {
    mkdir -p "$BACKUP_DIR"

    # Save world if server is running
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        echo "Saving world..."
        tmux send-keys -t "$SESSION" "save-all" C-m
        sleep 5
        tmux send-keys -t "$SESSION" "save-off" C-m
        sleep 2
    fi

    # Create backup
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    ARCHIVE="${BACKUP_DIR}/world_${TIMESTAMP}.tar.gz"

    echo "Creating backup: $ARCHIVE"

    # Backup world directories (handle different world structures)
    cd "$SERVER_DIR"
    if [[ -d "world" ]]; then
        tar -czf "$ARCHIVE" world world_nether world_the_end 2>/dev/null || \
            tar -czf "$ARCHIVE" world
    else
        echo "ERROR: World directory not found"
        [[ -n "${SAVE_OFF:-}" ]] && tmux send-keys -t "$SESSION" "save-on" C-m
        exit 1
    fi

    # Re-enable saving
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        tmux send-keys -t "$SESSION" "save-on" C-m
    fi

    echo "Backup: $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"

    # Retention
    ls -1t "${BACKUP_DIR}"/world_*.tar.gz 2>/dev/null | \
        tail -n +$((RETENTION + 1)) | \
        xargs -r rm -f

    echo "Backups retained: $(ls -1 "${BACKUP_DIR}"/world_*.tar.gz 2>/dev/null | wc -l)"
}

show_help() {
    cat <<EOF
Usage: $(basename "$0") {start|stop|restart|status|backup|console|cmd "command"}

Commands:
  start     Start server in tmux session
  stop      Graceful shutdown
  restart   Stop and start
  status    Check if running
  backup    Backup world data
  console   Attach to tmux session
  cmd       Send command to server

Environment Variables:
  MC_SESSION     tmux session name (default: minecraft)
  MC_SERVER_DIR  Server directory (default: /srv/minecraft)
  MC_JAR         Server JAR file (default: server.jar)
  MC_JVM_ARGS    JVM arguments (default: -Xmx4G -Xms2G)
  MC_BACKUP_DIR  Backup directory (default: /var/backups/minecraft)
  MC_RETENTION   Backups to keep (default: 14)

Examples:
  $(basename "$0") start
  $(basename "$0") backup
  $(basename "$0") cmd "say Server restarting in 5 minutes"
  $(basename "$0") cmd "whitelist add PlayerName"
EOF
}

# =============================================================================
# Main
# =============================================================================

case "${1:-help}" in
    start)   start_server ;;
    stop)    stop_server ;;
    restart) stop_server; sleep 2; start_server ;;
    status)  status_server ;;
    backup)  backup_server ;;
    console) tmux attach -t "$SESSION" ;;
    cmd)     shift; send_command "$@" ;;
    help|--help|-h) show_help ;;
    *)
        echo "Unknown command: $1"
        echo "Run '$(basename "$0") help' for usage"
        exit 1
        ;;
esac
```

### Systemd Service

`/etc/systemd/system/minecraft.service`:

```ini
[Unit]
Description=Minecraft Server
After=network.target

[Service]
Type=forking
User=minecraft
Group=minecraft
WorkingDirectory=/srv/minecraft

ExecStart=/usr/local/bin/mc_server.sh start
ExecStop=/usr/local/bin/mc_server.sh stop

Restart=on-failure
RestartSec=10
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
```

### Backup Timer

```ini
# /etc/systemd/system/mc-backup.timer
[Unit]
Description=Minecraft backup every 6 hours

[Timer]
OnCalendar=*-*-* 00,06,12,18:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

---

## Part 4: Monitoring and Alerts

### Service Check Script

```bash
#!/bin/bash
# check_game_servers.sh

check_service() {
    local name="$1"
    local service="$2"

    if systemctl is-active "$service" &>/dev/null; then
        echo "[OK] $name is running"
    else
        echo "[FAIL] $name is not running"
        # Send alert (customize for notification system)
        # curl -X POST "https://hooks.slack.com/..." -d "{\"text\":\"$name is down!\"}"
    fi
}

check_service "Vintage Story" "vintagestory.service"
check_service "Minecraft" "minecraft.service"
```

### Disk Space Alert Script

```bash
#!/bin/bash
# check_backup_disk.sh

BACKUP_DIRS="/var/backups/vintagestory /var/backups/minecraft"
THRESHOLD=90  # Percent

for dir in $BACKUP_DIRS; do
    if [[ -d "$dir" ]]; then
        USAGE=$(df "$dir" | tail -1 | awk '{print $5}' | tr -d '%')
        if [[ $USAGE -gt $THRESHOLD ]]; then
            echo "WARNING: $dir is ${USAGE}% full"
        fi
    fi
done
```

---

## Quick Reference

| Task | Vintage Story | Minecraft |
|------|---------------|-----------|
| Start | `systemctl start vintagestory` | `mc_server.sh start` |
| Stop | `systemctl stop vintagestory` | `mc_server.sh stop` |
| Logs | `journalctl -u vintagestory -f` | `mc_server.sh console` |
| Backup | `vs_backup.sh` | `mc_server.sh backup` |
| Update | `vs_update.sh /path/to/server.tar.gz` | Manual JAR replacement |

## Summary

These scripts provide:

- **Automated backups** with configurable retention
- **Integrity verification** before backup completion
- **Safe updates** with automatic rollback on failure
- **Systemd integration** for reliability and scheduling
- **tmux management** for Minecraft console access
- **Graceful shutdown** to prevent data corruption

The patterns adapt to any game server. Path and command modifications enable support for Factorio, Valheim, Terraria, or other self-hosted games.

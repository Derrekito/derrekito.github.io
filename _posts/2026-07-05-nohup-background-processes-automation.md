---
title: "nohup for Background Processes: Use Cases, Tradeoffs, and Alternatives"
date: 2026-07-05 10:00:00 -0700
categories: [Linux, Automation]
tags: [nohup, bash, systemd, background-processes, automation]
---

Running long-lived processes that survive terminal disconnection: appropriate use cases for `nohup`, comparison with systemd, and implementation patterns for automated scripts.

## Problem Statement

When an SSH connection terminates, processes started in that session are killed:

```bash
ssh server
python train_model.py  # Takes 12 hours
# Close terminal -> process killed
```

This behavior occurs because:
1. The shell receives `SIGHUP` (hangup signal) when the terminal closes
2. The shell forwards `SIGHUP` to all child processes
3. Most programs exit upon receiving `SIGHUP`

## Solution: nohup

`nohup` (no hangup) provides immunity to `SIGHUP`:

```bash
nohup python train_model.py &
```

The process survives terminal disconnection.

## nohup Operation

```bash
nohup command [args] &
```

Behavior:
1. **Ignores SIGHUP** - Process continues when terminal closes
2. **Redirects stdout/stderr** - To `nohup.out` if not explicitly redirected
3. **Requires explicit backgrounding** - The `&` operator is still necessary

```bash
# Basic usage
nohup ./long_script.sh &

# Custom output file
nohup ./script.sh > output.log 2>&1 &

# Discard output
nohup ./script.sh > /dev/null 2>&1 &
```

## Use Cases

### 1. One-Off Long-Running Tasks

```bash
# Model training
nohup python train.py --epochs 100 > training.log 2>&1 &

# Large file transfer
nohup rsync -avz /data/ remote:/backup/ > rsync.log 2>&1 &

# Database migration
nohup ./migrate.sh > migration.log 2>&1 &
```

### 2. Development Servers

```bash
# Start a persistent dev server
nohup python -m http.server 8000 > /dev/null 2>&1 &

# Jekyll with future posts
nohup bundle exec jekyll serve --future --host 0.0.0.0 > jekyll.log 2>&1 &
```

### 3. Scripted Automation

When automation tools spawn persistent processes:

```bash
#!/bin/bash
# deploy.sh - Start services after deployment

# Start the app
nohup ./app serve > /var/log/app.log 2>&1 &
APP_PID=$!

# Save PID for later management
echo $APP_PID > /var/run/app.pid

echo "Started app with PID $APP_PID"
```

## Integration with Automation Tools

### Challenge

Automation tools (Ansible, scripts, CI/CD) typically:
- Execute commands over SSH
- Close the connection upon completion
- Expect commands to finish before proceeding

This behavior conflicts with background process requirements.

### Pattern 1: Fire and Forget

```bash
#!/bin/bash
# Start and exit immediately

nohup /opt/app/server > /var/log/server.log 2>&1 &
disown  # Remove from shell's job table

# Script exits immediately, process continues
```

The `disown` command removes the process from the shell's job table, preventing signal delivery when the shell exits.

### Pattern 2: Start and Verify

```bash
#!/bin/bash
# Start and confirm execution

nohup /opt/app/server > /var/log/server.log 2>&1 &
PID=$!
disown

sleep 2  # Allow time to start or crash

if kill -0 $PID 2>/dev/null; then
    echo "Server started: PID $PID"
    echo $PID > /var/run/server.pid
else
    echo "Server failed to start"
    exit 1
fi
```

### Pattern 3: With Health Check

```bash
#!/bin/bash
# Start and wait for healthy state

nohup /opt/app/server > /var/log/server.log 2>&1 &
PID=$!
disown

# Wait for health endpoint
for i in {1..30}; do
    if curl -sf http://localhost:8080/health > /dev/null; then
        echo "Server healthy: PID $PID"
        echo $PID > /var/run/server.pid
        exit 0
    fi
    sleep 1
done

echo "Server failed health check"
kill $PID 2>/dev/null
exit 1
```

### Ansible Example

```yaml
- name: Start background service with nohup
  ansible.builtin.shell: |
    nohup /opt/app/server > /var/log/server.log 2>&1 &
    disown
    sleep 2
    pgrep -f "/opt/app/server" > /var/run/server.pid
  args:
    executable: /bin/bash
  async: 10
  poll: 0

- name: Wait for service
  ansible.builtin.uri:
    url: http://localhost:8080/health
  register: health
  until: health.status == 200
  retries: 30
  delay: 1
```

## Tradeoffs

### nohup Advantages

| Advantage | Description |
|-----------|-------------|
| Simple | Single command, no configuration files |
| Universal | Functions on any Unix system |
| No root required | Executes under any user account |
| Immediate | No service registration necessary |
| Scriptable | Integrates easily with automation |

### nohup Disadvantages

| Disadvantage | Description |
|--------------|-------------|
| No auto-restart | Process termination is permanent |
| No dependency management | Start order cannot be specified |
| Manual cleanup | PID files, log rotation require manual handling |
| No boot persistence | Does not survive system restart |
| Limited monitoring | Basic process checks only |

## Selection Criteria

### Use nohup When:

- **One-off tasks**: Migrations, backups, training runs
- **Development**: Quick dev servers, testing
- **Simple deployments**: Single process, short-term
- **No root access**: Cannot create systemd services
- **Cross-platform scripts**: Must function on various Unix systems

### Use systemd When:

- **Production services**: Require reliability, monitoring
- **Auto-restart required**: Process should recover from crashes
- **Boot persistence**: Must start on system boot
- **Complex dependencies**: Services depend on each other
- **Resource limits**: Require cgroups, memory limits
- **Logging integration**: Require journald integration

### Decision Tree

```text
Need auto-restart on crash?
├── Yes → systemd
└── No
    └── Need to start on boot?
        ├── Yes → systemd
        └── No
            └── One-off or development?
                ├── Yes → nohup
                └── Production service → systemd
```

## Alternatives to nohup

### 1. disown (Bash built-in)

```bash
./long_process &
disown

# Or disown specific job
./process1 &
./process2 &
disown %1  # Disown first job
```

Distinction from nohup: `disown` operates on already-running processes.

### 2. setsid (New Session)

```bash
setsid ./long_process > output.log 2>&1 &
```

Creates a new session, completely detaching from the terminal.

### 3. screen/tmux

```bash
# Start in screen
screen -dmS myprocess ./long_process

# Reattach later
screen -r myprocess
```

Advantages: Reattachment capability, output visibility, process interaction.

### 4. systemd-run (Ad-hoc systemd)

```bash
systemd-run --user --unit=myprocess ./long_process
```

Provides systemd benefits without creating a service file.

### 5. Proper systemd Service

```ini
# /etc/systemd/system/myapp.service
[Unit]
Description=My Application
After=network.target

[Service]
Type=simple
ExecStart=/opt/app/server
Restart=always
User=appuser

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now myapp
```

## Common Patterns

### PID File Management

```bash
#!/bin/bash
PIDFILE="/var/run/myapp.pid"
LOGFILE="/var/log/myapp.log"

start() {
    if [ -f "$PIDFILE" ] && kill -0 $(cat "$PIDFILE") 2>/dev/null; then
        echo "Already running"
        return 1
    fi

    nohup /opt/app/server > "$LOGFILE" 2>&1 &
    echo $! > "$PIDFILE"
    disown
    echo "Started with PID $(cat $PIDFILE)"
}

stop() {
    if [ -f "$PIDFILE" ]; then
        kill $(cat "$PIDFILE") 2>/dev/null
        rm -f "$PIDFILE"
        echo "Stopped"
    else
        echo "Not running"
    fi
}

case "$1" in
    start) start ;;
    stop) stop ;;
    restart) stop; sleep 1; start ;;
    *) echo "Usage: $0 {start|stop|restart}" ;;
esac
```

### Log Rotation with nohup

Since nohup does not rotate logs, manual handling is required:

```bash
#!/bin/bash
# Rotate logs before starting

LOGFILE="/var/log/myapp.log"

if [ -f "$LOGFILE" ]; then
    mv "$LOGFILE" "$LOGFILE.$(date +%Y%m%d_%H%M%S)"
fi

# Keep only last 5 logs
ls -t /var/log/myapp.log.* 2>/dev/null | tail -n +6 | xargs -r rm

nohup /opt/app/server > "$LOGFILE" 2>&1 &
disown
```

Alternatively, use a named pipe with `logger`:

```bash
mkfifo /tmp/myapp.pipe
nohup sh -c 'cat /tmp/myapp.pipe | logger -t myapp' &
nohup /opt/app/server > /tmp/myapp.pipe 2>&1 &
```

### Wrapper for Automation Tools

```bash
#!/bin/bash
# nohup-wrapper.sh - Standard wrapper for background processes

CMD="$1"
PIDFILE="$2"
LOGFILE="${3:-/dev/null}"
HEALTH_URL="$4"
TIMEOUT="${5:-30}"

# Start process
nohup $CMD > "$LOGFILE" 2>&1 &
PID=$!
disown

# Save PID
echo $PID > "$PIDFILE"

# Health check if URL provided
if [ -n "$HEALTH_URL" ]; then
    for i in $(seq 1 $TIMEOUT); do
        if curl -sf "$HEALTH_URL" > /dev/null; then
            echo "healthy"
            exit 0
        fi
        sleep 1
    done
    echo "unhealthy"
    kill $PID 2>/dev/null
    exit 1
fi

# No health check, just verify process started
sleep 2
if kill -0 $PID 2>/dev/null; then
    echo "started"
    exit 0
else
    echo "failed"
    exit 1
fi
```

Usage:

```bash
./nohup-wrapper.sh "/opt/app/server" "/var/run/app.pid" "/var/log/app.log" "http://localhost:8080/health"
```

## Debugging nohup Issues

### Process Dies Immediately

```bash
# Check for path issues
which mycommand

# Run without nohup first
./mycommand

# Check nohup.out for errors
cat nohup.out
```

### Cannot Find the Process

```bash
# Find by command name
pgrep -f "mycommand"

# Find by port
ss -tlnp | grep :8080

# Check PID file
cat /var/run/myapp.pid
```

### Output Not Appearing

```bash
# Flush output in Python
python -u script.py  # Unbuffered

# Or in the script
import sys
sys.stdout.flush()
```

```bash
# Force line buffering
stdbuf -oL ./mycommand > output.log 2>&1 &
```

## Summary

| Method | Complexity | Auto-restart | Boot persist | Best for |
|--------|------------|--------------|--------------|----------|
| nohup | Low | No | No | One-off tasks, development |
| disown | Low | No | No | Already-running processes |
| screen/tmux | Medium | No | No | Interactive, reattachable |
| systemd-run | Medium | Optional | No | Ad-hoc with systemd features |
| systemd service | High | Yes | Yes | Production services |

**Guideline**: Use `nohup` for quick tasks. Migrate to systemd when reliability, monitoring, or boot persistence is required.

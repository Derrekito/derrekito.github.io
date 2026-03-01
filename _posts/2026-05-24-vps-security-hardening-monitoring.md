---
title: "VPS Security Hardening and Monitoring with Auditd, Fail2ban, and a One-Command Report"
date: 2026-05-24 10:00:00 -0700
categories: [Security, Linux]
tags: [vps, security, auditd, fail2ban, sysctl, ssh, hardening, monitoring, auto-update, geoip]
---

This post presents a complete VPS security stack: kernel hardening via sysctl, file change auditing with auditd, brute-force protection with fail2ban, automated updates with conditional reboots, GeoIP whitelisting, and a single script that summarizes all security metrics into a readable report.

## Problem Statement

A fresh VPS presents several security vulnerabilities:

- SSH exposed to the internet with default settings
- No visibility into authentication attempts
- No alerting when critical files change
- No automatic blocking of attackers

Multiple defensive layers are required:

| Layer | Tool | Purpose |
|-------|------|---------|
| Prevention | sysctl, SSH config | Reduce attack surface |
| Detection | auditd | Log file changes, sudo usage |
| Response | fail2ban | Auto-ban repeat offenders |
| Maintenance | Auto-updates | Stay patched, reboot when needed |
| Network | GeoIP blocking | Drop traffic from unwanted regions |
| Visibility | Report script | Consolidated status view |

## Architecture

```text
┌─────────────────────────────────────────────────────────────────────┐
│                        SECURITY STACK                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐            │
│  │   PREVENT    │   │   DETECT     │   │   RESPOND    │            │
│  ├──────────────┤   ├──────────────┤   ├──────────────┤            │
│  │ SSH hardening│   │ auditd       │   │ fail2ban     │            │
│  │ sysctl       │   │ journald     │   │ iptables     │            │
│  │ firewall     │   │ lastb/last   │   │              │            │
│  └──────────────┘   └──────────────┘   └──────────────┘            │
│         │                  │                  │                     │
│         └──────────────────┼──────────────────┘                     │
│                            ▼                                        │
│                   ┌────────────────┐                                │
│                   │ REPORT SCRIPT  │                                │
│                   │ One command to │                                │
│                   │ see everything │                                │
│                   └────────────────┘                                │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Layer 1: Kernel Hardening (sysctl)

Create `/etc/sysctl.d/90-security.conf`:

```ini
# Log martian packets (spoofed source addresses)
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Strict reverse path filtering (drop packets with unreachable source)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Disable ICMP redirects (MITM protection)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Disable IPv6 router advertisements (not needed on servers)
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0

# Restrict unprivileged BPF (CVE mitigations)
kernel.unprivileged_bpf_disabled = 1

# Hide kernel pointers from unprivileged users
kernel.kptr_restrict = 2

# Restrict dmesg to root
kernel.dmesg_restrict = 1

# Disable core dumps for SUID binaries
fs.suid_dumpable = 0
```

Apply immediately:

```bash
sudo sysctl --system
```

### Setting Descriptions

| Setting | Attack Mitigated |
|---------|------------------|
| `log_martians` | Detect IP spoofing attempts |
| `rp_filter` | Block packets with forged source IPs |
| `accept_redirects=0` | Prevent MITM route injection |
| `accept_ra=0` | Prevent rogue IPv6 router attacks |
| `unprivileged_bpf_disabled` | Block BPF-based container escapes |
| `kptr_restrict` | Hide kernel addresses (exploit hardening) |
| `dmesg_restrict` | Prevent info leaks via dmesg |
| `suid_dumpable=0` | Prevent credential extraction from core dumps |

## Layer 2: SSH Hardening

Edit `/etc/ssh/sshd_config`:

```text
# Only IPv4 (disable if IPv6 is required)
AddressFamily inet

# No root login
PermitRootLogin no

# Fail fast
MaxAuthTries 3

# Keys only, no passwords
PasswordAuthentication no
PermitEmptyPasswords no

# Explicit authorized_keys location
AuthorizedKeysFile .ssh/authorized_keys
```

Restart SSH:

```bash
sudo systemctl restart sshd
```

### Rationale

- **No root login**: Attackers must guess both username AND key
- **MaxAuthTries 3**: Fewer guesses before disconnect
- **No passwords**: Eliminates brute-force attack vector entirely (keys only)

## Layer 3: File Auditing (auditd)

Auditd monitors files and logs access/modifications. Create `/etc/audit/rules.d/security.rules`:

```bash
# Clear existing rules
-D

# Buffer size (increase for busy systems)
-b 8192

# Failure mode: 1=printk, 2=panic
-f 1

# === AUTHENTICATION ===
-w /var/log/lastlog -p wa -k logins
-w /var/run/faillock -p wa -k logins
-w /var/log/tallylog -p wa -k logins

# PAM config
-w /etc/pam.d -p wa -k auth_config
-w /etc/security -p wa -k auth_config

# === PRIVILEGE ESCALATION ===
-w /etc/sudoers -p wa -k sudo_config
-w /etc/sudoers.d -p wa -k sudo_config
-a always,exit -F arch=b64 -S execve -F path=/usr/bin/sudo -k sudo_exec
-a always,exit -F arch=b64 -S execve -F path=/usr/bin/su -k sudo_exec

# === IDENTITY FILES ===
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/gshadow -p wa -k identity

# === SSH ===
-w /etc/ssh/sshd_config -p wa -k sshd_config
-w /etc/ssh/sshd_config.d -p wa -k sshd_config

# === SCHEDULED TASKS ===
-w /etc/crontab -p wa -k cron
-w /etc/cron.d -p wa -k cron
-w /var/spool/cron -p wa -k cron

# === SERVICES ===
-w /etc/systemd/system -p wa -k systemd
-w /usr/lib/systemd/system -p wa -k systemd

# === NETWORK ===
-w /etc/hosts -p wa -k network
-w /etc/resolv.conf -p wa -k network
-w /etc/iptables -p wa -k firewall
-w /etc/nftables.conf -p wa -k firewall

# Make rules immutable until reboot
-e 2
```

Load rules:

```bash
sudo augenrules --load
sudo systemctl enable --now auditd
```

### Querying Audit Logs

```bash
# All sudo executions today
sudo ausearch -k sudo_exec -ts today

# Changes to passwd/shadow
sudo ausearch -k identity -ts today

# SSH config modifications
sudo ausearch -k sshd_config -ts today

# Recent cron changes
sudo ausearch -k cron -ts recent
```

### Understanding Audit Output

```text
type=SYSCALL ... key="identity"
type=PATH name="/etc/passwd"
type=PROCTITLE proctitle="useradd badguy"
```

The key (`-k` flag) enables filtering of related events. The PATH shows the file accessed, PROCTITLE shows the command.

## Layer 4: Brute-Force Protection (fail2ban)

### Base Configuration

Create `/etc/fail2ban/jail.local`:

```ini
[DEFAULT]
# Ban for 1 hour
bantime = 1h

# Detection window
findtime = 10m

# Strikes before ban
maxretry = 5

# Use systemd journal
backend = systemd

# Never ban these IPs (home IP, etc.)
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = ssh
maxretry = 3
```

### Nginx Jails

Protect the web server from scanners and bots:

```ini
[nginx-botsearch]
enabled = true
port = http,https
logpath = /var/log/nginx/access.log
maxretry = 2
findtime = 1m
bantime = 24h

[nginx-bad-request]
enabled = true
port = http,https
logpath = /var/log/nginx/access.log
maxretry = 3
bantime = 1h

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 3
bantime = 1h

[nginx-forbidden]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 5
bantime = 1h
```

### Custom Jail: Rathole Tunnels

For rathole tunnels (see [previous post](/posts/rathole-secure-tunnels-mcp/)), add protection.

Create `/etc/fail2ban/filter.d/rathole-ssh.conf`:

```ini
[Definition]
failregex = ^.*RATHOLE_BLOCKED: .*SRC=<HOST>.*DPT=(2222|2223).*$
ignoreregex =
```

Create `/etc/fail2ban/jail.d/rathole-ssh.conf`:

```ini
[rathole-ssh]
enabled = true
filter = rathole-ssh
backend = systemd
journalmatch = _TRANSPORT=kernel
port = 2222,2223
maxretry = 3
findtime = 10m
bantime = 1h
action = iptables-multiport[name=rathole-ssh, port="2222,2223", protocol=tcp]
```

### Enable fail2ban

```bash
sudo systemctl enable --now fail2ban
```

### Check Status

```bash
# List all jails
sudo fail2ban-client status

# Check specific jail
sudo fail2ban-client status sshd

# Recent bans
sudo grep "Ban\|Unban" /var/log/fail2ban.log | tail -20
```

## Layer 5: The Report Script

Consolidate all security information with a single script that shows:

- Recent logins and failures
- Sudo activity
- Critical file changes
- Fail2ban status and recent bans
- Network connections
- System health

Create `/usr/local/bin/security-report`:

```bash
#!/bin/bash
# Security Report Script
# Usage: security-report [hours]
# Default: last 24 hours

HOURS="${1:-24}"
SINCE="$(date -d "${HOURS} hours ago" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
DIVIDER="═══════════════════════════════════════════════════════════════════"

echo "$DIVIDER"
echo "  SECURITY REPORT - $(hostname)"
echo "  Generated: $(date)"
echo "  Period: Last ${HOURS} hours"
echo "$DIVIDER"

# === AUTHENTICATION ===
echo -e "\n[AUTHENTICATION]"
echo "─────────────────────────────────────────────────────────────────────"

echo -e "\nSuccessful logins:"
last -n 20 2>/dev/null | head -20

echo -e "\nFailed login attempts (last 20):"
sudo lastb 2>/dev/null | head -20 || echo "  (requires root)"

echo -e "\nCurrent sessions:"
who

# === SUDO ACTIVITY ===
echo -e "\n\n[SUDO ACTIVITY]"
echo "─────────────────────────────────────────────────────────────────────"
sudo ausearch -k sudo_exec -ts recent 2>/dev/null | \
    grep -E 'type=SYSCALL|exe=|comm=' | head -30 || \
    echo "  No recent sudo activity or auditd not running"

# === AUDIT: FILE CHANGES ===
echo -e "\n\n[CRITICAL FILE CHANGES]"
echo "─────────────────────────────────────────────────────────────────────"

echo -e "\nIdentity files (passwd, shadow, group):"
sudo ausearch -k identity -ts today 2>/dev/null | \
    grep -E 'name=|type=PATH' | head -20 || echo "  None"

echo -e "\nSSH config changes:"
sudo ausearch -k sshd_config -ts today 2>/dev/null | \
    grep -E 'name=|type=PATH' | head -10 || echo "  None"

echo -e "\nSystemd unit changes:"
sudo ausearch -k systemd -ts today 2>/dev/null | \
    grep -E 'name=|type=PATH' | head -10 || echo "  None"

echo -e "\nCron changes:"
sudo ausearch -k cron -ts today 2>/dev/null | \
    grep -E 'name=|type=PATH' | head -10 || echo "  None"

# === FAIL2BAN ===
echo -e "\n\n[FAIL2BAN STATUS]"
echo "─────────────────────────────────────────────────────────────────────"
if command -v fail2ban-client &>/dev/null; then
    sudo fail2ban-client status 2>/dev/null
    echo ""

    for jail in $(sudo fail2ban-client status 2>/dev/null | \
                  grep "Jail list" | sed 's/.*://;s/,//g'); do
        echo "--- $jail ---"
        sudo fail2ban-client status "$jail" 2>/dev/null | \
            grep -E 'Currently|Total'
    done

    echo -e "\nRecent bans (last ${HOURS}h):"
    sudo grep -E "Ban|Unban" /var/log/fail2ban.log 2>/dev/null | tail -20
else
    echo "  fail2ban not installed"
fi

# === NETWORK ===
echo -e "\n\n[NETWORK]"
echo "─────────────────────────────────────────────────────────────────────"

echo "Listening ports (external):"
ss -tlnp 2>/dev/null | grep -v "127.0.0" | grep LISTEN

echo -e "\nTop connections by IP:"
ss -tnp 2>/dev/null | grep ESTAB | \
    awk '{print $5}' | cut -d: -f1 | \
    sort | uniq -c | sort -rn | head -10

# === SYSTEM ===
echo -e "\n\n[SYSTEM]"
echo "─────────────────────────────────────────────────────────────────────"

echo "Uptime:"
uptime

echo -e "\nDisk usage:"
df -h / | tail -1

echo -e "\nMemory:"
free -h | grep Mem

echo -e "\nRunning services:"
systemctl list-units --type=service --state=running --no-pager 2>/dev/null | \
    grep -c running | xargs echo "Total:"

# === RECENT WARNINGS ===
echo -e "\n\n[RECENT SECURITY EVENTS]"
echo "─────────────────────────────────────────────────────────────────────"
sudo journalctl -p warning --since "${HOURS} hours ago" --no-pager 2>/dev/null | \
    tail -30

echo -e "\n$DIVIDER"
echo "  END OF REPORT"
echo "$DIVIDER"
```

Make executable:

```bash
sudo chmod +x /usr/local/bin/security-report
```

### Usage

```bash
# Last 24 hours (default)
security-report

# Last 6 hours
security-report 6

# Last week
security-report 168
```

### Sample Output

```text
═══════════════════════════════════════════════════════════════════
  SECURITY REPORT - myvps
  Generated: Sat Feb 28 14:30:00 MST 2026
  Period: Last 24 hours
═══════════════════════════════════════════════════════════════════

[AUTHENTICATION]
─────────────────────────────────────────────────────────────────────

Successful logins:
youruser  pts/0   your.home.ip     Sat Feb 28 14:25   still logged in
youruser  pts/0   your.home.ip     Sat Feb 28 10:12 - 12:45  (02:33)

Failed login attempts (last 20):
root     ssh:notty    45.227.253.130   Sat Feb 28 13:42 - 13:42  (00:00)
admin    ssh:notty    103.145.12.88    Sat Feb 28 11:15 - 11:15  (00:00)

Current sessions:
youruser  pts/0        2026-02-28 14:25 (your.home.ip)


[FAIL2BAN STATUS]
─────────────────────────────────────────────────────────────────────
Status
|- Number of jail:      5
`- Jail list:   nginx-botsearch, nginx-forbidden, nginx-http-auth, rathole-ssh, sshd

--- sshd ---
   |- Currently banned: 2
   `- Total banned:     47
--- nginx-botsearch ---
   |- Currently banned: 5
   `- Total banned:     312

Recent bans (last 24h):
2026-02-28 13:42:15 fail2ban.actions: NOTICE  [sshd] Ban 45.227.253.130
2026-02-28 11:15:03 fail2ban.actions: NOTICE  [sshd] Ban 103.145.12.88
2026-02-28 09:22:41 fail2ban.actions: NOTICE  [nginx-botsearch] Ban 185.220.101.34
```

## Scheduled Reports

### Daily Email

Create `/etc/cron.d/security-report`:

```bash
0 8 * * * root /usr/local/bin/security-report 24 | mail -s "Daily Security Report - $(hostname)" you@example.com
```

### Weekly Summary

```bash
0 8 * * 1 root /usr/local/bin/security-report 168 | mail -s "Weekly Security Report - $(hostname)" you@example.com
```

## Alerting on Critical Events

For real-time alerts on critical file changes, add a systemd path unit.

`/etc/systemd/system/passwd-alert.path`:

```ini
[Unit]
Description=Monitor /etc/passwd for changes

[Path]
PathModified=/etc/passwd

[Install]
WantedBy=multi-user.target
```

`/etc/systemd/system/passwd-alert.service`:

```ini
[Unit]
Description=Alert on /etc/passwd change

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo "ALERT: /etc/passwd modified on $(hostname) at $(date)" | mail -s "CRITICAL: passwd changed" you@example.com'
```

Enable:

```bash
sudo systemctl enable --now passwd-alert.path
```

## Quick Reference

### Check Security Status

```bash
# One-command overview
security-report

# Currently banned IPs
sudo fail2ban-client status sshd

# Recent file changes
sudo ausearch -k identity -ts today

# Current logged-in users
who
```

### Respond to Incidents

```bash
# Manually ban an IP
sudo fail2ban-client set sshd banip 1.2.3.4

# Unban an IP
sudo fail2ban-client set sshd unbanip 1.2.3.4

# View full audit log for today
sudo ausearch -ts today | less

# Check what a specific user did
sudo ausearch -ua username -ts today
```

### Maintenance

```bash
# Rotate audit logs
sudo service auditd rotate

# Check fail2ban is running
sudo fail2ban-client ping

# Reload fail2ban after config change
sudo fail2ban-client reload

# Verify sysctl settings
sysctl -a | grep -E "rp_filter|log_martians|kptr_restrict"
```

## Automated Updates with Conditional Reboot

Security patches should be applied promptly, but manual updates are often neglected. Automate them with intelligent reboot handling.

### The Update Script

Create `/usr/local/bin/auto-update.sh`:

```bash
#!/bin/bash
# Auto-update with conditional reboot
set -euo pipefail

LOG="/var/log/auto-update.log"

# Packages that require a reboot when updated
REBOOT_PATTERNS="^linux$|^linux-lts|^linux-zen|^linux-hardened|^nvidia|^mesa|^vulkan|^amdgpu|^xf86-video"

touch "$LOG"
chmod 640 "$LOG"

echo "=== Update started: $(date) ===" >> "$LOG"

# Check for available updates (Arch Linux)
UPDATES=$(checkupdates 2>/dev/null || true)

if [ -z "$UPDATES" ]; then
    echo "No updates available" >> "$LOG"
    exit 0
fi

echo "Updates available:" >> "$LOG"
echo "$UPDATES" >> "$LOG"

# Check if any kernel/driver updates require reboot
NEEDS_REBOOT=$(echo "$UPDATES" | cut -d' ' -f1 | grep -E "$REBOOT_PATTERNS" || true)

# Perform update
if ! pacman -Syu --noconfirm >> "$LOG" 2>&1; then
    echo "ERROR: Update failed" >> "$LOG"
    exit 1
fi

echo "Update completed successfully" >> "$LOG"

# Reboot if kernel or graphics drivers were updated
if [ -n "$NEEDS_REBOOT" ]; then
    echo "Kernel/driver updates detected, scheduling reboot:" >> "$LOG"
    echo "$NEEDS_REBOOT" >> "$LOG"
    echo "Rebooting in 1 minute..." >> "$LOG"
    shutdown -r +1 "System reboot for kernel/driver updates"
fi

echo "=== Update finished: $(date) ===" >> "$LOG"
```

For Debian/Ubuntu, replace the update commands:

```bash
# Debian/Ubuntu version
UPDATES=$(apt list --upgradable 2>/dev/null | grep -v "^Listing" || true)
REBOOT_PATTERNS="linux-image|linux-headers|nvidia|mesa"

# Perform update
apt update && apt upgrade -y >> "$LOG" 2>&1
```

### Systemd Timer

`/etc/systemd/system/auto-update.service`:

```ini
[Unit]
Description=Automatic system update with conditional reboot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/auto-update.sh
```

`/etc/systemd/system/auto-update.timer`:

```ini
[Unit]
Description=Run auto-update daily at 3am

[Timer]
OnCalendar=*-*-* 03:00:00
RandomizedDelaySec=15m
Persistent=true

[Install]
WantedBy=timers.target
```

Enable:

```bash
sudo chmod +x /usr/local/bin/auto-update.sh
sudo systemctl enable --now auto-update.timer
```

### Conditional Reboot Rationale

Not all updates require a reboot. The script only reboots when:

| Package Pattern | Reboot Reason |
|-----------------|--------------|
| `linux*` | Kernel updates require reboot to load |
| `nvidia`, `amdgpu` | GPU drivers loaded at boot |
| `mesa`, `vulkan` | Graphics stack, safer to reboot |

Regular package updates (nginx, fail2ban, etc.) apply immediately without disruption.

### Check Update History

```bash
# Recent update activity
tail -50 /var/log/auto-update.log

# Next scheduled run
systemctl list-timers auto-update.timer
```

## GeoIP Whitelisting

Block entire countries at the kernel level with ipset. Only allow traffic from the desired country.

### The Update Script

Create `/etc/geoblock/update-blocklist.sh`:

```bash
#!/bin/bash
# GeoIP whitelist - only allow US traffic
set -euo pipefail

IPSET_NAME="geoallow"
ZONE_DIR="/etc/geoblock/zones"
MIN_ENTRIES=15000  # US zone should have ~17k entries

mkdir -p "$ZONE_DIR"

echo "Downloading US IP zones..."
curl -sSL "https://www.ipdeny.com/ipblocks/data/countries/us.zone" \
    -o "$ZONE_DIR/us.zone.new"

# Validate download
new_count=$(grep -cE '^[0-9]' "$ZONE_DIR/us.zone.new" 2>/dev/null || echo 0)
if [[ "$new_count" -lt "$MIN_ENTRIES" ]]; then
    echo "ERROR: Zone file only has $new_count entries (min $MIN_ENTRIES)"
    rm -f "$ZONE_DIR/us.zone.new"
    exit 1
fi

mv "$ZONE_DIR/us.zone.new" "$ZONE_DIR/us.zone"
echo "Zone validated: $new_count entries"

# Build new set atomically (no downtime)
TEMP_SET="${IPSET_NAME}_tmp"
ipset create "$TEMP_SET" hash:net maxelem 100000 2>/dev/null || ipset flush "$TEMP_SET"

# Always allow localhost
ipset add "$TEMP_SET" 127.0.0.0/8

# Load country IPs
while read -r cidr; do
    [[ -z "$cidr" || "$cidr" =~ ^# ]] && continue
    ipset add "$TEMP_SET" "$cidr" 2>/dev/null
done < "$ZONE_DIR/us.zone"

# Atomic swap
ipset swap "$TEMP_SET" "$IPSET_NAME"
ipset destroy "$TEMP_SET"

echo "GeoIP whitelist updated"
```

### IPTables Rule

Add to the firewall setup:

```bash
# Create the ipset if it does not exist
ipset create geoallow hash:net maxelem 100000 2>/dev/null || true

# Drop traffic not in whitelist (apply to INPUT chain)
iptables -I INPUT -m set ! --match-set geoallow src -j DROP
```

### Weekly Updates

`/etc/systemd/system/geoblock-update.timer`:

```ini
[Unit]
Description=Weekly GeoIP update

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
```

`/etc/systemd/system/geoblock-update.service`:

```ini
[Unit]
Description=Update GeoIP blocklist

[Service]
Type=oneshot
ExecStart=/etc/geoblock/update-blocklist.sh
```

Enable:

```bash
sudo systemctl enable --now geoblock-update.timer
```

### Adding More Countries

For multiple countries, download and merge zones:

```bash
for country in us ca gb; do
    curl -sSL "https://www.ipdeny.com/ipblocks/data/countries/${country}.zone" \
        >> "$ZONE_DIR/allowed.zone"
done
```

## Conclusion

A layered security approach provides comprehensive protection:

1. **sysctl**: Kernel-level hardening (prevent classes of attacks)
2. **SSH config**: Reduce attack surface (keys only, no root)
3. **auditd**: Record changes and access events (detection)
4. **fail2ban**: Automatic response to attacks (block repeat offenders)
5. **Auto-updates**: Stay patched with intelligent reboots
6. **GeoIP blocking**: Reduce attack surface by country
7. **Report script**: Single command for consolidated status view

The report script is the force multiplier—instead of requiring multiple commands, `security-report` provides the complete picture in seconds.

This stack addresses the majority of VPS security requirements with minimal maintenance. The tools are standard, well-documented, and available in every major distribution's package manager.

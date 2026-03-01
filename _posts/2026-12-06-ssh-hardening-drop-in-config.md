---
title: "SSH Hardening with Drop-in Configuration Files"
date: 2026-12-06 10:00:00 -0700
categories: [Linux, Security]
tags: [ssh, security, hardening, automation, sysadmin]
---

Default SSH configurations prioritize compatibility over security. This post presents a minimal hardening script that uses the modern `sshd_config.d` drop-in directory approach, ensuring clean separation of custom settings while maintaining system upgradability.

## Problem Statement

### Default SSH Attack Surface

Out-of-the-box OpenSSH configurations expose several attack vectors:

1. **Root login enabled**: Direct root access allows attackers to target the most privileged account
2. **Password authentication**: Susceptible to brute-force attacks, dictionary attacks, and credential stuffing
3. **Unlimited authentication attempts**: Default `MaxAuthTries 6` provides excessive brute-force runway

A single compromised password or successful brute-force attempt grants full system access. SSH servers face continuous automated attacks—security logs commonly show hundreds of failed authentication attempts daily.

### Traditional Configuration Challenges

Editing `/etc/ssh/sshd_config` directly introduces maintenance burden:

- **Upgrade conflicts**: Package updates may overwrite custom modifications
- **Merge complexity**: Manual three-way merges during system upgrades
- **Audit difficulty**: Custom settings intermixed with defaults obscure security posture
- **Rollback friction**: Reverting changes requires careful file editing

## Technical Background: Drop-in Configuration Architecture

Modern OpenSSH (8.0+) supports modular configuration through the `Include` directive. Most Linux distributions now ship with:

```bash
# In /etc/ssh/sshd_config
Include /etc/ssh/sshd_config.d/*.conf
```

### Configuration Precedence

OpenSSH applies the **first match wins** rule. When a directive appears multiple times, the first occurrence takes precedence. The include statement position determines override behavior:

```text
/etc/ssh/sshd_config:
  Include /etc/ssh/sshd_config.d/*.conf   # Line 1: Drop-ins processed first
  PermitRootLogin yes                      # Line 50: Default setting (ignored if set above)
```

Files in `sshd_config.d/` are processed in lexicographic order:

```text
10-custom.conf      # Processed first
50-hardening.conf   # Processed second
99-overrides.conf   # Processed last
```

The naming convention `50-hardening.conf` provides middle-ground positioning—allowing both earlier overrides (10-xx) and later adjustments (90-xx) if needed.

### Advantages of Drop-in Files

| Aspect | Direct Edit | Drop-in |
|--------|-------------|---------|
| Upgrade safety | Conflicts likely | Preserved |
| Audit clarity | Settings scattered | Isolated in separate file |
| Rollback | Edit required | Delete file |
| Automation | Parse-and-modify | Simple file write |

## Hardening Measures

The script applies three critical settings:

```bash
PermitRootLogin no
PasswordAuthentication no
MaxAuthTries 3
```

### PermitRootLogin no

Disabling root login provides defense-in-depth:

- **Eliminates direct root attacks**: Attackers must compromise a regular user first, then escalate
- **Enforces accountability**: All administrative actions trace to a named user via `sudo`
- **Reduces attack surface**: The `root` username is universally known; other usernames are not

Legitimate administrative access remains available through `sudo` or `su` after authenticating as a regular user.

### PasswordAuthentication no

Disabling password authentication forces key-based authentication:

- **Eliminates brute-force viability**: Private keys contain 2048+ bits of entropy vs. typical 40-80 bit passwords
- **Removes credential theft risk**: Passwords can be phished, keylogged, or shoulder-surfed; private keys cannot
- **Enables hardware security**: Keys can reside on hardware tokens (YubiKey, smart cards)

**Prerequisite**: At least one authorized public key must exist in `~/.ssh/authorized_keys` for each user requiring access. Enabling this setting without key-based access configured results in lockout.

### MaxAuthTries 3

Reducing authentication attempts from the default 6 to 3:

- **Accelerates lockout**: Faster connection termination for brute-force attempts
- **Reduces log noise**: Fewer attempts per connection means cleaner audit trails
- **Maintains usability**: Three attempts suffice for legitimate users (key passphrase typos, etc.)

## Implementation Walkthrough

The hardening script implements safety-first automation:

```bash
#!/usr/bin/env bash
set -euo pipefail

CONF="/etc/ssh/sshd_config.d/50-hardening.conf"
```

### Safety Check: Root Privileges

SSH configuration modification requires root access:

```bash
if [[ $EUID -ne 0 ]]; then
    echo "Run as root or with sudo."
    exit 1
fi
```

### Safety Check: Drop-in Support Verification

Not all systems support `sshd_config.d`. Older installations or minimal configurations may lack the `Include` directive:

```bash
if ! grep -q '^Include.*/etc/ssh/sshd_config.d/' /etc/ssh/sshd_config 2>/dev/null; then
    echo "Error: /etc/ssh/sshd_config does not include /etc/ssh/sshd_config.d/."
    echo "This system may need manual configuration."
    exit 1
fi
```

This check prevents silent failures where the configuration file would be written but never processed.

### Configuration Deployment

The script creates the hardening configuration:

```bash
mkdir -p /etc/ssh/sshd_config.d

cat > "$CONF" << 'EOF'
PermitRootLogin no
PasswordAuthentication no
MaxAuthTries 3
EOF

echo "Wrote $CONF"
```

### Configuration Validation

Before applying changes, the script validates the complete configuration:

```bash
if ! sshd -t; then
    echo "Error: sshd config validation failed. Reverting."
    rm -f "$CONF"
    exit 1
fi
```

The `sshd -t` command parses all configuration files and reports syntax errors. If validation fails, the script removes the newly created file and exits—leaving the system in its original working state.

### Cross-Platform Service Reload

Different systems use different service management approaches. The script handles multiple scenarios:

```bash
# Reload sshd (try systemctl, then service, then direct signal)
if command -v systemctl &>/dev/null && systemctl is-active sshd &>/dev/null; then
    systemctl reload sshd
elif command -v systemctl &>/dev/null && systemctl is-active ssh &>/dev/null; then
    systemctl reload ssh
elif command -v service &>/dev/null; then
    service sshd reload 2>/dev/null || service ssh reload
else
    kill -HUP "$(cat /run/sshd.pid 2>/dev/null)" 2>/dev/null || true
fi
```

This cascade handles:
- **systemd systems**: Most modern distributions (Arch, Fedora, Ubuntu 16.04+, RHEL 7+)
- **SysVinit systems**: Older distributions using `service` command
- **Minimal systems**: Direct SIGHUP to the running daemon

Note: Service names vary by distribution—Debian/Ubuntu use `ssh`, while RHEL/Fedora/Arch use `sshd`.

## Verification Procedures

After reload, the script displays active settings:

```bash
echo "SSH hardened. Active settings:"
sshd -T 2>/dev/null | grep -iE '^(permitrootlogin|passwordauthentication|maxauthtries|pubkeyauthentication|kbdinteractiveauthentication)'
```

### Understanding sshd -T Output

The `sshd -T` command outputs the effective configuration after processing all includes and applying precedence rules:

```text
permitrootlogin no
passwordauthentication no
maxauthtries 3
pubkeyauthentication yes
kbdinteractiveauthentication no
```

Key verification points:

| Setting | Expected Value | Concern if Different |
|---------|----------------|----------------------|
| `permitrootlogin` | no | Direct root access remains possible |
| `passwordauthentication` | no | Brute-force attacks remain viable |
| `maxauthtries` | 3 | Higher values provide more attack runway |
| `pubkeyauthentication` | yes | Must be enabled when passwords disabled |
| `kbdinteractiveauthentication` | no | Alternative password method; should be disabled |

### Manual Verification

Additional verification commands:

```bash
# Show effective configuration for a specific user
sshd -T -C user=admin,host=192.168.1.100,addr=192.168.1.100

# Test configuration syntax only
sshd -t

# Show which file set each directive
sshd -T | head -50
```

## Additional Hardening Options

The script provides baseline hardening. Additional measures for higher-security environments include:

### Fail2ban Integration

Fail2ban monitors authentication logs and temporarily bans IP addresses exhibiting attack patterns:

```bash
# Install
sudo pacman -S fail2ban  # Arch
sudo apt install fail2ban  # Debian/Ubuntu

# Enable SSH jail
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
```

Create `/etc/fail2ban/jail.d/sshd.local`:

```ini
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
```

### Port Knocking

Port knocking hides the SSH port until a specific sequence of connection attempts occurs:

```bash
# Example knockd configuration
[openSSH]
    sequence    = 7000,8000,9000
    seq_timeout = 10
    command     = /sbin/iptables -A INPUT -s %IP% -p tcp --dport 22 -j ACCEPT
    tcpflags    = syn
```

### Non-Standard Port

Changing the default port reduces automated scanning noise (not a security measure, but reduces log volume):

```bash
# In /etc/ssh/sshd_config.d/50-hardening.conf
Port 2222
```

### Additional Restrictive Settings

Extended hardening configuration:

```bash
# Extended /etc/ssh/sshd_config.d/50-hardening.conf
PermitRootLogin no
PasswordAuthentication no
MaxAuthTries 3

# Additional restrictions
PermitEmptyPasswords no
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
PrintMotd no
TCPKeepAlive no
Compression no

# Timeout settings
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 30

# Allowed users/groups (restrict who can SSH)
# AllowUsers admin deploy
# AllowGroups ssh-users
```

## Rollback Procedures

If lockout occurs or settings cause issues, recovery requires out-of-band access.

### Console Access Recovery

From physical console, virtual console (VM), or IPMI/iLO/DRAC:

```bash
# Remove the hardening file
sudo rm /etc/ssh/sshd_config.d/50-hardening.conf

# Reload SSH
sudo systemctl reload sshd
```

### Single-User Mode Recovery

If console access is unavailable but bootloader access exists:

1. Reboot the system
2. Edit GRUB entry: add `single` or `init=/bin/bash` to kernel line
3. Mount filesystem read-write: `mount -o remount,rw /`
4. Remove the configuration: `rm /etc/ssh/sshd_config.d/50-hardening.conf`
5. Reboot: `reboot -f`

### Pre-Hardening Checklist

Before running the script, verify:

1. **SSH key access works**: Test key-based login before disabling passwords
   ```bash
   ssh -o PasswordAuthentication=no user@host
   ```

2. **Console access available**: Ensure alternative access method exists

3. **Current session preserved**: The script reloads (not restarts) sshd—existing sessions remain active

4. **Backup administrative access**: Secondary user with sudo privileges provides redundancy

### Recovery Key Preparation

Generate and securely store a recovery keypair before hardening:

```bash
# Generate dedicated recovery key
ssh-keygen -t ed25519 -f ~/.ssh/recovery_key -C "emergency-recovery"

# Add to authorized_keys
cat ~/.ssh/recovery_key.pub >> ~/.ssh/authorized_keys

# Store private key securely offline (printed, encrypted USB, etc.)
```

## Complete Script

For reference, the complete hardening script:

```bash
#!/usr/bin/env bash
set -euo pipefail

CONF="/etc/ssh/sshd_config.d/50-hardening.conf"

if [[ $EUID -ne 0 ]]; then
    echo "Run as root or with sudo."
    exit 1
fi

# Check for sshd_config.d support (Include directive)
if ! grep -q '^Include.*/etc/ssh/sshd_config.d/' /etc/ssh/sshd_config 2>/dev/null; then
    echo "Error: /etc/ssh/sshd_config does not include /etc/ssh/sshd_config.d/."
    echo "This system may need manual configuration."
    exit 1
fi

mkdir -p /etc/ssh/sshd_config.d

cat > "$CONF" << 'EOF'
PermitRootLogin no
PasswordAuthentication no
MaxAuthTries 3
EOF

echo "Wrote $CONF"

# Validate config
if ! sshd -t; then
    echo "Error: sshd config validation failed. Reverting."
    rm -f "$CONF"
    exit 1
fi

# Reload sshd (try systemctl, then service, then direct signal)
if command -v systemctl &>/dev/null && systemctl is-active sshd &>/dev/null; then
    systemctl reload sshd
elif command -v systemctl &>/dev/null && systemctl is-active ssh &>/dev/null; then
    systemctl reload ssh
elif command -v service &>/dev/null; then
    service sshd reload 2>/dev/null || service ssh reload
else
    kill -HUP "$(cat /run/sshd.pid 2>/dev/null)" 2>/dev/null || true
fi

echo "SSH hardened. Active settings:"
sshd -T 2>/dev/null | grep -iE '^(permitrootlogin|passwordauthentication|maxauthtries|pubkeyauthentication|kbdinteractiveauthentication)'
```

## Summary

The drop-in configuration approach provides:

- **Clean separation**: Custom settings isolated from distribution defaults
- **Upgrade safety**: Package updates cannot overwrite custom configuration
- **Safe automation**: Pre-flight checks and validation prevent broken configurations
- **Easy rollback**: Single file deletion restores default behavior
- **Cross-platform support**: Works across systemd and SysVinit systems

The three settings—disabled root login, disabled password authentication, and reduced authentication attempts—address the most common SSH attack vectors while maintaining usability for legitimate key-based access.

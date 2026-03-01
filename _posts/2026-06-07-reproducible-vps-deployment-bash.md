---
title: "Reproducible VPS Deployments with Bash and Age Encryption"
date: 2026-06-07 10:00:00 -0700
categories: [DevOps, Automation]
tags: [bash, deployment, age, encryption, secrets, vps, infrastructure-as-code]
---

This post presents a complete redeployment bundle for rebuilding a VPS from scratch: pack secrets with age encryption, deploy configs and services with a single script, and verify with an automated pentest. No Ansible, no Terraform—just bash.

## Problem Statement

VPS configurations accumulate over time:

- SSH hardening, fail2ban jails
- nginx with custom locations and rate limiting
- Rathole tunnels with rotating tokens
- WireGuard mesh, Discord bots, systemd timers
- Numerous scripts in `/usr/local/bin`

Several scenarios necessitate complete reconstruction:
- VPS provider outage resulting in disk loss
- Migration to a different provider
- Staging copy deployment

The question becomes: can the system be rebuilt from memory in an hour?

## Proposed Solution: Deployment Bundle

A self-contained directory that rebuilds the server from a fresh OS install:

```text
vps-deploy/
├── deploy.sh              # Main deployment script
├── packages.txt           # Package list
├── README.md              # Architecture docs
├── secrets/               # Encrypted secrets (not in git)
│   └── secrets.tar.gz.age
├── configs/
│   ├── ssh/
│   │   └── sshd_config
│   ├── nginx/
│   │   └── nginx.conf
│   ├── fail2ban/
│   │   ├── jail.local
│   │   └── jail.d/
│   ├── rathole/
│   │   └── client-scripts/
│   └── geoblock/
│       └── update-blocklist.sh
├── scripts/
│   ├── auto-update.sh
│   ├── security-report.sh
│   └── rotate-tokens.sh
├── systemd/
│   ├── auto-update.service
│   ├── auto-update.timer
│   └── discord-bot.service
└── app/
    └── discord_bot.py
```

## Secrets Management with Age

[Age](https://github.com/FiloSottile/age) is a simple, modern encryption tool. It encrypts all secrets into a single archive that can be safely stored (but NOT in git).

### Packing Secrets from a Live System

Add this to the deploy script:

```bash
pack_secrets() {
    log "Packing secrets from live system..."

    if [[ $EUID -ne 0 ]]; then
        die "Must run as root to read protected files"
    fi

    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT

    local secrets_dir="$tmpdir/secrets"
    mkdir -p "$secrets_dir/certs" "$secrets_dir/ssh"

    # Collect secrets - customize for specific setup
    collect_if_exists() {
        local src="$1" dst="$2"
        if [[ -f "$src" ]]; then
            cp "$src" "$secrets_dir/$dst"
            ok "Packed $dst"
        else
            warn "Missing $src"
        fi
    }

    collect_if_exists "/etc/rathole/server.toml" "rathole-server.toml"
    collect_if_exists "/etc/rathole/rotation.key" "rotation.key"
    collect_if_exists "/etc/wireguard/wg0.conf" "wg0.conf"
    collect_if_exists "/home/myuser/.app.env" "app.env"
    collect_if_exists "/home/myuser/.ssh/authorized_keys" "ssh/authorized_keys"

    # Collect directory of certs
    if [[ -d /etc/rathole/certs ]]; then
        cp /etc/rathole/certs/* "$secrets_dir/certs/" 2>/dev/null
        ok "Packed TLS certs"
    fi

    # Create tarball
    local tarball="$SCRIPT_DIR/secrets.tar.gz"
    tar -czf "$tarball" -C "$tmpdir" secrets

    # Encrypt with age
    if command -v age &>/dev/null; then
        age -p -o "$SCRIPT_DIR/secrets.tar.gz.age" "$tarball"
        rm -f "$tarball"
        ok "Encrypted secrets saved to secrets.tar.gz.age"
        warn "REMEMBER YOUR PASSPHRASE!"
    else
        warn "age not installed - tarball saved unencrypted"
        warn "Install age and encrypt: age -p -o secrets.tar.gz.age secrets.tar.gz"
    fi
}
```

Usage:

```bash
sudo ./deploy.sh --pack-secrets
```

### Unpacking Secrets During Deploy

```bash
deploy_secrets() {
    local secrets_file="$SCRIPT_DIR/secrets.tar.gz.age"

    if [[ ! -f "$secrets_file" ]]; then
        die "Secrets file not found: $secrets_file"
    fi

    local tmpdir
    tmpdir=$(mktemp -d)

    # Decrypt
    log "Decrypting secrets..."
    age -d -o "$tmpdir/secrets.tar.gz" "$secrets_file"
    tar -xzf "$tmpdir/secrets.tar.gz" -C "$tmpdir"

    local sdir="$tmpdir/secrets"

    # Deploy each secret to its location
    deploy_secret() {
        local src="$1" dst="$2" mode="$3" owner="$4"
        if [[ -f "$sdir/$src" ]]; then
            mkdir -p "$(dirname "$dst")"
            cp "$sdir/$src" "$dst"
            chmod "$mode" "$dst"
            chown "$owner" "$dst"
            ok "Deployed $dst"
        fi
    }

    deploy_secret "rathole-server.toml" "/etc/rathole/server.toml" 600 "root:root"
    deploy_secret "rotation.key" "/etc/rathole/rotation.key" 600 "root:root"
    deploy_secret "wg0.conf" "/etc/wireguard/wg0.conf" 600 "root:root"
    deploy_secret "app.env" "/home/myuser/.app.env" 600 "myuser:myuser"
    deploy_secret "ssh/authorized_keys" "/home/myuser/.ssh/authorized_keys" 600 "myuser:myuser"

    # Deploy certs directory
    if [[ -d "$sdir/certs" ]]; then
        mkdir -p /etc/rathole/certs
        cp "$sdir/certs/"* /etc/rathole/certs/
        chmod 600 /etc/rathole/certs/*
        chown root:root /etc/rathole/certs/*
        ok "Deployed TLS certs"
    fi

    # Securely delete temp files
    find "$tmpdir" -type f -exec shred -u {} \; 2>/dev/null || rm -rf "$tmpdir"
    rm -rf "$tmpdir"

    ok "Secrets deployed and temp files shredded"
}
```

## Deploy Script Structure

### Header and Utilities

```bash
#!/bin/bash
# VPS Deployment Script
# Usage:
#   deploy.sh              Fully automated
#   deploy.sh -i           Interactive (confirm each step)
#   deploy.sh --dry-run    Preview without executing
#   deploy.sh --pack-secrets  Pack secrets from live system
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INTERACTIVE=false
DRY_RUN=false

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[0;33m'
BLU='\033[0;34m'
RST='\033[0m'

log()  { printf "${BLU}[*]${RST} %s\n" "$1"; }
ok()   { printf "${GRN}[+]${RST} %s\n" "$1"; }
warn() { printf "${YLW}[!]${RST} %s\n" "$1"; }
err()  { printf "${RED}[-]${RST} %s\n" "$1"; }
die()  { err "$1"; exit 1; }
```

### Interactive Mode Helper

```bash
confirm_step() {
    local step_name="$1"
    local step_desc="$2"

    echo ""
    printf "${BLU}=== Step: %s ===${RST}\n" "$step_name"
    echo "$step_desc"

    if $DRY_RUN; then
        warn "[DRY RUN] Would execute: $step_name"
        return 2  # Skip
    fi

    if ! $INTERACTIVE; then
        return 0  # Proceed
    fi

    while true; do
        read -rp "[Y/n/s] (yes/no/skip): " choice
        case "${choice,,}" in
            y|yes|"") return 0 ;;
            n|no) die "Aborted at: $step_name" ;;
            s|skip) warn "Skipping: $step_name"; return 2 ;;
        esac
    done
}
```

### Step Functions

Each deployment step is implemented as a function:

```bash
step_validate() {
    if confirm_step "Validate" "Check running as root on target OS"; then
        [[ $EUID -ne 0 ]] && die "Must run as root"
        [[ ! -f /etc/arch-release ]] && die "Designed for Arch Linux"
        ok "Validation passed"
    fi
}

step_install_packages() {
    if confirm_step "Install packages" "Install from packages.txt"; then
        pacman -Sy
        pacman -S --needed --noconfirm - < "$SCRIPT_DIR/packages.txt"
        ok "Packages installed"
    fi
}

step_create_user() {
    if confirm_step "Create user" "Create user with sudo access"; then
        if ! id myuser &>/dev/null; then
            useradd -m -G wheel -s /bin/bash myuser
            ok "Created user"
        fi

        # Enable wheel sudo
        sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

        mkdir -p /home/myuser/.ssh
        chmod 700 /home/myuser/.ssh
        chown myuser:myuser /home/myuser/.ssh
        ok "User configured"
    fi
}

step_deploy_ssh() {
    if confirm_step "Deploy SSH" "Install hardened sshd_config"; then
        cp "$SCRIPT_DIR/configs/ssh/sshd_config" /etc/ssh/sshd_config
        chmod 644 /etc/ssh/sshd_config
        systemctl restart sshd
        ok "SSH hardened"
    fi
}

step_deploy_configs() {
    if confirm_step "Deploy configs" "nginx, fail2ban, geoblock"; then
        # Nginx
        cp "$SCRIPT_DIR/configs/nginx/nginx.conf" /etc/nginx/nginx.conf
        chmod 640 /etc/nginx/nginx.conf
        chown root:http /etc/nginx/nginx.conf

        # Substitute rotation key into nginx config
        if [[ -f /etc/rathole/rotation.key ]]; then
            local key=$(cat /etc/rathole/rotation.key)
            sed -i "s|__ROTATION_KEY__|${key}|g" /etc/nginx/nginx.conf
        fi

        # Fail2ban
        cp "$SCRIPT_DIR/configs/fail2ban/jail.local" /etc/fail2ban/jail.local
        cp -r "$SCRIPT_DIR/configs/fail2ban/jail.d/"* /etc/fail2ban/jail.d/

        # Geoblock
        mkdir -p /etc/geoblock
        cp "$SCRIPT_DIR/configs/geoblock/"* /etc/geoblock/
        chmod +x /etc/geoblock/*.sh

        ok "Configs deployed"
    fi
}

step_deploy_scripts() {
    if confirm_step "Deploy scripts" "Install to /usr/local/bin"; then
        for script in "$SCRIPT_DIR/scripts/"*; do
            local name=$(basename "$script")
            cp "$script" "/usr/local/bin/$name"
            chmod 755 "/usr/local/bin/$name"
        done

        # Tighten permissions on secret-handling scripts
        for s in rotate-tokens.sh rotate-rathole-tokens.sh; do
            [[ -f "/usr/local/bin/$s" ]] && chmod 700 "/usr/local/bin/$s"
        done

        ok "Scripts deployed"
    fi
}

step_deploy_systemd() {
    if confirm_step "Deploy systemd" "Unit files, enable services"; then
        cp "$SCRIPT_DIR/systemd/"* /etc/systemd/system/
        systemctl daemon-reload

        # Enable services
        systemctl enable --now nginx fail2ban

        # Enable timers
        systemctl enable --now auto-update.timer

        ok "Services enabled"
    fi
}

step_certbot() {
    if confirm_step "Certbot" "Obtain TLS certificate"; then
        if [[ -f /etc/letsencrypt/live/your-domain.com/fullchain.pem ]]; then
            ok "Certificate already exists"
            return
        fi

        systemctl stop nginx
        certbot certonly --standalone -d your-domain.com \
            --non-interactive --agree-tos \
            --register-unsafely-without-email
        systemctl start nginx
        ok "Certificate obtained"
    fi
}

step_permissions() {
    if confirm_step "Permissions" "Enforce correct ownership/modes"; then
        # SSH
        chmod 644 /etc/ssh/sshd_config

        # Nginx
        chmod 640 /etc/nginx/nginx.conf
        chown root:http /etc/nginx/nginx.conf

        # Secrets
        [[ -f /etc/rathole/server.toml ]] && chmod 600 /etc/rathole/server.toml
        [[ -f /etc/rathole/rotation.key ]] && chmod 600 /etc/rathole/rotation.key
        [[ -f /etc/wireguard/wg0.conf ]] && chmod 600 /etc/wireguard/wg0.conf

        ok "Permissions set"
    fi
}
```

### Self-Test After Deploy

```bash
step_pentest() {
    if confirm_step "Pentest" "Run security audit against localhost"; then
        if [[ -x /usr/local/bin/vps-pentest.sh ]]; then
            /usr/local/bin/vps-pentest.sh 127.0.0.1 || warn "Some pentest checks failed"
        else
            warn "Pentest script not found"
        fi
        ok "Pentest complete"
    fi
}
```

### Summary

```bash
step_summary() {
    echo ""
    echo "========================================"
    printf "${GRN}  DEPLOYMENT COMPLETE${RST}\n"
    echo "========================================"
    echo ""

    log "Service status:"
    for svc in sshd nginx fail2ban; do
        local state=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
        if [[ "$state" == "active" ]]; then
            printf "  ${GRN}%-25s %s${RST}\n" "$svc" "$state"
        else
            printf "  ${RED}%-25s %s${RST}\n" "$svc" "$state"
        fi
    done

    echo ""
    log "Listening ports:"
    ss -tlnp | grep LISTEN | awk '{printf "  %s\n", $4}'

    echo ""
    log "Next steps:"
    echo "  1. Verify SSH access from external machine"
    echo "  2. Run pentest from external: vps-pentest.sh <server-ip>"
    echo "  3. Update DNS if IP changed"
    echo "  4. Test certbot renewal: certbot renew --dry-run"
}
```

### Main Execution

```bash
# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--interactive) INTERACTIVE=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --pack-secrets) pack_secrets; exit 0 ;;
        -h|--help) usage ;;
        *) die "Unknown option: $1" ;;
    esac
done

# Run all steps
step_validate
step_install_packages
step_create_user
step_deploy_secrets
step_deploy_ssh
step_deploy_configs
step_deploy_scripts
step_deploy_systemd
step_certbot
step_permissions
step_pentest
step_summary
```

## Package List

Create `packages.txt`:

```text
# Core
base-devel
git
curl
wget

# Security
fail2ban
ufw
wireguard-tools
age

# Web
nginx
certbot
certbot-nginx

# Monitoring
htop
iotop
ncdu

# Networking
nmap
net-tools
bind-tools

# Python (for bots/scripts)
python
python-pip
```

## Usage

### Initial Setup (from live server)

```bash
# Pack secrets from current working server
sudo ./deploy.sh --pack-secrets
# Enter a passphrase

# Store secrets.tar.gz.age somewhere safe (NOT in git)
```

### Deploy to Fresh VPS

```bash
# Copy bundle to new server
scp -r vps-deploy/ root@new-server:/root/
scp secrets.tar.gz.age root@new-server:/root/vps-deploy/

# SSH in and deploy
ssh root@new-server
cd /root/vps-deploy

# Preview what will happen
./deploy.sh --dry-run

# Interactive mode (confirm each step)
./deploy.sh -i

# Fully automated
./deploy.sh
```

### Verify Deployment

```bash
# From an external machine
./vps-pentest.sh new-server-ip
```

## Config Templates with Placeholders

For configs that require secrets substitution, use placeholders:

`configs/nginx/nginx.conf`:
```nginx
location = /api/v1/config {
    if ($http_x_api_key != "__ROTATION_KEY__") {
        return 403;
    }
    # ...
}
```

The deploy script substitutes:
```bash
if [[ -f /etc/rathole/rotation.key ]]; then
    local key=$(cat /etc/rathole/rotation.key)
    sed -i "s|__ROTATION_KEY__|${key}|g" /etc/nginx/nginx.conf
fi
```

## Exclusion Guidelines

| Exclude | Reason |
|---------------|-----|
| Private keys | Use secrets archive |
| API tokens | Use secrets archive |
| `.git` directory | Not needed for deploy |
| Log files | Generated at runtime |
| Build artifacts | Install from packages |

## Comparison with Other Tools

| Tool | Advantages | Disadvantages |
|------|------|------|
| **This approach** | Simple, auditable, no dependencies | Manual, less declarative |
| Ansible | Declarative, idempotent | Learning curve, YAML complexity |
| Terraform | Cloud-native, state management | Excessive for single VPS |
| NixOS | Fully reproducible | Complete paradigm shift |
| Docker | Isolated, portable | Adds container layer |

Bash scripts are optimal when:
- Managing one or few servers
- Complete understanding of every line is desired
- External dependencies should be avoided
- Shell proficiency already exists

## Disaster Recovery Workflow

1. **Regular backups**: Run `--pack-secrets` monthly or after config changes
2. **Store encrypted secrets**: Keep `secrets.tar.gz.age` in a secure location (password manager, encrypted drive)
3. **Version the bundle**: Keep `vps-deploy/` in a private git repo (without secrets)
4. **Test periodically**: Spin up a test VPS and verify the deploy works

## Security Considerations

### Secrets Archive

- **Passphrase strength**: Use a strong, unique passphrase
- **Storage**: Never commit to git, store in password manager
- **Rotation**: Re-pack after rotating any secrets
- **Shredding**: The script shreds decrypted temp files

### During Deploy

- **Root access**: Deploy runs as root (necessary for system config)
- **Network exposure**: Run certbot in standalone mode briefly
- **Verification**: Always run pentest after deploy

### Permissions Matrix

| File | Mode | Owner | Rationale |
|------|------|-------|-----|
| `/etc/ssh/sshd_config` | 644 | root:root | Public config |
| `/etc/nginx/nginx.conf` | 640 | root:http | nginx needs read |
| `/etc/rathole/*.toml` | 600 | root:root | Contains tokens |
| `/etc/wireguard/*.conf` | 600 | root:root | Contains private key |
| Secret-handling scripts | 700 | root:root | Root-only execution |

## Extending the Bundle

### Adding a New Service

1. Add package to `packages.txt`
2. Add config to `configs/servicename/`
3. Add systemd unit to `systemd/`
4. Add deploy step function
5. Add to secrets if needed

### Adding a New Secret

1. Update `pack_secrets()` to collect it
2. Update `deploy_secrets()` to place it
3. Update `step_permissions()` for correct mode
4. Document in README

## Conclusion

A bash deployment bundle provides:

- **Reproducibility**: Rebuild from scratch in minutes
- **Transparency**: Every step is readable shell
- **Portability**: Works on any system with bash
- **Security**: Secrets encrypted with age, never in git
- **Verification**: Self-pentest confirms hardening

The bundle serves as a disaster recovery plan, documentation, and deployment automation in one directory. When a VPS fails unexpectedly, having this preparation ensures rapid recovery.

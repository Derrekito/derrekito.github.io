---
title: "Caddy and Local DNS for Network-Wide Dev Access"
date: 2026-07-19 10:00:00 -0700
categories: [Development, Networking]
tags: [caddy, dns, pfsense, unbound, reverse-proxy, development]
---

Network-wide access to local development servers using domain names like `blog.lan` and `dashboard.lan` instead of IP:port combinations such as `192.168.1.51:4000`.

## Problem Statement

Development servers running on a workstation:

```text
localhost:4000  - Jekyll blog
localhost:5173  - Vite frontend
localhost:8080  - API docs
localhost:9000  - Dashboard
```

This configuration presents limitations:
- Inaccessible from laptops, phones, or tablets
- Port numbers must be memorized
- No HTTPS (required by certain APIs)

## Proposed Solution

1. **Caddy** as reverse proxy - routes `blog.lan` to `localhost:4000`
2. **Local DNS** - resolves `*.lan` to the workstation IP
3. **Firewall rules** - permits traffic from LAN

## Part 1: Caddy Reverse Proxy

### Installation

```bash
# Arch Linux
sudo pacman -S caddy

# Ubuntu/Debian
sudo apt install caddy

# macOS
brew install caddy
```

### Basic Configuration

Caddy configuration resides at `/etc/caddy/Caddyfile`. For modularity, use includes:

```text
# /etc/caddy/Caddyfile
{
    admin "unix//run/caddy/admin.socket"
}

import /etc/caddy/conf.d/*
```

Create the conf.d directory:

```bash
sudo mkdir -p /etc/caddy/conf.d
```

### Local Development Configuration

Create `/etc/caddy/conf.d/local-dev.caddyfile`:

```text
# .localhost domains (local machine only)
# These receive automatic HTTPS with self-signed certs

dashboard.localhost {
    reverse_proxy localhost:9000
}

blog.localhost {
    reverse_proxy localhost:4000
}

app.localhost {
    reverse_proxy localhost:5173
}

# .lan domains (network-wide access)
# Use internal TLS since Let's Encrypt does not issue certs for .lan

dashboard.lan {
    tls internal
    reverse_proxy localhost:9000
}

blog.lan {
    tls internal
    reverse_proxy localhost:4000
}

app.lan {
    tls internal
    reverse_proxy localhost:5173
}
```

### Domain Types

**`.localhost` domains:**
- Resolved by browsers automatically (RFC 6761)
- Always point to 127.0.0.1
- Function only on the local machine
- Caddy generates self-signed certificates automatically

**`.lan` domains:**
- Require DNS configuration (covered below)
- Function from any device on the network
- `tls internal` instructs Caddy to use self-signed certificates (Let's Encrypt does not issue certificates for private TLDs)

### Starting Caddy

```bash
# Validate config
sudo caddy validate --config /etc/caddy/Caddyfile

# Enable and start
sudo systemctl enable --now caddy

# Check status
sudo systemctl status caddy
```

### Testing Local Access

```bash
# Should work immediately
curl -sk https://blog.localhost/
```

## Part 2: Local DNS with pfSense/Unbound

For `.lan` domains to function from other devices, DNS resolution is required. pfSense (or OPNsense) includes Unbound DNS.

### Creating a Custom Configuration File

SSH into the pfSense system:

```bash
ssh root@192.168.1.1
```

Create a configuration file that will not be overwritten by the GUI:

```bash
cat > /var/unbound/local_services.conf << 'EOF'
# Local development services
# This file is NOT managed by pfSense GUI

server:
local-zone: "lan." static
local-data: "dashboard.lan. A 192.168.1.51"
local-data: "blog.lan. A 192.168.1.51"
local-data: "app.lan. A 192.168.1.51"
local-data: "api.lan. A 192.168.1.51"
local-data: "docs.lan. A 192.168.1.51"
EOF
```

Replace `192.168.1.51` with the workstation IP.

### Including the Configuration

Note: pfSense regenerates `unbound.conf` from its XML configuration. To persist custom includes, add them via the GUI's "Custom options" field, which is stored base64-encoded.

**Option A: Via pfSense GUI**

1. Navigate to Services -> DNS Resolver
2. Scroll to "Custom options"
3. Add: `include: /var/unbound/local_services.conf`
4. Save and Apply

**Option B: Via config.xml**

```bash
# Get current custom_options
grep 'custom_options' /cf/conf/config.xml

# Create new value with include added
NEW_OPTS=$(echo -n 'server:include: /var/unbound/pfb_dnsbl.*conf
include: /var/unbound/local_services.conf' | base64 -w0)

# Update config.xml
sed -i '' "s|<custom_options>.*</custom_options>|<custom_options>${NEW_OPTS}</custom_options>|" /cf/conf/config.xml
```

### Restarting Unbound

```bash
# On pfSense
pfSsh.php playback svc restart unbound
```

### Testing DNS

From any device on the network:

```bash
dig +short dashboard.lan @192.168.1.1
# Should return: 192.168.1.51
```

## Part 3: Firewall Configuration

The workstation firewall likely blocks incoming connections. Allow HTTP/HTTPS from the LAN:

### UFW (Ubuntu/Debian)

```bash
sudo ufw allow from 192.168.1.0/24 to any port 80 proto tcp comment "Caddy HTTP"
sudo ufw allow from 192.168.1.0/24 to any port 443 proto tcp comment "Caddy HTTPS"
```

### firewalld (Fedora/RHEL)

```bash
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.1.0/24" port port="80" protocol="tcp" accept'
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.1.0/24" port port="443" protocol="tcp" accept'
sudo firewall-cmd --reload
```

### iptables

```bash
sudo iptables -A INPUT -p tcp -s 192.168.1.0/24 --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp -s 192.168.1.0/24 --dport 443 -j ACCEPT
```

## Part 4: Testing from Another Device

From a laptop or phone (connected to the same network):

```bash
# Test DNS
nslookup dashboard.lan

# Test HTTPS (will warn about self-signed cert)
curl -sk https://dashboard.lan/
```

In a browser, navigate to `https://dashboard.lan`. A certificate warning will appear - this is expected for self-signed certificates. Accept to proceed.

## Adding New Services

When adding a new development server:

1. **Add DNS entry** (on pfSense):
   ```bash
   ssh root@192.168.1.1
   echo 'local-data: "newapp.lan. A 192.168.1.51"' >> /var/unbound/local_services.conf
   pfSsh.php playback svc restart unbound
   ```

2. **Add Caddy config**:
   ```
   newapp.localhost {
       reverse_proxy localhost:3000
   }

   newapp.lan {
       tls internal
       reverse_proxy localhost:3000
   }
   ```

3. **Reload Caddy**:
   ```bash
   sudo systemctl reload caddy
   ```

## TLD Selection Rationale

- **`.local`** is reserved for mDNS (Bonjour/Avahi) - causes conflicts
- **`.localhost`** is reserved for loopback - does not resolve to other IPs
- **`.lan`** is commonly used for private networks and functions reliably
- **`.home.arpa`** is the IETF-recommended TLD for home networks (RFC 8375)

## Troubleshooting

### Caddy Startup Failure

```bash
# Check config syntax
sudo caddy validate --config /etc/caddy/Caddyfile

# Check logs
journalctl -u caddy -f
```

### DNS Resolution Failure

```bash
# Test direct query to DNS server
dig dashboard.lan @192.168.1.1

# Check if Unbound loaded the config
ssh root@192.168.1.1 "unbound-checkconf /var/unbound/unbound.conf"

# Check if include is present
ssh root@192.168.1.1 "grep 'local_services' /var/unbound/unbound.conf"
```

### Connection Refused from LAN

```bash
# Check if Caddy is listening on all interfaces
ss -tlnp | grep caddy
# Should show *:80 and *:443, not 127.0.0.1:80

# Check firewall
sudo ufw status
sudo iptables -L INPUT -n | grep -E "80|443"
```

### Certificate Warnings

Caddy uses self-signed certificates for `.lan` domains since Let's Encrypt does not issue certificates for private TLDs. To eliminate recurring warnings, trust Caddy's root CA.

## Part 5: Trusting Caddy's Root CA

Caddy generates a local Certificate Authority. Trusting it once enables automatic trust for all `.lan` certificates.

### Locating the Root CA

```bash
# Caddy stores its CA here
sudo ls /var/lib/caddy/pki/authorities/local/
# root.crt  root.key  intermediate.crt  intermediate.key

# Check validity (should be ~10 years)
sudo openssl x509 -in /var/lib/caddy/pki/authorities/local/root.crt -noout -dates
```

### Copying for Import

```bash
sudo cp /var/lib/caddy/pki/authorities/local/root.crt ~/caddy-root-ca.crt
sudo chown $USER:$USER ~/caddy-root-ca.crt
```

### Linux System-Wide Trust

```bash
# Arch Linux
sudo cp ~/caddy-root-ca.crt /etc/ca-certificates/trust-source/anchors/
sudo update-ca-trust

# Ubuntu/Debian
sudo cp ~/caddy-root-ca.crt /usr/local/share/ca-certificates/caddy-root-ca.crt
sudo update-ca-certificates

# Verify
curl https://dashboard.lan/  # No -k needed
```

### Firefox

Firefox uses its own certificate store:

1. Settings -> Privacy & Security -> Certificates -> View Certificates
2. **Authorities** tab -> Import
3. Select `~/caddy-root-ca.crt`
4. Check **"Trust this CA to identify websites"**
5. OK

### Chrome/Chromium

Chrome uses the system store on Linux, but manual addition is also possible:

1. Settings -> Privacy and security -> Security -> Manage certificates
2. **Authorities** tab -> Import
3. Select `~/caddy-root-ca.crt`
4. Check **"Trust this certificate for identifying websites"**

### Other Network Devices

Copy the root CA to each device and import:

```bash
# Copy to laptop
scp ~/caddy-root-ca.crt user@laptop:~/

# Copy to phone (via web server)
python3 -m http.server 8888
# Then download http://192.168.1.51:8888/caddy-root-ca.crt on phone
```

**iOS**: Download the certificate, navigate to Settings -> Profile Downloaded -> Install, then Settings -> General -> About -> Certificate Trust Settings -> Enable.

**Android**: Download the certificate, navigate to Settings -> Security -> Install certificate -> CA certificate.

**Windows**: Double-click the `.crt` file -> Install Certificate -> Local Machine -> Place in "Trusted Root Certification Authorities".

**macOS**: Double-click the `.crt` file -> Add to Keychain -> Trust -> "Always Trust".

### Trust Verification

After importing, restart the browser and visit `https://dashboard.lan`. A green padlock should appear with no warnings.

## Summary

The configuration provides:
- **Caddy** routing domain names to development servers
- **Local DNS** resolving `.lan` domains network-wide
- **Firewall rules** permitting LAN access

Development servers become accessible from any device:
- `https://dashboard.lan` - Services dashboard
- `https://blog.lan` - Jekyll blog
- `https://app.lan` - Frontend dev server

Port numbers and IP addresses are no longer required.

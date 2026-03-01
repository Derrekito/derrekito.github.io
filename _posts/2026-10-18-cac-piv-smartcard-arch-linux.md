---
title: "CAC/PIV Smartcard Authentication on Arch Linux"
date: 2026-10-18
categories: [Linux, Security]
tags: [arch, cac, piv, smartcard, pki, nss, pkcs11, dod]
---

Common Access Card (CAC) and Personal Identity Verification (PIV) smartcard authentication presents unique challenges on Linux systems. Unlike Windows, which includes native smartcard middleware, Linux requires manual configuration of cryptographic libraries, PKCS#11 modules, and browser security databases. This guide documents the complete implementation process for Arch Linux, enabling DoD personnel to access CAC-protected resources through Firefox and Chromium-based browsers.

## Problem Statement

Department of Defense (DoD) systems rely on CAC smartcards for two-factor authentication. The CAC contains X.509 certificates for identity verification, email encryption, and digital signatures. Government websites validate these certificates against the DoD Public Key Infrastructure (PKI) trust chain.

Several factors complicate CAC deployment on Linux:

1. **Middleware fragmentation**: Multiple PKCS#11 implementations exist (OpenSC, CoolKey, SafeNet), each with different compatibility profiles.
2. **Browser certificate stores**: Firefox uses its own Network Security Services (NSS) database, separate from the system certificate store.
3. **Trust chain requirements**: DoD root and intermediate certificates must be explicitly imported and trusted.
4. **Service dependencies**: The PC/SC daemon must run before smartcard operations function.

## Technical Background

### Public Key Infrastructure (PKI)

PKI provides the cryptographic foundation for CAC authentication. Each CAC contains multiple X.509 certificates:

- **PIV Authentication**: Primary certificate for website authentication
- **Email Signature**: For S/MIME digital signatures
- **Email Encryption**: For S/MIME encrypted communications
- **Card Authentication**: Machine-readable certificate for physical access

These certificates chain to DoD root Certificate Authorities (CAs). Without the root CA certificates installed and trusted, browsers cannot validate the certificate chain, resulting in authentication failures.

### PKCS#11 Architecture

PKCS#11 (Public Key Cryptography Standards #11) defines a platform-independent API for cryptographic tokens. The architecture consists of:

```
+------------------+
|   Application    |  (Firefox, Chrome, ssh)
+------------------+
         |
+------------------+
|  PKCS#11 Module  |  (opensc-pkcs11.so)
+------------------+
         |
+------------------+
|   PC/SC Layer    |  (pcscd)
+------------------+
         |
+------------------+
|   CCID Driver    |  (libccid)
+------------------+
         |
+------------------+
|  USB Card Reader |  (SCM SCR3500, etc.)
+------------------+
```

The OpenSC PKCS#11 module (`/usr/lib/opensc-pkcs11.so`) translates high-level cryptographic requests into smartcard commands via the PC/SC interface.

### NSS Security Databases

Mozilla's Network Security Services (NSS) maintains certificate and key storage in SQLite databases:

- **cert9.db**: Certificate storage (SQLite format)
- **key4.db**: Private key storage
- **pkcs11.txt**: PKCS#11 module configuration

Each Firefox profile maintains an independent NSS database. Chrome/Chromium uses a shared NSS database at `~/.pki/nssdb/`. Both require explicit PKCS#11 module registration and DoD certificate imports.

## Prerequisites

### Hardware Requirements

A CCID-compliant USB smartcard reader is required. Tested readers include:

| Reader | USB ID | Status |
|--------|--------|--------|
| SCM SCR3500 | 04e6:5410 | Recommended |
| HID Omnikey 3121 | 076b:3021 | Compatible |
| Alcor AU9540 | 058f:9540 | Compatible |

Verify reader detection:

```bash
lsusb | grep -i smart
```

### Software Packages

The following packages provide smartcard infrastructure on Arch Linux:

| Package | Purpose |
|---------|---------|
| `pcsclite` | PC/SC daemon and libraries |
| `ccid` | USB CCID driver for smartcard readers |
| `opensc` | OpenSC smartcard tools and PKCS#11 module |
| `nss` | Network Security Services (certutil, modutil) |
| `pcsc-tools` | Diagnostic utilities (pcsc_scan) |
| `firefox` | Web browser with NSS support |

Package installation:

```bash
sudo pacman -S pcsclite ccid nss opensc pcsc-tools firefox
```

## Implementation

### PC/SC Service Configuration

The PC/SC daemon (`pcscd`) provides the smartcard communication layer. Socket activation ensures the service starts on demand:

```bash
sudo systemctl enable pcscd.socket
sudo systemctl start pcscd.socket
```

Verify the OpenSC PKCS#11 library exists:

```bash
ls -l /usr/lib/opensc-pkcs11.so
```

### Smartcard Reader Verification

Insert the CAC into the reader and verify detection:

```bash
pcsc_scan
```

Expected output includes reader identification and ATR (Answer To Reset) data:

```
Reader 0: SCM Microsystems Inc. SCR 3500 A Contact Reader 00 00
  Event number: 0
  Card state: Card inserted,
  ATR: 3B DB 96 00 80 1F 03 00 31 C0 64 77 E3 03 00 82 90 00
```

### Firefox Profile Detection

Firefox stores profiles in `~/.mozilla/firefox/`. Profile directories follow the pattern `*.default*`:

```bash
find ~/.mozilla/firefox -maxdepth 1 -name "*.default*" -type d
```

If no profiles exist, create one:

```bash
firefox --ProfileManager
```

### DoD Certificate Acquisition

The DoD PKI certificates are distributed through MilitaryCAC. Download and extract:

```bash
wget -qP /tmp "https://militarycac.com/maccerts/AllCerts.zip"
unzip -qo /tmp/AllCerts.zip -d /tmp/AllCerts
```

The archive contains root and intermediate CA certificates in DER format (`.cer` files).

### NSS Database Initialization

Each browser profile requires NSS database initialization and configuration. The process applies to both Firefox profiles and the Chrome/Chromium shared database.

#### Firefox Profile Configuration

For each Firefox profile directory:

```bash
PROFILE_DIR="$HOME/.mozilla/firefox/xxxxxxxx.default-release"

# Remove existing databases (clean initialization)
rm -f "$PROFILE_DIR"/{cert9.db,key4.db,pkcs11.txt}

# Initialize empty NSS database
certutil -d sql:"$PROFILE_DIR" -N --empty-password
```

#### Chrome/Chromium Configuration

Chrome and Chromium share a single NSS database:

```bash
CHROME_DIR="$HOME/.pki/nssdb"
mkdir -p "$CHROME_DIR"

rm -f "$CHROME_DIR"/{cert9.db,key4.db,pkcs11.txt}
certutil -d sql:"$CHROME_DIR" -N --empty-password
```

### PKCS#11 Module Registration

Register the OpenSC PKCS#11 module with each NSS database:

```bash
modutil -dbdir sql:"$PROFILE_DIR" -add "OpenSC-PKCS11" \
        -libfile /usr/lib/opensc-pkcs11.so -force
```

Verify registration:

```bash
modutil -dbdir sql:"$PROFILE_DIR" -list | grep -i OpenSC
```

### Certificate Import

Import all DoD certificates from the extracted archive:

```bash
for cert in /tmp/AllCerts/*.cer; do
    cert_name="$(basename "$cert")"
    certutil -d sql:"$PROFILE_DIR" -A -t "CT,," -n "$cert_name" -i "$cert"
done
```

The trust flags `CT,,` indicate:

- **C**: Trusted CA for client authentication
- **T**: Trusted CA for email (S/MIME)
- Third position (empty): Code signing trust (not set)

#### Root Certificate Trust

DoD root certificates require elevated trust settings:

```bash
for root_cert in DoDRoot3.cer DoDRoot4.cer DoDRoot5.cer DoDRoot6.cer; do
    certutil -d sql:"$PROFILE_DIR" -M -t "CT,C,C" -n "$root_cert"
done
```

The trust flags `CT,C,C` grant full trust for SSL/TLS, email, and code signing.

### File Permissions

NSS database files require appropriate ownership:

```bash
chown "$USER":"$USER" "$PROFILE_DIR"/{cert9.db,key4.db,pkcs11.txt}
chmod 600 "$PROFILE_DIR"/{cert9.db,key4.db,pkcs11.txt}
```

## Browser Configuration

### Firefox Verification

1. Navigate to **Settings** > **Privacy & Security** > **Security Devices**
2. Verify "OpenSC-PKCS11" appears in the module list
3. With CAC inserted, the module should show certificate slots

If the module is missing, load manually:

1. Click **Load**
2. Module Name: `OpenSC-PKCS11`
3. Module filename: `/usr/lib/opensc-pkcs11.so`

### Chrome/Chromium Verification

1. Navigate to **Settings** > **Privacy and Security** > **Security** > **Manage certificates**
2. Select the **Authorities** tab
3. Verify DoD root certificates appear (DoD Root CA 3, 4, 5, 6)

Chrome loads PKCS#11 modules through `~/.pki/nssdb/pkcs11.txt` automatically.

### Authentication Test

Access a CAC-protected resource to verify configuration:

1. Insert CAC into reader
2. Navigate to a DoD CAC-enabled site
3. A certificate selection dialog should appear
4. Select "Certificate for PIV Authentication"
5. Enter CAC PIN when prompted

## Verification Procedures

### PKCS#11 Object Enumeration

List objects accessible through the PKCS#11 module:

```bash
pkcs11-tool --module /usr/lib/opensc-pkcs11.so --list-objects
```

Expected output includes certificate and public key objects for each CAC certificate.

### Certificate Chain Verification

Verify imported certificates:

```bash
certutil -d sql:"$PROFILE_DIR" -L | grep -E 'DoDRoot[3-6]'
```

### Module Registration Status

Confirm PKCS#11 module presence:

```bash
certutil -d sql:"$PROFILE_DIR" -U | grep -i OpenSC
```

## Troubleshooting

### Reader Not Detected

**Symptom**: `pcsc_scan` reports "Scanning present readers" indefinitely with no reader listed.

**Resolution**:

1. Verify USB connection: `lsusb | grep -i smart`
2. Check CCID driver loading: `dmesg | grep -i ccid`
3. Restart PC/SC daemon: `sudo systemctl restart pcscd.socket`
4. Verify reader permissions: `ls -l /dev/bus/usb/*/*`

### Card Not Recognized

**Symptom**: Reader detected but `pcsc_scan` shows "Card state: Card removed" despite card insertion.

**Resolution**:

1. Reinsert card firmly
2. Test card in another reader
3. Clean card contacts
4. Verify card is not expired

### Certificate Selection Dialog Missing

**Symptom**: Browser does not prompt for certificate selection on CAC-protected sites.

**Resolution**:

1. Verify PKCS#11 module loaded: Check browser security device settings
2. Confirm CAC inserted and reader operational: `pkcs11-tool --module /usr/lib/opensc-pkcs11.so --list-slots`
3. Clear browser cache and restart
4. Verify site requires client certificate authentication

### PIN Prompt Not Appearing

**Symptom**: Certificate dialog appears but no PIN prompt follows selection.

**Resolution**:

1. Some sites cache PIN entry; restart browser to clear
2. Verify OpenSC middleware handles PIN dialog: `pkcs11-tool --module /usr/lib/opensc-pkcs11.so --login --list-objects`
3. Check for PIN caching in `~/.config/opensc/opensc.conf`

### Certificate Chain Errors

**Symptom**: Browser reports "SEC_ERROR_UNKNOWN_ISSUER" or similar trust errors.

**Resolution**:

1. Verify DoD root certificates imported:
   ```bash
   certutil -d sql:"$PROFILE_DIR" -L | grep DoD
   ```
2. Verify trust settings on root certificates:
   ```bash
   certutil -d sql:"$PROFILE_DIR" -L -n "DoDRoot3.cer"
   ```
3. Re-import certificates if trust flags incorrect

### Multiple Firefox Profiles

If multiple Firefox profiles exist, each requires independent configuration. The setup script iterates through all `*.default*` profile directories automatically.

## Automated Setup Script

A complete setup script handles all configuration steps. The script requires root privileges to install packages and manage services, but configures NSS databases for the invoking user.

Script location: `~/.scripts/cac_setup_arch.sh`

Execution:

```bash
sudo ~/.scripts/cac_setup_arch.sh
```

The script performs:

1. Package installation via pacman
2. PC/SC service enablement
3. Firefox profile detection
4. Chrome NSS database creation
5. DoD certificate download and import
6. PKCS#11 module registration
7. Trust configuration for root certificates
8. Permission correction for NSS files

## Security Considerations

### Certificate Trust

Importing DoD certificates establishes trust for all certificates issued by the DoD PKI. This configuration is appropriate for DoD systems but may not be suitable for general-purpose machines.

### PIN Security

CAC PINs protect private key operations. The PIN is never transmitted over the network; cryptographic operations occur on the smartcard itself. PIN caching behavior depends on OpenSC configuration.

### Database Permissions

NSS database files contain trust settings and potentially cached credentials. Restrictive permissions (600) prevent unauthorized access.

## References

- [Arch Wiki: Smartcards](https://wiki.archlinux.org/title/Smartcards)
- [OpenSC Documentation](https://github.com/OpenSC/OpenSC/wiki)
- [NSS Tools Documentation](https://firefox-source-docs.mozilla.org/security/nss/legacy/tools/index.html)
- [MilitaryCAC Linux Instructions](https://militarycac.com/linux.htm)
- [DoD PKI/PKE Information](https://public.cyber.mil/pki-pke/)

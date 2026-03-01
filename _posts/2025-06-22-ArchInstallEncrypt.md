---
title: "Arch Linux Installation Guide with Full Root Encryption"
date: 2025-06-22
categories: [Linux, Installation]
tags: [arch, luks, encryption, grub, uefi]
pin: true
---

# Arch Linux Installation Guide with Full Root Encryption

This guide provides a step-by-step process for installing Arch Linux with **full root partition encryption** using **LUKS** and **GRUB**. Two methods are covered: a **fresh installation** (recommended, organized into multiple sections) and **encryption of an existing installation**. This guide builds on the [Arch Wiki Installation Guide](https://wiki.archlinux.org/title/Installation_guide).

## General Assumptions

- **Installer**: System booted into the Arch Linux ISO live environment.
- **Secure Boot**: Disabled and in setup mode.
- **Bootloader**: GRUB with UEFI.
- **/boot**: Unencrypted, separate from root (`/`).
- **Root Partition (`/`)**: Encrypted with LUKS.
- **Hardware**: UEFI system with sufficient disk space.
- **Network**: Internet access required.
- **Backup**: Critical data backed up.

> **Warning**: Partitioning and encryption modify the disk. **Backup all data** and verify device names (e.g., `/dev/nvme0n1pX`) with `lsblk -f`.

---

## Section 1: Configure Installer Environment

This section covers the Arch ISO live environment setup.

### 1.1 Set Console Keyboard Layout and Font

```bash
loadkeys us
setfont ter-116n  # Optional
```

List options if needed:

```bash
ls /usr/share/kbd/keymaps/**/*.map.gz
ls /usr/share/kbd/consolefonts/
```

### 1.2 Verify Boot Mode

Confirm UEFI mode:

```bash
ls /sys/firmware/efi/efivars
```

If empty, enable UEFI in BIOS.

### 1.3 Connect to the Internet

Wired (DHCP):

```bash
systemctl start dhcpcd
```

Wi-Fi:

The following example assumes the device name is wlan0. Run `iwctl device list` to identify the hardware configuration.
```bash
iwctl
device list
station wlan0 scan
station wlan0 get-networks
station wlan0 connect "SSID"
station wlan0 show
exit
```

Test:

```bash
ping archlinux.org
```

### 1.4 Update System Clock

```bash
timedatectl set-ntp true
timedatectl status
```

---

## Section 2: Partition the Disk

Configure the disk for UEFI with GPT.

### 2.1 Partition Layout

| Mount Point | Partition        | Partition Type        | Suggested Size         |
| ----------- | ---------------- | --------------------- | ---------------------- |
| `/boot/efi` | `/dev/nvme0n1p1` | EFI System Partition  | 1 GiB                  |
| `/boot`     | `/dev/nvme0n1p2` | Linux Filesystem      | 1 GiB                  |
| `[SWAP]`    | `/dev/nvme0n1p3` | Linux Swap            | At least 4 GiB         |
| `/`         | `/dev/nvme0n1p4` | Linux x86-64 Root (/) | 23–32 GiB or remainder |

### 2.2 Create Partitions

## Section 2: Partition the Disk

Partition `/dev/nvme0n1` for UEFI with GPT to support LUKS encryption and GRUB. A separate EFI partition is required for UEFI booting.

> **CRITICAL WARNING**: Partitioning **erases all data** on `/dev/nvme0n1`. **Back up all data** to an external drive. Run `lsblk -f` to confirm `/dev/nvme0n1`. Wrong disk selection results in data loss. To encrypt an existing Arch installation, **skip to Section 8**. For recovery procedures, see **Section 10**.

### 2.1 Verify Disk

```bash
lsblk -f
```

Example:
```text
NAME        FSTYPE       LABEL  UUID                                 MOUNTPOINT
nvme0n1
├─nvme0n1p1 vfat                <UUID>                             [none]
├─nvme0n1p2 ext4                <UUID>                             [none]
├─nvme0n1p3 swap                <UUID>                             [none]
└─nvme0n1p4 crypto_LUKS         <UUID>                             [none]
```

If partitions exist and data preservation is required, **stop**. Use **Section 8** or **10**. Proceed only for fresh installation.

### 2.2 Create Partitions

---

```bash
fdisk /dev/nvme0n1
```

In `fdisk` (GPT setup):

1. **Create a new GPT partition table**:

   ```text
   Command (m for help): g
   ```

2. **EFI System Partition** (for UEFI bootloader like `grubx64.efi`):

   ```text
   Command (m for help): n
   Partition number: 1
   First sector: (press Enter)
   Last sector: +1G
   Command (m for help): t
   Partition number: 1
   Partition type: 1  # or type `L` and select "EFI System"
   ```

3. **Boot Partition** (for kernel and initramfs, unencrypted):

   ```text
   Command (m for help): n
   Partition number: 2
   First sector: (press Enter)
   Last sector: +1G
   Command (m for help): t
   Partition number: 2
   Partition type: Linux filesystem
   ```

4. **Swap Partition** (virtual memory, may be encrypted later):

   ```text
   Command (m for help): n
   Partition number: 3
   First sector: (press Enter)
   Last sector: +4G
   Command (m for help): t
   Partition number: 3
   Partition type: Linux swap
   ```

5. **Root Partition** (encrypted root filesystem, `/`):

   ```text
   Command (m for help): n
   Partition number: 4
   First sector: (press Enter)
   Last sector: (press Enter to use remaining space)
   Command (m for help): t
   Partition number: 4
   Partition type: Linux filesystem
   ```

6. **Write changes and exit**:

   ```text
   Command (m for help): w
   ```

---

**Verify layout:**

```bash
fdisk -l /dev/nvme0n1
```

**Expected output:**

```text
/dev/nvme0n1p1  ... 1G EFI System
/dev/nvme0n1p2  ... 1G Linux filesystem
/dev/nvme0n1p3  ... 4G Linux swap
/dev/nvme0n1p4  ...    Linux filesystem
```

---

**Partition Layout Summary**

| Mount Point | Partition        | Type               | Size      |
| ----------- | ---------------- | ------------------ | --------- |
| `/boot/efi` | `/dev/nvme0n1p1` | EFI System (FAT32) | 1 GiB     |
| `/boot`     | `/dev/nvme0n1p2` | Linux (ext4)       | 1 GiB     |
| `[SWAP]`    | `/dev/nvme0n1p3` | Linux Swap         | 4 GiB     |
| `/`         | `/dev/nvme0n1p4` | Linux (ext4)       | Remainder |

---

### 2.3 Format Partitions (Non-Encrypted)

```bash
mkfs.fat -F32 /dev/nvme0n1p1  # EFI
mkfs.ext4 /dev/nvme0n1p2      # Boot
```

Swap and root partitions are formatted later (after encryption setup, if applicable).

> **Note**: A separate `/boot/efi` (FAT32) is required for UEFI systems to store the bootloader (`grubx64.efi`). The unencrypted `/boot` (ext4) holds the kernel and initramfs. A single `/boot` partition is not recommended due to UEFI compatibility constraints and FAT32's 4 GiB file size limitation.

---
## Section 3: Method 1 – Set Up LUKS Encryption

This section covers LUKS encryption setup for the root partition.

### 3.1 Encrypt Root Partition

```bash
cryptsetup luksFormat /dev/nvme0n1p4
cryptsetup open /dev/nvme0n1p4 cryptroot
mkfs.ext4 /dev/mapper/cryptroot
```

### 3.2 Configure Swap (Optional Encryption)

- **Unencrypted Swap**:

```bash
mkswap /dev/nvme0n1p3
swapon /dev/nvme0n1p3
```

- **Encrypted Swap** (random key per boot):

```bash
cryptsetup open --type plain -d /dev/urandom /dev/nvme0n1p3 cryptswap
mkswap /dev/mapper/cryptswap
swapon /dev/mapper/cryptswap
```

---

## Section 4: Method 1 – Mount Filesystems and Install Base System

This section covers partition mounting and base system installation.

### 4.1 Mount Filesystems

```bash
mount /dev/mapper/cryptroot /mnt
mkdir /mnt/boot
mount /dev/nvme0n1p2 /mnt/boot
mkdir /mnt/boot/efi
mount /dev/nvme0n1p1 /mnt/boot/efi
```

### 4.2 Install Base System

```bash
pacstrap /mnt base linux linux-firmware base-devel \
vim sudo networkmanager man-db man-pages bash-completion \
inetutils grub efibootmgr mkinitcpio lvm2 \
dosfstools e2fsprogs
```

---

## Package Descriptions

| Package           | Purpose                                                                |
| ----------------- | ---------------------------------------------------------------------- |
| `base`            | Core system utilities                                                  |
| `linux`           | Kernel                                                                 |
| `linux-firmware`  | Firmware for wireless/network/GPU devices                              |
| `base-devel`      | Required to build AUR packages with `makepkg` (e.g., for `yay`)        |
| `vim`             | Text editor (available in ISO unlike `nano`)                           |
| `sudo`            | Privilege escalation for non-root users                                |
| `networkmanager`  | Versatile networking daemon                                            |
| `man-db`          | `man` command                                                          |
| `man-pages`       | System manual pages                                                    |
| `bash-completion` | Tab completion for bash                                                |
| `inetutils`       | Provides `hostname`, `ping`, and other basic networking tools          |
| `grub`            | Required for bootloader installation                                   |
| `efibootmgr`      | Required for EFI bootloader setup                                      |
| `mkinitcpio`      | Builds the initramfs (hook system for encryption, filesystems, etc.)   |
| `lvm2`            | Required for LVM volumes (including encrypted systems)                 |
| `dosfstools`      | Required for EFI partition formatting with `mkfs.fat -F32`             |
| `e2fsprogs`       | Includes `fsck`, `mkfs.ext4`, and tools for ext4 filesystems           |

### 4.3 Generate fstab

```bash
genfstab -U /mnt >> /mnt/etc/fstab
```

Add encrypted swap (if applicable):

```bash
echo "/dev/mapper/cryptswap  none  swap  sw  0  0" >> /mnt/etc/fstab
```

Verify `/mnt/etc/fstab`:

```text
/dev/mapper/cryptroot  /  ext4  defaults  0  1
```

---

## Section 5: Method 1 – Configure System and Encryption

This section covers installed system and encryption settings configuration.

### 5.1 Chroot and Set Up Basics

```bash
arch-chroot /mnt
```

Configure:

```bash
ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "arch" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
passwd
```

### 5.2 Configure Encryption

---

### 5.2 Configure Encryption

Get the UUID of the encrypted root partition:

```bash
blkid -s UUID -o value /dev/nvme0n1p4
```

Append it to `/etc/crypttab`:

```bash
echo "cryptroot UUID=$(blkid -s UUID -o value /dev/nvme0n1p4) none luks" >> /etc/crypttab
```

When re-running this guide or if uncertain, inspect the file to avoid duplicates:

```bash
vim /etc/crypttab
```

Ensure only one `cryptroot` entry exists and that it matches the UUID of `/dev/nvme0n1p4`.

#### Encrypted Swap (Optional):

For encrypted swap with a random key per boot, add:

```bash
echo "cryptswap /dev/nvme0n1p3 /dev/urandom swap" >> /etc/crypttab
```

Then verify:

```bash
vim /etc/crypttab
```

Remove any duplicate `cryptswap` or `cryptroot` entries. Duplicates can cause boot hangs or cryptsetup errors.

### 5.3 Configure Initramfs

Edit `/etc/mkinitcpio.conf`:

```ini
HOOKS=(base udev autodetect kms keyboard keymap consolefont modconf block encrypt filesystems fsck)
```

Regenerate:

```bash
mkinitcpio -P
```

---

## Section 6: Method 1 – Install and Configure GRUB

This section covers GRUB setup for booting the encrypted system.

### 6.1 Install GRUB

```bash
pacman -S grub efibootmgr
```

### 6.2 Configure GRUB

### 1. Get the UUID of the encrypted root partition:

```bash
blkid -s UUID -o value /dev/nvme0n1p4
```

Example output:

```text
e1c4fafe-73c5-47b9-bc91-5f1ae7a9ef10
```

### 2. Edit `/etc/default/grub` with the UUID value:

```bash
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet cryptdevice=UUID=e1c4fafe-73c5-47b9-bc91-5f1ae7a9ef10:cryptroot root=/dev/mapper/cryptroot"
```

Install and generate config:

```bash
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
```

---

## Section 7: Method 1 – Reboot and Verify

This section covers finalization and installation verification.

### 7.1 Exit and Reboot

```bash
exit
umount -R /mnt
swapoff -a  # If swap is active
reboot
```

### 7.2 Verify Installation

- Confirm LUKS password prompt at boot.
- Check mounts:

```bash
lsblk
# Verify /dev/mapper/cryptroot is mounted on /
```

- Verify kernel parameters:

```bash
cat /proc/cmdline
# Should include cryptdevice=...
```

---

## Section 8: Method 2 – Encrypt Existing Arch Installation

This section covers encryption of an existing Arch Linux root partition.

### 8.1 Boot into Arch ISO

Boot the Arch ISO and verify:

```bash
lsblk -f
```

Identify:
- Root (`/dev/nvme0n1p4`).
- Boot (`/dev/nvme0n1p2`).
- EFI (`/dev/nvme0n1p1`).
- Swap (`/dev/nvme0n1p3`).

### 8.2 Backup Root Filesystem

```bash
mount /dev/nvme0n1p4 /mnt
mkdir /backup
rsync -aAXv /mnt/ /backup/
```

> Verify backup integrity.

### 8.3 Encrypt Root Partition

> **Warning**: This operation destroys the root partition.

```bash
cryptsetup luksFormat /dev/nvme0n1p4
cryptsetup open /dev/nvme0n1p4 cryptroot
mkfs.ext4 /dev/mapper/cryptroot
mount /dev/mapper/cryptroot /mnt
```

### 8.4 Restore Backup

```bash
rsync -aAXv /backup/ /mnt/
mount /dev/nvme0n1p2 /mnt/boot
mount /dev/nvme0n1p1 /mnt/boot/efi
```

### 8.5 Configure Encryption

Edit `/mnt/etc/crypttab`:

```bash
echo "cryptroot UUID=$(blkid -s UUID -o value /dev/nvme0n1p4) none luks" >> /mnt/etc/crypttab
```

Update `/mnt/etc/fstab`:

```text
/dev/mapper/cryptroot  /  ext4  defaults  0  1
```

### 8.6 Chroot and Update System

```bash
arch-chroot /mnt
```

Edit `/etc/mkinitcpio.conf`:

```ini
HOOKS=(base udev autodetect keyboard keymap consolefont modconf block encrypt microcode filesystems fsck)
```

Regenerate:

```bash
mkinitcpio -P
```

### 8.7 Update GRUB

Edit `/etc/default/grub`:

```bash
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet cryptdevice=UUID=$(blkid -s UUID -o value /dev/nvme0n1p4):cryptroot root=/dev/mapper/cryptroot"
```

Regenerate:

```bash
grub-mkconfig -o /boot/grub/grub.cfg
```

### 8.8 Exit and Reboot

```bash
exit
umount -R /mnt
reboot
```

### 8.9 Post-Boot Checks

- Confirm LUKS prompt.
- Verify mounts:

```bash
lsblk
```

- Check kernel parameters:

```bash
cat /proc/cmdline
```

---

## Section 9: Optional – Enable Secure Boot

1. Install `sbctl`:

```bash
pacman -S sbctl
```

2. Create and enroll keys:

```bash
sbctl create-keys
sbctl enroll-keys
```

3. Sign binaries:

```bash
sbctl sign -s /boot/efi/EFI/GRUB/grubx64.efi
sbctl sign -s /boot/vmlinuz-linux
```

4. Enable Secure Boot in BIOS and reboot.

5. Verify:

```bash
sbctl status
```

---

## Section 10: Notes and Troubleshooting

### Common Boot Failures

* **Hangs after password prompt with `/dev/mapper/cryptroot: clean`**

  * The system may not be hung; it may be slow or stuck on a failing service.
  * At GRUB, press `e`, add `systemd.unit=multi-user.target` at the end of the `linux` line, boot, and check `systemctl blame` and `journalctl -xb`.

* **Failed to start Remount Root and Kernel File Systems**

  * Typically caused by:

    * Broken or duplicated lines in `/etc/fstab`
    * Missing `cryptroot` or `cryptswap` entries in `/etc/crypttab`
    * Mistyped UUIDs or invalid `mapper` devices

---

### `read swap header failed`

* For encrypted swap with a random key:

  ```bash
  cryptsetup open --type plain -d /dev/urandom /dev/nvme0n1p3 cryptswap
  mkswap /dev/mapper/cryptswap
  swapon /dev/mapper/cryptswap
  ```

* Do not run `mkswap` inside the chroot unless the device was properly opened from the host.

* `fstab` should contain:

  ```text
  /dev/mapper/cryptswap none swap sw 0 0
  ```

* `crypttab` should contain:

  ```text
  cryptswap /dev/nvme0n1p3 /dev/urandom swap
  ```

---

### Missing GRUB Files (e.g., `grubx64.efi`, `core.efi`)

* This occurs if `pacstrap` was run but `/boot/efi` was not mounted, or if `rsync` skipped boot partitions.
* Resolution:

  ```bash
  grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
  grub-mkconfig -o /boot/grub/grub.cfg
  ```

---

### `genfstab` not found in chroot

* The command is in the `arch-install-scripts` package, which may not be present in the installed system:

  ```bash
  pacman -S arch-install-scripts
  genfstab -U / >> /etc/fstab
  ```

---

### `fstab` issues from nested or extra mounts

* After copying from or mounting backup systems, extraneous entries may appear:

  ```text
  UUID=xxxx /mnt/extra ext4 ...
  ```

  Remove such entries unless explicitly required for boot.

---

### Slow Boot Analysis

* Use `systemd-analyze` to check boot time:

  ```bash
  systemd-analyze
  systemd-analyze blame
  ```
* Common causes:

  * `NetworkManager-wait-online.service`
  * Missing swap devices
  * Invalid UUIDs


---

## Section 11: Post-Installation Setup

After installing Arch Linux with root encryption (Method 1 or Method 2), configure the system for daily use. This section covers AUR helper (`yay`) setup, user creation, networking enablement, and essential package installation.

### 11.1 Create a User Account

Create a non-root user for security and daily use:

```bash
useradd -m -G wheel username  # Replace 'username' with the desired name
passwd username
```

Grant the user `sudo` privileges:

```bash
pacman -S sudo
EDITOR=nano visudo
```

Uncomment the line to allow `wheel` group `sudo` access:

```ini
%wheel ALL=(ALL:ALL) ALL
```

### 11.2 Enable Networking

Set up networking for the installed system (the live environment uses `dhcpcd` or `iwctl`).

- **For wired connections (simple)**:

Install and enable `dhcpcd`:

```bash
pacman -S dhcpcd
systemctl enable dhcpcd@eth0  # Replace 'eth0' with the interface (check with 'ip link')
```

- **For versatile networking (wired and Wi-Fi)**:

Install `NetworkManager`:

```bash
pacman -S networkmanager
systemctl enable NetworkManager
```

Configure with `nmtui` (terminal UI) or `nmcli`:

```bash
nmtui  # Follow prompts to set up wired or Wi-Fi
```

Verify connectivity:

```bash
ping archlinux.org
```

### 11.3 Install an AUR Helper (yay)

The Arch User Repository (AUR) provides community packages. Install `yay` to manage AUR packages.

1. Install dependencies:

```bash
pacman -S base-devel git
```

2. Clone and build `yay`:

```bash
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
```

3. Verify `yay` installation:

```bash
yay --version
```

4. Update system and AUR packages:

```bash
yay -Syu
```

> **Note**: Run `yay` as a non-root user. Use `yay -S package` to install AUR packages (e.g., `yay -S google-chrome`).

### 11.4 Install Common Packages

Install essential tools for a functional system:

```bash
pacman -S vim bash-completion man-db man-pages texinfo
```

### 11.5 Additional Configuration

Enhance the system with optional tools and settings.

- **Enable automatic updates** (optional):

Install `pacman-contrib` for package cache management:

```bash
pacman -S pacman-contrib
systemctl enable paccache.timer  # Cleans package cache weekly
```

Install `auracle` for lightweight AUR update checking:

```bash
yay -S auracle  # CLI tool to query AUR updates
```

Check for AUR updates manually:

```bash
auracle sync  # Lists available AUR package updates
```

To automate AUR update checks, create a systemd timer (optional):

1. Create a script to check updates:

```bash
sudo vim /usr/local/bin/check-aur-updates.sh
```

Add:

```bash
#!/bin/bash
auracle sync
```

Save and exit (`:wq` in `vim`). Make it executable:

```bash
sudo chmod +x /usr/local/bin/check-aur-updates.sh
```

2. Create a systemd service:

```bash
sudo vim /etc/systemd/system/aur-update-check.service
```

Add:

```ini
[Unit]
Description=Check for AUR updates
[Service]
Type=oneshot
ExecStart=/usr/local/bin/check-aur-updates.sh
```

Save and exit.

3. Create a systemd timer:

```bash
sudo vim /etc/systemd/system/aur-update-check.timer
```

Add:

```ini
[Unit]
Description=Daily AUR update check
[Timer]
OnCalendar=daily
Persistent=true
[Install]
WantedBy=timers.target
```

Save and exit. Enable and start the timer:

```bash
systemctl enable --now aur-update-check.timer
```

> **Note**: `auracle sync` only lists updates. To apply updates, run `yay -Syu` as a non-root user. The timer logs updates to `/var/log/systemd` (view with `journalctl -u aur-update-check`).

- **Set up a firewall** (optional):

```bash
pacman -S ufw
systemctl enable ufw
ufw enable
```

- **Check system logs**:

```bash
journalctl -b  # View boot logs for errors
```


### 11.6 Reboot

Reboot to ensure all services (e.g., networking, display manager) start correctly:

```bash
reboot
```

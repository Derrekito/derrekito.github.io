---
title: "A Simple rsync Backup Script with Smart Excludes"
date: 2026-03-03
categories: [Automation, DevOps]
tags: [bash, rsync, backup, linux, automation]
---

Backups don't need to be complicated. This post presents a single-file rsync wrapper that handles the common cases: excluding development cruft, resuming interrupted transfers, and optionally verifying checksums.

## The Problem

You have directories to back up regularly:
- Project folders with `node_modules` and `__pycache__` bloat
- Data directories that shouldn't include virtual environments
- Large transfers that might get interrupted

You want a script that:
- Excludes development artifacts automatically
- Resumes partial transfers
- Logs everything for debugging
- Optionally verifies file integrity

## The Script

```bash
#!/bin/bash

set -euo pipefail

print_usage() {
    echo "Usage: $0 --src=SOURCE_DIR --dest=DEST_DIR [--verify|-v]"
    echo
    echo "Options:"
    echo "  --src=DIR       Absolute path to source directory"
    echo "  --dest=DIR      Absolute path to destination directory"
    echo "  --verify, -v    Enable checksum-based verification (slower but safer)"
    echo "  --help, -h      Show this help message"
    exit 1
}

# Parse arguments
SRC=""
DEST=""
USE_CHECKSUM=0

for arg in "$@"; do
    case "$arg" in
        --src=*)
            SRC="${arg#*=}"
            ;;
        --dest=*)
            DEST="${arg#*=}"
            ;;
        --verify|-v)
            USE_CHECKSUM=1
            ;;
        --help|-h)
            print_usage
            ;;
        *)
            echo "Unknown argument: $arg"
            print_usage
            ;;
    esac
done

# Validate arguments
if [[ -z "$SRC" || -z "$DEST" ]]; then
    echo "Error: --src and --dest are required."
    print_usage
fi

# Log file
LOGFILE="$HOME/rsync-backup.log"
mkdir -p "$(dirname "$LOGFILE")"

log_message() {
    echo "$1" | tee -a "$LOGFILE"
}

log_message "Starting rsync from $SRC to $DEST on $(date)"
[[ $USE_CHECKSUM -eq 1 ]] && log_message "Checksum verification mode ENABLED"

# Validate source
if [[ ! -d "$SRC" ]]; then
    log_message "Error: Source directory $SRC does not exist"
    exit 1
fi

# Create destination if missing
if [[ ! -d "$DEST" ]]; then
    log_message "Creating destination directory $DEST"
    mkdir -p "$DEST"
fi

# Create temporary exclude file
EXCLUDE_FILE="$(mktemp /tmp/rsync-exclude.XXXXXX)"
cat > "$EXCLUDE_FILE" <<EOF
venv/
.venv/
**/node_modules/
**/__pycache__/
**/.mypy_cache/
**/.pytest_cache/
.DS_Store
EOF

# Build rsync options
RSYNC_OPTS=(-aP
    --partial --partial-dir=.rsync-partials
    --log-file="$LOGFILE"
    --exclude-from="$EXCLUDE_FILE"
)

# Add checksum if requested
[[ $USE_CHECKSUM -eq 1 ]] && RSYNC_OPTS+=(--checksum)

# Run rsync
rsync "${RSYNC_OPTS[@]}" "$SRC" "$DEST"

if [[ $? -eq 0 ]]; then
    log_message "Rsync completed successfully on $(date)"
else
    log_message "Error: Rsync failed with exit code $?"
    rm -f "$EXCLUDE_FILE"
    exit 1
fi

rm -f "$EXCLUDE_FILE"
```

## Key Features

### Smart Excludes

The script automatically skips common development artifacts:

| Pattern | Purpose |
|---------|---------|
| `venv/`, `.venv/` | Python virtual environments |
| `**/node_modules/` | npm dependencies (often gigabytes) |
| `**/__pycache__/` | Python bytecode cache |
| `**/.mypy_cache/` | Type checker cache |
| `**/.pytest_cache/` | Test runner cache |
| `.DS_Store` | macOS metadata files |

These patterns use `**` to match at any depth in the directory tree.

### Resumable Transfers

The script uses `--partial` with a dedicated partial directory:

```bash
--partial --partial-dir=.rsync-partials
```

If a transfer is interrupted mid-file, rsync saves the partial file in `.rsync-partials/`. On the next run, it resumes from where it left off rather than starting over. This is essential for large files over unreliable connections.

### Checksum Verification

By default, rsync uses file size and modification time to detect changes. With `--verify`, the script adds `--checksum` to force byte-level comparison:

```bash
# Fast mode (default) - uses mtime and size
./backup.sh --src=/data --dest=/backup

# Verification mode - computes checksums
./backup.sh --src=/data --dest=/backup --verify
```

Use verification mode when:
- Backing up to a new destination for the first time
- Recovering from a failed or interrupted backup
- Verifying backup integrity periodically

### Logging

All operations log to `~/rsync-backup.log`:

```
Starting rsync from /mnt/extra/ to /mnt/backup/ on Mon Mar  3 14:32:01 MST 2026
Checksum verification mode ENABLED
Rsync completed successfully on Mon Mar  3 14:47:23 MST 2026
```

The log includes rsync's detailed transfer log, useful for debugging failed transfers or auditing what changed.

## Usage Examples

### Basic Backup

```bash
./backup.sh --src=/home/user/projects --dest=/mnt/backup/projects
```

### External Drive Backup

```bash
# Mount point to USB drive
./backup.sh --src=/home/user --dest=/run/media/user/BackupDrive/home
```

### Network Backup (via mounted share)

```bash
# NFS or CIFS mount
./backup.sh --src=/var/data --dest=/mnt/nas/backups/data
```

### Periodic Verification

```bash
# Weekly cron job with verification
0 3 * * 0 /opt/backup.sh --src=/data --dest=/backup --verify
```

## Extending the Script

### Add More Excludes

Edit the heredoc to add project-specific exclusions:

```bash
cat > "$EXCLUDE_FILE" <<EOF
venv/
.venv/
**/node_modules/
**/__pycache__/
**/.mypy_cache/
**/.pytest_cache/
.DS_Store
# Add your own
*.log
*.tmp
build/
dist/
.git/
EOF
```

### Dry Run Mode

Add a `--dry-run` flag to preview changes:

```bash
--dry-run|-n)
    DRY_RUN=1
    ;;
```

Then add to rsync options:

```bash
[[ $DRY_RUN -eq 1 ]] && RSYNC_OPTS+=(--dry-run)
```

### Remote Destinations

rsync natively supports SSH destinations:

```bash
./backup.sh --src=/data --dest=user@server:/backup/data
```

The script works unchanged—rsync handles the SSH transport.

## Installation

```bash
# Download
curl -o ~/bin/backup.sh https://raw.githubusercontent.com/Derrekito/emergency_backup/main/backup.sh

# Make executable
chmod +x ~/bin/backup.sh

# Verify rsync is installed
rsync --version
```

On Arch Linux:

```bash
sudo pacman -S rsync
```

## Summary

| Feature | Implementation |
|---------|----------------|
| Exclude dev artifacts | Temporary exclude file with common patterns |
| Resume interrupted transfers | `--partial --partial-dir` |
| Verify integrity | `--checksum` flag |
| Logging | `--log-file` + tee to console |
| Progress display | `-P` flag (progress + partial) |

This script handles 90% of backup scenarios in under 130 lines. For more complex needs like incremental snapshots or deduplication, consider tools like `restic` or `borg`—but for straightforward directory mirroring, rsync with smart defaults gets the job done.

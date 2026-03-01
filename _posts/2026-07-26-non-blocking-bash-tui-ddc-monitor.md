---
title: "Non-Blocking Bash TUI for DDC/CI Monitor Control"
date: 2026-07-26 10:00:00 -0700
categories: [Linux, Automation]
tags: [bash, tui, ddcutil, monitor, ddc-ci, background-workers]
---

A responsive terminal UI for controlling external monitors via DDC/CI. Background workers decouple slow device queries from display updates, maintaining UI responsiveness.

## DDC/CI Overview

DDC/CI (Display Data Channel Command Interface) enables bidirectional communication between a host system and display monitors over the video cable. Most monitors manufactured after 2000 implement this protocol.

DDC/CI exposes monitor settings as Virtual Control Panel (VCP) codes:

| Setting | VCP Code | Description |
|---------|----------|-------------|
| Brightness | 0x10 | Backlight intensity |
| Contrast | 0x12 | Black/white ratio |
| RGB Gain | 0x16/0x18/0x1A | Color channel intensity |
| Volume | 0x62 | Built-in speaker volume |
| Input Source | 0x60 | HDMI1, DP, etc. |
| Power Mode | 0xD6 | On/standby/off |

The `ddcutil` utility provides command-line access on Linux systems.

## Motivation

DDC/CI enables programmatic monitor control, eliminating manual OSD navigation:

```bash
# Night mode: reduced brightness and blue light
ddcutil setvcp 0x10 30   # Brightness 30%
ddcutil setvcp 0x1A 40   # Reduce blue gain

# Presentation mode: maximum brightness
ddcutil setvcp 0x10 100

# Input source switching
ddcutil setvcp 0x60 0x0f  # DisplayPort
```

Additional capabilities include:
- Consistent color calibration across multiple displays
- Integration with cron, ambient light sensors, or window manager hooks
- Remote operation over SSH without GUI dependencies

## Performance Constraint

DDC/CI operates over I2C, introducing 100-500ms latency per query depending on the monitor. Sequential reads of 12 settings require 2-6 seconds—acceptable for batch scripts, but prohibitive for interactive interfaces.

## Problem Statement

Synchronous TUI implementations block on each query:

```bash
# Blocks for 500ms per feature
brightness=$(ddcutil getvcp 0x10 | grep -oP 'current value =\s*\K[0-9]+')
contrast=$(ddcutil getvcp 0x12 | grep -oP 'current value =\s*\K[0-9]+')
# ... 10 more features = 5+ second refresh
```

The interface becomes unresponsive during query operations.

## Solution Architecture

The implementation decouples device queries from display updates:

1. **Background workers** poll each VCP code continuously
2. **Cache files** store current values in a temporary directory
3. **Main loop** reads from cache (instantaneous) and redraws
4. **User input** buffers until explicit commit

```text
┌─────────────────────────────────────────────────────┐
│                    Main TUI Loop                     │
│  ┌─────────────────────────────────────────────┐    │
│  │  Read from cache files (instant)            │    │
│  │  Display menu with current values           │    │
│  │  Handle user input (non-blocking read)      │    │
│  │  Buffer changes until "Save"                │    │
│  └─────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
           ↑ reads                    ↓ writes on save
┌──────────┴──────────┐      ┌────────┴────────┐
│   /tmp/cache/0x10   │      │   ddcutil       │
│   /tmp/cache/0x12   │      │   setvcp        │
│   /tmp/cache/...    │      └─────────────────┘
└─────────────────────┘
           ↑ writes
┌──────────┴──────────────────────────────────────────┐
│              Background Workers (per VCP)            │
│  while true; do                                      │
│    value=$(ddcutil getvcp $vcp)                      │
│    echo "$value" > /tmp/cache/$vcp                   │
│    sleep 0.5                                         │
│  done &                                              │
└──────────────────────────────────────────────────────┘
```

## Implementation

```bash
#!/bin/bash
# monitor_control.sh - Non-blocking DDC/CI monitor control TUI

# Temporary cache directory (auto-cleaned on exit)
TMP_CACHE=$(mktemp -d /tmp/ddc_cache.XXXXXX)
trap "rm -rf $TMP_CACHE; kill 0" EXIT

# Buffered user changes (applied on save)
declare -A BUFFERED

# Features: "Name:VCP_Code:MaxValue"
FEATURES=(
    "Brightness:0x10:100"
    "Contrast:0x12:100"
    "Red Gain:0x16:100"
    "Green Gain:0x18:100"
    "Blue Gain:0x1A:100"
    "Horizontal Position:0x20:100"
    "Vertical Position:0x30:100"
    "Audio Volume:0x62:100"
    "Red Black Level:0x6C:100"
    "Green Black Level:0x6E:100"
    "Blue Black Level:0x70:100"
    "Sharpness:0x87:4"
)

# =============================================================================
# Background Workers
# =============================================================================

background_query() {
    local vcp="$1"
    while true; do
        local value
        value=$(sudo ddcutil getvcp "$vcp" 2>/dev/null | \
                grep -oP 'current value =\s*\K[0-9]+')
        [[ -z "$value" ]] && value="N/A"
        echo "$value" > "$TMP_CACHE/$vcp"
        sleep 0.5
    done
}

# Launch a background worker for each feature
for feature in "${FEATURES[@]}"; do
    IFS=':' read -r _ vcp _ <<< "$feature"
    background_query "$vcp" &
done

# =============================================================================
# Display Functions
# =============================================================================

redraw_menu() {
    clear
    echo "================ Monitor DDC/CI Control ================"
    echo ""
    echo "Buffered changes pending: ${#BUFFERED[@]}"
    echo ""

    local index=1
    for feature in "${FEATURES[@]}"; do
        IFS=':' read -r name vcp max <<< "$feature"

        local current
        if [[ -n "${BUFFERED[$vcp]}" ]]; then
            # Show buffered value (user override)
            current="${BUFFERED[$vcp]}*"
        elif [[ -f "$TMP_CACHE/$vcp" ]]; then
            current=$(cat "$TMP_CACHE/$vcp")
        else
            current="Loading..."
        fi

        printf "%2d) %-20s (VCP %s) - Current: %s (Max: %s)\n" \
               "$index" "$name" "$vcp" "$current" "$max"
        ((index++))
    done

    printf "%2d) Save and Exit (apply changes)\n" "$index"
    ((index++))
    printf "%2d) Exit without saving\n" "$index"
    echo "=========================================================="
}

# =============================================================================
# Feature Adjustment
# =============================================================================

adjust_feature() {
    local index="$1"
    IFS=':' read -r name vcp max <<< "${FEATURES[$((index-1))]}"

    while true; do
        clear
        echo "----- Adjusting $name (VCP $vcp) -----"

        local current
        if [[ -f "$TMP_CACHE/$vcp" ]]; then
            current=$(cat "$TMP_CACHE/$vcp")
        else
            current="Loading..."
        fi

        echo "Current value: $current (Allowed: 0-$max)"
        echo -n "Enter new value (or 'b' to go back): "

        # Non-blocking read with 1-second timeout
        # Allows display to refresh while waiting
        if read -t 1 -r input; then
            if [[ "$input" == "b" ]]; then
                return
            elif [[ "$input" =~ ^[0-9]+$ ]]; then
                if (( input >= 0 && input <= max )); then
                    BUFFERED["$vcp"]="$input"
                    return
                else
                    echo "Invalid: must be between 0 and $max"
                    sleep 1
                fi
            else
                echo "Invalid input"
                sleep 1
            fi
        fi
        # Timeout: loop redraws with fresh cache value
    done
}

# =============================================================================
# Main Loop
# =============================================================================

while true; do
    redraw_menu
    echo -n "Select an option: "

    # Short timeout keeps the display fresh
    read -t 1 -r selection
    [[ -z "$selection" ]] && continue

    total=${#FEATURES[@]}
    opt_save=$((total + 1))
    opt_exit=$((total + 2))

    if [[ "$selection" =~ ^[0-9]+$ ]]; then
        if (( selection >= 1 && selection <= total )); then
            adjust_feature "$selection"
        elif (( selection == opt_save )); then
            clear
            echo "Applying buffered changes..."
            for vcp in "${!BUFFERED[@]}"; do
                value="${BUFFERED[$vcp]}"
                echo "Setting VCP $vcp to $value..."
                sudo ddcutil setvcp "$vcp" "$value"
            done
            echo "Changes applied."
            exit 0
        elif (( selection == opt_exit )); then
            echo "Exiting without saving."
            exit 0
        else
            echo "Invalid selection."
            sleep 1
        fi
    else
        echo "Enter a number."
        sleep 1
    fi
done
```

## Key Implementation Patterns

### Non-Blocking Input

The `read -t 1` timeout enables continuous display updates:

```bash
read -t 1 -r selection
[[ -z "$selection" ]] && continue
```

Without input within 1 second, the loop continues and redraws. Input remains immediately responsive when provided.

### Process Cleanup

The trap statement terminates workers and removes the cache directory on exit:

```bash
trap "rm -rf $TMP_CACHE; kill 0" EXIT
```

The `kill 0` signal targets all processes in the current process group.

### Change Buffering

Modifications accumulate in an associative array rather than applying immediately:

```bash
declare -A BUFFERED
# ...
BUFFERED["$vcp"]="$input"
```

Buffered values display with an asterisk indicator:

```bash
if [[ -n "${BUFFERED[$vcp]}" ]]; then
    current="${BUFFERED[$vcp]}*"
```

This approach reduces EEPROM write cycles by batching changes.

### Per-Feature Cache Files

Each VCP code writes to a dedicated cache file:

```bash
echo "$value" > "$TMP_CACHE/$vcp"
```

This eliminates race conditions between workers. For production use, atomic write-and-rename provides additional safety:

```bash
echo "$value" > "$TMP_CACHE/$vcp.tmp"
mv "$TMP_CACHE/$vcp.tmp" "$TMP_CACHE/$vcp"
```

## Prerequisites

Install ddcutil:

```bash
# Arch
sudo pacman -S ddcutil

# Debian/Ubuntu
sudo apt install ddcutil

# Verify functionality
sudo ddcutil detect
sudo ddcutil getvcp 0x10  # Brightness
```

Load the i2c-dev kernel module if necessary:

```bash
sudo modprobe i2c-dev
echo "i2c-dev" | sudo tee /etc/modules-load.d/i2c-dev.conf
```

### Execution

```bash
chmod +x monitor_control.sh
./monitor_control.sh
```

Select features by number, enter new values, then select "Save and Exit" to apply all changes.

### Passwordless sudo Configuration

For convenience, configure ddcutil to run without password prompts:

```bash
# /etc/sudoers.d/ddcutil
username ALL=(ALL) NOPASSWD: /usr/bin/ddcutil
```

## Extensions

### Multiple Monitor Support

Specify the display number with `-d`:

```bash
value=$(sudo ddcutil -d 1 getvcp "$vcp" 2>/dev/null | ...)
```

### Preset Configurations

Define preset profiles:

```bash
declare -A PRESETS
PRESETS["day"]="0x10:80 0x12:50 0x16:50 0x18:50 0x1A:50"
PRESETS["night"]="0x10:30 0x12:40 0x16:40 0x18:40 0x1A:50"

apply_preset() {
    local preset="$1"
    for setting in ${PRESETS[$preset]}; do
        IFS=':' read -r vcp value <<< "$setting"
        sudo ddcutil setvcp "$vcp" "$value"
    done
}
```

### Profile Persistence

Save current settings to disk:

```bash
save_profile() {
    local name="$1"
    for feature in "${FEATURES[@]}"; do
        IFS=':' read -r _ vcp _ <<< "$feature"
        if [[ -f "$TMP_CACHE/$vcp" ]]; then
            echo "$vcp:$(cat "$TMP_CACHE/$vcp")"
        fi
    done > "$HOME/.config/monitor-profiles/$name"
}
```

## General Pattern

This architecture applies to any TUI polling slow devices:

1. Spawn background workers for each query
2. Write results to individual temp files
3. Main loop reads from files (instantaneous)
4. Use `read -t N` for non-blocking input
5. Batch writes to reduce device operations
6. Clean up on exit with trap

Applicable domains include IPMI/BMC queries, SNMP polling, USB device status, network device configuration, and I2C/SMBus peripherals.

## Benefits

| Synchronous Approach | Background Worker Approach |
|---------------------|---------------------------|
| 2-6 second refresh | Instantaneous refresh |
| UI blocks during queries | UI remains responsive |
| Input unavailable while loading | Input accepted continuously |
| Sequential queries | Parallel queries |
| Missed rapid input | All input buffered |

The tradeoff is implementation complexity: background process management, temp file coordination, exit cleanup, and potential race conditions. This overhead proves worthwhile for interactive utilities but may exceed requirements for simpler applications.

## Limitations

**Variable monitor support.** DDC/CI implementation quality varies across manufacturers. Some monitors support read-only access; others report incorrect VCP capabilities.

**Permission requirements.** Operation requires root privileges or `i2c` group membership.

**Single monitor scope.** The default implementation targets the first detected monitor. Multi-monitor configurations require the `-d` flag.

**Deferred feedback.** Changes buffer until explicit save. Monitor state does not update until commit.

**EEPROM wear considerations.** Monitor settings persist in EEPROM with finite write endurance. Avoid high-frequency write operations.

## Conclusion

DDC/CI provides programmatic monitor control capabilities. I2C bus latency challenges interactive interface design, but background workers with file-based caching maintain UI responsiveness effectively.

The pattern—spawn workers, cache to files, read from cache—generalizes to any slow-device polling scenario: IPMI, SNMP, USB sensors, or I2C peripherals.

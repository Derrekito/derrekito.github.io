---
title: "VirtualBox VM Orchestration with a Simple Bash Script"
date: 2026-06-21 10:00:00 -0700
categories: [Virtualization, Automation]
tags: [virtualbox, bash, vm, automation, headless, lab]
---

A single script manages multiple VirtualBox VMs: batch start/stop operations, headless mode for servers, graceful shutdown, and systemd integration for automatic startup at boot.

## Problem Statement

Running a lab environment with multiple VMs (OpenStack, Kubernetes, development clusters) presents several challenges:

- Starting 5+ VMs individually through the GUI
- Tracking which VMs to start and in what order
- Shutting down all VMs before rebooting the host
- No centralized method to check status

VBoxManage provides command-line control, but the commands are verbose:

```bash
VBoxManage startvm "Keystone" --type headless
VBoxManage startvm "Glance" --type headless
VBoxManage startvm "Nova" --type headless
# ... repeat for each VM
```

## Proposed Solution

A script manages a filtered set of VMs with concise commands:

```bash
./vm_manage.sh start      # Start all lab VMs
./vm_manage.sh stop       # Graceful shutdown all
./vm_manage.sh status     # Show which are running
./vm_manage.sh start Nova # Start just one
```

## Script Implementation

```bash
#!/bin/bash
# vm_manage.sh - VirtualBox headless VM management

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

# Filter pattern - VMs matching this regex are managed
# Examples:
#   "Keystone|Glance|Nova"     - OpenStack components
#   "^k8s-"                    - Kubernetes nodes
#   ".*-dev$"                  - Development VMs
VM_FILTER="${VM_FILTER:-Keystone|Glance|Nova|Neutron|Controller}"

# Delay between VM starts (reduces resource contention)
START_DELAY="${START_DELAY:-5}"

# Delay between VM stops
STOP_DELAY="${STOP_DELAY:-2}"

# Shutdown method: "acpi" (graceful) or "poweroff" (hard)
SHUTDOWN_METHOD="${SHUTDOWN_METHOD:-acpi}"

# =============================================================================
# Get matching VMs
# =============================================================================

get_managed_vms() {
    VBoxManage list vms | \
        awk -F\" -v pattern="$VM_FILTER" '$2 ~ pattern {print $2}'
}

mapfile -t VMS < <(get_managed_vms)

# =============================================================================
# Helper functions
# =============================================================================

is_running() {
    local vm="$1"
    VBoxManage list runningvms 2>/dev/null | grep -q "^\"$vm\" "
}

get_vm_state() {
    local vm="$1"
    VBoxManage showvminfo "$vm" --machinereadable 2>/dev/null | \
        grep "^VMState=" | cut -d'"' -f2
}

# =============================================================================
# Commands
# =============================================================================

show_help() {
    cat <<EOF
Usage: $(basename "$0") {list|start [vm]|stop [vm]|status|help}

VirtualBox VM Management Script

Commands:
  list           List all managed VMs
  start [vm]     Start specific VM or all if no name given
  stop [vm]      Stop specific VM or all if no name given
  status         Show running VMs with state
  help           Show this help

Environment Variables:
  VM_FILTER      Regex pattern for VM names (default: OpenStack components)
  START_DELAY    Seconds between VM starts (default: 5)
  STOP_DELAY     Seconds between VM stops (default: 2)
  SHUTDOWN_METHOD  "acpi" for graceful, "poweroff" for hard (default: acpi)

Examples:
  $(basename "$0") list
  $(basename "$0") start
  $(basename "$0") start Nova
  $(basename "$0") stop
  $(basename "$0") status

  VM_FILTER="^k8s-" $(basename "$0") start   # Start all k8s-* VMs
EOF
}

list_vms() {
    echo "Managed VMs (pattern: $VM_FILTER):"
    if [[ ${#VMS[@]} -eq 0 ]]; then
        echo "  (none found)"
        return
    fi
    for vm in "${VMS[@]}"; do
        local state
        state=$(get_vm_state "$vm")
        printf "  %-30s %s\n" "$vm" "($state)"
    done
}

start_vm() {
    local vm="$1"

    if [[ -z "$vm" ]]; then
        echo "Error: VM name required"
        return 1
    fi

    if is_running "$vm"; then
        echo "Skipping: '$vm' is already running"
        return 0
    fi

    echo "Starting '$vm' in headless mode..."
    if VBoxManage startvm "$vm" --type headless 2>/dev/null; then
        echo "Started: $vm"
    else
        echo "Error: Failed to start '$vm'"
        echo "  Check: VBoxManage showvminfo \"$vm\" | grep -i state"
        return 1
    fi
}

stop_vm() {
    local vm="$1"

    if [[ -z "$vm" ]]; then
        echo "Error: VM name required"
        return 1
    fi

    if ! is_running "$vm"; then
        echo "Skipping: '$vm' is not running"
        return 0
    fi

    echo "Stopping '$vm' ($SHUTDOWN_METHOD)..."

    case "$SHUTDOWN_METHOD" in
        acpi)
            if VBoxManage controlvm "$vm" acpipowerbutton 2>/dev/null; then
                echo "ACPI shutdown signal sent to: $vm"
            else
                echo "Error: Failed to send ACPI signal to '$vm'"
                return 1
            fi
            ;;
        poweroff)
            if VBoxManage controlvm "$vm" poweroff 2>/dev/null; then
                echo "Powered off: $vm"
            else
                echo "Error: Failed to power off '$vm'"
                return 1
            fi
            ;;
        *)
            echo "Error: Unknown shutdown method: $SHUTDOWN_METHOD"
            return 1
            ;;
    esac
}

start_all() {
    if [[ ${#VMS[@]} -eq 0 ]]; then
        echo "No VMs match pattern: $VM_FILTER"
        return 1
    fi

    echo "Starting ${#VMS[@]} VMs..."
    local started=0
    for vm in "${VMS[@]}"; do
        if start_vm "$vm"; then
            ((started++))
        fi
        if [[ $started -lt ${#VMS[@]} ]]; then
            sleep "$START_DELAY"
        fi
    done
    echo "Started $started/${#VMS[@]} VMs"
}

stop_all() {
    if [[ ${#VMS[@]} -eq 0 ]]; then
        echo "No VMs match pattern: $VM_FILTER"
        return 1
    fi

    echo "Stopping ${#VMS[@]} VMs..."
    local stopped=0
    for vm in "${VMS[@]}"; do
        if stop_vm "$vm"; then
            ((stopped++))
        fi
        sleep "$STOP_DELAY"
    done
    echo "Stop signal sent to $stopped/${#VMS[@]} VMs"
}

show_status() {
    echo "Running VMs:"
    local running
    running=$(VBoxManage list runningvms 2>/dev/null)

    if [[ -z "$running" ]]; then
        echo "  (none)"
        return
    fi

    echo "$running" | while read -r line; do
        echo "  $line"
    done

    echo ""
    echo "Managed VM Status:"
    for vm in "${VMS[@]}"; do
        local state
        state=$(get_vm_state "$vm")
        if [[ "$state" == "running" ]]; then
            printf "  %-30s \033[32m%s\033[0m\n" "$vm" "$state"
        else
            printf "  %-30s \033[33m%s\033[0m\n" "$vm" "$state"
        fi
    done
}

# =============================================================================
# Main
# =============================================================================

case "${1:-help}" in
    list)
        list_vms
        ;;
    start)
        if [[ -n "${2:-}" ]]; then
            start_vm "$2"
        else
            start_all
        fi
        ;;
    stop)
        if [[ -n "${2:-}" ]]; then
            stop_vm "$2"
        else
            stop_all
        fi
        ;;
    status)
        show_status
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run '$(basename "$0") help' for usage"
        exit 1
        ;;
esac
```

## Usage

### Basic Commands

```bash
# List managed VMs with their state
./vm_manage.sh list

# Start all VMs (with delay between each)
./vm_manage.sh start

# Start specific VM
./vm_manage.sh start Nova

# Stop all VMs (graceful ACPI shutdown)
./vm_manage.sh stop

# Stop specific VM
./vm_manage.sh stop Glance

# Show running status
./vm_manage.sh status
```

### Custom VM Sets

The `VM_FILTER` environment variable selects different VM groups:

```bash
# Kubernetes nodes
VM_FILTER="^k8s-" ./vm_manage.sh start

# Development VMs
VM_FILTER=".*-dev$" ./vm_manage.sh status

# Specific project
VM_FILTER="myproject-" ./vm_manage.sh stop
```

### Hard Shutdown

For VMs that do not respond to ACPI signals:

```bash
SHUTDOWN_METHOD=poweroff ./vm_manage.sh stop
```

## Systemd Integration

Systemd enables automatic VM startup at boot.

### Service File

Create `/etc/systemd/system/lab-vms.service`:

```ini
[Unit]
Description=Start lab VMs
After=vboxdrv.service
Requires=vboxdrv.service

[Service]
Type=oneshot
RemainAfterExit=yes

# Run as the user who owns the VMs
User=youruser
Group=youruser

# Start VMs
ExecStart=/usr/local/bin/vm_manage.sh start

# Stop VMs on shutdown (give them time)
ExecStop=/usr/local/bin/vm_manage.sh stop
TimeoutStopSec=120

# Environment (optional - override defaults)
Environment="VM_FILTER=Keystone|Glance|Nova|Neutron"
Environment="START_DELAY=10"
Environment="SHUTDOWN_METHOD=acpi"

[Install]
WantedBy=multi-user.target
```

### Installation and Activation

```bash
# Install script
sudo cp vm_manage.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/vm_manage.sh

# Enable service
sudo systemctl daemon-reload
sudo systemctl enable lab-vms.service

# Test
sudo systemctl start lab-vms.service
sudo systemctl status lab-vms.service
```

### Manual Control

```bash
# Start VMs
sudo systemctl start lab-vms

# Stop VMs
sudo systemctl stop lab-vms

# Check status
systemctl status lab-vms
```

## Multiple VM Groups

For different projects, separate services can be created:

```bash
# /etc/systemd/system/openstack-vms.service
Environment="VM_FILTER=Keystone|Glance|Nova|Neutron"

# /etc/systemd/system/k8s-vms.service
Environment="VM_FILTER=^k8s-"
```

Alternatively, a single script with configuration files can manage multiple groups:

```bash
# /etc/vm-groups/openstack
VM_FILTER="Keystone|Glance|Nova|Neutron"
START_DELAY=10

# /etc/vm-groups/kubernetes
VM_FILTER="^k8s-"
START_DELAY=5
```

```bash
#!/bin/bash
# Load config
source "/etc/vm-groups/$1"
shift
exec /usr/local/bin/vm_manage.sh "$@"
```

## VM Readiness Detection

For VMs requiring boot completion before dependent services start:

```bash
wait_for_vm() {
    local vm="$1"
    local port="${2:-22}"  # SSH port
    local timeout="${3:-120}"

    echo "Waiting for $vm to be ready (port $port)..."

    local ip
    ip=$(VBoxManage guestproperty get "$vm" "/VirtualBox/GuestInfo/Net/0/V4/IP" 2>/dev/null | awk '{print $2}')

    if [[ -z "$ip" || "$ip" == "value" ]]; then
        echo "Warning: Could not get IP for $vm (guest additions required)"
        return 1
    fi

    local elapsed=0
    while ! nc -z "$ip" "$port" 2>/dev/null; do
        sleep 5
        ((elapsed += 5))
        if [[ $elapsed -ge $timeout ]]; then
            echo "Timeout waiting for $vm"
            return 1
        fi
    done

    echo "$vm is ready ($ip:$port)"
}
```

## Snapshot Management

Additional snapshot commands extend functionality:

```bash
snapshot_create() {
    local vm="$1"
    local name="${2:-snapshot-$(date +%Y%m%d_%H%M%S)}"

    echo "Creating snapshot '$name' for $vm..."
    VBoxManage snapshot "$vm" take "$name"
}

snapshot_restore() {
    local vm="$1"
    local name="$2"

    if is_running "$vm"; then
        echo "Stopping $vm before restore..."
        stop_vm "$vm"
        sleep 5
    fi

    echo "Restoring snapshot '$name' for $vm..."
    VBoxManage snapshot "$vm" restore "$name"
}

snapshot_list() {
    local vm="$1"
    echo "Snapshots for $vm:"
    VBoxManage snapshot "$vm" list 2>/dev/null || echo "  (none)"
}
```

## Troubleshooting

### VM Startup Failure

```bash
# Check VM state
VBoxManage showvminfo "VMName" | grep -i state

# Common issues:
# - "saved" state: VBoxManage discardstate "VMName"
# - "locked" session: Kill any VBoxHeadless processes
# - Missing disk: Check storage attachments
```

### ACPI Shutdown Failure

Some VMs lack ACPI support or guest additions:

```bash
# Force shutdown
SHUTDOWN_METHOD=poweroff ./vm_manage.sh stop VMName

# Or install guest additions in the VM
```

### VM Name Discovery

```bash
# List all VMs
VBoxManage list vms

# List running VMs
VBoxManage list runningvms

# Detailed info
VBoxManage showvminfo "VMName"
```

## Summary

This script provides:

- **Single command** to start/stop multiple VMs
- **Headless mode** for server-style operation
- **Graceful shutdown** via ACPI
- **Flexible filtering** for different VM groups
- **Systemd integration** for automatic startup
- **Staggered starts** to reduce resource contention

The `VM_FILTER` pattern can be adapted to match any VM naming convention, enabling orchestration for any VirtualBox lab environment.

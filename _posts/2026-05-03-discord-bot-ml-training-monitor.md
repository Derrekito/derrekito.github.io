---
title: "Building a Discord Bot to Monitor ML Training Across Multiple Machines"
date: 2026-05-03 10:00:00 -0700
categories: [Python, Machine Learning]
tags: [discord, python, monitoring, machine-learning, ssh, asyncio, gpu]
---

This post presents a Discord bot that monitors GPU utilization, training progress, and logs across multiple remote machines via SSH tunnels. The implementation enables training run monitoring from mobile devices.

## Problem Statement

Running ML training jobs on multiple machines—a desktop with a 4090, a server with A100s, or cloud instances—presents several monitoring challenges:

1. Checking training progress requires SSH access to each machine
2. GPU utilization and temperature data is not readily accessible
3. Recent training logs require manual retrieval
4. Mobile access to this information is limited

Discord provides an always-available mobile interface that can serve as a monitoring dashboard.

## Architecture

```text
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Mobile Device  │     │   VPS/Server    │     │ Training Machines│
│  (Discord App)  │────▶│  (Discord Bot)  │────▶│  (SSH Tunnels)   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                              │
                              ├── Machine 1 (desktop) :2222
                              └── Machine 2 (server)  :2223
```

The bot runs on a VPS or any persistent server and connects to training machines via SSH. Interaction occurs through Discord slash commands.

## Prerequisites

- Python 3.10+
- A Discord bot token ([Discord Developer Portal](https://discord.com/developers/applications))
- SSH access to training machines
- `discord.py` library

```bash
pip install discord.py
```

## Implementation

### Configuration

Machine definitions:

```python
from dataclasses import dataclass

@dataclass
class Machine:
    name: str
    display_name: str
    ssh_port: int
    ssh_user: str
    ssh_host: str = "localhost"  # localhost if using tunnels
    has_gpu: bool = True
    training_dir: str = "~/ml_training"

MACHINES = {
    "1": Machine(
        name="desktop",
        display_name="Machine 1 (RTX 4090)",
        ssh_port=2222,
        ssh_user="username",
    ),
    "2": Machine(
        name="server",
        display_name="Machine 2 (A100)",
        ssh_port=2223,
        ssh_user="username",
    ),
}
```

### SSH Command Execution

The core utility executes commands on remote machines asynchronously:

```python
import asyncio

SSH_TIMEOUT = 10
SSH_OPTIONS = [
    "-o", "ConnectTimeout=5",
    "-o", "BatchMode=yes",
    "-o", "StrictHostKeyChecking=accept-new"
]

async def run_ssh_command(
    machine: Machine,
    command: str,
    timeout: int = SSH_TIMEOUT
) -> tuple[bool, str]:
    """Run command on remote machine via SSH. Returns (success, output)."""
    ssh_cmd = [
        "ssh",
        *SSH_OPTIONS,
        "-p", str(machine.ssh_port),
        f"{machine.ssh_user}@{machine.ssh_host}",
        command
    ]

    try:
        proc = await asyncio.create_subprocess_exec(
            *ssh_cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(
            proc.communicate(),
            timeout=timeout
        )

        if proc.returncode == 0:
            return True, stdout.decode().strip()
        else:
            return False, stderr.decode().strip()

    except asyncio.TimeoutError:
        return False, "SSH timeout"
    except Exception as e:
        return False, str(e)
```

Key implementation details:
- **`BatchMode=yes`**: Prevents password prompts (requires key-based authentication)
- **`asyncio.create_subprocess_exec`**: Non-blocking SSH calls
- **`asyncio.wait_for`**: Prevents hung connections from blocking the bot

### Gathering Machine Status

Query GPU and training status in a single call:

```python
import re

async def get_machine_status(machine: Machine) -> dict:
    """Get comprehensive status from a machine."""
    status = {
        "online": False,
        "hostname": None,
        "error": None,
        "gpu": None,
        "training": None,
    }

    # Check connectivity
    success, output = await run_ssh_command(machine, "hostname")
    if not success:
        status["error"] = output
        return status

    status["online"] = True
    status["hostname"] = output

    # Get GPU status via nvidia-smi
    gpu_cmd = """nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw \
                 --format=csv,noheader,nounits 2>/dev/null || echo 'NO_GPU'"""

    success, output = await run_ssh_command(machine, gpu_cmd)
    if success and output != "NO_GPU":
        try:
            parts = [p.strip() for p in output.split(",")]
            status["gpu"] = {
                "compute": int(parts[0]) if parts[0].isdigit() else 0,
                "memory_used": int(float(parts[1])),
                "memory_total": int(float(parts[2])),
                "temp": int(float(parts[3])),
                "power": float(parts[4]),
            }
        except (ValueError, IndexError):
            pass  # GPU parsing failed, leave as None

    # Get training status
    training_cmd = f"""
    cd {machine.training_dir} 2>/dev/null || exit 0
    echo "DIR_EXISTS"
    pgrep -af train.py >/dev/null && echo "RUNNING" || echo "STOPPED"
    if [ -f training.log ]; then
        tail -50 training.log 2>/dev/null
    fi
    if [ -f config.json ]; then
        cat config.json 2>/dev/null
    fi
    """

    success, output = await run_ssh_command(machine, training_cmd, timeout=15)
    if success and "DIR_EXISTS" in output:
        training = {
            "running": "RUNNING" in output,
            "epoch": 0,
            "total_epochs": 10000
        }

        # Parse config for total epochs
        if match := re.search(r'"epochs"\s*:\s*(\d+)', output):
            training["total_epochs"] = int(match.group(1))

        # Parse training log for current epoch
        epoch_matches = re.findall(r"Epoch (\d+)", output)
        if epoch_matches:
            training["epoch"] = int(epoch_matches[-1])

        # Parse metrics from log
        for line in reversed(output.split("\n")):
            if "Epoch" in line:
                if acc := re.search(r"Acc: ([\d.]+)", line):
                    training["accuracy"] = float(acc.group(1))
                if loss := re.search(r"Loss: ([\d.]+)", line):
                    training["loss"] = float(loss.group(1))
                break

        status["training"] = training

    return status
```

### Formatting for Discord

Convert status data into readable embeds:

```python
def format_machine_status(machine: Machine, status: dict, detailed: bool = False) -> str:
    """Format machine status for Discord embed."""
    if not status["online"]:
        return f"❌ **Unreachable** ({status.get('error', 'Unknown error')})"

    lines = ["✅ **Online**"]

    if status.get("gpu"):
        gpu = status["gpu"]
        mem_pct = gpu['memory_used'] / gpu['memory_total'] * 100
        lines.append(
            f"GPU: {gpu['compute']}% | "
            f"Mem: {gpu['memory_used']:,}/{gpu['memory_total']:,} MB ({mem_pct:.0f}%)"
        )
        if detailed:
            lines.append(f"Temp: {gpu['temp']}°C | Power: {gpu['power']:.0f}W")

    if status.get("training"):
        t = status["training"]
        if t["running"]:
            pct = t["epoch"] / t["total_epochs"] * 100 if t["total_epochs"] else 0
            lines.append(
                f"Training: Epoch {t['epoch']:,} / {t['total_epochs']:,} ({pct:.1f}%)"
            )
            if detailed:
                if t.get("accuracy"):
                    lines.append(f"Accuracy: {t['accuracy']:.4f}")
                if t.get("loss"):
                    lines.append(f"Loss: {t['loss']:.4f}")
        else:
            lines.append("Training: Not running")

    return "\n".join(lines)
```

### Bot Class

Set up the Discord bot with slash commands:

```python
import discord
from discord import app_commands
from discord.ext import commands
from datetime import datetime, timezone
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class StatusBot(commands.Bot):
    def __init__(self):
        intents = discord.Intents.default()
        intents.message_content = True
        super().__init__(command_prefix="!", intents=intents)

    async def setup_hook(self):
        await self.tree.sync()
        logger.info(f"Synced {len(self.tree.get_commands())} slash commands")

    async def on_ready(self):
        logger.info(f"Logged in as {self.user}")


bot = StatusBot()
```

### Slash Commands

#### Overview Status

```python
@bot.tree.command(name="status", description="Status of all machines")
async def status_all(interaction: discord.Interaction):
    await interaction.response.defer()  # May take a few seconds

    embed = discord.Embed(
        title="🖥️ Machine Status",
        color=discord.Color.blue(),
        timestamp=datetime.now(timezone.utc),
    )

    # Query all machines in parallel
    tasks = {mid: get_machine_status(m) for mid, m in MACHINES.items()}
    results = await asyncio.gather(*tasks.values())

    for (mid, machine), status in zip(MACHINES.items(), results):
        embed.add_field(
            name=f"Machine {mid}: {machine.display_name}",
            value=format_machine_status(machine, status, detailed=False),
            inline=False,
        )

    await interaction.followup.send(embed=embed)
```

#### Detailed Machine Status

```python
@bot.tree.command(name="status1", description="Detailed status of Machine 1")
async def status1(interaction: discord.Interaction):
    await interaction.response.defer()
    machine = MACHINES["1"]
    status = await get_machine_status(machine)

    embed = discord.Embed(
        title=f"🖥️ {machine.display_name}",
        color=discord.Color.green() if status["online"] else discord.Color.red(),
        timestamp=datetime.now(timezone.utc),
    )
    embed.description = format_machine_status(machine, status, detailed=True)

    if status.get("hostname"):
        embed.set_footer(text=f"Hostname: {status['hostname']}")

    await interaction.followup.send(embed=embed)
```

#### GPU Details

```python
@bot.tree.command(name="gpu1", description="Full nvidia-smi output for Machine 1")
async def gpu1(interaction: discord.Interaction):
    await interaction.response.defer()
    machine = MACHINES["1"]

    success, output = await run_ssh_command(machine, "nvidia-smi", timeout=15)

    if success:
        # Discord message limit is 2000 chars, code blocks add ~10
        await interaction.followup.send(
            f"**{machine.display_name}**\n```\n{output[:1900]}\n```"
        )
    else:
        await interaction.followup.send(f"**{machine.display_name}**: ❌ {output}")
```

#### Training Logs

```python
@bot.tree.command(name="logs1", description="Recent training logs from Machine 1")
@app_commands.describe(lines="Number of lines (default 20, max 50)")
async def logs1(interaction: discord.Interaction, lines: int = 20):
    await interaction.response.defer()
    machine = MACHINES["1"]
    lines = min(lines, 50)  # Cap at 50

    cmd = f"tail -n {lines} {machine.training_dir}/training.log 2>/dev/null || echo 'No log file'"
    success, output = await run_ssh_command(machine, cmd, timeout=15)

    if success:
        await interaction.followup.send(
            f"**{machine.display_name}** logs:\n```\n{output[:1900]}\n```"
        )
    else:
        await interaction.followup.send(f"**{machine.display_name}**: ❌ {output}")
```

#### Arbitrary Command Execution

```python
@bot.tree.command(name="ssh", description="Run command on a machine")
@app_commands.describe(machine="Machine number (1 or 2)", command="Command to run")
async def ssh_cmd(interaction: discord.Interaction, machine: str, command: str):
    await interaction.response.defer()

    if machine not in MACHINES:
        await interaction.followup.send(f"Unknown machine: {machine}. Use 1 or 2.")
        return

    m = MACHINES[machine]
    success, output = await run_ssh_command(m, command, timeout=30)

    if success:
        await interaction.followup.send(f"**{m.display_name}**:\n```\n{output[:1900]}\n```")
    else:
        await interaction.followup.send(f"**{m.display_name}**: ❌ {output}")
```

> **Security Note:** The `/ssh` command provides broad access. Consider restricting it to specific Discord users or removing it for public bots.

### Running the Bot

```python
def main():
    token = os.getenv("DISCORD_BOT_TOKEN")
    if not token:
        logger.error("DISCORD_BOT_TOKEN not set!")
        return

    logger.info("Starting ML training status bot...")
    bot.run(token)


if __name__ == "__main__":
    main()
```

## Deployment

### Systemd Service

Create `/etc/systemd/system/discord-status-bot.service`:

```ini
[Unit]
Description=Discord ML Training Status Bot
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=youruser
WorkingDirectory=/home/youruser
EnvironmentFile=/home/youruser/.discord_bot.env
ExecStart=/usr/bin/python3 /home/youruser/discord_status_bot.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Create `/home/youruser/.discord_bot.env`:

```bash
DISCORD_BOT_TOKEN=your_bot_token_here
```

Secure and enable:

```bash
chmod 600 ~/.discord_bot.env
sudo systemctl daemon-reload
sudo systemctl enable --now discord-status-bot
```

### SSH Key Setup

The bot requires passwordless SSH access to training machines:

```bash
# Generate key if needed
ssh-keygen -t ed25519 -C "discord-bot"

# Copy to each training machine
ssh-copy-id -p 2222 user@localhost  # Machine 1
ssh-copy-id -p 2223 user@localhost  # Machine 2
```

### SSH Tunnels (Optional)

If training machines are not directly accessible, use SSH tunnels or a tool like [rathole](https://github.com/rapiz1/rathole) to expose SSH ports through a central server.

Example: Training machine connects to VPS, VPS forwards `localhost:2222` to the training machine's SSH.

## Usage

Available commands in Discord:

| Command | Description |
|---------|-------------|
| `/status` | Overview of all machines |
| `/status1` | Detailed status of Machine 1 |
| `/status2` | Detailed status of Machine 2 |
| `/gpu1` | Full `nvidia-smi` output from Machine 1 |
| `/gpu2` | Full `nvidia-smi` output from Machine 2 |
| `/logs1 [lines]` | Recent training logs from Machine 1 |
| `/logs2 [lines]` | Recent training logs from Machine 2 |
| `/ssh <machine> <command>` | Run arbitrary command |

### Example Output

```text
🖥️ Machine Status

Machine 1: RTX 4090 Desktop
✅ Online
GPU: 98% | Mem: 22,451/24,564 MB (91%)
Training: Epoch 15,420 / 40,000 (38.6%)

Machine 2: A100 Server
✅ Online
GPU: 45% | Mem: 12,000/40,960 MB (29%)
Training: Not running
```

## Extensions

### Progress Notifications

A background task can send alerts when training completes or encounters errors:

```python
from discord.ext import tasks

@tasks.loop(minutes=5)
async def check_training_status():
    channel = bot.get_channel(YOUR_CHANNEL_ID)

    for mid, machine in MACHINES.items():
        status = await get_machine_status(machine)

        if status.get("training"):
            t = status["training"]

            # Alert on completion
            if t["epoch"] >= t["total_epochs"] - 1:
                await channel.send(
                    f"🎉 **{machine.display_name}**: Training complete! "
                    f"Final accuracy: {t.get('accuracy', 'N/A')}"
                )

            # Alert on crash (was running, now stopped)
            # Would need to track previous state
```

### GPU Temperature Alerts

```python
@tasks.loop(minutes=1)
async def check_gpu_temps():
    channel = bot.get_channel(YOUR_CHANNEL_ID)

    for mid, machine in MACHINES.items():
        status = await get_machine_status(machine)

        if status.get("gpu") and status["gpu"]["temp"] > 85:
            await channel.send(
                f"🔥 **Warning**: {machine.display_name} GPU at {status['gpu']['temp']}°C!"
            )
```

### Training Graphs

Generate matplotlib plots and upload them:

```python
@bot.tree.command(name="plot1", description="Training loss curve from Machine 1")
async def plot1(interaction: discord.Interaction):
    await interaction.response.defer()
    machine = MACHINES["1"]

    # Fetch log data
    cmd = f"cat {machine.training_dir}/training.log | grep -oP 'Loss: [\\d.]+' | tail -1000"
    success, output = await run_ssh_command(machine, cmd, timeout=30)

    if not success:
        await interaction.followup.send(f"Failed to fetch logs: {output}")
        return

    # Parse losses
    losses = [float(line.split()[-1]) for line in output.strip().split('\n') if line]

    # Generate plot
    import matplotlib.pyplot as plt
    import io

    fig, ax = plt.subplots(figsize=(10, 6))
    ax.plot(losses)
    ax.set_xlabel('Step')
    ax.set_ylabel('Loss')
    ax.set_title(f'{machine.display_name} Training Loss')

    buf = io.BytesIO()
    fig.savefig(buf, format='png', dpi=100)
    buf.seek(0)
    plt.close(fig)

    await interaction.followup.send(
        file=discord.File(buf, filename='training_loss.png')
    )
```

## Complete Script

The full bot implementation in one file:

```python
#!/usr/bin/env python3
"""Discord bot for monitoring ML training across multiple machines via SSH."""

import asyncio
import logging
import os
import re
from dataclasses import dataclass
from datetime import datetime, timezone

import discord
from discord import app_commands
from discord.ext import commands

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SSH_TIMEOUT = 10
SSH_OPTIONS = ["-o", "ConnectTimeout=5", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new"]


@dataclass
class Machine:
    name: str
    display_name: str
    ssh_port: int
    ssh_user: str
    ssh_host: str = "localhost"
    has_gpu: bool = True
    training_dir: str = "~/ml_training"


MACHINES = {
    "1": Machine(name="desktop", display_name="Machine 1 (Desktop)", ssh_port=2222, ssh_user="user"),
    "2": Machine(name="server", display_name="Machine 2 (Server)", ssh_port=2223, ssh_user="user"),
}


async def run_ssh_command(machine: Machine, command: str, timeout: int = SSH_TIMEOUT) -> tuple[bool, str]:
    ssh_cmd = ["ssh", *SSH_OPTIONS, "-p", str(machine.ssh_port), f"{machine.ssh_user}@{machine.ssh_host}", command]
    try:
        proc = await asyncio.create_subprocess_exec(*ssh_cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout)
        return (True, stdout.decode().strip()) if proc.returncode == 0 else (False, stderr.decode().strip())
    except asyncio.TimeoutError:
        return False, "SSH timeout"
    except Exception as e:
        return False, str(e)


async def get_machine_status(machine: Machine) -> dict:
    status = {"online": False, "hostname": None, "error": None, "gpu": None, "training": None}

    success, output = await run_ssh_command(machine, "hostname")
    if not success:
        status["error"] = output
        return status

    status["online"] = True
    status["hostname"] = output

    # GPU
    gpu_cmd = "nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw --format=csv,noheader,nounits 2>/dev/null || echo 'NO_GPU'"
    success, output = await run_ssh_command(machine, gpu_cmd)
    if success and output != "NO_GPU":
        try:
            parts = [p.strip() for p in output.split(",")]
            status["gpu"] = {"compute": int(parts[0]), "memory_used": int(float(parts[1])), "memory_total": int(float(parts[2])), "temp": int(float(parts[3])), "power": float(parts[4])}
        except:
            pass

    # Training
    training_cmd = f"cd {machine.training_dir} 2>/dev/null && echo DIR_EXISTS && (pgrep -af train.py >/dev/null && echo RUNNING || echo STOPPED) && tail -50 training.log 2>/dev/null"
    success, output = await run_ssh_command(machine, training_cmd, timeout=15)
    if success and "DIR_EXISTS" in output:
        training = {"running": "RUNNING" in output, "epoch": 0, "total_epochs": 10000}
        if m := re.findall(r"Epoch (\d+)", output):
            training["epoch"] = int(m[-1])
        status["training"] = training

    return status


def format_status(machine: Machine, status: dict, detailed: bool = False) -> str:
    if not status["online"]:
        return f"❌ **Unreachable** ({status.get('error', 'Unknown')})"
    lines = ["✅ **Online**"]
    if g := status.get("gpu"):
        lines.append(f"GPU: {g['compute']}% | Mem: {g['memory_used']:,}/{g['memory_total']:,} MB")
        if detailed:
            lines.append(f"Temp: {g['temp']}°C | Power: {g['power']:.0f}W")
    if t := status.get("training"):
        if t["running"]:
            pct = t["epoch"] / t["total_epochs"] * 100
            lines.append(f"Training: Epoch {t['epoch']:,} / {t['total_epochs']:,} ({pct:.1f}%)")
        else:
            lines.append("Training: Not running")
    return "\n".join(lines)


class StatusBot(commands.Bot):
    def __init__(self):
        super().__init__(command_prefix="!", intents=discord.Intents.default())

    async def setup_hook(self):
        await self.tree.sync()

    async def on_ready(self):
        logger.info(f"Logged in as {self.user}")


bot = StatusBot()


@bot.tree.command(name="status", description="Status of all machines")
async def status_all(interaction: discord.Interaction):
    await interaction.response.defer()
    embed = discord.Embed(title="🖥️ Machine Status", color=discord.Color.blue(), timestamp=datetime.now(timezone.utc))
    results = await asyncio.gather(*[get_machine_status(m) for m in MACHINES.values()])
    for (mid, machine), status in zip(MACHINES.items(), results):
        embed.add_field(name=machine.display_name, value=format_status(machine, status), inline=False)
    await interaction.followup.send(embed=embed)


@bot.tree.command(name="gpu1", description="GPU details for Machine 1")
async def gpu1(interaction: discord.Interaction):
    await interaction.response.defer()
    success, output = await run_ssh_command(MACHINES["1"], "nvidia-smi", timeout=15)
    await interaction.followup.send(f"```\n{output[:1900]}\n```" if success else f"❌ {output}")


@bot.tree.command(name="logs1", description="Training logs from Machine 1")
@app_commands.describe(lines="Number of lines")
async def logs1(interaction: discord.Interaction, lines: int = 20):
    await interaction.response.defer()
    m = MACHINES["1"]
    success, output = await run_ssh_command(m, f"tail -n {min(lines, 50)} {m.training_dir}/training.log", timeout=15)
    await interaction.followup.send(f"```\n{output[:1900]}\n```" if success else f"❌ {output}")


def main():
    if token := os.getenv("DISCORD_BOT_TOKEN"):
        bot.run(token)
    else:
        logger.error("DISCORD_BOT_TOKEN not set!")


if __name__ == "__main__":
    main()
```

## Conclusion

This bot provides remote ML training monitoring through an accessible mobile interface. Key implementation aspects:

- **Async SSH**: Use `asyncio.create_subprocess_exec` for non-blocking remote commands
- **Parallel queries**: `asyncio.gather` enables simultaneous machine status checks
- **Discord embeds**: Rich formatting provides readable status updates
- **Slash commands**: Modern Discord UX with autocomplete support

The implementation handles edge cases including SSH timeouts, missing GPU drivers, and nonexistent training directories. Extensions such as progress notifications, temperature alerts, or training graphs can be added as needed.

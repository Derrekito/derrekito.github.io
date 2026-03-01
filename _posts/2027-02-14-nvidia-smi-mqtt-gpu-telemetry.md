---
title: Publishing GPU Telemetry to MQTT with nvidia-smi
date: 2027-02-14 10:00:00 -0700
categories: [Monitoring, Infrastructure]
tags: [nvidia, gpu, mqtt, python, monitoring, home-assistant, grafana]
---

GPU telemetry provides critical insight into hardware health, particularly in environments where reliability matters—radiation testing facilities, HPC clusters, or home lab GPU servers. This post presents a zero-dependency Python solution for publishing nvidia-smi metrics to MQTT brokers, enabling integration with monitoring dashboards and home automation systems.

## Problem Statement

NVIDIA GPUs expose extensive telemetry through the `nvidia-smi` command-line tool: temperature, power draw, memory usage, ECC error counts, and more. However, this data remains trapped in the terminal unless exported to a monitoring system.

Common approaches introduce dependencies:

- **NVIDIA DCGM**: Enterprise-focused, requires GPU driver integration
- **Prometheus exporters**: Add HTTP server dependencies, Prometheus infrastructure
- **Python MQTT libraries**: Require `paho-mqtt` or similar packages

For lightweight deployments—embedded systems, air-gapped networks, or minimal containers—external dependencies create friction. A solution using only Python's standard library and existing system tools simplifies deployment and maintenance.

## Zero-Dependency Design Rationale

The implementation relies on two assumptions:

1. Python 3 exists on the system (standard on Linux)
2. `mosquitto_pub` (from mosquitto-clients) handles MQTT publishing

This design provides several advantages:

| Aspect | Dependency-based | Zero-dependency |
|--------|-----------------|-----------------|
| Installation | `pip install paho-mqtt python-dotenv` | Copy single file |
| Virtual environments | Required | Optional |
| Container size | Larger (pip packages) | Minimal |
| Air-gapped systems | Requires package mirroring | Works immediately |
| Debugging | Library internals | CLI tool behavior |

The `mosquitto_pub` CLI handles connection management, TLS negotiation, and MQTT protocol details. The Python script focuses on data collection and transformation.

## nvidia-smi Output Parsing

The `nvidia-smi -q` command produces indented key-value output rather than structured JSON:

```text
==============NVSMI LOG==============

Timestamp                                 : Sun Feb 14 10:30:45 2027
Driver Version                            : 550.54.14
CUDA Version                              : 12.4

Attached GPUs                             : 1
GPU 00000000:01:00.0
    Product Name                          : NVIDIA GeForce RTX 4090
    ECC Mode
        Current                           : Disabled
        Pending                           : Disabled
    ECC Errors
        Volatile
            SRAM Correctable              : N/A
            SRAM Uncorrectable            : N/A
        Aggregate
            SRAM Correctable              : N/A
            SRAM Uncorrectable            : N/A
```

### Stack-Based Indentation Parser

The parser converts this hierarchical text into nested dictionaries using indent tracking:

```python
def parse_indented_kv(raw_text):
    """
    Convert indented 'Key : Value' blocks into a nested dict.
    Lines without ':' open a new nested object.
    """
    data = {}
    stack = [data]
    indents = [0]

    for line in raw_text.splitlines():
        if not line.strip() or line.startswith("="):
            continue

        indent = len(line) - len(line.lstrip(" "))

        # Pop to correct level
        while indents and indent < indents[-1]:
            stack.pop()
            indents.pop()

        # Split key/value
        if ":" in line:
            key, val = line.strip().split(":", 1)
            key = key.strip()
            val = val.strip()
            stack[-1][key] = val
        else:
            # New subsection header without a colon
            key = line.strip()
            if key not in stack[-1] or not isinstance(stack[-1].get(key), dict):
                stack[-1][key] = {}
            stack.append(stack[-1][key])
            indents.append(indent)

    return data
```

The algorithm maintains a stack of nested dictionaries and an associated indent level stack. When indentation decreases, the parser pops back to the appropriate nesting level. Lines containing colons become key-value pairs; lines without colons create new nested objects.

### Resulting JSON Structure

The parser transforms the nvidia-smi output into structured JSON:

```json
{
    "Timestamp": "Sun Feb 14 10:30:45 2027",
    "Driver Version": "550.54.14",
    "CUDA Version": "12.4",
    "GPU 00000000:01:00.0": {
        "Product Name": "NVIDIA GeForce RTX 4090",
        "ECC Mode": {
            "Current": "Disabled",
            "Pending": "Disabled"
        },
        "ECC Errors": {
            "Volatile": {
                "SRAM Correctable": "N/A",
                "SRAM Uncorrectable": "N/A"
            },
            "Aggregate": {
                "SRAM Correctable": "N/A",
                "SRAM Uncorrectable": "N/A"
            }
        }
    },
    "_poll_timestamp": "2027-02-14T17:30:45.123456+00:00"
}
```

## Environment Configuration Pattern

### Minimal .env Loader

Rather than depending on `python-dotenv`, a minimal loader handles the common case:

```python
def load_dotenv(path=".env"):
    if not os.path.isfile(path):
        return
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            if "=" not in s:
                continue
            k, v = s.split("=", 1)
            k = k.strip()
            v = v.strip()
            # Strip optional surrounding quotes
            if (v.startswith('"') and v.endswith('"')) or \
               (v.startswith("'") and v.endswith("'")):
                v = v[1:-1]
            os.environ.setdefault(k, v)
```

This loader:
- Ignores blank lines and comments
- Handles quoted values (single or double quotes)
- Uses `setdefault` to avoid overwriting existing environment variables

### Configuration Variables

The complete configuration set covers nvidia-smi behavior, MQTT connection, and output formatting:

```bash
# nvidia-smi settings
NVIDIA_SMI_BIN=nvidia-smi
GPU_INDEX=0
POLL_INTERVAL=5

# MQTT connection
MQTT_HOST=192.168.1.100
MQTT_PORT=1883
MQTT_TOPIC=gpu/ecc
MQTT_QOS=0
MQTT_RETAIN=0
MQTT_CLIENT_ID=gpu-monitor-01

# MQTT authentication (optional)
MQTT_USERNAME=mqttuser
MQTT_PASSWORD=secretpassword

# MQTT TLS (optional)
MQTT_TLS=0
MQTT_CAFILE=/path/to/ca.crt
MQTT_CERT=/path/to/client.crt
MQTT_KEY=/path/to/client.key

# Output control
ENABLE_MQTT=1
PRINT_PRETTY=1
ADD_TIMESTAMP=1
```

### Boolean Environment Variables

A helper function handles various truthy string representations:

```python
def env_bool(name, default="0"):
    return os.environ.get(name, default).strip() in ("1", "true", "TRUE", "yes", "YES")
```

## MQTT Publishing via CLI Wrapper

The `mqtt_publish` function constructs and executes the `mosquitto_pub` command:

```python
def mqtt_publish(payload_str, cfg):
    """
    Publish using mosquitto_pub CLI. Raises on failure.
    """
    mosq = cfg["MOSQUITTO_PUB_BIN"]
    if not which(mosq):
        raise RuntimeError(f"mosquitto_pub not found (MOSQUITTO_PUB_BIN='{mosq}')")

    cmd = [
        mosq,
        "-h", cfg["MQTT_HOST"],
        "-p", str(cfg["MQTT_PORT"]),
        "-t", cfg["MQTT_TOPIC"],
        "-m", payload_str,
        "-q", str(cfg["MQTT_QOS"]),
    ]

    if cfg["MQTT_RETAIN"]:
        cmd.append("--retain")
    if cfg["MQTT_CLIENT_ID"]:
        cmd.extend(["-i", cfg["MQTT_CLIENT_ID"]])
    if cfg["MQTT_USERNAME"]:
        cmd.extend(["-u", cfg["MQTT_USERNAME"]])
    if cfg["MQTT_PASSWORD"]:
        cmd.extend(["-P", cfg["MQTT_PASSWORD"]])
    if cfg["MQTT_TLS"]:
        cmd.append("--tls")
        if cfg["MQTT_CAFILE"]:
            cmd.extend(["--cafile", cfg["MQTT_CAFILE"]])
        if cfg["MQTT_CERT"]:
            cmd.extend(["--cert", cfg["MQTT_CERT"]])
        if cfg["MQTT_KEY"]:
            cmd.extend(["--key", cfg["MQTT_KEY"]])

    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if p.returncode != 0:
        raise RuntimeError(f"mosquitto_pub failed: {p.stderr.strip()}")
```

Key implementation details:

- **Pre-flight check**: Verify `mosquitto_pub` exists before attempting publish
- **Argument list construction**: Build command array dynamically based on configuration
- **Shell safety**: Use `subprocess.run` with argument list (not shell=True)
- **Error propagation**: Raise exceptions with stderr content for debugging

## Signal Handling for Graceful Shutdown

Long-running monitoring processes require clean shutdown behavior. The implementation uses `threading.Event` for cooperative termination:

```python
from threading import Event
import signal

stop_event = Event()

def _signal_handler(signum, frame):
    stop_event.set()

for sig in (signal.SIGINT, signal.SIGTERM):
    try:
        signal.signal(sig, _signal_handler)
    except Exception:
        pass  # Not all platforms allow setting all handlers
```

The main loop checks `stop_event` and uses interruptible waits:

```python
while not stop_event.is_set():
    loop_start = time.monotonic()

    # ... collect and publish metrics ...

    # Interval pacing with interruptible wait
    elapsed = time.monotonic() - loop_start
    remaining = max(0.0, interval - elapsed)

    # Wait in small chunks to react quickly to stop_event
    end_time = time.monotonic() + remaining
    while not stop_event.is_set() and time.monotonic() < end_time:
        time.sleep(min(0.1, end_time - time.monotonic()))
```

This pattern ensures:

- **Ctrl+C responsiveness**: Maximum 100ms delay before shutdown begins
- **Clean exit**: No partial operations or zombie processes
- **Container compatibility**: Responds to SIGTERM from Docker/systemd

## Integration Examples

### Home Assistant MQTT Sensor

Configure Home Assistant to consume GPU metrics via MQTT:

```yaml
# configuration.yaml
mqtt:
  sensor:
    - name: "GPU Temperature"
      state_topic: "gpu/ecc"
      value_template: "{{ value_json['GPU 00000000:01:00.0']['Temperature']['GPU Current Temp'].split()[0] }}"
      unit_of_measurement: "°C"
      device_class: temperature

    - name: "GPU ECC Errors"
      state_topic: "gpu/ecc"
      value_template: >
        {% set gpu = value_json['GPU 00000000:01:00.0'] %}
        {% set volatile = gpu['ECC Errors']['Volatile'] %}
        {{ volatile['SRAM Uncorrectable'] }}

    - name: "GPU Driver Version"
      state_topic: "gpu/ecc"
      value_template: "{{ value_json['Driver Version'] }}"
```

### Grafana with InfluxDB

Use Telegraf to bridge MQTT to InfluxDB, then visualize in Grafana:

```toml
# telegraf.conf
[[inputs.mqtt_consumer]]
  servers = ["tcp://localhost:1883"]
  topics = ["gpu/ecc"]
  data_format = "json"

[[outputs.influxdb_v2]]
  urls = ["http://localhost:8086"]
  token = "${INFLUX_TOKEN}"
  organization = "homelab"
  bucket = "gpu_metrics"
```

### Systemd Service

Deploy as a system service for persistent monitoring:

```ini
# /etc/systemd/system/nvidia-mqtt.service
[Unit]
Description=NVIDIA GPU Metrics to MQTT
After=network.target

[Service]
Type=simple
User=nobody
WorkingDirectory=/opt/nvidia-mqtt
ExecStart=/usr/bin/python3 nvidia-smi-to-mqtt.py
Restart=always
RestartSec=10
EnvironmentFile=/opt/nvidia-mqtt/.env

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable nvidia-mqtt
sudo systemctl start nvidia-mqtt
```

## Use Cases

### Radiation Testing

When evaluating GPU behavior under radiation exposure (proton beams, neutron sources), ECC error accumulation indicates single-event upsets (SEUs). Real-time MQTT publishing enables:

- Live dashboards during beam time
- Automatic alerting on error thresholds
- Correlation with beam current logs

### HPC Cluster Monitoring

Aggregate GPU health across compute nodes:

```bash
# Per-node topic structure
MQTT_TOPIC=cluster/$(hostname)/gpu/${GPU_INDEX}
```

This enables fleet-wide visibility into:

- Node failures before job impact
- Thermal hotspots requiring cooling attention
- Memory errors indicating hardware degradation

### Home Lab GPU Servers

For AI inference servers or Plex transcoding boxes, GPU monitoring provides:

- Temperature trending over time
- Power consumption tracking
- Health verification after driver updates

## Summary

Publishing GPU telemetry to MQTT requires minimal infrastructure when leveraging existing CLI tools. The zero-dependency approach—Python stdlib plus `mosquitto_pub`—produces a portable, maintainable solution suitable for environments where traditional monitoring stacks introduce unwanted complexity.

Key techniques demonstrated:

1. **Stack-based parsing** for hierarchical text output
2. **Minimal .env loading** without external packages
3. **CLI wrapper pattern** for protocol handling
4. **Cooperative shutdown** with threading primitives

The resulting script deploys as a single file, configures via environment variables, and integrates with any MQTT-capable monitoring system.

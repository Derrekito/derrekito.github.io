---
title: "Real-Time Telemetry (Part 3): Hardware Test Simulators with Finite State Machines"
date: 2026-10-04
categories: [IoT, Testing]
tags: [simulation, fsm, state-machine, testing, bash, python, telemetry]
series: real-time-telemetry
series_order: 3
---

Testing a telemetry pipeline requires data. Real hardware requires physical setup, lab time, and equipment availability. Simulators generate realistic data on demand, enabling development and testing without hardware dependencies. This post covers building device simulators using finite state machines (FSMs) for behavior modeling and separate sensor simulators for continuous telemetry.

## Why Simulate?

Hardware testing scenarios that benefit from simulation:

- **Development**: Build and test the dashboard before hardware arrives
- **CI/CD**: Run automated tests without physical equipment
- **Load testing**: Generate data volumes impossible with single devices
- **Edge cases**: Trigger failure modes that rarely occur naturally
- **Demos**: Show system capabilities without complex lab setup

The goal: simulators that produce output indistinguishable from real devices, following the same protocols and data formats.

## Two Types of Simulators

Hardware test systems typically involve two data sources:

1. **Device Under Test (DUT)**: The hardware being evaluated. Outputs structured data (JSON events, status messages, errors) based on its internal state.

2. **Environmental Sensors**: Power supplies, temperature monitors, etc. Output continuous telemetry (voltage, current, temperature) at fixed intervals.

Each requires a different simulation approach.

## FSM-Based Device Simulation

A device under test isn't a random number generator. It has states: powered off, booting, running, crashed. Transitions between states follow rules: you can't crash before booting. A finite state machine models this behavior.

### State Definition

Define the states your device can occupy:

```bash
# System states
SYS_STATE="POWER_OFF"    # POWER_OFF, POWER_ON, BOOTING, RUNNING,
                          # KERNEL_PANIC, HANG, REBOOTING, SHUTTING_DOWN

# Application states
APP_STATE="NOT_STARTED"  # NOT_STARTED, STARTING, RUNNING,
                          # CRASHED, SEGFAULT, HUNG, RESTARTING

# Sequence counter for ordering
SEQ=0
```

Two parallel state machines: one for the system (kernel/OS level), one for the application running on it. They interact—the app can only run if the system is running.

### State Transitions

Transitions are functions that update state and log the change:

```bash
transition_sys() {
  local next="$1"
  log INFO "SYS_TRANSITION" "System -> $next"
  SYS_STATE="$next"
}

transition_app() {
  local next="$1"
  log INFO "APP_TRANSITION" "App -> $next"
  APP_STATE="$next"
}
```

### Guard Functions

Not all transitions are legal. Guard functions enforce the rules:

```bash
legal_sys_event() {
  local ev="$1"
  case "$ev" in
    POWER_ON)          [[ "$SYS_STATE" = "POWER_OFF" ]] ;;
    BOOTING)           [[ "$SYS_STATE" = "POWER_ON" ]] ;;
    BOOT_OK)           [[ "$SYS_STATE" = "BOOTING" ]] ;;
    SHUTDOWN)          [[ "$SYS_STATE" = "RUNNING" ]] ;;
    SHUTDOWN_COMPLETE) [[ "$SYS_STATE" = "SHUTTING_DOWN" ]] ;;
    REBOOT)            [[ "$SYS_STATE" =~ ^(RUNNING|KERNEL_PANIC|HANG)$ ]] ;;
    KERNEL_PANIC)      [[ "$SYS_STATE" = "RUNNING" ]] ;;
    HANG)              [[ "$SYS_STATE" = "RUNNING" ]] ;;
    WATCHDOG_RESET)    [[ "$SYS_STATE" =~ ^(KERNEL_PANIC|HANG)$ ]] ;;
    *)                 return 1 ;;
  esac
}

legal_app_event() {
  local ev="$1"
  case "$ev" in
    APP_START)      [[ "$SYS_STATE" = "RUNNING" && "$APP_STATE" = "NOT_STARTED" ]] ;;
    APP_STARTED)    [[ "$APP_STATE" = "STARTING" ]] ;;
    APP_SEGFAULT)   [[ "$APP_STATE" =~ ^(STARTING|RUNNING)$ ]] ;;
    APP_CRASH)      [[ "$APP_STATE" =~ ^(STARTING|RUNNING)$ ]] ;;
    APP_HANG)       [[ "$APP_STATE" = "RUNNING" ]] ;;
    APP_RESTARTED)  [[ "$APP_STATE" = "RESTARTING" ]] ;;
    *)              return 1 ;;
  esac
}
```

The guards encode domain knowledge: you can only boot after powering on, you can only crash while running, the app can only start if the system is running.

### Event Dispatch

A central dispatcher routes events through guards to handlers:

```bash
dispatch_event() {
  local ev="$1"
  ((SEQ++))

  if [[ "$ev" =~ ^APP_ ]]; then
    if legal_app_event "$ev"; then
      handle_app_event "$ev"
    else
      log DEBUG "$ev" "Illegal app transition ignored"
    fi
  else
    if legal_sys_event "$ev"; then
      handle_sys_event "$ev"
    else
      log DEBUG "$ev" "Illegal system transition ignored"
    fi
  fi
}
```

Illegal events are logged but ignored. This prevents invalid state combinations while still recording what was attempted.

### Event Handlers with Actions

Some transitions trigger actions—emitting log files, starting processes, sending data:

```bash
handle_sys_event() {
  local ev="$1"
  case "$ev" in
    POWER_ON)          transition_sys POWER_ON ;;
    BOOTING)           action_booting ;;
    BOOT_OK)           transition_sys RUNNING ;;
    SHUTDOWN)          action_shutdown ;;
    SHUTDOWN_COMPLETE) transition_sys POWER_OFF ;;
    KERNEL_PANIC)      action_kernel_panic ;;
    HANG)              transition_sys HANG ;;
    WATCHDOG_RESET)    transition_sys REBOOTING ;;
    *)                 log DEBUG "$ev" "Unhandled event" ;;
  esac
}

action_booting() {
  transition_sys BOOTING

  # Emit realistic boot log
  if [ -f "/app/msg/boot.log" ]; then
    while IFS= read -r line; do
      echo "$line"
      sleep 0.1
    done < /app/msg/boot.log &
  fi
}

action_kernel_panic() {
  log ERROR "KERNEL_PANIC" "Kernel panic detected"

  # Emit panic trace
  if [ -f "/app/msg/panic.log" ]; then
    cat /app/msg/panic.log &
  fi

  transition_sys KERNEL_PANIC
}
```

Actions can run background processes. The boot action streams a realistic boot log line by line. The panic action dumps a kernel trace.

### Application State Machine

The application state machine runs on top of the system state machine:

```bash
handle_app_event() {
  local ev="$1"
  case "$ev" in
    APP_START)    transition_app STARTING ;;
    APP_STARTED)  action_app_started ;;
    APP_SEGFAULT) action_app_segfault ;;
    APP_CRASH)    action_app_crash ;;
    APP_HANG)     action_app_hang ;;
    APP_RESTARTED) action_app_started ;;
    *)            log DEBUG "$ev" "Unhandled app event" ;;
  esac
}

action_app_started() {
  transition_app RUNNING

  # Launch the actual test application
  if [ -f "/app/test_binary" ]; then
    /app/test_binary &
    APP_PID=$!
    log INFO "APP_STARTED" "Test binary launched (PID: $APP_PID)"
  fi
}

action_app_segfault() {
  log ERROR "APP_SEGFAULT" "Application segmentation fault"

  # Kill the running process
  if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
    kill -KILL "$APP_PID" 2>/dev/null || true
    APP_PID=""
  fi

  transition_app SEGFAULT
  transition_app RESTARTING
}
```

The app simulator can launch real binaries that generate data. When simulating crashes, it kills those processes and transitions to the appropriate state.

## Event Drivers

Something needs to generate events. Three approaches:

### Random Driver

Generate events probabilistically during normal operation:

```bash
drive_random() {
  log INFO "DRIVER_RANDOM" "Starting random event driver"

  # Events with weights (higher = more likely)
  local events=(
    "APP_SEGFAULT:5"
    "APP_CRASH:5"
    "APP_HANG:3"
    "KERNEL_PANIC:2"
    "HANG:1"
    "WATCHDOG_RESET:2"
  )

  while true; do
    sleep "${TICK_SECONDS:-1}"

    # Only generate events when system and app are running
    if [[ "$SYS_STATE" == "RUNNING" && "$APP_STATE" == "RUNNING" ]]; then
      # 10% chance per tick
      if (( RANDOM % 100 < 10 )); then
        local entry="${events[$((RANDOM % ${#events[@]}))]}"
        local event="${entry%:*}"
        dispatch_event "$event"
      fi
    fi
  done
}
```

The random driver only fires events when the system is in a state where those events make sense. Invalid events get filtered by the guards anyway, but checking first avoids log noise.

### Scripted Driver

Read events from a file for deterministic test sequences:

```bash
drive_scripted() {
  [ -f "$EVENT_FILE" ] || { echo "Event file not found" >&2; exit 1; }

  log INFO "START_SCRIPTED" "file=$EVENT_FILE"

  while IFS= read -r ev || [ -n "$ev" ]; do
    # Skip empty lines and comments
    [ -z "$ev" ] && continue
    [[ "$ev" =~ ^[[:space:]]*# ]] && continue

    dispatch_event "$ev"
    sleep "$TICK_SECONDS"
  done < "$EVENT_FILE"
}
```

Example event file:

```
# Power-up sequence
POWER_ON
BOOTING
BOOT_OK

# Start application
APP_START
APP_STARTED

# Simulate failures
APP_SEGFAULT
APP_RESTARTED

KERNEL_PANIC
WATCHDOG_RESET
BOOT_OK

# Clean shutdown
SHUTDOWN
SHUTDOWN_COMPLETE
```

Scripted mode enables reproducible test scenarios. Every run produces the same event sequence.

### Coverage Driver

Ensure every state gets visited within a time budget:

```bash
drive_cover() {
  log INFO "DRIVER_COVER" "Starting coverage driver (${COVER_SECONDS}s)"

  local deadline=$(($(date +%s) + COVER_SECONDS))
  local visited=()

  while (( $(date +%s) < deadline )); do
    # Find unvisited states and generate events to reach them
    # ... coverage logic ...
    sleep 1
  done

  log INFO "DRIVER_COVER" "Coverage complete: ${#visited[@]} states visited"
}
```

Coverage mode is useful for integration testing—ensuring the pipeline handles all possible device states.

## Sensor Simulation

Environmental sensors are simpler—they emit continuous readings without complex state machines.

```python
import json
import time
import random
import paho.mqtt.client as mqtt

MQTT_HOST = os.getenv("MQTT_HOST", "mqtt")
MQTT_TOPIC = "telemetry/sensors/power"
SENSOR_ID = os.getenv("SENSOR_ID", "power_sensor_12v")

def generate_voltage():
    """Simulate 12V supply with realistic variation."""
    return round(random.uniform(11.8, 12.4), 3)

def generate_current():
    """Simulate load current variation."""
    return round(random.uniform(0.2, 2.0), 3)

client = mqtt.Client()
client.connect(MQTT_HOST, 1883, 60)
client.loop_start()

while True:
    payload = {
        "timestamp": time.time(),
        "sensor_id": SENSOR_ID,
        "voltage": generate_voltage(),
        "current": generate_current()
    }

    client.publish(MQTT_TOPIC, json.dumps(payload))
    time.sleep(1)
```

Simple, stateless, continuous. The sensor simulator runs independently of the device simulator.

### Realistic Variation

Random uniform distribution isn't realistic. Real sensors have:

- **Drift**: Gradual change over time
- **Noise**: High-frequency variation
- **Correlation**: Related measurements move together

Add realism:

```python
class RealisticSensor:
    def __init__(self, nominal, drift_rate=0.001, noise_std=0.05):
        self.nominal = nominal
        self.drift_rate = drift_rate
        self.noise_std = noise_std
        self.current_drift = 0

    def read(self):
        # Accumulate drift (random walk)
        self.current_drift += random.gauss(0, self.drift_rate)

        # Add noise
        noise = random.gauss(0, self.noise_std)

        # Combine
        return self.nominal + self.current_drift + noise

voltage_sensor = RealisticSensor(12.0, drift_rate=0.0001, noise_std=0.02)
current_sensor = RealisticSensor(1.0, drift_rate=0.001, noise_std=0.1)
```

## Output Formatting

Match the real device's output format exactly. If the device outputs JSON:

```python
payload = {
    "timestamp": time.time(),
    "error_type": "memory",
    "address": f"0x{random.randint(0, 0xFFFFFFFF):08x}",
    "thread_id": random.randint(0, 7),
    "iteration": iteration_count
}
print(json.dumps(payload))
```

If it outputs structured text with prefixes:

```bash
echo "B> $(date -u +%FT%TZ) System booting, firmware v2.3.1"
echo "M> Matrix test starting: 1024x1024"
```

The ingestion pipeline shouldn't know (or care) whether data comes from real hardware or a simulator.

## Network Communication

Simulators need to send data to the ingestion layer. Options:

### UDP for Legacy Protocols

Some devices communicate over UDP. The simulator does the same:

```bash
# Send to dut_ingest on port 5000
echo "$log_line" | socat -u - UDP-SENDTO:dut_ingest:5000

# Or with netcat
echo "$log_line" | nc -u dut_ingest 5000
```

### MQTT for Structured Data

Modern designs publish directly to MQTT:

```python
client.publish("telemetry/device/events", json.dumps(payload))
```

### Health Checks

Support health checks so orchestration can verify the simulator is running:

```bash
# In the main loop, check for ping requests
response=$(echo "ping" | nc -u -w5 dut_ingest 5000)
if [ "$response" == "pong" ]; then
  echo "Ingestion layer is ready"
fi
```

## Docker Integration

Package simulators as Docker containers:

```dockerfile
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    socat \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY lib/ lib/
COPY msg/ msg/
COPY scripts/ scripts/
COPY entrypoint.sh .

RUN chmod +x entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]
CMD ["-m", "random"]
```

Configure via Docker Compose:

```yaml
services:
  dut_sim:
    build: ./dut_sim
    depends_on:
      dut_ingest:
        condition: service_started
    command: ["-f", "/app/scripts/events.txt", "-t", "2"]
    networks:
      - backend

  pacs_sim:
    build: ./pacs_sim
    depends_on:
      mqtt:
        condition: service_healthy
    environment:
      - MQTT_HOST=mqtt
      - SENSOR_ID=power_sensor_12v
    networks:
      - backend
```

Use Docker Compose profiles to enable/disable simulators:

```yaml
services:
  dut_sim:
    profiles: [sim]
    # ...

  pacs_sim:
    profiles: [sim]
    # ...
```

Start with simulators: `docker compose --profile sim up`
Start without: `docker compose up`

## Reproducibility

For debugging, simulators need to produce identical output across runs.

### Seeded Randomness

```bash
# Set seed from command line
if [ -n "${RANDOM_SEED:-}" ]; then
  RANDOM="$RANDOM_SEED"
  echo "[INFO] Random seed: $RANDOM_SEED"
fi
```

```python
import random
random.seed(int(os.getenv("RANDOM_SEED", "42")))
```

### Deterministic Timing

Use fixed delays rather than real-time waits for scripted mode:

```bash
# Scripted mode: fixed delay between events
sleep "$TICK_SECONDS"

# Random mode: variable but seeded
sleep $(( (RANDOM % 3) + 1 ))
```

## Testing the Simulators

Verify simulators produce expected output:

```bash
# Run scripted sequence, capture output
./entrypoint.sh -f scripts/test_sequence.txt -t 0.1 > output.log

# Verify expected transitions occurred
grep "SYS_TRANSITION.*RUNNING" output.log
grep "APP_STARTED" output.log
grep "KERNEL_PANIC" output.log

# Verify no illegal transitions
! grep "Illegal.*transition" output.log
```

## What's Next

With simulators generating data, the full pipeline can run without hardware. The final post covers Docker Compose orchestration: managing service dependencies, using profiles for different environments, and automating builds with Makefiles.

---

*This post is Part 3 of the Real-Time Telemetry series. Previous: [MQTT-to-MongoDB Ingestion Pipelines](/posts/mqtt-mongodb-ingestion-pipelines). Next: [Docker Compose Orchestration for Multi-Service Systems](/posts/docker-compose-orchestration-patterns)*

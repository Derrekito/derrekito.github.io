---
title: "Real-Time Telemetry (Part 0): Architecture Overview"
date: 2026-10-02
categories: [IoT, Architecture]
tags: [mqtt, mongodb, dash, docker, telemetry, iot, real-time]
series: real-time-telemetry
series_order: 0
---

Hardware test systems generate continuous streams of data: sensor readings, device status, error events, performance metrics. The challenge isn't collecting this data—it's making it useful in real time. Engineers need to see what's happening *now*, not query a database five minutes later.

This post introduces an architecture for real-time telemetry dashboards that solves three problems simultaneously: live data visualization without polling, persistent storage for post-analysis, and decoupled components that can evolve independently. The stack—MQTT, MongoDB, and Plotly Dash—isn't novel, but the integration patterns are worth documenting.

## The Problem: Test System Telemetry

Consider a hardware test rig monitoring multiple devices under test (DUTs). Each device streams diagnostic output: memory test results, temperature readings, error counts, status transitions. A power/analog conditioning system (PACS) adds environmental data: voltage rails, current draw, ambient temperature.

Traditional approaches poll a database on a timer:

```python
# The polling antipattern
@app.callback(Output('chart', 'figure'), Input('interval', 'n_intervals'))
def update_chart(n):
    data = db.collection.find().sort('timestamp', -1).limit(100)
    return build_figure(data)
```

This has several failure modes:

1. **Latency**: Data appears 1-30 seconds after generation, depending on poll interval
2. **Database load**: Every dashboard client hammers the database with identical queries
3. **Missed events**: Fast transients between poll intervals go unnoticed
4. **Scaling**: More clients = more database load, not a graceful degradation

The goal: data appears on the dashboard within milliseconds of generation, database queries happen only for historical analysis, and adding dashboard clients doesn't increase system load.

## Architecture Overview

The solution separates real-time delivery from persistent storage:

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Devices   │     │    MQTT     │     │   MongoDB   │
│  (DUT/PACS) │────▶│   Broker    │────▶│  (storage)  │
└─────────────┘     └──────┬──────┘     └─────────────┘
                           │
                           │ subscribe
                           ▼
                    ┌─────────────┐
                    │    Dash     │
                    │  Dashboard  │
                    └─────────────┘
```

Three components, three responsibilities:

| Component | Role | Protocol |
|-----------|------|----------|
| MQTT Broker | Message routing | Pub/sub over TCP |
| MongoDB | Persistent storage | Document writes |
| Dash Dashboard | Real-time visualization | MQTT subscribe + WebSocket to browser |

Data flows through MQTT to all subscribers simultaneously. The dashboard receives messages at the same moment they're written to the database—no polling required.

## Why MQTT?

MQTT (Message Queuing Telemetry Transport) was designed for constrained devices and unreliable networks. Its properties make it ideal for telemetry:

**Publish/Subscribe Decoupling**: Publishers don't know about subscribers. Adding a new dashboard doesn't require reconfiguring devices.

**Topic-Based Routing**: Messages route by topic string. Subscribers can use wildcards (`sensors/#`) to receive entire topic trees.

**QoS Levels**: Choose between fire-and-forget (QoS 0), at-least-once (QoS 1), or exactly-once (QoS 2) delivery.

**Retained Messages**: The broker stores the last message on each topic. New subscribers immediately receive current state without waiting.

**Lightweight Protocol**: Minimal overhead suits embedded devices with limited resources.

For this architecture, we use Mosquitto, the reference MQTT broker implementation:

```yaml
# docker-compose.yml (excerpt)
services:
  mqtt:
    image: eclipse-mosquitto:2
    ports:
      - "1883:1883"
    healthcheck:
      test: ["CMD-SHELL", "mosquitto_pub -h localhost -t healthcheck -m test"]
      interval: 5s
      timeout: 3s
      retries: 5
```

The healthcheck publishes a test message—if that succeeds, the broker is operational.

## Topic Architecture

Topic design determines how data flows through the system. A hierarchical structure enables flexible subscription patterns:

```
telemetry/
├── pacs/              # Power/analog sensor data
│   └── {sensor_id}    # Per-sensor readings
├── dut/               # Device under test data
│   ├── boot/          # Boot/startup messages
│   ├── status/        # State transitions
│   ├── errors/        # Error events
│   └── metrics/       # Performance data
└── cmd/               # Command/control topics
    └── run/           # Run number coordination
```

This hierarchy enables targeted subscriptions:

```python
# Subscribe to all DUT data
client.subscribe("telemetry/dut/#")

# Subscribe only to errors
client.subscribe("telemetry/dut/errors")

# Subscribe to everything
client.subscribe("telemetry/#")
```

The ingestion service subscribes to `telemetry/#` and routes messages to MongoDB collections based on topic:

```python
def resolve_collection(topic):
    """Map MQTT topic to MongoDB collection"""
    if not topic.startswith("telemetry/"):
        raise ValueError(f"Unrecognized topic: {topic}")
    subtopic = topic[len("telemetry/"):]
    collection_name = subtopic.replace("/", "_")
    return db[collection_name]
```

Topic `telemetry/dut/errors` becomes collection `dut_errors`. Simple, predictable, debuggable.

## The Ingestion Bridge

A dedicated service bridges MQTT to MongoDB. This seems like unnecessary complexity—why not have devices write directly to the database?

**Decoupling**: Devices speak MQTT. They don't need MongoDB drivers, connection pooling, or retry logic.

**Buffering**: The broker buffers messages during database outages. Direct writes would fail.

**Transformation**: The bridge can enrich messages (timestamps, metadata) before storage.

**Monitoring**: A single ingestion point simplifies debugging and metrics.

The ingestion service is minimal:

```python
def on_message(client, userdata, msg):
    # Decode and validate
    payload = json.loads(msg.payload.decode("utf-8"))

    # Prepare document with metadata
    document = {
        "ingested_at": time.time(),
        "topic": msg.topic,
        "payload": payload
    }

    # Route to appropriate collection
    collection = resolve_collection(msg.topic)
    collection.insert_one(document)
```

The service subscribes to `telemetry/#` on startup, receiving every message that flows through the system. Each message becomes a MongoDB document, preserving the original payload with added metadata.

## Real-Time Dashboard Updates

The dashboard subscribes directly to MQTT, bypassing the database for live data:

```python
import paho.mqtt.client as mqtt
import queue

# Thread-safe queue for cross-thread communication
mqtt_queue = queue.Queue()

def on_message(client, userdata, msg):
    payload = json.loads(msg.payload.decode())
    mqtt_queue.put(payload)

def start_mqtt_client():
    client = mqtt.Client()
    client.on_message = on_message
    client.connect("mqtt", 1883, 60)
    client.subscribe("telemetry/#")

    # Run in background thread
    thread = threading.Thread(target=client.loop_forever)
    thread.daemon = True
    thread.start()
```

Dash callbacks check the queue for new messages:

```python
@app.callback(
    Output('live-chart', 'figure'),
    Input('interval', 'n_intervals')
)
def update_live_chart(n):
    messages = []
    while not mqtt_queue.empty():
        try:
            messages.append(mqtt_queue.get_nowait())
        except queue.Empty:
            break

    if messages:
        # Update chart with new data
        return build_incremental_figure(messages)

    return dash.no_update  # No new data, don't re-render
```

The interval component triggers callbacks, but we only update the chart when new MQTT messages arrive. No database queries for live data.

## In-Memory Statistics

Querying MongoDB for aggregate statistics (total errors, messages per second, etc.) is expensive. Instead, maintain running statistics in memory:

```python
class RunStatistics:
    def __init__(self, run_number):
        self.run_number = run_number
        self.start_time = time.time()
        self.error_count = 0
        self.message_count = 0
        self.lock = threading.Lock()

    def update_from_message(self, message):
        with self.lock:
            self.message_count += 1
            if message.get('error_type'):
                self.error_count += 1

    def get_stats(self):
        with self.lock:
            uptime = time.time() - self.start_time
            return {
                'errors': self.error_count,
                'messages': self.message_count,
                'rate': self.message_count / uptime if uptime > 0 else 0
            }
```

Every MQTT message updates the in-memory tracker. Dashboard callbacks read from the tracker, not the database. Statistics appear instantly, with zero query overhead.

This pattern—MQTT for real-time, MongoDB for historical—lets each technology do what it's best at.

## Run Number Coordination

Test campaigns organize data by "run number"—a sequential identifier for each test execution. The challenge: multiple components need to agree on the current run number without a central coordinator.

MQTT retained messages solve this elegantly:

```python
# Start a new run
new_run = get_next_run_number()
client.publish("telemetry/cmd/run", str(new_run), retain=True)
```

The `retain=True` flag tells the broker to store this message. Any component that subscribes to `telemetry/cmd/run` immediately receives the current run number—even if it connects after the message was published.

Components include the run number in their messages:

```python
def publish_error(error_data):
    error_data['run_number'] = current_run_number
    client.publish("telemetry/dut/errors", json.dumps(error_data))
```

The dashboard filters data by run number, showing only events from the selected test:

```python
def get_run_queue(run_number):
    """Get message queue filtered by run number"""
    return run_filtered_queues[run_number]
```

No database queries, no coordination service, no race conditions. The broker maintains consensus.

## Docker Compose Orchestration

All components run in Docker containers, orchestrated by Docker Compose:

```yaml
services:
  mqtt:
    profiles: [core]
    build: ./mqtt
    healthcheck:
      test: ["CMD-SHELL", "mosquitto_pub -h localhost -t healthcheck -m test"]

  mongodb:
    profiles: [core]
    build: ./mongodb
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "27017"]

  mqtt_ingest:
    profiles: [core]
    build: ./mqtt_ingest
    depends_on:
      mqtt:
        condition: service_healthy
      mongodb:
        condition: service_healthy

  dash:
    profiles: [ui]
    build: ./dash
    depends_on:
      mqtt:
        condition: service_healthy
      mongodb:
        condition: service_healthy
```

Key patterns:

**Profiles**: Group services by function. `docker compose --profile core up` starts infrastructure without the UI. `docker compose --profile ui up` adds the dashboard.

**Health Checks**: Services wait for dependencies to be *healthy*, not just *started*. The ingestion service won't attempt database connections until MongoDB responds to pings.

**Depends On with Conditions**: `condition: service_healthy` ensures startup order respects actual readiness, not just container creation.

## What's Next

This post covered the architectural decisions. Subsequent posts dive into implementation details:

1. **Live Dashboards with Plotly Dash + MQTT** - Real-time updates, in-memory statistics, callback patterns
2. **MQTT-to-MongoDB Ingestion Pipelines** - Topic routing, message transformation, error handling
3. **Hardware Test Simulators with Finite State Machines** - Device simulation for testing without hardware
4. **Docker Compose Orchestration for Multi-Service Systems** - Profiles, Makefile automation, service dependencies

Each post provides enough detail for implementation while maintaining focus on the specific topic.

## Conclusion

The MQTT + MongoDB + Dash stack solves real-time telemetry with clear separation of concerns:

- **MQTT** handles message routing and real-time delivery
- **MongoDB** provides persistent storage for historical analysis
- **Dash** visualizes both live streams and historical data

The key insight: don't poll the database for real-time data. Subscribe to the same message stream that feeds the database. Data appears on the dashboard as fast as it can travel through the network—no artificial delays, no database load, no scaling problems.

The architecture applies to any telemetry problem: manufacturing test systems, environmental monitoring, lab automation, IoT sensor networks. The patterns transfer; only the topic names change.

---

*This post is Part 0 of the Real-Time Telemetry series. Next: [Live Dashboards with Plotly Dash + MQTT](/posts/real-time-dash-mqtt-integration)*

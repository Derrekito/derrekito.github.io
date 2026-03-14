---
title: "Real-Time Telemetry (Part 2): MQTT-to-MongoDB Ingestion Pipelines"
date: 2026-10-03
categories: [IoT, Data Engineering]
tags: [mqtt, mongodb, python, data-pipeline, ingestion, telemetry]
series: real-time-telemetry
series_order: 2
---

The dashboard subscribes to MQTT for real-time updates. But real-time data is ephemeral—once displayed, it's gone. Persistent storage enables historical analysis, trend detection, and post-mortem debugging. This post covers building reliable MQTT-to-MongoDB ingestion pipelines: topic-based routing, message transformation, error handling, and run number coordination.

## Architecture

The ingestion layer sits between the MQTT broker and MongoDB:

```
Devices ──▶ MQTT Broker ──▶ Ingestion Service ──▶ MongoDB
                │
                └──▶ Dashboard (parallel path)
```

Two subscribers receive the same messages simultaneously. The dashboard displays them; the ingestion service persists them. Neither depends on the other—if the dashboard crashes, data keeps flowing to MongoDB. If MongoDB goes down, the dashboard keeps updating.

## Topic-to-Collection Mapping

MQTT topics form a hierarchy. MongoDB collections are flat. The ingestion service maps between them:

```
Topic                      Collection
─────────────────────────  ──────────────
telemetry/sensors/temp     sensors_temp
telemetry/sensors/power    sensors_power
telemetry/events/errors    events_errors
telemetry/events/status    events_status
```

The mapping function strips the common prefix and replaces slashes with underscores:

```python
def resolve_collection(topic: str) -> Collection:
    """Map MQTT topic to MongoDB collection."""
    PREFIX = "telemetry/"

    if not topic.startswith(PREFIX):
        raise ValueError(f"Unrecognized topic: {topic}")

    subtopic = topic[len(PREFIX):]
    collection_name = subtopic.replace("/", "_")

    return db[collection_name]
```

This creates collections dynamically. New topics automatically get new collections—no schema changes required.

## Basic Ingestion Service

The minimal ingestion service subscribes to all topics under a prefix and writes each message to the appropriate collection:

```python
import json
import time
import logging
from pymongo import MongoClient
from pymongo.errors import ConnectionFailure, OperationFailure
import paho.mqtt.client as mqtt

logger = logging.getLogger(__name__)

# Configuration from environment
MQTT_HOST = os.getenv("MQTT_HOST", "mqtt")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))
MONGO_HOST = os.getenv("MONGO_HOST", "mongodb")
MONGO_PORT = int(os.getenv("MONGO_PORT", "27017"))
MONGO_DB = os.getenv("MONGO_DB")

if not MONGO_DB:
    raise ValueError("MONGO_DB environment variable required")

# MongoDB connection
mongo_client = MongoClient(MONGO_HOST, MONGO_PORT, serverSelectionTimeoutMS=5000)
mongo_client.admin.command("ping")  # Verify connection
db = mongo_client[MONGO_DB]

def on_connect(client, userdata, flags, rc, properties):
    logger.info(f"Connected to MQTT broker (rc={rc})")
    client.subscribe("telemetry/#")

def on_message(client, userdata, msg):
    try:
        # Decode payload
        raw_payload = msg.payload.decode("utf-8")

        # Parse JSON or store as string
        try:
            payload = json.loads(raw_payload)
            data_type = type(payload).__name__
        except json.JSONDecodeError:
            payload = raw_payload
            data_type = "str"

        # Build document with metadata
        document = {
            "ingested_at": time.time(),
            "data_type": data_type,
        }

        # Handle different payload types
        if isinstance(payload, dict):
            document["payload"] = payload
        elif isinstance(payload, list):
            document["data"] = payload
        else:
            document["message"] = payload

        # Route to collection and insert
        collection = resolve_collection(msg.topic)
        result = collection.insert_one(document)
        logger.info(f"Stored to {collection.name}: {result.inserted_id}")

    except ValueError as e:
        logger.warning(f"Ignored topic: {e}")
    except Exception as e:
        logger.error(f"Ingestion error: {e}")

# MQTT client setup
client = mqtt.Client(callback_api_version=mqtt.CallbackAPIVersion.VERSION2)
client.on_connect = on_connect
client.on_message = on_message
client.connect(MQTT_HOST, MQTT_PORT, 60)
client.loop_forever()
```

This handles the happy path. Real systems need more.

## Payload Validation

Not all payloads are valid. Implement defensive checks:

```python
def on_message(client, userdata, msg):
    # Size limit (1MB)
    if len(msg.payload) > 1_000_000:
        logger.warning(f"Payload too large: {len(msg.payload)} bytes")
        return

    # UTF-8 validation
    try:
        raw_payload = msg.payload.decode("utf-8")
    except UnicodeDecodeError:
        logger.warning(f"Invalid UTF-8 on topic {msg.topic}")
        return

    # JSON parsing with fallback
    try:
        payload = json.loads(raw_payload)
    except json.JSONDecodeError:
        # Store as string, not an error
        payload = raw_payload

    # Continue processing...
```

## Retry Logic

MongoDB operations can fail transiently. Implement retry with backoff:

```python
def insert_with_retry(collection, document, max_attempts=3):
    """Insert document with retry logic."""
    for attempt in range(max_attempts):
        try:
            result = collection.insert_one(document)
            return result
        except OperationFailure as e:
            if attempt == max_attempts - 1:
                logger.error(f"Insert failed after {max_attempts} attempts: {e}")
                raise
            logger.warning(f"Insert attempt {attempt + 1} failed, retrying...")
            time.sleep(1 * (attempt + 1))  # Linear backoff
```

For critical data, consider a dead-letter queue:

```python
def insert_with_dlq(collection, document):
    """Insert with dead-letter queue fallback."""
    try:
        return insert_with_retry(collection, document)
    except OperationFailure:
        # Store in dead-letter collection for manual review
        dlq = db["dead_letter_queue"]
        dlq.insert_one({
            "original_collection": collection.name,
            "document": document,
            "failed_at": time.time(),
        })
        logger.error(f"Document moved to DLQ: {document.get('_id', 'unknown')}")
```

## Message Routing by Pattern

Some systems need more sophisticated routing than topic-to-collection mapping. Device output might include prefix markers indicating message type:

```
B> System booting, firmware v2.3.1
M> Matrix test starting, size 1024x1024
{"error_type": "memory", "address": "0x7fff1234", "value": 42}
```

Route based on content patterns:

```python
class MessageProcessor:
    """Route messages based on content patterns."""

    def __init__(self, mqtt_manager):
        self.mqtt_manager = mqtt_manager

    def process_line(self, line: str):
        """Route line to appropriate topic based on pattern."""
        stripped = line.strip()

        # Boot messages: B> prefix
        if stripped.startswith("B>"):
            content = stripped[2:].lstrip()
            self._publish_structured("boot", content)
            return

        # Matrix messages: M> prefix
        if stripped.startswith("M>"):
            content = stripped[2:].lstrip()
            self._publish_structured("matrix", content)
            return

        # JSON messages: starts with {
        if stripped.startswith("{"):
            self._publish_json(stripped)
            return

        # Unrecognized: route to fallback
        logger.warning(f"Unrecognized format: {stripped[:100]}")
        self._publish_structured("fallback", stripped)

    def _publish_structured(self, message_type: str, content: str):
        """Wrap raw content in structured message."""
        message = {
            "timestamp": time.time(),
            "message_type": message_type,
            "content": content,
        }
        topic = f"telemetry/device/{message_type}"
        self.mqtt_manager.publish(topic, json.dumps(message))

    def _publish_json(self, raw_json: str):
        """Parse and republish JSON messages."""
        try:
            parsed = json.loads(raw_json)
            topic = "telemetry/device/events"
            self.mqtt_manager.publish(topic, json.dumps(parsed))
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON: {e}")
            self._publish_structured("malformed", raw_json)
```

## Normalizing Non-Standard JSON

Some embedded devices output JSON-like formats without proper quoting:

```
{error_type:memory, address:0x7fff1234, count:42}
```

Normalize before parsing:

```python
import re

def normalize_json(message: str) -> str:
    """Convert {key:value} to {"key":"value"} format."""

    def quote_replacement(match):
        key = match.group(1).strip()
        value = match.group(2).strip()

        # Don't quote numbers, booleans, null
        if _is_json_literal(value):
            return f'"{key}":{value}'
        else:
            return f'"{key}":"{value}"'

    stripped = message.strip()

    if stripped.startswith('{') and stripped.endswith('}'):
        normalized = re.sub(
            r'([a-zA-Z_][a-zA-Z0-9_]*):([^,}]+)',
            quote_replacement,
            stripped
        )
        return normalized

    return message

def _is_json_literal(value: str) -> bool:
    """Check if value is a valid JSON literal (number, bool, null)."""
    if value.lower() in ('true', 'false', 'null'):
        return True
    try:
        float(value)
        return True
    except ValueError:
        return False
```

## Run Number Coordination

Test campaigns organize data by "run number"—a monotonically increasing identifier. All messages from a test run share the same run number, enabling filtering and aggregation.

The challenge: the device generating data doesn't know the run number. A separate control system manages test execution. How do they coordinate?

**Solution: MQTT retained messages.**

The control system publishes the run number to a dedicated topic with the `retain` flag:

```python
# Control system starts a new run
new_run = get_next_run_number()
client.publish("telemetry/run", json.dumps({"run_number": new_run}), retain=True)
```

The ingestion service subscribes to this topic on startup. The broker immediately delivers the retained message—the last value published to that topic. The service then embeds the run number in all subsequent messages.

```python
class MQTTManager:
    def __init__(self):
        self.current_run_number = "unknown"
        self.run_number_lock = threading.Lock()

    def query_latest_run_number(self):
        """Query retained run number on startup."""
        query_completed = threading.Event()
        found_run = None

        def on_message(client, userdata, msg):
            nonlocal found_run
            try:
                data = json.loads(msg.payload.decode())
                found_run = data.get("run_number")
                if found_run:
                    self.set_run_number(found_run)
            except Exception as e:
                logger.warning(f"Error parsing run number: {e}")
            query_completed.set()
            client.disconnect()

        # Temporary client just for the query
        query_client = mqtt.Client()
        query_client.on_message = on_message
        query_client.connect(MQTT_HOST, MQTT_PORT)
        query_client.subscribe("telemetry/run")
        query_client.loop_start()

        # Wait for retained message or timeout
        query_completed.wait(timeout=5.0)
        query_client.loop_stop()

        if not found_run:
            logger.warning("No retained run number found, using fallback")
            self.set_run_number("unknown")

    def set_run_number(self, run_number):
        with self.run_number_lock:
            old = self.current_run_number
            self.current_run_number = run_number
            logger.info(f"Run number: {old} → {run_number}")

    def publish_with_run_number(self, topic: str, data: dict):
        """Publish message with embedded run number."""
        with self.run_number_lock:
            data["run_number"] = self.current_run_number
        self.client.publish(topic, json.dumps(data))
```

Subscribe to the run topic for updates during operation:

```python
def _on_connect(self, client, userdata, flags, rc, properties=None):
    if rc == 0:
        # Subscribe to run number updates
        client.subscribe("telemetry/run")
        logger.info("Subscribed to run topic")

def _on_message(self, client, userdata, msg):
    if msg.topic == "telemetry/run":
        try:
            data = json.loads(msg.payload.decode())
            run_number = data.get("run_number")
            if run_number:
                self.set_run_number(run_number)
        except json.JSONDecodeError:
            logger.warning("Invalid JSON in run message")
```

Now every ingested document includes `run_number`, enabling queries like:

```python
# Get all errors from run 42
db.device_errors.find({"payload.run_number": 42})

# Aggregate error counts per run
db.device_errors.aggregate([
    {"$group": {"_id": "$payload.run_number", "count": {"$sum": 1}}}
])
```

## Multi-Input Ingestion

Some systems receive data from multiple sources: UDP packets from legacy devices, stdin from process pipes, HTTP webhooks. Handle all inputs in a single service:

```python
import select
import socket
import sys

class MultiInputIngestor:
    def __init__(self):
        self.running = True
        self.mqtt_manager = MQTTManager()
        self.processor = MessageProcessor(self.mqtt_manager)

        # UDP socket for legacy devices
        self.udp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.udp_socket.bind(("", 5000))

    def run(self):
        """Main loop handling multiple input sources."""
        while self.running:
            # Monitor both stdin and UDP
            ready, _, _ = select.select(
                [sys.stdin, self.udp_socket], [], [], 0.1
            )

            for source in ready:
                if source == sys.stdin:
                    self._process_stdin()
                elif source == self.udp_socket:
                    self._process_udp()

    def _process_stdin(self):
        """Process line from stdin."""
        line = sys.stdin.readline()
        if line:
            self.processor.process_line(line.strip())

    def _process_udp(self):
        """Process UDP packet."""
        data, addr = self.udp_socket.recvfrom(65535)

        try:
            raw = data.decode("utf-8")

            # Health check support
            if raw.strip() == "ping":
                self.udp_socket.sendto(b"pong", addr)
                return

            self.processor.process_line(raw)

        except UnicodeDecodeError:
            logger.warning(f"Non-UTF8 data from {addr}")
            self._handle_binary_data(data)

    def _handle_binary_data(self, data: bytes):
        """Handle non-text data."""
        self.processor.process_line(data.hex())
```

## Queue-Based Publishing

Don't block the message handler on MQTT publishes. Use a queue with a background publisher thread:

```python
class MQTTManager:
    def __init__(self):
        self.publish_queue = queue.Queue(maxsize=1000)
        self.publisher_thread = None
        self.running = False

    def start_publisher(self):
        """Start background publisher thread."""
        self.running = True
        self.publisher_thread = threading.Thread(
            target=self._publisher_loop, daemon=True
        )
        self.publisher_thread.start()

    def publish(self, topic: str, message: str, qos: int = 0):
        """Queue message for publishing."""
        try:
            self.publish_queue.put((topic, message, qos), block=False)
        except queue.Full:
            # Drop oldest message to make room
            try:
                self.publish_queue.get_nowait()
                self.publish_queue.put((topic, message, qos), block=False)
            except queue.Empty:
                pass

    def _publisher_loop(self):
        """Background thread that drains the publish queue."""
        while self.running:
            try:
                topic, message, qos = self.publish_queue.get(timeout=1)
                self.client.publish(topic, message, qos=qos)
            except queue.Empty:
                continue
            except Exception as e:
                logger.error(f"Publish error: {e}")
```

## Reconnection Handling

Network interruptions happen. Implement exponential backoff reconnection:

```python
def _on_disconnect(self, client, userdata, flags, rc, properties=None):
    """Handle disconnection with exponential backoff."""
    if rc != 0:
        logger.warning(f"Disconnected (rc={rc}), reconnecting...")
        backoff = 1

        while self.running:
            try:
                client.reconnect()
                logger.info("Reconnected successfully")
                return
            except Exception as e:
                logger.error(f"Reconnect failed: {e}, retrying in {backoff}s")
                time.sleep(backoff)
                backoff = min(backoff * 2, 60)  # Cap at 60 seconds
```

## Docker Deployment

Package the ingestion service as a Docker container:

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY *.py .

CMD ["python", "mqtt_ingest.py"]
```

Configure via environment variables in Docker Compose:

```yaml
services:
  mqtt_ingest:
    build: ./mqtt_ingest
    depends_on:
      mqtt:
        condition: service_healthy
      mongodb:
        condition: service_healthy
    environment:
      - MQTT_HOST=mqtt
      - MQTT_PORT=1883
      - MONGO_HOST=mongodb
      - MONGO_PORT=27017
      - MONGO_DB=telemetry
    restart: unless-stopped
```

The `depends_on` with `condition: service_healthy` ensures the ingestion service only starts after both MQTT and MongoDB are ready.

## Monitoring and Observability

Add metrics for operational visibility:

```python
class IngestMetrics:
    def __init__(self):
        self.messages_received = 0
        self.messages_stored = 0
        self.errors = 0
        self.start_time = time.time()

    def record_received(self):
        self.messages_received += 1

    def record_stored(self):
        self.messages_stored += 1

    def record_error(self):
        self.errors += 1

    def get_stats(self) -> dict:
        uptime = time.time() - self.start_time
        return {
            "messages_received": self.messages_received,
            "messages_stored": self.messages_stored,
            "errors": self.errors,
            "uptime_seconds": uptime,
            "rate": self.messages_received / uptime if uptime > 0 else 0,
        }

metrics = IngestMetrics()
```

Expose metrics via a health endpoint or publish to a monitoring topic:

```python
def publish_metrics():
    """Publish metrics to monitoring topic."""
    while True:
        time.sleep(60)
        stats = metrics.get_stats()
        client.publish("telemetry/metrics/ingest", json.dumps(stats))
```

## What's Next

The ingestion pipeline is complete. But testing requires real device data—or does it? The next post covers building device simulators with finite state machines, enabling full system testing without hardware.

---

*This post is Part 2 of the Real-Time Telemetry series. Previous: [Live Dashboards with Plotly Dash + MQTT](/posts/real-time-dash-mqtt-integration). Next: [Hardware Test Simulators with Finite State Machines](/posts/hardware-test-simulators-fsm)*

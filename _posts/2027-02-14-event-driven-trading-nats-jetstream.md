---
title: "Part 1: Designing an Event-Driven Trading Infrastructure with NATS JetStream"
date: 2027-02-14 10:00:00 -0700
categories: [Trading Systems, Architecture]
tags: [nats, jetstream, event-driven, microservices, financial-data, real-time, python]
series: real-time-trading-infrastructure
series_order: 1
---

*Part 1 of the Real-Time Trading Infrastructure series. This 10-part series covers the design and implementation of a production-grade trading platform.*

Financial markets generate millions of events per second. Price updates, order executions, position changes, and risk calculations flow continuously through trading systems. Traditional request-response architectures struggle under this load—synchronous calls create bottlenecks, tight coupling prevents independent scaling, and failures cascade through dependent services. Event-driven architecture addresses these challenges through asynchronous message passing, temporal decoupling, and replay capabilities essential for financial auditing.

This post examines the design of an event-driven trading infrastructure using NATS JetStream, covering message broker selection criteria, stream topology patterns, and implementation details for high-throughput financial data processing.

## Why Event-Driven Architecture for Trading Systems

Trading platforms exhibit characteristics that align naturally with event-driven patterns:

**High-Frequency Updates**: Market data feeds generate thousands of price updates per second per instrument. Synchronous processing cannot keep pace; the system must handle updates asynchronously without blocking downstream consumers.

**Temporal Decoupling**: Order execution services should not wait for risk calculations to complete. Position updates must propagate to multiple consumers—portfolio tracking, P&L calculation, compliance monitoring—without the producer knowing which consumers exist.

**Replay and Audit Requirements**: Regulatory compliance demands complete audit trails. Event sourcing enables reconstruction of system state at any point in time, essential for trade surveillance and dispute resolution.

**Independent Scaling**: Market data handlers require different scaling characteristics than order management. Event-driven systems allow horizontal scaling of individual components without architectural changes.

**Fault Isolation**: A failing analytics service should not impact order execution. Message queues provide natural circuit breakers, preventing cascade failures.

## Message Broker Selection: NATS vs Kafka vs RabbitMQ

Trading systems impose specific requirements on message infrastructure: sub-millisecond latency, at-least-once delivery guarantees, message persistence, and operational simplicity. Three brokers merit consideration.

### Apache Kafka

Kafka dominates enterprise event streaming through its distributed commit log architecture. Strengths include:

- Proven at massive scale (trillions of messages per day at LinkedIn)
- Strong durability guarantees with configurable replication
- Mature ecosystem with Kafka Streams, Connect, and Schema Registry
- Excellent throughput for batch analytics

However, Kafka introduces operational complexity unsuitable for smaller teams:

- ZooKeeper dependency (though being removed in newer versions)
- Complex partition management and rebalancing
- High resource requirements for coordination overhead
- Minimum cluster size for production reliability

### RabbitMQ

RabbitMQ provides traditional message queue semantics with AMQP protocol compliance:

- Flexible routing through exchanges and bindings
- Acknowledgment-based delivery with dead letter handling
- Familiar queue semantics for developers
- Plugin ecosystem for management and monitoring

Limitations for trading systems include:

- Single-node message ordering only
- Replay requires external tooling or storage
- Performance degrades under high message rates
- Clustering adds complexity without improving throughput

### NATS with JetStream

NATS occupies a different design point: simplicity, performance, and operational elegance. Core NATS provides fire-and-forget pub/sub at millions of messages per second with sub-millisecond latency. JetStream adds persistence, exactly-once delivery, and replay capabilities.

Advantages for trading infrastructure:

- **Operational Simplicity**: Single binary, minimal configuration, embedded or clustered
- **Performance**: Sub-millisecond latency for real-time market data
- **JetStream Persistence**: Durable streams with configurable retention
- **Subject Hierarchies**: Wildcard subscriptions enable flexible routing
- **Lightweight Footprint**: Runs efficiently on modest hardware
- **Built-in Clustering**: RAFT-based consensus without external dependencies

NATS trades some of Kafka's analytics features for operational simplicity and latency characteristics that suit real-time trading systems.

## System Architecture Overview

The following diagram illustrates the event flow through a trading platform built on NATS JetStream:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         NATS JetStream Cluster                               │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                           STREAMS                                        ││
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐  ││
│  │  │ MARKET_DATA  │  │   ORDERS     │  │  POSITIONS   │  │    RISK     │  ││
│  │  │ md.>         │  │ orders.>     │  │ positions.>  │  │ risk.>      │  ││
│  │  └──────────────┘  └──────────────┘  └──────────────┘  └─────────────┘  ││
│  └─────────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────┘
         ▲                    ▲                    ▲                ▲
         │                    │                    │                │
    ┌────┴────┐          ┌────┴────┐          ┌────┴────┐      ┌────┴────┐
    │ Market  │          │  Order  │          │Position │      │  Risk   │
    │  Data   │          │ Gateway │          │ Manager │      │ Engine  │
    │ Adapter │          │         │          │         │      │         │
    └─────────┘          └─────────┘          └─────────┘      └─────────┘
         ▲                    ▲                    │                │
         │                    │                    ▼                ▼
    ┌─────────┐          ┌─────────┐          ┌─────────┐      ┌─────────┐
    │Exchange │          │  REST   │          │Portfolio│      │Alerting │
    │  Feed   │          │   API   │          │   UI    │      │ System  │
    └─────────┘          └─────────┘          └─────────┘      └─────────┘
```

### Component Responsibilities

**Market Data Adapter**: Connects to exchange feeds, normalizes data formats, publishes to `md.<exchange>.<instrument>` subjects.

**Order Gateway**: Receives order requests via REST API, validates parameters, publishes to `orders.new`, listens for execution reports on `orders.executed.<order_id>`.

**Position Manager**: Consumes execution reports, maintains position state, publishes position updates to `positions.<account>.<instrument>`.

**Risk Engine**: Subscribes to positions and market data, calculates real-time risk metrics, publishes alerts to `risk.alerts.<severity>`.

## JetStream Stream Design Patterns

JetStream streams define how messages persist and which subjects belong to each stream. Proper stream design impacts performance, storage efficiency, and consumer flexibility.

### Stream Configuration

```python
import nats
from nats.js.api import StreamConfig, RetentionPolicy, StorageType

async def create_market_data_stream(js):
    """Configure market data stream with appropriate retention."""
    config = StreamConfig(
        name="MARKET_DATA",
        subjects=["md.>"],  # Capture all market data subjects
        retention=RetentionPolicy.LIMITS,
        max_age=86400,  # 24 hours in seconds
        max_bytes=10_737_418_240,  # 10 GB
        storage=StorageType.FILE,
        num_replicas=3,
        duplicate_window=120,  # 2 minutes dedup window
    )

    await js.add_stream(config)
    print(f"Created stream: {config.name}")
```

### Subject Hierarchy Design

Subject hierarchies enable flexible subscription patterns through wildcards:

```
md.                          # Market data root
  ├── md.nyse.               # NYSE exchange
  │   ├── md.nyse.AAPL       # Apple quotes
  │   ├── md.nyse.GOOG       # Google quotes
  │   └── md.nyse.MSFT       # Microsoft quotes
  ├── md.nasdaq.             # NASDAQ exchange
  │   ├── md.nasdaq.TSLA     # Tesla quotes
  │   └── md.nasdaq.AMZN     # Amazon quotes
  └── md.crypto.             # Cryptocurrency
      ├── md.crypto.BTC-USD  # Bitcoin
      └── md.crypto.ETH-USD  # Ethereum

orders.                      # Order lifecycle
  ├── orders.new             # New order submissions
  ├── orders.validated       # Orders passing validation
  ├── orders.rejected        # Validation failures
  ├── orders.executed.>      # Execution reports by order ID
  └── orders.cancelled.>     # Cancellation confirmations
```

Subscription patterns supported by this hierarchy:

| Pattern | Description |
|---------|-------------|
| `md.>` | All market data across all exchanges |
| `md.nyse.>` | All NYSE instruments |
| `md.*.AAPL` | AAPL across all exchanges |
| `orders.executed.*` | All execution reports |
| `orders.>` | Complete order lifecycle |

### Stream Separation Strategy

Separate streams serve different retention and performance requirements:

```python
async def create_all_streams(js):
    """Create streams with appropriate configurations."""

    # Market data: high volume, time-based retention
    await js.add_stream(StreamConfig(
        name="MARKET_DATA",
        subjects=["md.>"],
        max_age=86400,  # 24 hours
        storage=StorageType.FILE,
    ))

    # Orders: moderate volume, longer retention for audit
    await js.add_stream(StreamConfig(
        name="ORDERS",
        subjects=["orders.>"],
        max_age=2592000,  # 30 days
        storage=StorageType.FILE,
    ))

    # Positions: low volume, indefinite retention
    await js.add_stream(StreamConfig(
        name="POSITIONS",
        subjects=["positions.>"],
        retention=RetentionPolicy.LIMITS,
        max_bytes=1_073_741_824,  # 1 GB
        storage=StorageType.FILE,
    ))

    # Risk alerts: critical messages, replicated
    await js.add_stream(StreamConfig(
        name="RISK",
        subjects=["risk.>"],
        max_age=604800,  # 7 days
        num_replicas=3,
        storage=StorageType.FILE,
    ))
```

## NATS Client Implementation Patterns

The following patterns demonstrate production-ready NATS client implementations in Python using the official `nats-py` library.

### Connection Management

Robust connection handling requires reconnection logic and error callbacks:

```python
import asyncio
import nats
from nats.errors import ConnectionClosedError, TimeoutError

class NATSClient:
    """Managed NATS connection with automatic reconnection."""

    def __init__(self, servers: list[str]):
        self.servers = servers
        self.nc = None
        self.js = None

    async def connect(self):
        """Establish connection with reconnection handlers."""
        self.nc = await nats.connect(
            servers=self.servers,
            reconnect_time_wait=2,
            max_reconnect_attempts=60,
            error_cb=self._error_callback,
            disconnected_cb=self._disconnected_callback,
            reconnected_cb=self._reconnected_callback,
            closed_cb=self._closed_callback,
        )
        self.js = self.nc.jetstream()
        print(f"Connected to NATS: {self.nc.connected_url}")

    async def _error_callback(self, error):
        print(f"NATS error: {error}")

    async def _disconnected_callback(self):
        print("NATS disconnected")

    async def _reconnected_callback(self):
        print(f"NATS reconnected to {self.nc.connected_url}")

    async def _closed_callback(self):
        print("NATS connection closed")

    async def close(self):
        """Graceful shutdown."""
        if self.nc:
            await self.nc.drain()
            await self.nc.close()
```

### Publishing with Acknowledgment

JetStream publishing provides delivery confirmation:

```python
import json
from dataclasses import dataclass, asdict
from datetime import datetime

@dataclass
class MarketQuote:
    symbol: str
    exchange: str
    bid: float
    ask: float
    bid_size: int
    ask_size: int
    timestamp: str

    def to_json(self) -> bytes:
        return json.dumps(asdict(self)).encode()

class MarketDataPublisher:
    """Publish market data with delivery guarantees."""

    def __init__(self, js):
        self.js = js

    async def publish_quote(self, quote: MarketQuote):
        """Publish quote with acknowledgment."""
        subject = f"md.{quote.exchange.lower()}.{quote.symbol}"

        try:
            ack = await self.js.publish(
                subject,
                quote.to_json(),
                timeout=5.0,
            )
            return ack.seq  # Stream sequence number
        except TimeoutError:
            print(f"Publish timeout for {subject}")
            raise

    async def publish_batch(self, quotes: list[MarketQuote]):
        """Publish multiple quotes concurrently."""
        tasks = [self.publish_quote(q) for q in quotes]
        return await asyncio.gather(*tasks, return_exceptions=True)
```

### Durable Consumer Subscription

Durable consumers maintain position across restarts:

```python
from nats.js.api import ConsumerConfig, AckPolicy, DeliverPolicy

class MarketDataConsumer:
    """Consume market data with durable subscription."""

    def __init__(self, js, handler_callback):
        self.js = js
        self.handler = handler_callback
        self.subscription = None

    async def subscribe(self, subject_filter: str, consumer_name: str):
        """Create durable pull consumer."""
        config = ConsumerConfig(
            durable_name=consumer_name,
            ack_policy=AckPolicy.EXPLICIT,
            deliver_policy=DeliverPolicy.NEW,
            max_deliver=3,  # Retry failed messages up to 3 times
            ack_wait=30,  # Seconds before redelivery
            filter_subject=subject_filter,
        )

        self.subscription = await self.js.pull_subscribe(
            subject_filter,
            durable=consumer_name,
            config=config,
        )

    async def process_messages(self, batch_size: int = 100):
        """Fetch and process message batches."""
        while True:
            try:
                messages = await self.subscription.fetch(
                    batch=batch_size,
                    timeout=1.0,
                )

                for msg in messages:
                    try:
                        await self.handler(msg)
                        await msg.ack()
                    except Exception as e:
                        print(f"Handler error: {e}")
                        await msg.nak(delay=5)  # Retry after 5 seconds

            except TimeoutError:
                continue  # No messages available, retry
            except Exception as e:
                print(f"Fetch error: {e}")
                await asyncio.sleep(1)
```

### Push-Based Subscription for Low Latency

Push subscriptions minimize latency for real-time processing:

```python
class RealTimeQuoteHandler:
    """Low-latency push subscription for market data."""

    def __init__(self, js):
        self.js = js
        self.subscriptions = []

    async def subscribe_symbol(self, exchange: str, symbol: str, callback):
        """Subscribe to specific symbol with push delivery."""
        subject = f"md.{exchange.lower()}.{symbol}"

        async def message_handler(msg):
            quote = json.loads(msg.data.decode())
            await callback(quote)
            await msg.ack()

        sub = await self.js.subscribe(
            subject,
            cb=message_handler,
            durable=f"quote_handler_{exchange}_{symbol}",
            manual_ack=True,
        )
        self.subscriptions.append(sub)

    async def subscribe_exchange(self, exchange: str, callback):
        """Subscribe to all symbols on an exchange."""
        subject = f"md.{exchange.lower()}.>"

        async def message_handler(msg):
            quote = json.loads(msg.data.decode())
            await callback(quote)
            await msg.ack()

        sub = await self.js.subscribe(
            subject,
            cb=message_handler,
            durable=f"quote_handler_{exchange}_all",
            manual_ack=True,
        )
        self.subscriptions.append(sub)

    async def unsubscribe_all(self):
        """Clean shutdown of all subscriptions."""
        for sub in self.subscriptions:
            await sub.unsubscribe()
```

## Backpressure Handling

Financial data streams exhibit variable rates. Market open generates order-of-magnitude higher message rates than overnight sessions. Systems must handle bursts without data loss or cascade failures.

### Flow Control Configuration

JetStream provides built-in flow control for push consumers:

```python
from nats.js.api import ConsumerConfig, AckPolicy

async def create_flow_controlled_consumer(js):
    """Consumer with flow control for bursty workloads."""
    config = ConsumerConfig(
        durable_name="risk_calculator",
        ack_policy=AckPolicy.EXPLICIT,
        max_ack_pending=1000,  # Limit outstanding unacked messages
        flow_control=True,  # Enable flow control
        idle_heartbeat=5.0,  # Heartbeat interval in seconds
    )

    return await js.pull_subscribe(
        "positions.>",
        durable="risk_calculator",
        config=config,
    )
```

### Rate Limiting Publisher

When downstream systems cannot keep pace, publishers should throttle:

```python
import asyncio
from collections import deque
from datetime import datetime, timedelta

class RateLimitedPublisher:
    """Publisher with configurable rate limiting."""

    def __init__(self, js, max_rate: int = 10000):
        self.js = js
        self.max_rate = max_rate  # Messages per second
        self.timestamps = deque()
        self.lock = asyncio.Lock()

    async def publish(self, subject: str, data: bytes):
        """Publish with rate limiting."""
        async with self.lock:
            now = datetime.now()
            cutoff = now - timedelta(seconds=1)

            # Remove timestamps older than 1 second
            while self.timestamps and self.timestamps[0] < cutoff:
                self.timestamps.popleft()

            # Wait if at rate limit
            if len(self.timestamps) >= self.max_rate:
                sleep_time = (self.timestamps[0] - cutoff).total_seconds()
                if sleep_time > 0:
                    await asyncio.sleep(sleep_time)

            self.timestamps.append(now)

        return await self.js.publish(subject, data)
```

### Consumer Group Load Balancing

Multiple consumers share load through queue groups:

```python
async def create_consumer_group(js, group_name: str, subject: str, handler):
    """Create load-balanced consumer group."""
    # All consumers with same queue group receive round-robin delivery
    config = ConsumerConfig(
        durable_name=group_name,
        deliver_group=group_name,  # Queue group for load balancing
        ack_policy=AckPolicy.EXPLICIT,
        max_ack_pending=500,
    )

    return await js.subscribe(
        subject,
        queue=group_name,
        cb=handler,
        config=config,
    )

# Deploy multiple instances with same group name
# Messages distribute across instances automatically
```

## Message Replay and Recovery

JetStream maintains message history, enabling replay for recovery or backtesting:

```python
from nats.js.api import DeliverPolicy
from datetime import datetime, timedelta

class MessageReplayer:
    """Replay historical messages for recovery or analysis."""

    def __init__(self, js):
        self.js = js

    async def replay_from_time(
        self,
        stream: str,
        subject: str,
        start_time: datetime,
        handler
    ):
        """Replay messages from specific timestamp."""
        config = ConsumerConfig(
            deliver_policy=DeliverPolicy.BY_START_TIME,
            opt_start_time=start_time.isoformat(),
            ack_policy=AckPolicy.NONE,  # No acks for replay
        )

        sub = await self.js.subscribe(
            subject,
            config=config,
        )

        async for msg in sub.messages:
            await handler(msg)

    async def replay_from_sequence(
        self,
        stream: str,
        subject: str,
        start_seq: int,
        handler
    ):
        """Replay messages from specific sequence number."""
        config = ConsumerConfig(
            deliver_policy=DeliverPolicy.BY_START_SEQUENCE,
            opt_start_seq=start_seq,
            ack_policy=AckPolicy.NONE,
        )

        sub = await self.js.subscribe(
            subject,
            config=config,
        )

        async for msg in sub.messages:
            await handler(msg)
```

## Complete Example: Market Data Pipeline

The following demonstrates a complete market data ingestion and distribution pipeline:

```python
import asyncio
import json
import nats
from datetime import datetime
from dataclasses import dataclass, asdict

@dataclass
class Quote:
    symbol: str
    exchange: str
    bid: float
    ask: float
    timestamp: str

async def run_market_data_pipeline():
    """Complete market data pipeline example."""

    # Connect to NATS
    nc = await nats.connect("nats://localhost:4222")
    js = nc.jetstream()

    # Ensure stream exists
    try:
        await js.add_stream(
            name="MARKET_DATA",
            subjects=["md.>"],
            max_age=86400,
        )
    except nats.js.errors.BadRequestError:
        pass  # Stream already exists

    # Publisher task: simulate market data feed
    async def publisher():
        symbols = ["AAPL", "GOOG", "MSFT", "TSLA"]
        while True:
            for symbol in symbols:
                quote = Quote(
                    symbol=symbol,
                    exchange="NYSE",
                    bid=round(100 + (hash(symbol) % 100) + 0.01, 2),
                    ask=round(100 + (hash(symbol) % 100) + 0.02, 2),
                    timestamp=datetime.utcnow().isoformat(),
                )
                subject = f"md.nyse.{symbol}"
                await js.publish(subject, json.dumps(asdict(quote)).encode())
            await asyncio.sleep(0.1)  # 10 updates per second

    # Consumer task: process market data
    async def consumer():
        sub = await js.subscribe(
            "md.nyse.>",
            durable="market_data_processor",
        )

        async for msg in sub.messages:
            quote = json.loads(msg.data.decode())
            spread = quote["ask"] - quote["bid"]
            print(f"{quote['symbol']}: bid={quote['bid']}, ask={quote['ask']}, spread={spread:.4f}")
            await msg.ack()

    # Run both tasks
    await asyncio.gather(
        publisher(),
        consumer(),
    )

if __name__ == "__main__":
    asyncio.run(run_market_data_pipeline())
```

## Production Considerations

### Monitoring and Observability

NATS exposes metrics through its monitoring endpoint:

```python
import aiohttp

async def fetch_nats_metrics(monitoring_url: str = "http://localhost:8222"):
    """Fetch NATS server metrics for monitoring."""
    async with aiohttp.ClientSession() as session:
        # Server info
        async with session.get(f"{monitoring_url}/varz") as resp:
            server_info = await resp.json()

        # JetStream info
        async with session.get(f"{monitoring_url}/jsz") as resp:
            js_info = await resp.json()

        # Connection info
        async with session.get(f"{monitoring_url}/connz") as resp:
            conn_info = await resp.json()

    return {
        "server": server_info,
        "jetstream": js_info,
        "connections": conn_info,
    }
```

### High Availability Deployment

Production deployments require clustered NATS for fault tolerance:

```yaml
# nats-server.conf
server_name: nats-1
listen: 0.0.0.0:4222
http: 0.0.0.0:8222

jetstream {
  store_dir: /data/jetstream
  max_memory_store: 1G
  max_file_store: 100G
}

cluster {
  name: trading-cluster
  listen: 0.0.0.0:6222
  routes: [
    nats-route://nats-2:6222,
    nats-route://nats-3:6222,
  ]
}
```

### Security Configuration

Production systems require TLS and authentication:

```python
async def connect_secure():
    """Connect with TLS and credentials."""
    nc = await nats.connect(
        servers=["nats://nats.example.com:4222"],
        tls=nats.TLSConfig(
            ca_file="/certs/ca.pem",
            cert_file="/certs/client.pem",
            key_file="/certs/client-key.pem",
        ),
        user="trading_service",
        password="secure_password",
    )
    return nc
```

## Summary

Event-driven architecture provides the foundation for scalable, resilient trading systems. NATS JetStream offers an compelling combination of performance, operational simplicity, and durability for real-time financial data processing. Key design decisions include:

- **Stream separation** by data domain with appropriate retention policies
- **Subject hierarchies** enabling flexible subscription patterns
- **Durable consumers** maintaining position across restarts
- **Flow control** preventing cascade failures during traffic bursts
- **Message replay** supporting recovery and regulatory requirements

The patterns presented here establish the messaging foundation. However, a complete trading platform requires additional components: persistent storage for historical data, time-series databases for analytics, and caching layers for low-latency lookups.

---

*Next in the series: [Part 2: Polyglot Persistence for Trading Data](/posts/polyglot-persistence-trading-data/) examines storage strategies for different data types—time-series databases for market data, document stores for order state, and graph databases for entity relationships.*

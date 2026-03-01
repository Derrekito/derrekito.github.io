---
title: "Part 4: Building a Reliable WebSocket Data Pipeline for Cryptocurrency Markets"
date: 2027-03-14 10:00:00 -0700
categories: [Trading Systems, Data Engineering]
tags: [websocket, cryptocurrency, market-data, real-time, python, asyncio]
series: "Real-Time Trading Infrastructure"
series_order: 4
---

*Part 4 of the Real-Time Trading Infrastructure series. Previous posts covered [system architecture](/posts/trading-infrastructure-overview/) (Part 1), [exchange connectivity patterns](/posts/exchange-connectivity-patterns/) (Part 2), and [order book management](/posts/order-book-management/) (Part 3). Part 5 addresses [data persistence strategies](/posts/market-data-persistence/).*

Real-time market data forms the foundation of algorithmic trading systems. WebSocket connections provide low-latency streaming data from cryptocurrency exchanges, but production systems must handle connection failures, message validation, throughput monitoring, and data gap recovery. This post presents a complete WebSocket data pipeline implementation using Python asyncio, designed for sustained throughput exceeding 400 ticks per minute across multiple trading pairs.

## WebSocket Connection Lifecycle

WebSocket connections follow a predictable lifecycle: establishment, authentication (when required), subscription, steady-state data flow, and eventual disconnection. Production systems must manage each phase explicitly.

### Connection States

A state machine governs connection behavior:

```python
from enum import Enum, auto
from dataclasses import dataclass
from typing import Optional
import time

class ConnectionState(Enum):
    DISCONNECTED = auto()
    CONNECTING = auto()
    CONNECTED = auto()
    AUTHENTICATING = auto()
    SUBSCRIBING = auto()
    STREAMING = auto()
    RECONNECTING = auto()
    FAILED = auto()

@dataclass
class ConnectionMetrics:
    """Track connection health and performance."""
    connected_at: Optional[float] = None
    last_message_at: Optional[float] = None
    messages_received: int = 0
    reconnect_count: int = 0
    errors_count: int = 0

    def record_message(self) -> None:
        self.last_message_at = time.time()
        self.messages_received += 1

    def time_since_last_message(self) -> Optional[float]:
        if self.last_message_at is None:
            return None
        return time.time() - self.last_message_at
```

The state machine prevents invalid transitions and provides clear debugging information when connections fail.

### Base WebSocket Client

The following implementation provides connection management with automatic reconnection:

```python
import asyncio
import websockets
import json
import logging
from abc import ABC, abstractmethod
from typing import Callable, Awaitable, List, Dict, Any

logger = logging.getLogger(__name__)

class WebSocketClient(ABC):
    """Base WebSocket client with lifecycle management."""

    def __init__(
        self,
        url: str,
        subscriptions: List[str],
        on_message: Callable[[Dict[str, Any]], Awaitable[None]],
        heartbeat_interval: float = 30.0,
        connection_timeout: float = 10.0,
    ):
        self.url = url
        self.subscriptions = subscriptions
        self.on_message = on_message
        self.heartbeat_interval = heartbeat_interval
        self.connection_timeout = connection_timeout

        self.state = ConnectionState.DISCONNECTED
        self.metrics = ConnectionMetrics()
        self._websocket = None
        self._running = False
        self._tasks: List[asyncio.Task] = []

    async def connect(self) -> None:
        """Establish WebSocket connection."""
        self.state = ConnectionState.CONNECTING

        try:
            self._websocket = await asyncio.wait_for(
                websockets.connect(
                    self.url,
                    ping_interval=self.heartbeat_interval,
                    ping_timeout=self.heartbeat_interval * 2,
                    close_timeout=5.0,
                ),
                timeout=self.connection_timeout,
            )
            self.state = ConnectionState.CONNECTED
            self.metrics.connected_at = time.time()
            logger.info(f"Connected to {self.url}")

        except asyncio.TimeoutError:
            self.state = ConnectionState.FAILED
            raise ConnectionError(f"Connection timeout: {self.url}")
        except Exception as e:
            self.state = ConnectionState.FAILED
            raise ConnectionError(f"Connection failed: {e}")

    @abstractmethod
    async def authenticate(self) -> None:
        """Exchange-specific authentication. Override in subclass."""
        pass

    @abstractmethod
    async def subscribe(self) -> None:
        """Send subscription messages. Override in subclass."""
        pass

    @abstractmethod
    def parse_message(self, raw: str) -> Optional[Dict[str, Any]]:
        """Parse exchange-specific message format. Override in subclass."""
        pass

    async def _message_loop(self) -> None:
        """Main message processing loop."""
        async for raw_message in self._websocket:
            try:
                parsed = self.parse_message(raw_message)
                if parsed is not None:
                    self.metrics.record_message()
                    await self.on_message(parsed)
            except Exception as e:
                self.metrics.errors_count += 1
                logger.error(f"Message processing error: {e}")

    async def run(self) -> None:
        """Main run loop with automatic reconnection."""
        self._running = True

        while self._running:
            try:
                await self.connect()
                await self.authenticate()

                self.state = ConnectionState.SUBSCRIBING
                await self.subscribe()

                self.state = ConnectionState.STREAMING
                await self._message_loop()

            except websockets.ConnectionClosed as e:
                logger.warning(f"Connection closed: {e.code} {e.reason}")
            except Exception as e:
                logger.error(f"Connection error: {e}")
                self.metrics.errors_count += 1

            if self._running:
                self.state = ConnectionState.RECONNECTING
                self.metrics.reconnect_count += 1
                # Reconnection delay handled by backoff strategy
                await self._wait_before_reconnect()

    async def _wait_before_reconnect(self) -> None:
        """Apply exponential backoff. Override for custom behavior."""
        delay = min(30, 2 ** min(self.metrics.reconnect_count, 5))
        logger.info(f"Reconnecting in {delay} seconds...")
        await asyncio.sleep(delay)

    async def stop(self) -> None:
        """Gracefully stop the client."""
        self._running = False
        if self._websocket:
            await self._websocket.close()
        self.state = ConnectionState.DISCONNECTED
```

## Exchange-Specific Message Formats

Each cryptocurrency exchange defines its own WebSocket protocol. A normalization layer converts exchange-specific formats into a unified internal representation.

### Normalized Message Structure

```python
from dataclasses import dataclass
from decimal import Decimal
from typing import Optional
import time

@dataclass
class NormalizedTick:
    """Exchange-agnostic tick representation."""
    exchange: str
    symbol: str
    timestamp: float
    bid_price: Decimal
    bid_size: Decimal
    ask_price: Decimal
    ask_size: Decimal
    last_price: Optional[Decimal] = None
    last_size: Optional[Decimal] = None
    volume_24h: Optional[Decimal] = None
    receive_time: float = None

    def __post_init__(self):
        if self.receive_time is None:
            self.receive_time = time.time()

    @property
    def spread(self) -> Decimal:
        return self.ask_price - self.bid_price

    @property
    def spread_bps(self) -> Decimal:
        mid = (self.ask_price + self.bid_price) / 2
        return (self.spread / mid) * Decimal("10000")

    @property
    def latency_ms(self) -> float:
        return (self.receive_time - self.timestamp) * 1000
```

### Exchange Parser Implementation

Different exchanges require different parsing logic. The following example demonstrates parsing for a common message format:

```python
from abc import ABC, abstractmethod
from decimal import Decimal, InvalidOperation
from typing import Optional, Dict, Any
import json

class MessageParser(ABC):
    """Base parser for exchange messages."""

    @abstractmethod
    def parse(self, raw: str) -> Optional[NormalizedTick]:
        pass

    def _safe_decimal(self, value: Any) -> Optional[Decimal]:
        """Safely convert to Decimal."""
        if value is None:
            return None
        try:
            return Decimal(str(value))
        except (InvalidOperation, ValueError):
            return None


class GenericTickerParser(MessageParser):
    """Parser for common ticker message format."""

    def __init__(self, exchange: str):
        self.exchange = exchange

    def parse(self, raw: str) -> Optional[NormalizedTick]:
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            return None

        # Handle different message types
        msg_type = data.get("type") or data.get("e") or data.get("channel")

        if msg_type not in ("ticker", "bookTicker", "quote"):
            return None

        # Extract fields with fallbacks for different schemas
        symbol = data.get("symbol") or data.get("s") or data.get("pair")

        bid_price = self._safe_decimal(
            data.get("bidPrice") or data.get("b") or data.get("bid")
        )
        bid_size = self._safe_decimal(
            data.get("bidQty") or data.get("B") or data.get("bidSize")
        )
        ask_price = self._safe_decimal(
            data.get("askPrice") or data.get("a") or data.get("ask")
        )
        ask_size = self._safe_decimal(
            data.get("askQty") or data.get("A") or data.get("askSize")
        )

        # Timestamp handling
        ts = data.get("timestamp") or data.get("T") or data.get("time")
        if isinstance(ts, int):
            # Convert milliseconds to seconds if necessary
            timestamp = ts / 1000 if ts > 1e12 else ts
        else:
            timestamp = time.time()

        # Validate required fields
        if not all([symbol, bid_price, bid_size, ask_price, ask_size]):
            return None

        return NormalizedTick(
            exchange=self.exchange,
            symbol=symbol,
            timestamp=timestamp,
            bid_price=bid_price,
            bid_size=bid_size,
            ask_price=ask_price,
            ask_size=ask_size,
            last_price=self._safe_decimal(data.get("lastPrice") or data.get("c")),
            last_size=self._safe_decimal(data.get("lastQty") or data.get("Q")),
            volume_24h=self._safe_decimal(data.get("volume") or data.get("v")),
        )
```

## Reconnection Strategies and Exponential Backoff

Network failures occur regularly in production. A robust reconnection strategy must balance rapid recovery with avoiding connection floods that trigger rate limits.

### Exponential Backoff Implementation

```python
import random
from dataclasses import dataclass

@dataclass
class BackoffConfig:
    """Configuration for exponential backoff."""
    initial_delay: float = 1.0
    max_delay: float = 60.0
    multiplier: float = 2.0
    jitter: float = 0.1  # Random factor to prevent thundering herd
    max_attempts: int = 0  # 0 = unlimited


class ExponentialBackoff:
    """Exponential backoff with jitter."""

    def __init__(self, config: BackoffConfig = None):
        self.config = config or BackoffConfig()
        self._attempt = 0

    def reset(self) -> None:
        """Reset attempt counter after successful connection."""
        self._attempt = 0

    def next_delay(self) -> float:
        """Calculate next delay with jitter."""
        delay = min(
            self.config.initial_delay * (self.config.multiplier ** self._attempt),
            self.config.max_delay
        )

        # Add jitter
        jitter_range = delay * self.config.jitter
        delay += random.uniform(-jitter_range, jitter_range)

        self._attempt += 1
        return max(0, delay)

    def should_retry(self) -> bool:
        """Check if more attempts are allowed."""
        if self.config.max_attempts == 0:
            return True
        return self._attempt < self.config.max_attempts


class ReconnectingWebSocketClient(WebSocketClient):
    """WebSocket client with configurable reconnection."""

    def __init__(self, *args, backoff_config: BackoffConfig = None, **kwargs):
        super().__init__(*args, **kwargs)
        self._backoff = ExponentialBackoff(backoff_config)

    async def _wait_before_reconnect(self) -> None:
        if not self._backoff.should_retry():
            self._running = False
            raise ConnectionError("Max reconnection attempts exceeded")

        delay = self._backoff.next_delay()
        logger.info(f"Reconnecting in {delay:.2f}s (attempt {self._backoff._attempt})")
        await asyncio.sleep(delay)

    async def _on_connected(self) -> None:
        """Called after successful connection establishment."""
        self._backoff.reset()
```

### Circuit Breaker Pattern

Repeated failures indicate systemic problems. A circuit breaker prevents resource exhaustion:

```python
from enum import Enum
import time

class CircuitState(Enum):
    CLOSED = auto()      # Normal operation
    OPEN = auto()        # Failing, reject immediately
    HALF_OPEN = auto()   # Testing recovery


class CircuitBreaker:
    """Circuit breaker for connection management."""

    def __init__(
        self,
        failure_threshold: int = 5,
        recovery_timeout: float = 60.0,
        success_threshold: int = 2,
    ):
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout
        self.success_threshold = success_threshold

        self._state = CircuitState.CLOSED
        self._failures = 0
        self._successes = 0
        self._last_failure_time = 0

    @property
    def state(self) -> CircuitState:
        if self._state == CircuitState.OPEN:
            if time.time() - self._last_failure_time > self.recovery_timeout:
                self._state = CircuitState.HALF_OPEN
                self._successes = 0
        return self._state

    def record_success(self) -> None:
        if self._state == CircuitState.HALF_OPEN:
            self._successes += 1
            if self._successes >= self.success_threshold:
                self._state = CircuitState.CLOSED
                self._failures = 0
        elif self._state == CircuitState.CLOSED:
            self._failures = 0

    def record_failure(self) -> None:
        self._failures += 1
        self._last_failure_time = time.time()

        if self._state == CircuitState.HALF_OPEN:
            self._state = CircuitState.OPEN
        elif self._failures >= self.failure_threshold:
            self._state = CircuitState.OPEN

    def allow_request(self) -> bool:
        state = self.state
        if state == CircuitState.CLOSED:
            return True
        elif state == CircuitState.HALF_OPEN:
            return True
        return False
```

## Message Validation and Normalization

Invalid or malformed messages must be detected and logged without crashing the pipeline. Validation occurs at multiple levels.

### Schema Validation

```python
from dataclasses import dataclass
from typing import List, Set, Optional
from decimal import Decimal

@dataclass
class ValidationResult:
    valid: bool
    errors: List[str]


class TickValidator:
    """Validate normalized tick data."""

    def __init__(
        self,
        known_symbols: Set[str],
        max_spread_bps: Decimal = Decimal("100"),
        max_latency_ms: float = 5000,
        min_price: Decimal = Decimal("0"),
        max_price: Decimal = Decimal("1000000"),
    ):
        self.known_symbols = known_symbols
        self.max_spread_bps = max_spread_bps
        self.max_latency_ms = max_latency_ms
        self.min_price = min_price
        self.max_price = max_price

    def validate(self, tick: NormalizedTick) -> ValidationResult:
        errors = []

        # Symbol validation
        if tick.symbol not in self.known_symbols:
            errors.append(f"Unknown symbol: {tick.symbol}")

        # Price sanity checks
        if tick.bid_price <= self.min_price:
            errors.append(f"Invalid bid price: {tick.bid_price}")
        if tick.ask_price <= self.min_price:
            errors.append(f"Invalid ask price: {tick.ask_price}")
        if tick.bid_price > self.max_price:
            errors.append(f"Bid price exceeds maximum: {tick.bid_price}")
        if tick.ask_price > self.max_price:
            errors.append(f"Ask price exceeds maximum: {tick.ask_price}")

        # Bid/ask relationship
        if tick.bid_price >= tick.ask_price:
            errors.append(f"Crossed market: bid={tick.bid_price} >= ask={tick.ask_price}")

        # Spread check
        if tick.spread_bps > self.max_spread_bps:
            errors.append(f"Spread too wide: {tick.spread_bps} bps")

        # Size validation
        if tick.bid_size <= 0:
            errors.append(f"Invalid bid size: {tick.bid_size}")
        if tick.ask_size <= 0:
            errors.append(f"Invalid ask size: {tick.ask_size}")

        # Timestamp validation
        if tick.latency_ms > self.max_latency_ms:
            errors.append(f"Excessive latency: {tick.latency_ms:.0f}ms")
        if tick.latency_ms < -1000:  # Allow small negative for clock drift
            errors.append(f"Future timestamp detected: {tick.latency_ms:.0f}ms")

        return ValidationResult(valid=len(errors) == 0, errors=errors)
```

### Validation Pipeline Integration

```python
class ValidatingMessageHandler:
    """Message handler with validation layer."""

    def __init__(
        self,
        validator: TickValidator,
        downstream: Callable[[NormalizedTick], Awaitable[None]],
        log_invalid: bool = True,
    ):
        self.validator = validator
        self.downstream = downstream
        self.log_invalid = log_invalid

        self.valid_count = 0
        self.invalid_count = 0

    async def handle(self, tick: NormalizedTick) -> None:
        result = self.validator.validate(tick)

        if result.valid:
            self.valid_count += 1
            await self.downstream(tick)
        else:
            self.invalid_count += 1
            if self.log_invalid:
                logger.warning(
                    f"Invalid tick {tick.symbol}: {', '.join(result.errors)}"
                )

    @property
    def validation_rate(self) -> float:
        total = self.valid_count + self.invalid_count
        if total == 0:
            return 1.0
        return self.valid_count / total
```

## Throughput Optimization

Sustaining 400+ ticks per minute requires careful attention to processing efficiency. Several techniques improve throughput.

### Batched Processing

Individual message processing incurs overhead. Batching amortizes this cost:

```python
import asyncio
from collections import deque
from typing import Deque

class BatchingHandler:
    """Batch messages for efficient processing."""

    def __init__(
        self,
        batch_processor: Callable[[List[NormalizedTick]], Awaitable[None]],
        max_batch_size: int = 100,
        max_wait_ms: float = 50,
    ):
        self.batch_processor = batch_processor
        self.max_batch_size = max_batch_size
        self.max_wait_ms = max_wait_ms

        self._buffer: Deque[NormalizedTick] = deque()
        self._lock = asyncio.Lock()
        self._flush_task: Optional[asyncio.Task] = None

    async def handle(self, tick: NormalizedTick) -> None:
        async with self._lock:
            self._buffer.append(tick)

            if len(self._buffer) >= self.max_batch_size:
                await self._flush()
            elif self._flush_task is None:
                self._flush_task = asyncio.create_task(
                    self._scheduled_flush()
                )

    async def _scheduled_flush(self) -> None:
        await asyncio.sleep(self.max_wait_ms / 1000)
        async with self._lock:
            if self._buffer:
                await self._flush()
            self._flush_task = None

    async def _flush(self) -> None:
        if not self._buffer:
            return

        batch = list(self._buffer)
        self._buffer.clear()

        await self.batch_processor(batch)
```

### Connection Multiplexing

A single WebSocket connection may become a bottleneck. Multiple connections distribute load:

```python
class ConnectionPool:
    """Pool of WebSocket connections for load distribution."""

    def __init__(
        self,
        client_factory: Callable[[], WebSocketClient],
        pool_size: int = 3,
    ):
        self.client_factory = client_factory
        self.pool_size = pool_size
        self._clients: List[WebSocketClient] = []

    async def start(self) -> None:
        for i in range(self.pool_size):
            client = self.client_factory()
            self._clients.append(client)

        # Start all connections concurrently
        await asyncio.gather(
            *[client.run() for client in self._clients],
            return_exceptions=True
        )

    async def stop(self) -> None:
        await asyncio.gather(
            *[client.stop() for client in self._clients]
        )

    def aggregate_metrics(self) -> Dict[str, Any]:
        return {
            "total_messages": sum(c.metrics.messages_received for c in self._clients),
            "total_errors": sum(c.metrics.errors_count for c in self._clients),
            "active_connections": sum(
                1 for c in self._clients
                if c.state == ConnectionState.STREAMING
            ),
        }
```

## Monitoring and Alerting

Continuous monitoring detects degradation before it causes trading failures.

### Rate Monitoring

```python
from collections import deque
from dataclasses import dataclass
import time

@dataclass
class RateWindow:
    """Sliding window rate calculation."""
    window_seconds: float = 60.0

    def __post_init__(self):
        self._timestamps: Deque[float] = deque()

    def record(self) -> None:
        now = time.time()
        self._timestamps.append(now)
        self._prune(now)

    def _prune(self, now: float) -> None:
        cutoff = now - self.window_seconds
        while self._timestamps and self._timestamps[0] < cutoff:
            self._timestamps.popleft()

    def rate_per_minute(self) -> float:
        now = time.time()
        self._prune(now)
        return len(self._timestamps) * (60.0 / self.window_seconds)


class ThroughputMonitor:
    """Monitor message throughput with alerting."""

    def __init__(
        self,
        min_rate_per_minute: float = 400,
        alert_callback: Callable[[str], Awaitable[None]] = None,
        check_interval: float = 10.0,
    ):
        self.min_rate = min_rate_per_minute
        self.alert_callback = alert_callback
        self.check_interval = check_interval

        self._rate = RateWindow(window_seconds=60.0)
        self._running = False
        self._last_alert_time = 0
        self._alert_cooldown = 300  # 5 minutes between alerts

    def record_message(self) -> None:
        self._rate.record()

    async def start_monitoring(self) -> None:
        self._running = True
        while self._running:
            rate = self._rate.rate_per_minute()
            logger.debug(f"Current rate: {rate:.1f} ticks/min")

            if rate < self.min_rate:
                await self._maybe_alert(rate)

            await asyncio.sleep(self.check_interval)

    async def _maybe_alert(self, rate: float) -> None:
        now = time.time()
        if now - self._last_alert_time < self._alert_cooldown:
            return

        self._last_alert_time = now
        message = f"Low throughput: {rate:.1f}/min (threshold: {self.min_rate}/min)"
        logger.warning(message)

        if self.alert_callback:
            await self.alert_callback(message)

    def stop(self) -> None:
        self._running = False
```

### Health Check Endpoint

Expose monitoring data for external systems:

```python
from aiohttp import web

class HealthCheckServer:
    """HTTP server for health checks and metrics."""

    def __init__(
        self,
        clients: List[WebSocketClient],
        throughput_monitor: ThroughputMonitor,
        port: int = 8080,
    ):
        self.clients = clients
        self.monitor = throughput_monitor
        self.port = port
        self._app = web.Application()
        self._app.router.add_get("/health", self.health_handler)
        self._app.router.add_get("/metrics", self.metrics_handler)

    async def health_handler(self, request: web.Request) -> web.Response:
        streaming_count = sum(
            1 for c in self.clients
            if c.state == ConnectionState.STREAMING
        )

        healthy = streaming_count > 0
        status = 200 if healthy else 503

        return web.json_response(
            {"status": "healthy" if healthy else "unhealthy",
             "streaming_connections": streaming_count},
            status=status
        )

    async def metrics_handler(self, request: web.Request) -> web.Response:
        metrics = {
            "connections": [
                {
                    "state": c.state.name,
                    "messages_received": c.metrics.messages_received,
                    "reconnect_count": c.metrics.reconnect_count,
                    "errors": c.metrics.errors_count,
                    "last_message_age_sec": c.metrics.time_since_last_message(),
                }
                for c in self.clients
            ],
            "throughput": {
                "rate_per_minute": self.monitor._rate.rate_per_minute(),
                "target_rate": self.monitor.min_rate,
            },
        }
        return web.json_response(metrics)

    async def start(self) -> None:
        runner = web.AppRunner(self._app)
        await runner.setup()
        site = web.TCPSite(runner, "0.0.0.0", self.port)
        await site.start()
        logger.info(f"Health check server running on port {self.port}")
```

## Gap Detection and Recovery

Market data gaps cause incorrect trading decisions. Detection and recovery mechanisms ensure data completeness.

### Sequence Number Tracking

```python
@dataclass
class SequenceTracker:
    """Track message sequences per symbol."""

    def __init__(self):
        self._sequences: Dict[str, int] = {}
        self._gaps: List[tuple] = []

    def check(self, symbol: str, sequence: int) -> Optional[tuple]:
        """Check for gaps. Returns (expected, received) if gap detected."""
        if symbol not in self._sequences:
            self._sequences[symbol] = sequence
            return None

        expected = self._sequences[symbol] + 1

        if sequence == expected:
            self._sequences[symbol] = sequence
            return None
        elif sequence > expected:
            gap = (expected, sequence - 1)
            self._gaps.append((symbol, gap))
            self._sequences[symbol] = sequence
            logger.warning(f"Gap detected for {symbol}: {gap}")
            return gap
        else:
            # Duplicate or out-of-order
            logger.debug(f"Out-of-order message: {symbol} expected {expected}, got {sequence}")
            return None

    def get_gaps(self) -> List[tuple]:
        return self._gaps.copy()

    def clear_gaps(self) -> None:
        self._gaps.clear()
```

### Timestamp-Based Gap Detection

When sequence numbers are unavailable, timestamp analysis detects gaps:

```python
class TimestampGapDetector:
    """Detect gaps based on message timing."""

    def __init__(
        self,
        expected_interval_ms: float = 100,
        gap_threshold_multiplier: float = 10,
    ):
        self.expected_interval = expected_interval_ms
        self.threshold = expected_interval_ms * gap_threshold_multiplier

        self._last_timestamps: Dict[str, float] = {}

    def check(self, symbol: str, timestamp: float) -> Optional[float]:
        """Check for timing gaps. Returns gap duration if detected."""
        if symbol not in self._last_timestamps:
            self._last_timestamps[symbol] = timestamp
            return None

        interval_ms = (timestamp - self._last_timestamps[symbol]) * 1000
        self._last_timestamps[symbol] = timestamp

        if interval_ms > self.threshold:
            logger.warning(
                f"Timing gap for {symbol}: {interval_ms:.0f}ms "
                f"(expected ~{self.expected_interval:.0f}ms)"
            )
            return interval_ms

        return None
```

### Recovery Strategies

Gap recovery depends on exchange capabilities:

```python
class GapRecoveryManager:
    """Manage gap recovery strategies."""

    def __init__(
        self,
        rest_client,  # Exchange REST API client
        recovery_queue: asyncio.Queue,
    ):
        self.rest_client = rest_client
        self.recovery_queue = recovery_queue
        self._recovering = set()

    async def recover_gap(
        self,
        symbol: str,
        start_sequence: int,
        end_sequence: int,
    ) -> None:
        """Attempt to recover missing messages via REST API."""
        recovery_key = (symbol, start_sequence, end_sequence)

        if recovery_key in self._recovering:
            return  # Already recovering this gap

        self._recovering.add(recovery_key)

        try:
            logger.info(f"Recovering gap for {symbol}: {start_sequence}-{end_sequence}")

            # Fetch historical data from REST endpoint
            trades = await self.rest_client.get_recent_trades(
                symbol=symbol,
                limit=end_sequence - start_sequence + 100
            )

            # Filter to gap range and queue for processing
            for trade in trades:
                if start_sequence <= trade.sequence <= end_sequence:
                    await self.recovery_queue.put(trade)

            logger.info(f"Recovered {len(trades)} messages for {symbol}")

        except Exception as e:
            logger.error(f"Gap recovery failed for {symbol}: {e}")
        finally:
            self._recovering.discard(recovery_key)
```

## Complete Pipeline Assembly

The following example combines all components into a production-ready pipeline:

```python
async def main():
    # Configuration
    symbols = ["BTC-USD", "ETH-USD", "SOL-USD"]
    min_throughput = 400  # ticks per minute

    # Initialize components
    validator = TickValidator(known_symbols=set(symbols))
    throughput_monitor = ThroughputMonitor(min_rate_per_minute=min_throughput)
    gap_detector = TimestampGapDetector()

    # Message processing chain
    async def process_tick(tick: NormalizedTick) -> None:
        throughput_monitor.record_message()
        gap_detector.check(tick.symbol, tick.timestamp)
        # Forward to downstream systems (storage, strategy engine, etc.)
        logger.debug(f"Processed: {tick.symbol} {tick.bid_price}/{tick.ask_price}")

    validating_handler = ValidatingMessageHandler(
        validator=validator,
        downstream=process_tick,
    )

    # Create WebSocket client
    client = ReconnectingWebSocketClient(
        url="wss://exchange.example.com/ws",
        subscriptions=[f"ticker:{s}" for s in symbols],
        on_message=validating_handler.handle,
        backoff_config=BackoffConfig(max_delay=30),
    )

    # Start health server and monitoring
    health_server = HealthCheckServer(
        clients=[client],
        throughput_monitor=throughput_monitor,
        port=8080,
    )

    # Run all components
    await asyncio.gather(
        client.run(),
        throughput_monitor.start_monitoring(),
        health_server.start(),
    )


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s"
    )
    asyncio.run(main())
```

## Conclusion

Building reliable WebSocket data pipelines requires attention to connection lifecycle management, message validation, reconnection strategies, and gap detection. The patterns presented in this post provide a foundation for production cryptocurrency market data systems capable of sustained throughput exceeding 400 ticks per minute.

Key takeaways:

1. **State machine management** provides clear connection lifecycle control and debugging capabilities
2. **Exchange-agnostic normalization** decouples business logic from exchange-specific protocols
3. **Exponential backoff with jitter** prevents connection storms during outages
4. **Multi-layer validation** catches malformed data before it affects trading decisions
5. **Continuous throughput monitoring** enables proactive problem detection
6. **Gap detection and recovery** ensures data completeness for accurate analysis

The next post in this series covers data persistence strategies, including time-series database selection, compression techniques, and query optimization for historical analysis.

---

## Series Navigation

- **Part 1**: [System Architecture Overview](/posts/trading-infrastructure-overview/)
- **Part 2**: [Exchange Connectivity Patterns](/posts/exchange-connectivity-patterns/)
- **Part 3**: [Order Book Management](/posts/order-book-management/)
- **Part 4**: Building a Reliable WebSocket Data Pipeline (this post)
- **Part 5**: [Data Persistence Strategies](/posts/market-data-persistence/)
- **Part 6**: [Latency Measurement and Optimization](/posts/latency-optimization/)
- **Part 7**: [Strategy Execution Engine](/posts/strategy-execution-engine/)
- **Part 8**: [Risk Management Systems](/posts/risk-management-systems/)
- **Part 9**: [Backtesting Infrastructure](/posts/backtesting-infrastructure/)
- **Part 10**: [Production Deployment](/posts/production-deployment/)

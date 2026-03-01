---
title: "Part 2: Choosing the Right Database for Each Job: MongoDB, Redis, and DuckDB"
date: 2027-02-21 10:00:00 -0700
categories: [Trading Systems, Databases]
tags: [mongodb, redis, duckdb, time-series, caching, polyglot-persistence, python]
series: real-time-trading-infrastructure
series_order: 2
---

*Part 2 of the [Real-Time Trading Infrastructure series](/posts/real-time-trading-infrastructure-series/). Previous: [Part 1: Market Data Ingestion](/posts/market-data-ingestion-websockets/). Next: [Part 3: Event-Driven Architecture with Message Queues](/posts/event-driven-trading-message-queues/).*

Trading systems generate heterogeneous data with conflicting access patterns. Tick data arrives at millisecond intervals and requires append-only storage with time-based queries. Position state demands sub-millisecond reads with atomic updates. Historical analysis spans months of data with complex aggregations. No single database architecture optimizes for all three workloads simultaneously. Polyglot persistence—using purpose-built databases for each access pattern—resolves this fundamental tension.

This post examines a three-database architecture: MongoDB for time-series tick storage, Redis for hot state caching, and DuckDB for analytical queries. The focus remains on schema design, query patterns, and the critical challenge of maintaining consistency across storage layers.

## The Case Against Monolithic Storage

A naive approach stores all trading data in a single relational database. This creates predictable failure modes:

**Write contention**: High-frequency tick ingestion competes with position lookups. Lock contention degrades both workloads.

**Query latency variance**: Analytical queries scanning historical data block operational queries. A backtest consuming CPU spikes order execution latency.

**Schema rigidity**: Financial instruments vary in structure. Options carry strike prices and expiration dates absent from equities. Forcing heterogeneous instruments into normalized tables produces sparse schemas or complex joins.

**Scaling limitations**: Vertical scaling (larger servers) hits cost ceilings. Horizontal scaling (sharding) complicates transactional guarantees.

Polyglot persistence addresses these limitations by routing each data type to storage optimized for its access pattern.

## Data Flow Architecture

The following diagram illustrates data movement between storage layers:

```text
                        ┌─────────────────────────────────────────────┐
                        │           Market Data Feeds                 │
                        │     (WebSocket, FIX, Proprietary APIs)      │
                        └─────────────────┬───────────────────────────┘
                                          │
                                          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         Ingestion Layer                                 │
│                    (Normalization, Validation)                          │
└────────────┬────────────────────┬────────────────────┬──────────────────┘
             │                    │                    │
             ▼                    ▼                    ▼
┌────────────────────┐  ┌─────────────────┐  ┌────────────────────────────┐
│      MongoDB       │  │      Redis      │  │    Event Bus (Optional)   │
│   (Tick Storage)   │  │  (Hot Cache)    │  │      (Kafka/RabbitMQ)     │
│                    │  │                 │  │                            │
│ - Time-series data │  │ - Current state │  │ - Signal distribution      │
│ - TTL expiration   │  │ - Position data │  │ - Order events             │
│ - Capped collections│ │ - Order book    │  │ - Strategy coordination    │
└────────────┬───────┘  └────────┬────────┘  └────────────────────────────┘
             │                   │
             │                   │
             ▼                   ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                          DuckDB (Analytics)                              │
│                                                                          │
│    - Backtesting queries         - Feature engineering                  │
│    - Performance reporting       - Statistical analysis                 │
│    - Historical aggregations     - Strategy optimization                │
└──────────────────────────────────────────────────────────────────────────┘
```

Data flows unidirectionally from ingestion through operational stores (MongoDB, Redis) to analytical storage (DuckDB). This separation prevents analytical workloads from impacting operational latency.

## MongoDB: Time-Series Tick Storage

MongoDB serves as the primary tick data store. Its document model accommodates varying instrument schemas without migration overhead. Time-series collections, introduced in MongoDB 5.0, optimize storage and query performance for temporal data.

### Time-Series Collection Schema

```python
from pymongo import MongoClient
from datetime import datetime, timedelta

client = MongoClient("mongodb://localhost:27017")
db = client["trading"]

# Create time-series collection for tick data
db.create_collection(
    "ticks",
    timeseries={
        "timeField": "timestamp",
        "metaField": "metadata",
        "granularity": "seconds"
    },
    expireAfterSeconds=86400 * 30  # 30-day TTL
)

# Create indexes for common query patterns
db.ticks.create_index([("metadata.symbol", 1), ("timestamp", -1)])
db.ticks.create_index([("metadata.exchange", 1), ("timestamp", -1)])
```

The `metaField` groups related measurements, enabling efficient compression and query filtering. Granularity hints optimize internal bucketing—"seconds" suits tick data; "hours" fits daily OHLCV bars.

### Document Structure

```python
tick_document = {
    "timestamp": datetime.utcnow(),
    "metadata": {
        "symbol": "AAPL",
        "exchange": "NASDAQ",
        "instrument_type": "equity"
    },
    "bid": 185.42,
    "ask": 185.44,
    "bid_size": 100,
    "ask_size": 250,
    "last_price": 185.43,
    "last_size": 50,
    "volume": 15234567,
    "conditions": ["regular", "eligible"]
}
```

Nested metadata enables filtering without scanning price fields. The `conditions` array captures trade qualifiers without schema modification.

### Capped Collections for Order Book Snapshots

Order book snapshots require bounded storage with automatic rotation. Capped collections guarantee insertion order and fixed size:

```python
# Create capped collection for order book snapshots
db.create_collection(
    "order_book_snapshots",
    capped=True,
    size=1073741824,  # 1 GB
    max=1000000       # Maximum 1M documents
)

order_book_snapshot = {
    "timestamp": datetime.utcnow(),
    "symbol": "AAPL",
    "bids": [
        {"price": 185.42, "size": 100},
        {"price": 185.41, "size": 250},
        {"price": 185.40, "size": 500}
    ],
    "asks": [
        {"price": 185.44, "size": 150},
        {"price": 185.45, "size": 300},
        {"price": 185.46, "size": 450}
    ]
}
```

Capped collections do not support TTL indexes—size bounds enforce retention. This suits high-frequency snapshots where storage is the limiting factor.

### Query Patterns

Common tick data queries follow predictable patterns:

```python
def get_ticks_in_range(symbol: str, start: datetime, end: datetime):
    """Retrieve ticks for symbol within time range."""
    return db.ticks.find({
        "metadata.symbol": symbol,
        "timestamp": {"$gte": start, "$lt": end}
    }).sort("timestamp", 1)


def get_vwap(symbol: str, minutes: int = 5):
    """Calculate volume-weighted average price."""
    cutoff = datetime.utcnow() - timedelta(minutes=minutes)

    pipeline = [
        {"$match": {
            "metadata.symbol": symbol,
            "timestamp": {"$gte": cutoff}
        }},
        {"$group": {
            "_id": None,
            "vwap": {
                "$sum": {"$multiply": ["$last_price", "$last_size"]}
            },
            "total_volume": {"$sum": "$last_size"}
        }},
        {"$project": {
            "vwap": {"$divide": ["$vwap", "$total_volume"]}
        }}
    ]

    result = list(db.ticks.aggregate(pipeline))
    return result[0]["vwap"] if result else None


def get_ohlcv_bars(symbol: str, interval_minutes: int = 1):
    """Aggregate ticks into OHLCV bars."""
    cutoff = datetime.utcnow() - timedelta(hours=1)

    pipeline = [
        {"$match": {
            "metadata.symbol": symbol,
            "timestamp": {"$gte": cutoff}
        }},
        {"$group": {
            "_id": {
                "$dateTrunc": {
                    "date": "$timestamp",
                    "unit": "minute",
                    "binSize": interval_minutes
                }
            },
            "open": {"$first": "$last_price"},
            "high": {"$max": "$last_price"},
            "low": {"$min": "$last_price"},
            "close": {"$last": "$last_price"},
            "volume": {"$sum": "$last_size"}
        }},
        {"$sort": {"_id": 1}}
    ]

    return list(db.ticks.aggregate(pipeline))
```

The `$dateTrunc` operator, available in MongoDB 5.0+, simplifies interval bucketing without client-side date manipulation.

## Redis: Hot Data Caching and State Management

Redis provides sub-millisecond access to frequently-read state. Position data, current prices, and order status reside in Redis for operational queries. The in-memory architecture eliminates disk I/O latency at the cost of storage capacity.

### Connection and Configuration

```python
import redis
import json
from typing import Optional, Dict, Any
from dataclasses import dataclass, asdict

pool = redis.ConnectionPool(
    host="localhost",
    port=6379,
    db=0,
    max_connections=50,
    decode_responses=True
)

r = redis.Redis(connection_pool=pool)
```

Connection pooling prevents socket exhaustion under high concurrency. The `decode_responses=True` flag returns strings instead of bytes.

### Position State Schema

```python
@dataclass
class Position:
    symbol: str
    quantity: int
    avg_cost: float
    unrealized_pnl: float
    realized_pnl: float
    last_update: str


def set_position(account_id: str, position: Position) -> None:
    """Store position with automatic expiration."""
    key = f"position:{account_id}:{position.symbol}"
    r.hset(key, mapping=asdict(position))
    r.expire(key, 86400)  # 24-hour expiration


def get_position(account_id: str, symbol: str) -> Optional[Position]:
    """Retrieve position state."""
    key = f"position:{account_id}:{symbol}"
    data = r.hgetall(key)

    if not data:
        return None

    return Position(
        symbol=data["symbol"],
        quantity=int(data["quantity"]),
        avg_cost=float(data["avg_cost"]),
        unrealized_pnl=float(data["unrealized_pnl"]),
        realized_pnl=float(data["realized_pnl"]),
        last_update=data["last_update"]
    )


def get_all_positions(account_id: str) -> Dict[str, Position]:
    """Retrieve all positions for account."""
    pattern = f"position:{account_id}:*"
    positions = {}

    for key in r.scan_iter(match=pattern):
        symbol = key.split(":")[-1]
        position = get_position(account_id, symbol)
        if position:
            positions[symbol] = position

    return positions
```

Hash structures (`HSET`/`HGETALL`) store position fields atomically. Individual field updates avoid full object serialization.

### Order Book Cache

Current order book state requires atomic updates and fast reads:

```python
def update_order_book(symbol: str, side: str, price: float, size: int) -> None:
    """Update order book level atomically."""
    key = f"orderbook:{symbol}:{side}"

    if size == 0:
        r.zrem(key, str(price))
    else:
        # Score = price for bids (descending), -price for asks (ascending)
        score = price if side == "bid" else -price
        r.zadd(key, {str(price): score})

        # Store size in separate hash
        size_key = f"orderbook:{symbol}:{side}:sizes"
        r.hset(size_key, str(price), size)


def get_top_of_book(symbol: str, depth: int = 5) -> Dict[str, Any]:
    """Retrieve top N levels of order book."""
    bids_key = f"orderbook:{symbol}:bid"
    asks_key = f"orderbook:{symbol}:ask"

    # Get prices (sorted sets provide ordering)
    bid_prices = r.zrevrange(bids_key, 0, depth - 1)
    ask_prices = r.zrange(asks_key, 0, depth - 1)

    # Get sizes
    bid_sizes_key = f"orderbook:{symbol}:bid:sizes"
    ask_sizes_key = f"orderbook:{symbol}:ask:sizes"

    bids = [
        {"price": float(p), "size": int(r.hget(bid_sizes_key, p) or 0)}
        for p in bid_prices
    ]
    asks = [
        {"price": float(p), "size": int(r.hget(ask_sizes_key, p) or 0)}
        for p in ask_prices
    ]

    return {"bids": bids, "asks": asks}
```

Sorted sets (`ZADD`/`ZRANGE`) maintain price level ordering. Separate hash structures store sizes, enabling level updates without full book reconstruction.

### Pub/Sub for Real-Time Updates

Redis Pub/Sub distributes state changes to subscribers:

```python
def publish_price_update(symbol: str, price: float, timestamp: str) -> None:
    """Publish price update to subscribers."""
    message = json.dumps({
        "symbol": symbol,
        "price": price,
        "timestamp": timestamp
    })
    r.publish(f"prices:{symbol}", message)


def subscribe_to_prices(symbols: list, callback):
    """Subscribe to price updates for symbols."""
    pubsub = r.pubsub()
    channels = [f"prices:{s}" for s in symbols]
    pubsub.subscribe(*channels)

    for message in pubsub.listen():
        if message["type"] == "message":
            data = json.loads(message["data"])
            callback(data)
```

Pub/Sub enables loose coupling between price ingestion and consuming strategies. Subscribers receive updates without polling.

## DuckDB: Analytical Queries and Backtesting

DuckDB provides analytical query performance comparable to columnar data warehouses in an embedded, serverless package. Its ability to query Parquet files directly—without loading into memory—suits large historical datasets.

### Database Setup

```python
import duckdb
from pathlib import Path

# Create persistent database
db_path = Path("./trading_analytics.duckdb")
conn = duckdb.connect(str(db_path))

# Enable parallel execution
conn.execute("SET threads TO 8")
conn.execute("SET memory_limit = '8GB'")
```

DuckDB operates in-process without server overhead. Configuration parameters tune resource consumption for available hardware.

### Schema for Historical Data

```python
def create_analytics_schema(conn):
    """Create tables for historical analysis."""

    # Historical tick data (loaded from MongoDB or Parquet exports)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS ticks (
            timestamp TIMESTAMP,
            symbol VARCHAR,
            exchange VARCHAR,
            bid DECIMAL(18, 6),
            ask DECIMAL(18, 6),
            bid_size INTEGER,
            ask_size INTEGER,
            last_price DECIMAL(18, 6),
            last_size INTEGER,
            volume BIGINT
        )
    """)

    # Pre-computed OHLCV bars
    conn.execute("""
        CREATE TABLE IF NOT EXISTS ohlcv_1m (
            timestamp TIMESTAMP,
            symbol VARCHAR,
            open DECIMAL(18, 6),
            high DECIMAL(18, 6),
            low DECIMAL(18, 6),
            close DECIMAL(18, 6),
            volume BIGINT,
            vwap DECIMAL(18, 6),
            trade_count INTEGER
        )
    """)

    # Trade execution history
    conn.execute("""
        CREATE TABLE IF NOT EXISTS executions (
            execution_id VARCHAR PRIMARY KEY,
            timestamp TIMESTAMP,
            symbol VARCHAR,
            side VARCHAR,
            quantity INTEGER,
            price DECIMAL(18, 6),
            commission DECIMAL(18, 6),
            strategy_id VARCHAR
        )
    """)

    # Create indexes for common query patterns
    conn.execute("CREATE INDEX IF NOT EXISTS idx_ticks_symbol_ts ON ticks(symbol, timestamp)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_ohlcv_symbol_ts ON ohlcv_1m(symbol, timestamp)")
```

Decimal types preserve price precision. Indexes accelerate time-range queries common in backtesting.

### Loading Data from Parquet

DuckDB queries Parquet files without explicit loading:

```python
def query_parquet_directly(parquet_path: str, symbol: str, start_date: str, end_date: str):
    """Query Parquet files without loading into DuckDB tables."""
    query = f"""
        SELECT *
        FROM read_parquet('{parquet_path}')
        WHERE symbol = '{symbol}'
          AND timestamp BETWEEN '{start_date}' AND '{end_date}'
        ORDER BY timestamp
    """
    return conn.execute(query).fetchdf()


def load_parquet_to_table(parquet_glob: str, table_name: str):
    """Load Parquet files into DuckDB table."""
    conn.execute(f"""
        INSERT INTO {table_name}
        SELECT * FROM read_parquet('{parquet_glob}')
    """)
```

Direct Parquet queries enable ad-hoc analysis without data movement. Bulk loading into tables suits repeated queries.

### Backtesting Queries

```python
def calculate_rolling_metrics(symbol: str, window_days: int = 30):
    """Calculate rolling volatility and returns."""
    query = f"""
        WITH daily_returns AS (
            SELECT
                DATE_TRUNC('day', timestamp) AS date,
                symbol,
                FIRST(open) AS open,
                LAST(close) AS close,
                (LAST(close) - FIRST(open)) / FIRST(open) AS daily_return
            FROM ohlcv_1m
            WHERE symbol = '{symbol}'
            GROUP BY DATE_TRUNC('day', timestamp), symbol
        )
        SELECT
            date,
            symbol,
            daily_return,
            AVG(daily_return) OVER (
                ORDER BY date
                ROWS BETWEEN {window_days - 1} PRECEDING AND CURRENT ROW
            ) AS rolling_mean_return,
            STDDEV(daily_return) OVER (
                ORDER BY date
                ROWS BETWEEN {window_days - 1} PRECEDING AND CURRENT ROW
            ) * SQRT(252) AS annualized_volatility
        FROM daily_returns
        ORDER BY date
    """
    return conn.execute(query).fetchdf()


def compute_strategy_performance(strategy_id: str):
    """Calculate performance metrics for strategy."""
    query = f"""
        WITH trades AS (
            SELECT
                timestamp,
                symbol,
                side,
                quantity,
                price,
                commission,
                CASE WHEN side = 'buy' THEN -quantity * price - commission
                     ELSE quantity * price - commission
                END AS cash_flow
            FROM executions
            WHERE strategy_id = '{strategy_id}'
        ),
        cumulative AS (
            SELECT
                timestamp,
                symbol,
                cash_flow,
                SUM(cash_flow) OVER (ORDER BY timestamp) AS cumulative_pnl
            FROM trades
        )
        SELECT
            MIN(timestamp) AS start_date,
            MAX(timestamp) AS end_date,
            COUNT(*) AS trade_count,
            SUM(cash_flow) AS total_pnl,
            MAX(cumulative_pnl) - MIN(cumulative_pnl) AS max_drawdown,
            AVG(CASE WHEN cash_flow > 0 THEN cash_flow END) AS avg_win,
            AVG(CASE WHEN cash_flow < 0 THEN cash_flow END) AS avg_loss,
            SUM(CASE WHEN cash_flow > 0 THEN 1 ELSE 0 END)::FLOAT / COUNT(*) AS win_rate
        FROM cumulative
    """
    return conn.execute(query).fetchone()
```

Window functions enable efficient rolling calculations without client-side iteration. DuckDB's columnar storage accelerates aggregations over millions of rows.

## Query Pattern Decision Tree

Selecting the appropriate database requires matching query characteristics to storage strengths:

```text
                        ┌─────────────────────┐
                        │   Query Arrives     │
                        └──────────┬──────────┘
                                   │
                        ┌──────────▼──────────┐
                        │  Latency Critical?  │
                        │   (< 1ms required)  │
                        └──────────┬──────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │                             │
              ┌─────▼─────┐                 ┌─────▼─────┐
              │    YES    │                 │    NO     │
              └─────┬─────┘                 └─────┬─────┘
                    │                             │
              ┌─────▼─────┐              ┌────────▼────────┐
              │   REDIS   │              │ Analytical?     │
              │           │              │ (aggregations,  │
              │ - Current │              │  window funcs)  │
              │   state   │              └────────┬────────┘
              │ - Positions│                      │
              │ - Order   │           ┌──────────┴──────────┐
              │   book    │           │                     │
              └───────────┘     ┌─────▼─────┐         ┌─────▼─────┐
                                │    YES    │         │    NO     │
                                └─────┬─────┘         └─────┬─────┘
                                      │                     │
                                ┌─────▼─────┐         ┌─────▼─────┐
                                │  DUCKDB   │         │  MONGODB  │
                                │           │         │           │
                                │ - Backtest│         │ - Tick    │
                                │ - Reports │         │   history │
                                │ - Feature │         │ - Time    │
                                │   compute │         │   range   │
                                └───────────┘         │   queries │
                                                      └───────────┘
```

This decision tree routes queries to optimal storage. Latency-critical operations use Redis; analytical workloads use DuckDB; time-series retrieval uses MongoDB.

## Data Consistency Across Stores

Multiple databases introduce consistency challenges. A trade execution must update:
1. Position state in Redis (immediate)
2. Execution record in MongoDB (durable)
3. Analytical tables in DuckDB (eventual)

### Eventual Consistency Pattern

```python
from datetime import datetime
import json


class ExecutionRecorder:
    """Record executions across storage layers with consistency guarantees."""

    def __init__(self, redis_client, mongo_db, duckdb_conn):
        self.redis = redis_client
        self.mongo = mongo_db
        self.duckdb = duckdb_conn

    def record_execution(self, execution: dict) -> bool:
        """
        Record execution with ordered writes.

        Write order: MongoDB (durable) -> Redis (fast) -> DuckDB (async)
        """
        execution_id = execution["execution_id"]

        # Step 1: Write to MongoDB first (durable storage)
        try:
            self.mongo.executions.insert_one(execution)
        except Exception as e:
            # Log and fail - no partial state
            return False

        # Step 2: Update Redis position state
        try:
            self._update_redis_position(execution)
        except Exception as e:
            # Log error but don't fail - MongoDB has record
            # Reconciliation process will fix Redis state
            pass

        # Step 3: Queue DuckDB update (async)
        self._queue_analytics_update(execution)

        return True

    def _update_redis_position(self, execution: dict) -> None:
        """Update position state in Redis."""
        account_id = execution["account_id"]
        symbol = execution["symbol"]
        key = f"position:{account_id}:{symbol}"

        # Atomic position update using Lua script
        lua_script = """
            local current = redis.call('HGETALL', KEYS[1])
            local quantity = tonumber(ARGV[1])
            local price = tonumber(ARGV[2])
            local side = ARGV[3]

            local current_qty = tonumber(redis.call('HGET', KEYS[1], 'quantity') or 0)
            local current_cost = tonumber(redis.call('HGET', KEYS[1], 'avg_cost') or 0)

            local new_qty, new_cost
            if side == 'buy' then
                new_qty = current_qty + quantity
                new_cost = (current_cost * current_qty + price * quantity) / new_qty
            else
                new_qty = current_qty - quantity
                new_cost = current_cost  -- Unchanged on sell
            end

            redis.call('HSET', KEYS[1], 'quantity', new_qty)
            redis.call('HSET', KEYS[1], 'avg_cost', new_cost)
            redis.call('HSET', KEYS[1], 'last_update', ARGV[4])

            return {new_qty, new_cost}
        """

        self.redis.eval(
            lua_script,
            1,
            key,
            execution["quantity"],
            execution["price"],
            execution["side"],
            execution["timestamp"]
        )

    def _queue_analytics_update(self, execution: dict) -> None:
        """Queue execution for async DuckDB insertion."""
        # In production: push to message queue
        # For simplicity: direct insert with batch accumulation
        self.redis.rpush("analytics:pending_executions", json.dumps(execution))
```

The write order prioritizes durability (MongoDB) before performance (Redis). Reconciliation processes periodically verify consistency between stores.

### Reconciliation Process

```python
def reconcile_positions(mongo_db, redis_client) -> dict:
    """
    Reconcile Redis position state against MongoDB executions.

    Run periodically (e.g., every 5 minutes) to fix drift.
    """
    discrepancies = []

    # Get all accounts with positions in Redis
    accounts = set()
    for key in redis_client.scan_iter(match="position:*"):
        parts = key.split(":")
        if len(parts) >= 2:
            accounts.add(parts[1])

    for account_id in accounts:
        # Calculate expected positions from MongoDB
        pipeline = [
            {"$match": {"account_id": account_id}},
            {"$group": {
                "_id": "$symbol",
                "net_quantity": {
                    "$sum": {
                        "$cond": [
                            {"$eq": ["$side", "buy"]},
                            "$quantity",
                            {"$multiply": ["$quantity", -1]}
                        ]
                    }
                }
            }}
        ]

        expected = {
            doc["_id"]: doc["net_quantity"]
            for doc in mongo_db.executions.aggregate(pipeline)
        }

        # Compare with Redis state
        for symbol, expected_qty in expected.items():
            position = get_position(account_id, symbol)
            redis_qty = position.quantity if position else 0

            if redis_qty != expected_qty:
                discrepancies.append({
                    "account_id": account_id,
                    "symbol": symbol,
                    "redis_quantity": redis_qty,
                    "expected_quantity": expected_qty
                })

                # Fix Redis state
                # (In production: alert before auto-fix)

    return {"discrepancies": discrepancies, "accounts_checked": len(accounts)}
```

Scheduled reconciliation detects and corrects drift between operational and durable storage layers.

## Schema Design Considerations for Financial Data

Financial data presents specific schema challenges:

### Decimal Precision

Floating-point representation introduces rounding errors unacceptable in financial calculations:

```python
# Wrong: floating-point accumulates errors
price = 0.1 + 0.2  # 0.30000000000000004

# Correct: use Decimal for price calculations
from decimal import Decimal, ROUND_HALF_UP

price = Decimal("0.1") + Decimal("0.2")  # Decimal('0.3')

# MongoDB: store as Decimal128
from bson.decimal128 import Decimal128

tick = {
    "price": Decimal128(Decimal("185.4325")),
    "timestamp": datetime.utcnow()
}

# DuckDB: use DECIMAL type with explicit precision
# DECIMAL(18, 6) supports prices up to 999,999,999,999.999999
```

### Timestamp Handling

Consistent timezone handling prevents subtle bugs:

```python
from datetime import datetime, timezone

# Always store UTC
timestamp = datetime.now(timezone.utc)

# MongoDB: stores timezone-aware datetimes
# DuckDB: use TIMESTAMP or TIMESTAMPTZ types

# Convert to exchange local time only for display
import pytz

eastern = pytz.timezone("US/Eastern")
local_time = timestamp.astimezone(eastern)
```

### Instrument Identification

Financial instruments require unambiguous identification:

```python
# Composite key for instrument identification
instrument_key = {
    "symbol": "AAPL",
    "exchange": "NASDAQ",
    "currency": "USD",
    "instrument_type": "equity"
}

# For derivatives, additional fields
option_key = {
    "underlying": "AAPL",
    "expiration": "2027-03-19",
    "strike": 190.0,
    "option_type": "call",
    "exchange": "CBOE"
}
```

Composite keys prevent ambiguity when instruments trade on multiple venues or share symbols across asset classes.

## Performance Benchmarks

Representative performance characteristics for each database:

| Operation | MongoDB | Redis | DuckDB |
|-----------|---------|-------|--------|
| Single document insert | 0.5-2ms | 0.1-0.3ms | 0.5-1ms |
| Bulk insert (10K docs) | 50-100ms | N/A | 20-50ms |
| Point lookup | 1-5ms | 0.1-0.5ms | 1-3ms |
| Time range query (1 day) | 10-50ms | N/A | 5-20ms |
| Aggregation (1M rows) | 500ms-2s | N/A | 100-300ms |

DuckDB excels at analytical queries; Redis dominates point lookups; MongoDB balances write throughput with query flexibility.

## Conclusion

Polyglot persistence matches database strengths to access patterns. MongoDB's time-series collections optimize tick storage with automatic TTL management. Redis provides sub-millisecond state access for operational queries. DuckDB delivers analytical performance for backtesting and reporting without server infrastructure.

The critical challenge lies not in individual database configuration but in maintaining consistency across stores. Ordered writes with reconciliation processes ensure data integrity while preserving the performance benefits of specialized storage.

The next post examines event-driven architecture patterns, using message queues to decouple trading system components and enable horizontal scaling.

---

*Series Navigation:*
- [Part 1: Market Data Ingestion](/posts/market-data-ingestion-websockets/) - WebSocket connections and data normalization
- **Part 2: Polyglot Persistence** (current)
- [Part 3: Event-Driven Architecture](/posts/event-driven-trading-message-queues/) - Message queues and system decoupling

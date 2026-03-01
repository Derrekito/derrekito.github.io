---
title: "Part 6: From Tick Data to OHLCV Bars: Real-Time Aggregation and ETL Pipelines"
date: 2027-04-04 10:00:00 -0700
categories: [Trading Systems, Data Engineering]
tags: [ohlcv, etl, time-series, mongodb, duckdb, python, data-aggregation]
series: real-time-trading-infrastructure
series_order: 6
---

*Part 6 of the [Real-Time Trading Infrastructure series](/posts/real-time-trading-infrastructure-series/). Previous: [Part 5: WebSocket Streaming and Order Book Management](/posts/websocket-orderbook-management/). Next: [Part 7: Backtesting Framework Architecture](/posts/backtesting-framework-architecture/).*

Raw tick data streams arrive at rates exceeding thousands of messages per second during active market sessions. Each tick represents a single trade or quote update—precise but overwhelming for most analytical purposes. OHLCV (Open, High, Low, Close, Volume) bars aggregate this torrent into digestible time intervals, transforming granular events into actionable market structure. This post examines bar construction algorithms, multi-timeframe aggregation strategies, and ETL pipelines that bridge operational databases to analytical engines.

The challenges extend beyond simple aggregation. Late-arriving data, market gaps, timezone transitions, and incomplete bars during live trading all require explicit handling. A robust implementation addresses these edge cases systematically rather than discovering them in production.

## OHLCV Bar Construction Fundamentals

An OHLCV bar summarizes all trading activity within a time interval:

- **Open**: First trade price in the interval
- **High**: Maximum trade price in the interval
- **Low**: Minimum trade price in the interval
- **Close**: Last trade price in the interval
- **Volume**: Total traded quantity in the interval

The apparent simplicity conceals implementation complexity. Consider: what defines the interval boundaries? How should the system handle intervals with no trades? What happens when trades arrive out of order?

### Interval Boundary Calculation

Bar boundaries align to wall-clock time, not to when the first trade arrives. A 5-minute bar starting at 09:30:00 covers [09:30:00, 09:35:00), regardless of whether the first trade occurs at 09:30:00.000 or 09:32:47.382.

```python
from datetime import datetime, timezone
from typing import NamedTuple
import math


class BarInterval(NamedTuple):
    """Represents a time interval for bar aggregation."""
    start: datetime
    end: datetime
    duration_seconds: int


def calculate_bar_interval(timestamp: datetime, interval_seconds: int) -> BarInterval:
    """
    Calculate the bar interval containing a given timestamp.

    Args:
        timestamp: The timestamp to locate within an interval.
        interval_seconds: Bar duration in seconds (60 for 1m, 300 for 5m, etc.).

    Returns:
        BarInterval with start, end, and duration.
    """
    # Convert to Unix timestamp for integer arithmetic
    unix_ts = timestamp.timestamp()

    # Floor to interval boundary
    interval_start_ts = math.floor(unix_ts / interval_seconds) * interval_seconds
    interval_end_ts = interval_start_ts + interval_seconds

    return BarInterval(
        start=datetime.fromtimestamp(interval_start_ts, tz=timezone.utc),
        end=datetime.fromtimestamp(interval_end_ts, tz=timezone.utc),
        duration_seconds=interval_seconds
    )


# Example usage
trade_time = datetime(2027, 4, 4, 14, 37, 23, tzinfo=timezone.utc)
bar_5m = calculate_bar_interval(trade_time, 300)
# Result: start=14:35:00, end=14:40:00
```

This boundary calculation ensures consistent bar alignment across all data sources and processing pipelines. Different systems observing the same trades produce identical bars because boundaries derive from wall-clock time, not arrival sequence.

### Stateful Bar Aggregator

The aggregator maintains partial bar state, updating as trades arrive and emitting completed bars at interval boundaries:

```python
from dataclasses import dataclass, field
from decimal import Decimal
from typing import Optional, Callable
import asyncio


@dataclass
class OHLCVBar:
    """Completed or in-progress OHLCV bar."""
    symbol: str
    interval_start: datetime
    interval_end: datetime
    interval_seconds: int
    open: Decimal
    high: Decimal
    low: Decimal
    close: Decimal
    volume: Decimal
    trade_count: int
    is_complete: bool = False

    def to_dict(self) -> dict:
        return {
            "symbol": self.symbol,
            "interval_start": self.interval_start.isoformat(),
            "interval_end": self.interval_end.isoformat(),
            "interval_seconds": self.interval_seconds,
            "open": str(self.open),
            "high": str(self.high),
            "low": str(self.low),
            "close": str(self.close),
            "volume": str(self.volume),
            "trade_count": self.trade_count,
            "is_complete": self.is_complete
        }


@dataclass
class BarAggregator:
    """
    Aggregates tick data into OHLCV bars.

    Handles multiple symbols and timeframes simultaneously.
    Emits bars via callback when intervals complete.
    """
    interval_seconds: int
    on_bar_complete: Callable[[OHLCVBar], None]
    _bars: dict[str, OHLCVBar] = field(default_factory=dict)
    _lock: asyncio.Lock = field(default_factory=asyncio.Lock)

    async def process_trade(
        self,
        symbol: str,
        timestamp: datetime,
        price: Decimal,
        quantity: Decimal
    ) -> Optional[OHLCVBar]:
        """
        Process a single trade tick.

        Returns completed bar if this trade triggered interval completion.
        """
        async with self._lock:
            interval = calculate_bar_interval(timestamp, self.interval_seconds)
            bar_key = f"{symbol}:{interval.start.isoformat()}"

            current_bar = self._bars.get(bar_key)

            if current_bar is None:
                # First trade in this interval
                self._bars[bar_key] = OHLCVBar(
                    symbol=symbol,
                    interval_start=interval.start,
                    interval_end=interval.end,
                    interval_seconds=self.interval_seconds,
                    open=price,
                    high=price,
                    low=price,
                    close=price,
                    volume=quantity,
                    trade_count=1,
                    is_complete=False
                )
            else:
                # Update existing bar
                current_bar.high = max(current_bar.high, price)
                current_bar.low = min(current_bar.low, price)
                current_bar.close = price
                current_bar.volume += quantity
                current_bar.trade_count += 1

            # Check for completed bars from previous intervals
            return await self._emit_completed_bars(timestamp)

    async def _emit_completed_bars(
        self,
        current_time: datetime
    ) -> Optional[OHLCVBar]:
        """Emit any bars whose intervals have ended."""
        completed = []

        for bar_key, bar in list(self._bars.items()):
            if current_time >= bar.interval_end and not bar.is_complete:
                bar.is_complete = True
                completed.append(bar)
                self.on_bar_complete(bar)

        # Clean up old completed bars (keep last 2 intervals for late data)
        cutoff = current_time.timestamp() - (self.interval_seconds * 2)
        self._bars = {
            k: v for k, v in self._bars.items()
            if v.interval_start.timestamp() > cutoff or not v.is_complete
        }

        return completed[0] if completed else None
```

The aggregator maintains thread safety through asyncio locks, essential when multiple WebSocket connections feed trades concurrently. The cleanup logic retains recent completed bars to handle late-arriving data while preventing unbounded memory growth.

## Multi-Timeframe Aggregation

Trading strategies often require multiple timeframe views simultaneously: 1-minute bars for entry timing, 15-minute bars for trend direction, daily bars for support/resistance levels. Rather than maintaining separate aggregation pipelines, larger timeframes derive from smaller ones through hierarchical aggregation.

### Timeframe Hierarchy

```python
from enum import IntEnum
from typing import List


class Timeframe(IntEnum):
    """Standard trading timeframes in seconds."""
    M1 = 60        # 1 minute
    M5 = 300       # 5 minutes
    M15 = 900      # 15 minutes
    H1 = 3600      # 1 hour
    H4 = 14400     # 4 hours
    D1 = 86400     # 1 day


TIMEFRAME_HIERARCHY = {
    Timeframe.M5: Timeframe.M1,    # 5m bars from 1m bars
    Timeframe.M15: Timeframe.M5,   # 15m bars from 5m bars
    Timeframe.H1: Timeframe.M15,   # 1h bars from 15m bars
    Timeframe.H4: Timeframe.H1,    # 4h bars from 1h bars
    Timeframe.D1: Timeframe.H4,    # Daily bars from 4h bars
}


def get_child_timeframes(target: Timeframe) -> List[Timeframe]:
    """Get all timeframes needed to build the target timeframe."""
    chain = [target]
    current = target

    while current in TIMEFRAME_HIERARCHY:
        parent = TIMEFRAME_HIERARCHY[current]
        chain.append(parent)
        current = parent

    return list(reversed(chain))


# Example: building 1-hour bars
# Returns: [M1, M5, M15, H1]
```

### Hierarchical Bar Builder

```python
@dataclass
class HierarchicalBarBuilder:
    """
    Builds multiple timeframe bars from tick data.

    Tick data produces 1-minute bars.
    1-minute bars aggregate into larger timeframes.
    """
    timeframes: List[Timeframe]
    on_bar_complete: Callable[[OHLCVBar], None]
    _aggregators: dict[Timeframe, BarAggregator] = field(default_factory=dict)
    _pending_aggregations: dict[Timeframe, List[OHLCVBar]] = field(default_factory=dict)

    def __post_init__(self):
        # Create aggregator for base timeframe (always M1 for tick data)
        self._aggregators[Timeframe.M1] = BarAggregator(
            interval_seconds=Timeframe.M1,
            on_bar_complete=lambda bar: self._handle_bar_complete(Timeframe.M1, bar)
        )

        # Initialize pending aggregations for derived timeframes
        for tf in self.timeframes:
            if tf != Timeframe.M1:
                self._pending_aggregations[tf] = []

    def _handle_bar_complete(self, timeframe: Timeframe, bar: OHLCVBar):
        """Handle completed bar, potentially triggering higher timeframe aggregation."""
        self.on_bar_complete(bar)

        # Find timeframes that use this timeframe as source
        for target_tf, source_tf in TIMEFRAME_HIERARCHY.items():
            if source_tf == timeframe and target_tf in self.timeframes:
                self._aggregate_to_higher_timeframe(target_tf, bar)

    def _aggregate_to_higher_timeframe(self, target_tf: Timeframe, source_bar: OHLCVBar):
        """Aggregate source bars into target timeframe bar."""
        self._pending_aggregations[target_tf].append(source_bar)

        # Calculate target interval
        target_interval = calculate_bar_interval(
            source_bar.interval_start,
            target_tf
        )

        # Check if target interval is complete
        pending = self._pending_aggregations[target_tf]
        expected_count = target_tf // TIMEFRAME_HIERARCHY[target_tf]

        # Filter to only bars in current target interval
        interval_bars = [
            b for b in pending
            if target_interval.start <= b.interval_start < target_interval.end
        ]

        if len(interval_bars) >= expected_count:
            # Aggregate into single bar
            aggregated = OHLCVBar(
                symbol=source_bar.symbol,
                interval_start=target_interval.start,
                interval_end=target_interval.end,
                interval_seconds=target_tf,
                open=interval_bars[0].open,
                high=max(b.high for b in interval_bars),
                low=min(b.low for b in interval_bars),
                close=interval_bars[-1].close,
                volume=sum(b.volume for b in interval_bars),
                trade_count=sum(b.trade_count for b in interval_bars),
                is_complete=True
            )

            # Emit and potentially cascade to even higher timeframes
            self._handle_bar_complete(target_tf, aggregated)

            # Clean up aggregated bars
            self._pending_aggregations[target_tf] = [
                b for b in pending
                if b.interval_start >= target_interval.end
            ]

    async def process_trade(
        self,
        symbol: str,
        timestamp: datetime,
        price: Decimal,
        quantity: Decimal
    ):
        """Process trade through the hierarchical aggregation pipeline."""
        await self._aggregators[Timeframe.M1].process_trade(
            symbol, timestamp, price, quantity
        )
```

This hierarchical approach reduces computational overhead significantly. Building a 4-hour bar from tick data requires processing thousands of ticks; building it from four 1-hour bars requires only four aggregation operations. The savings compound across multiple symbols and timeframes.

## Handling Incomplete Bars and Late-Arriving Data

Real-time trading systems must distinguish between bars still accumulating trades and bars representing intervals with no trading activity. A missing bar could indicate a data gap or simply a period of market inactivity.

### Gap Detection and Handling

```python
from typing import Tuple


@dataclass
class GapAwareBarManager:
    """
    Manages bar sequences with explicit gap handling.

    Distinguishes between:
    - Incomplete bars (interval still open)
    - Empty bars (interval closed with no trades)
    - Data gaps (missing data requiring backfill)
    """
    symbol: str
    interval_seconds: int
    _last_complete_bar: Optional[OHLCVBar] = None

    def check_for_gaps(
        self,
        new_bar: OHLCVBar
    ) -> Tuple[List[OHLCVBar], bool]:
        """
        Check for gaps between last complete bar and new bar.

        Returns:
            Tuple of (gap_bars_to_insert, has_gap)
        """
        if self._last_complete_bar is None:
            self._last_complete_bar = new_bar
            return [], False

        expected_start = self._last_complete_bar.interval_end
        actual_start = new_bar.interval_start

        if actual_start <= expected_start:
            # No gap (or overlap - handle late data separately)
            self._last_complete_bar = new_bar
            return [], False

        # Calculate number of missing intervals
        gap_seconds = (actual_start - expected_start).total_seconds()
        missing_intervals = int(gap_seconds / self.interval_seconds)

        if missing_intervals == 0:
            self._last_complete_bar = new_bar
            return [], False

        # Generate placeholder bars for gaps
        gap_bars = []
        current_start = expected_start

        for _ in range(missing_intervals):
            gap_bar = OHLCVBar(
                symbol=self.symbol,
                interval_start=current_start,
                interval_end=current_start + timedelta(seconds=self.interval_seconds),
                interval_seconds=self.interval_seconds,
                open=self._last_complete_bar.close,  # Forward-fill from last close
                high=self._last_complete_bar.close,
                low=self._last_complete_bar.close,
                close=self._last_complete_bar.close,
                volume=Decimal("0"),
                trade_count=0,
                is_complete=True
            )
            gap_bars.append(gap_bar)
            current_start = gap_bar.interval_end

        self._last_complete_bar = new_bar
        return gap_bars, True


def handle_late_arriving_trade(
    existing_bar: OHLCVBar,
    late_trade_price: Decimal,
    late_trade_quantity: Decimal,
    late_trade_timestamp: datetime
) -> OHLCVBar:
    """
    Update a completed bar with late-arriving trade data.

    Late trades can affect high, low, close, and volume.
    Open remains unchanged (first trade chronologically).
    """
    # Determine if this trade is chronologically first
    # Requires storing first trade timestamp in the bar

    updated_bar = OHLCVBar(
        symbol=existing_bar.symbol,
        interval_start=existing_bar.interval_start,
        interval_end=existing_bar.interval_end,
        interval_seconds=existing_bar.interval_seconds,
        open=existing_bar.open,  # May need update if trade is earlier
        high=max(existing_bar.high, late_trade_price),
        low=min(existing_bar.low, late_trade_price),
        close=existing_bar.close,  # May need update if trade is later
        volume=existing_bar.volume + late_trade_quantity,
        trade_count=existing_bar.trade_count + 1,
        is_complete=existing_bar.is_complete
    )

    return updated_bar
```

Gap handling strategies depend on downstream requirements. Forward-filling prices maintains technical indicator continuity; inserting explicit gap markers preserves data integrity for audit purposes. The implementation above forward-fills prices while setting volume to zero, clearly indicating synthetic bars.

## MongoDB to DuckDB ETL Pipeline

Operational trading systems prioritize write throughput and real-time access patterns. MongoDB handles tick data ingestion efficiently, scaling horizontally as volume increases. However, analytical queries—backtesting, performance analysis, market regime studies—benefit from columnar storage and vectorized execution. DuckDB provides these capabilities without the operational complexity of a dedicated analytical cluster.

### ETL Architecture Overview

The ETL pipeline extracts OHLCV bars from MongoDB, transforms them into analysis-ready format, and loads them into DuckDB. Two strategies address different requirements: incremental extraction for continuous updates, and full refresh for historical rebuilds.

```python
from pymongo import MongoClient
from pymongo.collection import Collection
import duckdb
from datetime import datetime, timedelta
from typing import Generator, Dict, Any


@dataclass
class ETLConfig:
    """Configuration for MongoDB to DuckDB ETL."""
    mongo_uri: str
    mongo_database: str
    mongo_collection: str
    duckdb_path: str
    batch_size: int = 10000


class OHLCVExtractor:
    """Extracts OHLCV bars from MongoDB."""

    def __init__(self, config: ETLConfig):
        self.config = config
        self.client = MongoClient(config.mongo_uri)
        self.db = self.client[config.mongo_database]
        self.collection: Collection = self.db[config.mongo_collection]

    def extract_incremental(
        self,
        symbol: str,
        timeframe: int,
        since: datetime
    ) -> Generator[Dict[str, Any], None, None]:
        """
        Extract bars modified since a given timestamp.

        Uses MongoDB's natural ordering and index on (symbol, interval_start).
        """
        query = {
            "symbol": symbol,
            "interval_seconds": timeframe,
            "interval_start": {"$gte": since}
        }

        cursor = self.collection.find(query).sort("interval_start", 1)

        batch = []
        for doc in cursor:
            batch.append(self._transform_document(doc))

            if len(batch) >= self.config.batch_size:
                yield from batch
                batch = []

        yield from batch

    def extract_full(
        self,
        symbol: str,
        timeframe: int,
        start_date: datetime,
        end_date: datetime
    ) -> Generator[Dict[str, Any], None, None]:
        """
        Extract all bars within a date range.

        Used for historical backfills and full refreshes.
        """
        query = {
            "symbol": symbol,
            "interval_seconds": timeframe,
            "interval_start": {
                "$gte": start_date,
                "$lt": end_date
            }
        }

        cursor = self.collection.find(query).sort("interval_start", 1)

        for doc in cursor:
            yield self._transform_document(doc)

    def _transform_document(self, doc: Dict[str, Any]) -> Dict[str, Any]:
        """Transform MongoDB document to DuckDB-compatible format."""
        return {
            "symbol": doc["symbol"],
            "interval_start": doc["interval_start"],
            "interval_end": doc["interval_end"],
            "interval_seconds": doc["interval_seconds"],
            "open": float(doc["open"]),
            "high": float(doc["high"]),
            "low": float(doc["low"]),
            "close": float(doc["close"]),
            "volume": float(doc["volume"]),
            "trade_count": doc.get("trade_count", 0),
            "is_complete": doc.get("is_complete", True)
        }
```

### DuckDB Loader with Schema Management

```python
class DuckDBLoader:
    """Loads OHLCV data into DuckDB with schema management."""

    SCHEMA = """
    CREATE TABLE IF NOT EXISTS ohlcv_bars (
        symbol VARCHAR NOT NULL,
        interval_start TIMESTAMP WITH TIME ZONE NOT NULL,
        interval_end TIMESTAMP WITH TIME ZONE NOT NULL,
        interval_seconds INTEGER NOT NULL,
        open DOUBLE NOT NULL,
        high DOUBLE NOT NULL,
        low DOUBLE NOT NULL,
        close DOUBLE NOT NULL,
        volume DOUBLE NOT NULL,
        trade_count INTEGER NOT NULL,
        is_complete BOOLEAN NOT NULL,
        etl_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (symbol, interval_seconds, interval_start)
    );

    CREATE INDEX IF NOT EXISTS idx_ohlcv_symbol_time
    ON ohlcv_bars (symbol, interval_start);

    CREATE INDEX IF NOT EXISTS idx_ohlcv_timeframe
    ON ohlcv_bars (interval_seconds, interval_start);
    """

    def __init__(self, duckdb_path: str):
        self.conn = duckdb.connect(duckdb_path)
        self._ensure_schema()

    def _ensure_schema(self):
        """Create tables and indexes if not present."""
        self.conn.execute(self.SCHEMA)

    def load_batch(self, bars: List[Dict[str, Any]]) -> int:
        """
        Load a batch of bars using INSERT OR REPLACE semantics.

        Returns number of rows affected.
        """
        if not bars:
            return 0

        # Create temporary table for batch
        self.conn.execute("""
            CREATE TEMPORARY TABLE IF NOT EXISTS staging_bars AS
            SELECT * FROM ohlcv_bars WHERE 1=0
        """)

        # Insert into staging
        self.conn.executemany("""
            INSERT INTO staging_bars (
                symbol, interval_start, interval_end, interval_seconds,
                open, high, low, close, volume, trade_count, is_complete
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, [
            (
                b["symbol"], b["interval_start"], b["interval_end"],
                b["interval_seconds"], b["open"], b["high"], b["low"],
                b["close"], b["volume"], b["trade_count"], b["is_complete"]
            )
            for b in bars
        ])

        # Upsert from staging to main table
        result = self.conn.execute("""
            INSERT OR REPLACE INTO ohlcv_bars
            SELECT *, CURRENT_TIMESTAMP as etl_timestamp
            FROM staging_bars
        """)

        affected = result.fetchone()[0] if result else len(bars)

        self.conn.execute("DROP TABLE staging_bars")

        return affected

    def get_latest_timestamp(
        self,
        symbol: str,
        timeframe: int
    ) -> Optional[datetime]:
        """Get the most recent bar timestamp for incremental extraction."""
        result = self.conn.execute("""
            SELECT MAX(interval_start)
            FROM ohlcv_bars
            WHERE symbol = ? AND interval_seconds = ?
        """, [symbol, timeframe]).fetchone()

        return result[0] if result and result[0] else None
```

### Incremental vs Full Refresh Strategies

Two ETL strategies address different operational requirements:

**Incremental extraction** queries the last loaded timestamp from DuckDB, applies a lookback buffer (typically 1 hour), and extracts all bars since that point. The lookback buffer re-extracts recent bars that might have received late updates, trading minor redundancy for correctness. This strategy runs frequently (every few minutes) with minimal resource consumption.

**Full refresh** deletes existing data in a date range before reloading from source. This strategy handles data corrections, schema migrations, and recovery from corruption. The complete reload ensures consistency but requires more time and resources.

The choice depends on operational context. Incremental extraction maintains near-real-time analytical availability; full refresh addresses exceptional circumstances requiring data reconstruction.

## DuckDB Analytical Query Patterns

DuckDB excels at analytical queries over OHLCV data. Window functions, time-series aggregations, and cross-timeframe joins execute efficiently on columnar storage.

```sql
-- Calculate daily returns with volatility metrics
WITH daily_stats AS (
    SELECT
        symbol,
        DATE_TRUNC('day', interval_start) as trading_day,
        FIRST(open ORDER BY interval_start) as day_open,
        MAX(high) as day_high,
        MIN(low) as day_low,
        LAST(close ORDER BY interval_start) as day_close,
        SUM(volume) as day_volume
    FROM ohlcv_bars
    WHERE interval_seconds = 60 AND interval_start >= '2027-01-01'
    GROUP BY symbol, DATE_TRUNC('day', interval_start)
)
SELECT
    symbol,
    COUNT(*) as trading_days,
    AVG((day_close - LAG(day_close) OVER (PARTITION BY symbol ORDER BY trading_day))
        / LAG(day_close) OVER (PARTITION BY symbol ORDER BY trading_day)) as avg_daily_return,
    STDDEV((day_close - LAG(day_close) OVER (PARTITION BY symbol ORDER BY trading_day))
        / LAG(day_close) OVER (PARTITION BY symbol ORDER BY trading_day)) as daily_volatility
FROM daily_stats
GROUP BY symbol;

-- Detect volume anomalies using rolling z-score
SELECT symbol, interval_start, volume,
    (volume - AVG(volume) OVER w) / NULLIF(STDDEV(volume) OVER w, 0) as volume_zscore
FROM ohlcv_bars
WHERE interval_seconds = 300
WINDOW w AS (PARTITION BY symbol ORDER BY interval_start
             ROWS BETWEEN 20 PRECEDING AND 1 PRECEDING)
HAVING ABS(volume_zscore) > 3;
```

These queries demonstrate DuckDB's analytical strengths: window functions with flexible frame specifications and efficient aggregations. Query execution benefits from columnar storage—reading only the columns needed for each query.

## Data Validation and Quality Checks

Data quality issues corrupt analysis results and degrade trading system performance. Systematic validation catches problems before they propagate through the pipeline.

### Validation Queries

DuckDB enables efficient data quality validation through SQL:

```sql
-- Check OHLC relationship validity (high >= open, close; low <= open, close)
SELECT interval_start, open, high, low, close
FROM ohlcv_bars
WHERE symbol = 'BTC-USD'
AND NOT (high >= open AND high >= close AND low <= open AND low <= close AND high >= low);

-- Detect price discontinuities exceeding threshold
WITH bar_gaps AS (
    SELECT
        interval_start,
        close,
        LAG(close) OVER (ORDER BY interval_start) as prev_close,
        ABS(close - LAG(close) OVER (ORDER BY interval_start)) /
            LAG(close) OVER (ORDER BY interval_start) * 100 as gap_percent
    FROM ohlcv_bars
    WHERE symbol = 'BTC-USD' AND interval_seconds = 60
)
SELECT * FROM bar_gaps WHERE gap_percent > 10.0;

-- Find duplicate bars at same timestamp
SELECT interval_start, COUNT(*) as bar_count
FROM ohlcv_bars
WHERE symbol = 'BTC-USD' AND interval_seconds = 60
GROUP BY interval_start
HAVING COUNT(*) > 1;

-- Identify volume anomalies using z-score
WITH volume_stats AS (
    SELECT AVG(volume) as avg_vol, STDDEV(volume) as std_vol
    FROM ohlcv_bars
    WHERE symbol = 'BTC-USD' AND interval_seconds = 60
)
SELECT b.interval_start, b.volume,
       (b.volume - vs.avg_vol) / NULLIF(vs.std_vol, 0) as zscore
FROM ohlcv_bars b CROSS JOIN volume_stats vs
WHERE b.symbol = 'BTC-USD'
AND ABS((b.volume - vs.avg_vol) / NULLIF(vs.std_vol, 0)) > 5;
```

These validation queries catch common data quality issues: impossible OHLC relationships (high below low), discontinuities suggesting missing data, volume anomalies indicating processing errors, and duplicates from idempotency failures. Production systems execute these checks after each ETL run, alerting on failures.

## Production Deployment Considerations

Production deployments require monitoring extraction latency, load latency, throughput, error rates, data freshness, and validation failure rates. When pipeline failures occur, recovery depends on failure mode: transient network failures warrant retry with exponential backoff; MongoDB unavailability requires queuing extraction requests; DuckDB corruption necessitates restore from backup followed by full refresh. The full refresh capability proves essential for recovery—any data range can be rebuilt from source without complex rollback procedures.

## Conclusion

OHLCV bar construction and ETL pipelines form the analytical foundation of trading systems. Careful attention to edge cases—interval boundaries, late-arriving data, market gaps—produces reliable aggregations. The MongoDB-to-DuckDB pipeline bridges operational and analytical requirements, enabling both real-time trading and historical analysis.

The implementations presented here prioritize correctness over performance optimization. Production deployments may require additional tuning: batch sizes calibrated to available memory, parallelized extraction across symbols, and incremental indexes for common query patterns. These optimizations build upon a correct foundation rather than replacing it.

The next post examines backtesting framework architecture, demonstrating how the OHLCV data prepared here feeds systematic strategy evaluation with proper handling of lookahead bias and transaction costs.

---

*This post is part of the Real-Time Trading Infrastructure series. Navigate to other posts:*
- *[Part 4: Time-Series Database Integration](/posts/timeseries-database-trading/)*
- *[Part 5: WebSocket Streaming and Order Book Management](/posts/websocket-orderbook-management/)*
- *[Part 7: Backtesting Framework Architecture](/posts/backtesting-framework-architecture/)*

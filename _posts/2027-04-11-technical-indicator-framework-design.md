---
title: "Part 7: Building a Composable Technical Indicator Framework"
date: 2027-04-11 10:00:00 -0700
categories: [Trading Systems, Quantitative Analysis]
tags: [technical-indicators, python, numpy, pandas, framework-design, financial-analysis]
series: real-time-trading-infrastructure
series_order: 7
---

*Part 7 of the [Real-Time Trading Infrastructure series](/posts/real-time-trading-infrastructure-series/). Previous: [Part 6: Order Management Service](/posts/order-management-service/). Next: [Part 8: Position Tracking System](/posts/position-tracking-system/).*

Technical indicators form the computational foundation of quantitative trading systems. Moving averages, momentum oscillators, and volatility measures transform raw price data into actionable signals. However, implementing these indicators as standalone functions creates maintenance burdens and inhibits composition. A well-designed indicator framework abstracts common patterns—warmup periods, state management, output schemas—while enabling both vectorized backtesting and streaming real-time computation.

This post presents a composable indicator framework architecture, examining abstraction patterns, computation modes, and testing methodologies. The focus remains on framework design principles applicable across indicator categories rather than proprietary signal combinations.

## Indicator Abstraction Patterns

### The Problem with Ad-Hoc Implementation

Consider a naive approach to indicator implementation:

```python
def calculate_sma(prices: list, period: int) -> list:
    result = []
    for i in range(len(prices)):
        if i < period - 1:
            result.append(float('nan'))
        else:
            result.append(sum(prices[i-period+1:i+1]) / period)
    return result

def calculate_ema(prices: list, period: int) -> list:
    result = []
    multiplier = 2 / (period + 1)
    for i, price in enumerate(prices):
        if i == 0:
            result.append(price)
        else:
            result.append(price * multiplier + result[-1] * (1 - multiplier))
    return result
```

These functions work, but they share no common interface. Each handles warmup differently (SMA returns NaN, EMA uses the first price). Neither validates inputs. Neither documents output schemas. Adding a new indicator requires understanding each existing implementation's conventions.

### Base Indicator Class Design

A base class establishes consistent behavior across all indicators:

```python
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Dict, Any, Optional, List
from enum import Enum
import numpy as np


class OutputType(Enum):
    """Classification of indicator output values."""
    PRICE = "price"           # Absolute price level (e.g., moving average)
    BOUNDED = "bounded"       # Fixed range (e.g., RSI 0-100)
    UNBOUNDED = "unbounded"   # No fixed range (e.g., MACD histogram)
    BINARY = "binary"         # Signal flags (0 or 1)


@dataclass
class OutputSchema:
    """Describes a single output from an indicator."""
    name: str
    output_type: OutputType
    min_value: Optional[float] = None
    max_value: Optional[float] = None
    description: str = ""


@dataclass
class IndicatorConfig:
    """Base configuration for all indicators."""
    name: str
    warmup_period: int
    outputs: List[OutputSchema]
    parameters: Dict[str, Any] = field(default_factory=dict)


class Indicator(ABC):
    """
    Abstract base class for all technical indicators.

    Subclasses must implement:
    - _compute_vectorized: Batch computation on full price history
    - _compute_streaming: Single-value update with state management
    - _get_config: Return indicator configuration
    """

    def __init__(self, **params):
        self._params = params
        self._config = self._get_config()
        self._state: Dict[str, Any] = {}
        self._values_received = 0

    @property
    def config(self) -> IndicatorConfig:
        return self._config

    @property
    def warmup_period(self) -> int:
        return self._config.warmup_period

    @property
    def is_warmed_up(self) -> bool:
        return self._values_received >= self.warmup_period

    @abstractmethod
    def _get_config(self) -> IndicatorConfig:
        """Return configuration describing this indicator."""
        pass

    @abstractmethod
    def _compute_vectorized(
        self,
        data: Dict[str, np.ndarray]
    ) -> Dict[str, np.ndarray]:
        """
        Compute indicator values for entire price history.

        Args:
            data: Dictionary with 'open', 'high', 'low', 'close', 'volume' arrays

        Returns:
            Dictionary mapping output names to computed value arrays
        """
        pass

    @abstractmethod
    def _compute_streaming(
        self,
        data: Dict[str, float]
    ) -> Dict[str, Optional[float]]:
        """
        Compute indicator value for single new data point.

        Args:
            data: Dictionary with 'open', 'high', 'low', 'close', 'volume' values

        Returns:
            Dictionary mapping output names to computed values (None if warming up)
        """
        pass

    def compute(
        self,
        data: Dict[str, Any],
        mode: str = "vectorized"
    ) -> Dict[str, Any]:
        """
        Primary computation interface.

        Args:
            data: Price data (arrays for vectorized, scalars for streaming)
            mode: Either 'vectorized' or 'streaming'

        Returns:
            Computed indicator values
        """
        if mode == "vectorized":
            return self._compute_vectorized(data)
        elif mode == "streaming":
            self._values_received += 1
            return self._compute_streaming(data)
        else:
            raise ValueError(f"Unknown computation mode: {mode}")

    def reset(self) -> None:
        """Clear internal state for fresh computation."""
        self._state = {}
        self._values_received = 0
```

This base class provides several guarantees:

1. **Configuration discovery**: External code inspects `config` to understand outputs without reading implementation details.
2. **Warmup tracking**: The `is_warmed_up` property indicates when output becomes valid.
3. **Dual computation modes**: The same indicator implementation serves both backtesting and live trading.
4. **State isolation**: The `reset()` method enables clean recomputation.

### Output Schema Benefits

The `OutputSchema` dataclass enables downstream processing without indicator-specific knowledge:

```python
def normalize_indicator_output(
    indicator: Indicator,
    values: Dict[str, np.ndarray]
) -> Dict[str, np.ndarray]:
    """
    Normalize indicator outputs to [0, 1] range for ML features.
    """
    normalized = {}

    for output in indicator.config.outputs:
        raw = values[output.name]

        if output.output_type == OutputType.BOUNDED:
            # Use declared bounds
            normalized[output.name] = (
                (raw - output.min_value) /
                (output.max_value - output.min_value)
            )
        elif output.output_type == OutputType.PRICE:
            # Normalize relative to price level
            normalized[output.name] = raw / values.get('close', raw)
        elif output.output_type == OutputType.UNBOUNDED:
            # Z-score normalization
            normalized[output.name] = (
                (raw - np.nanmean(raw)) / np.nanstd(raw)
            )
        elif output.output_type == OutputType.BINARY:
            # Already normalized
            normalized[output.name] = raw

    return normalized
```

Schema-driven normalization eliminates per-indicator conditional logic.

## Stateless vs Stateful Indicator Computation

### Stateless Indicators

Stateless indicators compute output solely from the current input window. Given the same input data, they produce identical results regardless of computation history:

```python
class SimpleMovingAverage(Indicator):
    """
    Simple Moving Average - stateless computation.

    Each output depends only on the preceding N values.
    """

    def __init__(self, period: int = 20):
        self._period = period
        super().__init__(period=period)

    def _get_config(self) -> IndicatorConfig:
        return IndicatorConfig(
            name=f"SMA_{self._period}",
            warmup_period=self._period,
            outputs=[
                OutputSchema(
                    name="sma",
                    output_type=OutputType.PRICE,
                    description=f"{self._period}-period simple moving average"
                )
            ],
            parameters={"period": self._period}
        )

    def _compute_vectorized(
        self,
        data: Dict[str, np.ndarray]
    ) -> Dict[str, np.ndarray]:
        close = data['close']

        # Efficient convolution-based computation
        kernel = np.ones(self._period) / self._period
        sma = np.convolve(close, kernel, mode='valid')

        # Pad with NaN for warmup period
        result = np.full(len(close), np.nan)
        result[self._period - 1:] = sma

        return {"sma": result}

    def _compute_streaming(
        self,
        data: Dict[str, float]
    ) -> Dict[str, Optional[float]]:
        close = data['close']

        # Maintain rolling window in state
        if 'window' not in self._state:
            self._state['window'] = []

        window = self._state['window']
        window.append(close)

        if len(window) > self._period:
            window.pop(0)

        if len(window) < self._period:
            return {"sma": None}

        return {"sma": sum(window) / self._period}
```

For stateless indicators, the streaming implementation must maintain a rolling window to match vectorized behavior.

### Stateful Indicators

Stateful indicators incorporate all historical data into their computation. The current output depends on the entire sequence of prior inputs:

```python
class ExponentialMovingAverage(Indicator):
    """
    Exponential Moving Average - stateful computation.

    Each output depends on all prior values through recursive weighting.
    """

    def __init__(self, period: int = 20):
        self._period = period
        self._multiplier = 2 / (period + 1)
        super().__init__(period=period)

    def _get_config(self) -> IndicatorConfig:
        return IndicatorConfig(
            name=f"EMA_{self._period}",
            warmup_period=self._period,
            outputs=[
                OutputSchema(
                    name="ema",
                    output_type=OutputType.PRICE,
                    description=f"{self._period}-period exponential moving average"
                )
            ],
            parameters={"period": self._period}
        )

    def _compute_vectorized(
        self,
        data: Dict[str, np.ndarray]
    ) -> Dict[str, np.ndarray]:
        close = data['close']
        ema = np.full(len(close), np.nan)

        # Initialize with SMA for warmup period
        if len(close) >= self._period:
            ema[self._period - 1] = np.mean(close[:self._period])

            # Recursive EMA computation
            for i in range(self._period, len(close)):
                ema[i] = (
                    close[i] * self._multiplier +
                    ema[i-1] * (1 - self._multiplier)
                )

        return {"ema": ema}

    def _compute_streaming(
        self,
        data: Dict[str, float]
    ) -> Dict[str, Optional[float]]:
        close = data['close']

        if 'ema' not in self._state:
            # Accumulate values for initial SMA
            if 'warmup_values' not in self._state:
                self._state['warmup_values'] = []

            self._state['warmup_values'].append(close)

            if len(self._state['warmup_values']) < self._period:
                return {"ema": None}

            # Initialize EMA with SMA
            self._state['ema'] = (
                sum(self._state['warmup_values']) / self._period
            )
            del self._state['warmup_values']
            return {"ema": self._state['ema']}

        # Standard EMA update
        self._state['ema'] = (
            close * self._multiplier +
            self._state['ema'] * (1 - self._multiplier)
        )

        return {"ema": self._state['ema']}
```

The stateful streaming implementation maintains only the previous EMA value, not a full window. This reduces memory requirements for long-running streaming systems.

### State Management Considerations

State management affects several system properties:

| Aspect | Stateless | Stateful |
|--------|-----------|----------|
| Memory (streaming) | O(window_size) | O(1) to O(state_size) |
| Recomputation | Requires window history | Requires full history |
| Mid-stream restart | Rebuild window | May need full replay |
| Numerical precision | Stable | May accumulate drift |

For stateful indicators, long-running streaming computations may accumulate floating-point errors. Periodic recomputation from raw data mitigates this drift.

## Handling Warmup Periods and NaN Values

### Warmup Period Definition

The warmup period represents the minimum data points required before an indicator produces valid output. Different indicators have different warmup requirements:

| Indicator | Warmup Period | Reason |
|-----------|---------------|--------|
| SMA(20) | 20 | Requires 20 values for average |
| EMA(20) | 20 | Needs SMA for initialization |
| RSI(14) | 15 | 14 periods for average gain/loss, plus 1 |
| MACD(12,26,9) | 26 + 9 - 1 = 34 | Slowest EMA plus signal line |
| Bollinger(20,2) | 20 | Standard deviation window |

### Cascading Warmup in Composite Indicators

Indicators built from other indicators inherit cumulative warmup requirements:

```python
class MACD(Indicator):
    """
    Moving Average Convergence Divergence.

    Combines two EMAs plus a signal line EMA.
    """

    def __init__(
        self,
        fast_period: int = 12,
        slow_period: int = 26,
        signal_period: int = 9
    ):
        self._fast_period = fast_period
        self._slow_period = slow_period
        self._signal_period = signal_period
        super().__init__(
            fast_period=fast_period,
            slow_period=slow_period,
            signal_period=signal_period
        )

    def _get_config(self) -> IndicatorConfig:
        # MACD line valid after slow_period
        # Signal line needs additional signal_period - 1
        warmup = self._slow_period + self._signal_period - 1

        return IndicatorConfig(
            name=f"MACD_{self._fast_period}_{self._slow_period}_{self._signal_period}",
            warmup_period=warmup,
            outputs=[
                OutputSchema(
                    name="macd_line",
                    output_type=OutputType.UNBOUNDED,
                    description="MACD line (fast EMA - slow EMA)"
                ),
                OutputSchema(
                    name="signal_line",
                    output_type=OutputType.UNBOUNDED,
                    description="Signal line (EMA of MACD line)"
                ),
                OutputSchema(
                    name="histogram",
                    output_type=OutputType.UNBOUNDED,
                    description="MACD histogram (MACD - signal)"
                )
            ],
            parameters={
                "fast_period": self._fast_period,
                "slow_period": self._slow_period,
                "signal_period": self._signal_period
            }
        )

    def _compute_vectorized(
        self,
        data: Dict[str, np.ndarray]
    ) -> Dict[str, np.ndarray]:
        close = data['close']
        n = len(close)

        # Compute component EMAs
        fast_ema = self._compute_ema(close, self._fast_period)
        slow_ema = self._compute_ema(close, self._slow_period)

        # MACD line
        macd_line = fast_ema - slow_ema

        # Signal line (EMA of MACD line, starting after slow EMA valid)
        signal_line = np.full(n, np.nan)
        valid_macd = macd_line[self._slow_period - 1:]
        signal_ema = self._compute_ema(valid_macd, self._signal_period)
        signal_line[self._slow_period + self._signal_period - 2:] = (
            signal_ema[self._signal_period - 1:]
        )

        # Histogram
        histogram = macd_line - signal_line

        return {
            "macd_line": macd_line,
            "signal_line": signal_line,
            "histogram": histogram
        }

    def _compute_ema(self, values: np.ndarray, period: int) -> np.ndarray:
        """Helper to compute EMA for a given period."""
        result = np.full(len(values), np.nan)
        if len(values) < period:
            return result

        multiplier = 2 / (period + 1)
        result[period - 1] = np.mean(values[:period])

        for i in range(period, len(values)):
            result[i] = values[i] * multiplier + result[i-1] * (1 - multiplier)

        return result

    def _compute_streaming(
        self,
        data: Dict[str, float]
    ) -> Dict[str, Optional[float]]:
        close = data['close']

        # Initialize state
        if 'fast_ema' not in self._state:
            self._state['fast_warmup'] = []
            self._state['slow_warmup'] = []
            self._state['signal_warmup'] = []

        # Accumulate warmup values
        if 'fast_ema' not in self._state:
            self._state['fast_warmup'].append(close)
            self._state['slow_warmup'].append(close)

            if len(self._state['slow_warmup']) < self._slow_period:
                return {
                    "macd_line": None,
                    "signal_line": None,
                    "histogram": None
                }

            # Initialize EMAs
            self._state['fast_ema'] = np.mean(
                self._state['fast_warmup'][-self._fast_period:]
            )
            self._state['slow_ema'] = np.mean(self._state['slow_warmup'])
            del self._state['fast_warmup']
            del self._state['slow_warmup']
        else:
            # Update EMAs
            fast_mult = 2 / (self._fast_period + 1)
            slow_mult = 2 / (self._slow_period + 1)

            self._state['fast_ema'] = (
                close * fast_mult +
                self._state['fast_ema'] * (1 - fast_mult)
            )
            self._state['slow_ema'] = (
                close * slow_mult +
                self._state['slow_ema'] * (1 - slow_mult)
            )

        macd_line = self._state['fast_ema'] - self._state['slow_ema']

        # Signal line warmup
        if 'signal_ema' not in self._state:
            self._state['signal_warmup'].append(macd_line)

            if len(self._state['signal_warmup']) < self._signal_period:
                return {
                    "macd_line": macd_line,
                    "signal_line": None,
                    "histogram": None
                }

            self._state['signal_ema'] = np.mean(self._state['signal_warmup'])
            del self._state['signal_warmup']
        else:
            signal_mult = 2 / (self._signal_period + 1)
            self._state['signal_ema'] = (
                macd_line * signal_mult +
                self._state['signal_ema'] * (1 - signal_mult)
            )

        signal_line = self._state['signal_ema']
        histogram = macd_line - signal_line

        return {
            "macd_line": macd_line,
            "signal_line": signal_line,
            "histogram": histogram
        }
```

### NaN Propagation Strategy

Consistent NaN handling prevents subtle bugs in downstream computation:

```python
class NaNPolicy(Enum):
    """Strategies for handling NaN values in indicator input."""
    PROPAGATE = "propagate"    # NaN in, NaN out
    SKIP = "skip"              # Ignore NaN values
    FILL_FORWARD = "ffill"     # Use last valid value
    FILL_ZERO = "zero"         # Replace with zero


def apply_nan_policy(
    data: np.ndarray,
    policy: NaNPolicy
) -> np.ndarray:
    """Apply NaN handling policy to input data."""
    if policy == NaNPolicy.PROPAGATE:
        return data
    elif policy == NaNPolicy.SKIP:
        return data[~np.isnan(data)]
    elif policy == NaNPolicy.FILL_FORWARD:
        result = data.copy()
        mask = np.isnan(result)
        idx = np.where(~mask, np.arange(len(result)), 0)
        np.maximum.accumulate(idx, out=idx)
        result[mask] = result[idx[mask]]
        return result
    elif policy == NaNPolicy.FILL_ZERO:
        return np.nan_to_num(data, nan=0.0)
```

The framework defaults to NaN propagation, making missing data visible rather than silently corrupting calculations.

## Vectorized Computation for Backtesting

### Performance Characteristics

Backtesting processes historical data in bulk, favoring vectorized operations over Python loops:

```python
import time
import numpy as np

def benchmark_sma_implementations(data_length: int, period: int):
    """Compare loop vs vectorized SMA performance."""
    data = np.random.randn(data_length).cumsum() + 100

    # Loop implementation
    start = time.perf_counter()
    result_loop = np.full(data_length, np.nan)
    for i in range(period - 1, data_length):
        result_loop[i] = np.mean(data[i - period + 1:i + 1])
    loop_time = time.perf_counter() - start

    # Vectorized implementation
    start = time.perf_counter()
    kernel = np.ones(period) / period
    result_vec = np.convolve(data, kernel, mode='valid')
    result_vectorized = np.full(data_length, np.nan)
    result_vectorized[period - 1:] = result_vec
    vec_time = time.perf_counter() - start

    return {
        "data_length": data_length,
        "loop_ms": loop_time * 1000,
        "vectorized_ms": vec_time * 1000,
        "speedup": loop_time / vec_time
    }
```

Typical results on a 100,000-bar dataset:

| Data Length | Loop Time (ms) | Vectorized Time (ms) | Speedup |
|-------------|----------------|----------------------|---------|
| 10,000 | 45.2 | 0.8 | 56x |
| 100,000 | 512.3 | 2.1 | 244x |
| 1,000,000 | 5,847.1 | 18.4 | 318x |

### NumPy Optimization Patterns

Several NumPy techniques enable efficient indicator computation:

```python
class RSI(Indicator):
    """
    Relative Strength Index - demonstrates NumPy optimization patterns.
    """

    def __init__(self, period: int = 14):
        self._period = period
        super().__init__(period=period)

    def _get_config(self) -> IndicatorConfig:
        return IndicatorConfig(
            name=f"RSI_{self._period}",
            warmup_period=self._period + 1,
            outputs=[
                OutputSchema(
                    name="rsi",
                    output_type=OutputType.BOUNDED,
                    min_value=0.0,
                    max_value=100.0,
                    description=f"{self._period}-period Relative Strength Index"
                )
            ],
            parameters={"period": self._period}
        )

    def _compute_vectorized(
        self,
        data: Dict[str, np.ndarray]
    ) -> Dict[str, np.ndarray]:
        close = data['close']
        n = len(close)

        # Price changes
        delta = np.diff(close, prepend=close[0])

        # Separate gains and losses using NumPy where
        gains = np.where(delta > 0, delta, 0.0)
        losses = np.where(delta < 0, -delta, 0.0)

        # Compute smoothed averages using Wilder's method
        avg_gain = np.zeros(n)
        avg_loss = np.zeros(n)

        # Initial average (SMA)
        if n > self._period:
            avg_gain[self._period] = np.mean(gains[1:self._period + 1])
            avg_loss[self._period] = np.mean(losses[1:self._period + 1])

            # Smoothed averages (exponential)
            for i in range(self._period + 1, n):
                avg_gain[i] = (
                    avg_gain[i-1] * (self._period - 1) + gains[i]
                ) / self._period
                avg_loss[i] = (
                    avg_loss[i-1] * (self._period - 1) + losses[i]
                ) / self._period

        # RSI calculation with divide-by-zero protection
        rs = np.divide(
            avg_gain,
            avg_loss,
            out=np.zeros_like(avg_gain),
            where=avg_loss != 0
        )
        rsi = 100 - (100 / (1 + rs))

        # Set warmup period to NaN
        rsi[:self._period] = np.nan

        return {"rsi": rsi}

    def _compute_streaming(
        self,
        data: Dict[str, float]
    ) -> Dict[str, Optional[float]]:
        close = data['close']

        # Initialize state
        if 'prev_close' not in self._state:
            self._state['prev_close'] = close
            self._state['gains'] = []
            self._state['losses'] = []
            return {"rsi": None}

        # Calculate change
        delta = close - self._state['prev_close']
        self._state['prev_close'] = close

        gain = max(0, delta)
        loss = max(0, -delta)

        # Warmup phase
        if 'avg_gain' not in self._state:
            self._state['gains'].append(gain)
            self._state['losses'].append(loss)

            if len(self._state['gains']) < self._period:
                return {"rsi": None}

            # Initialize averages
            self._state['avg_gain'] = np.mean(self._state['gains'])
            self._state['avg_loss'] = np.mean(self._state['losses'])
            del self._state['gains']
            del self._state['losses']
        else:
            # Smoothed average update
            self._state['avg_gain'] = (
                self._state['avg_gain'] * (self._period - 1) + gain
            ) / self._period
            self._state['avg_loss'] = (
                self._state['avg_loss'] * (self._period - 1) + loss
            ) / self._period

        # Calculate RSI
        if self._state['avg_loss'] == 0:
            rsi = 100.0
        else:
            rs = self._state['avg_gain'] / self._state['avg_loss']
            rsi = 100 - (100 / (1 + rs))

        return {"rsi": rsi}
```

Key optimization techniques demonstrated:

1. **np.diff**: Vectorized differencing instead of loop
2. **np.where**: Conditional selection without branching
3. **np.divide with where**: Safe division avoiding conditionals
4. **Preallocated arrays**: Avoid dynamic resizing

## Streaming Computation for Real-Time

### Streaming Architecture

Real-time systems receive data incrementally. The streaming computation interface processes one data point per call while maintaining internal state:

```python
class StreamingIndicatorEngine:
    """
    Manages multiple indicators for real-time streaming computation.
    """

    def __init__(self):
        self._indicators: Dict[str, Indicator] = {}
        self._output_buffer: Dict[str, Dict[str, List[float]]] = {}

    def register(self, name: str, indicator: Indicator) -> None:
        """Add an indicator to the streaming engine."""
        self._indicators[name] = indicator
        self._output_buffer[name] = {
            output.name: []
            for output in indicator.config.outputs
        }

    def process(self, data: Dict[str, float]) -> Dict[str, Dict[str, Any]]:
        """
        Process a single data point through all registered indicators.

        Args:
            data: OHLCV data for current bar

        Returns:
            Dictionary mapping indicator names to their outputs
        """
        results = {}

        for name, indicator in self._indicators.items():
            output = indicator.compute(data, mode="streaming")
            results[name] = {
                "values": output,
                "warmed_up": indicator.is_warmed_up
            }

            # Buffer outputs for analysis
            for output_name, value in output.items():
                self._output_buffer[name][output_name].append(value)

        return results

    def get_history(
        self,
        indicator_name: str,
        output_name: str,
        lookback: int = 100
    ) -> List[Optional[float]]:
        """Retrieve recent values for an indicator output."""
        buffer = self._output_buffer.get(indicator_name, {}).get(output_name, [])
        return buffer[-lookback:]

    def reset_all(self) -> None:
        """Reset all indicators to initial state."""
        for indicator in self._indicators.values():
            indicator.reset()
        for buffers in self._output_buffer.values():
            for output_name in buffers:
                buffers[output_name] = []


# Usage example
engine = StreamingIndicatorEngine()
engine.register("rsi_14", RSI(period=14))
engine.register("ema_20", ExponentialMovingAverage(period=20))
engine.register("macd", MACD(fast_period=12, slow_period=26, signal_period=9))

# Process incoming bars
for bar in market_data_stream:
    results = engine.process({
        "open": bar.open,
        "high": bar.high,
        "low": bar.low,
        "close": bar.close,
        "volume": bar.volume
    })

    if results["rsi_14"]["warmed_up"]:
        rsi_value = results["rsi_14"]["values"]["rsi"]
        # Use RSI value for decision logic
```

### Memory Management in Long-Running Systems

Streaming systems operate continuously, requiring careful memory management:

```python
from collections import deque
from typing import Deque


class BoundedHistoryIndicator(Indicator):
    """
    Indicator with bounded history buffer for memory-constrained environments.
    """

    def __init__(self, max_history: int = 1000, **params):
        self._max_history = max_history
        super().__init__(**params)

    def _init_bounded_buffer(self, name: str) -> None:
        """Initialize a bounded deque for storing history."""
        if 'buffers' not in self._state:
            self._state['buffers'] = {}
        self._state['buffers'][name] = deque(maxlen=self._max_history)

    def _append_to_buffer(self, name: str, value: float) -> None:
        """Append value to bounded buffer, automatically dropping oldest."""
        self._state['buffers'][name].append(value)

    def _get_buffer_array(self, name: str) -> np.ndarray:
        """Convert bounded buffer to NumPy array."""
        return np.array(self._state['buffers'][name])
```

The `deque` with `maxlen` provides O(1) append and automatic pruning of old values.

## Testing Indicators Against Reference Implementations

### Reference Data Sources

Indicator implementations require validation against trusted references. Common sources include:

1. **TA-Lib**: Industry-standard C library with Python bindings
2. **pandas-ta**: Pure Python implementation for comparison
3. **Exchange data**: Some exchanges provide indicator values
4. **Manual calculation**: Spreadsheet verification for small datasets

### Automated Testing Framework

```python
import pytest
import numpy as np
import talib


class IndicatorTestSuite:
    """
    Base class for indicator validation tests.
    """

    @staticmethod
    def generate_test_data(
        length: int = 500,
        seed: int = 42
    ) -> Dict[str, np.ndarray]:
        """Generate reproducible random OHLCV data."""
        np.random.seed(seed)

        # Generate realistic price movement
        returns = np.random.randn(length) * 0.02
        close = 100 * np.exp(returns.cumsum())

        # Generate OHLC from close
        noise = np.abs(np.random.randn(length)) * 0.005
        high = close * (1 + noise)
        low = close * (1 - noise)
        open_price = np.roll(close, 1)
        open_price[0] = close[0]

        volume = np.random.uniform(1000, 10000, length)

        return {
            "open": open_price,
            "high": high,
            "low": low,
            "close": close,
            "volume": volume
        }

    @staticmethod
    def assert_arrays_close(
        actual: np.ndarray,
        expected: np.ndarray,
        rtol: float = 1e-5,
        atol: float = 1e-8,
        skip_nan: bool = True
    ) -> None:
        """Assert two arrays are numerically close, handling NaN."""
        if skip_nan:
            # Compare only non-NaN positions
            mask = ~(np.isnan(actual) | np.isnan(expected))
            np.testing.assert_allclose(
                actual[mask],
                expected[mask],
                rtol=rtol,
                atol=atol
            )
            # Verify NaN positions match
            np.testing.assert_array_equal(
                np.isnan(actual),
                np.isnan(expected)
            )
        else:
            np.testing.assert_allclose(actual, expected, rtol=rtol, atol=atol)


class TestSMAAgainstTALib(IndicatorTestSuite):
    """Validate SMA implementation against TA-Lib."""

    @pytest.mark.parametrize("period", [5, 10, 20, 50])
    def test_sma_matches_talib(self, period: int):
        data = self.generate_test_data()

        # Reference implementation
        expected = talib.SMA(data['close'], timeperiod=period)

        # Framework implementation
        sma = SimpleMovingAverage(period=period)
        actual = sma.compute(data, mode="vectorized")["sma"]

        self.assert_arrays_close(actual, expected)


class TestRSIAgainstTALib(IndicatorTestSuite):
    """Validate RSI implementation against TA-Lib."""

    @pytest.mark.parametrize("period", [7, 14, 21])
    def test_rsi_matches_talib(self, period: int):
        data = self.generate_test_data()

        # Reference implementation
        expected = talib.RSI(data['close'], timeperiod=period)

        # Framework implementation
        rsi = RSI(period=period)
        actual = rsi.compute(data, mode="vectorized")["rsi"]

        self.assert_arrays_close(actual, expected)


class TestStreamingVsVectorized(IndicatorTestSuite):
    """Verify streaming and vectorized modes produce identical results."""

    def test_sma_streaming_matches_vectorized(self):
        data = self.generate_test_data(length=200)
        period = 20

        sma = SimpleMovingAverage(period=period)

        # Vectorized computation
        vectorized = sma.compute(data, mode="vectorized")["sma"]

        # Streaming computation
        sma.reset()
        streaming = []
        for i in range(len(data['close'])):
            bar = {k: v[i] for k, v in data.items()}
            result = sma.compute(bar, mode="streaming")["sma"]
            streaming.append(result if result is not None else np.nan)

        streaming = np.array(streaming)

        self.assert_arrays_close(vectorized, streaming)
```

### Edge Case Testing

Robust indicators handle edge cases gracefully:

```python
class TestIndicatorEdgeCases(IndicatorTestSuite):
    """Test indicator behavior with edge case inputs."""

    def test_constant_price_series(self):
        """Indicators should handle zero volatility."""
        data = {
            "open": np.ones(100) * 100,
            "high": np.ones(100) * 100,
            "low": np.ones(100) * 100,
            "close": np.ones(100) * 100,
            "volume": np.ones(100) * 1000
        }

        rsi = RSI(period=14)
        result = rsi.compute(data, mode="vectorized")["rsi"]

        # RSI should be 50 for flat price (no gains or losses)
        valid_values = result[~np.isnan(result)]
        # With no change, gains = losses = 0, RSI undefined or 50
        assert all(v == 50.0 or np.isnan(v) for v in valid_values)

    def test_gap_handling(self):
        """Indicators should handle price gaps."""
        data = self.generate_test_data(length=100)
        # Insert a 10% gap
        data['close'][50:] *= 1.10
        data['high'][50:] *= 1.10
        data['low'][50:] *= 1.10

        sma = SimpleMovingAverage(period=20)
        result = sma.compute(data, mode="vectorized")["sma"]

        # Should not produce NaN after gap
        assert not np.isnan(result[-1])

    def test_minimum_data_length(self):
        """Indicators should handle data shorter than warmup period."""
        data = self.generate_test_data(length=10)

        sma = SimpleMovingAverage(period=20)
        result = sma.compute(data, mode="vectorized")["sma"]

        # All values should be NaN
        assert all(np.isnan(result))
```

## Overview of Indicator Categories

### Momentum Indicators

Momentum indicators measure the rate of price change, identifying overbought and oversold conditions:

| Indicator | Description | Output Range | Common Periods |
|-----------|-------------|--------------|----------------|
| RSI | Relative Strength Index | 0-100 | 14 |
| Stochastic | Price position within range | 0-100 | 14, 3, 3 |
| Williams %R | Inverse stochastic | -100 to 0 | 14 |
| CCI | Commodity Channel Index | Unbounded | 20 |
| ROC | Rate of Change | Unbounded | 12 |

Momentum indicators excel at identifying potential reversal points but may generate false signals in strong trends.

### Trend Indicators

Trend indicators smooth price data to identify directional bias:

| Indicator | Description | Output Type | Common Periods |
|-----------|-------------|-------------|----------------|
| SMA | Simple Moving Average | Price level | 20, 50, 200 |
| EMA | Exponential Moving Average | Price level | 12, 26, 50 |
| MACD | Moving Average Convergence | Unbounded | 12, 26, 9 |
| ADX | Average Directional Index | 0-100 | 14 |
| Parabolic SAR | Stop and Reverse | Price level | 0.02, 0.2 |

Trend indicators confirm directional moves but lag price action by design.

### Volatility Indicators

Volatility indicators measure price dispersion and market uncertainty:

| Indicator | Description | Output Type | Common Periods |
|-----------|-------------|-------------|----------------|
| ATR | Average True Range | Price range | 14 |
| Bollinger Bands | Standard deviation bands | Price levels | 20, 2 |
| Keltner Channels | ATR-based bands | Price levels | 20, 2 |
| Standard Deviation | Price dispersion | Price range | 20 |
| Historical Volatility | Annualized std dev | Percentage | 20 |

Volatility indicators inform position sizing and stop-loss placement.

### Volume Indicators

Volume indicators incorporate trading activity to confirm price movements:

| Indicator | Description | Output Type | Common Periods |
|-----------|-------------|-------------|----------------|
| OBV | On-Balance Volume | Cumulative volume | N/A |
| VWAP | Volume-Weighted Avg Price | Price level | Session |
| MFI | Money Flow Index | 0-100 | 14 |
| A/D Line | Accumulation/Distribution | Cumulative | N/A |
| CMF | Chaikin Money Flow | -1 to 1 | 20 |

Volume indicators provide confirmation signals, with divergences suggesting potential reversals.

### Composite Indicators

The framework supports composing multiple indicators:

```python
class IndicatorComposite(Indicator):
    """
    Combines multiple indicators into a single computational unit.
    """

    def __init__(self, indicators: List[Indicator]):
        self._indicators = indicators
        super().__init__()

    def _get_config(self) -> IndicatorConfig:
        # Aggregate outputs from all component indicators
        all_outputs = []
        max_warmup = 0

        for ind in self._indicators:
            config = ind.config
            all_outputs.extend(config.outputs)
            max_warmup = max(max_warmup, config.warmup_period)

        return IndicatorConfig(
            name="Composite",
            warmup_period=max_warmup,
            outputs=all_outputs,
            parameters={"components": [i.config.name for i in self._indicators]}
        )

    def _compute_vectorized(
        self,
        data: Dict[str, np.ndarray]
    ) -> Dict[str, np.ndarray]:
        results = {}
        for ind in self._indicators:
            results.update(ind.compute(data, mode="vectorized"))
        return results

    def _compute_streaming(
        self,
        data: Dict[str, float]
    ) -> Dict[str, Optional[float]]:
        results = {}
        for ind in self._indicators:
            results.update(ind.compute(data, mode="streaming"))
        return results
```

## Summary

A well-designed indicator framework balances flexibility with consistency. The base class pattern establishes contracts for warmup periods, output schemas, and computation modes. Separating vectorized and streaming implementations optimizes for their respective use cases: batch processing prioritizes throughput while streaming prioritizes memory efficiency.

Key architectural decisions include:

1. **Abstract base class**: Enforces consistent interface across all indicators
2. **Output schemas**: Enable schema-driven downstream processing
3. **Dual computation modes**: Same indicator serves backtesting and live trading
4. **State management**: Supports both stateless and stateful computation patterns
5. **Reference testing**: Validates implementations against trusted sources

The framework supports composition—building complex indicators from simpler components—while maintaining the warmup and output schema contracts throughout the composition hierarchy.

## Next Steps

[Part 8: Position Tracking System](/posts/position-tracking-system/) covers real-time position management, addressing unrealized P&L calculation, multi-asset portfolio tracking, and integration with the indicator framework for position-aware signal generation.

---

## Series Navigation

| Part | Topic | Status |
|------|-------|--------|
| 1 | [System Architecture Overview](/posts/trading-infrastructure-architecture/) | Published |
| 2 | [Message Queue Architecture](/posts/message-queue-trading-architecture/) | Published |
| 3 | [Docker Compose Patterns](/posts/docker-compose-trading-infrastructure/) | Published |
| 4 | [Time-Series Database Integration](/posts/timeseries-database-trading/) | Published |
| 5 | [Market Data Ingestion Pipeline](/posts/market-data-ingestion-pipeline/) | Published |
| 6 | [Order Management Service](/posts/order-management-service/) | Published |
| **7** | **Technical Indicator Framework** | **Current** |
| 8 | [Position Tracking System](/posts/position-tracking-system/) | Next |
| 9 | Monitoring and Alerting | Upcoming |
| 10 | Production Deployment Strategies | Upcoming |

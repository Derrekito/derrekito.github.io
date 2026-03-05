---
title: "Real-Time Telemetry (Part 1): Live Dashboards with Plotly Dash + MQTT"
date: 2026-10-02
categories: [IoT, Web Development]
tags: [dash, plotly, mqtt, real-time, python, websocket, telemetry]
series: real-time-telemetry
series_order: 1
---

Plotly Dash excels at building data visualization dashboards in pure Python. But its default update mechanism—polling callbacks on a timer—doesn't scale for real-time telemetry. This post shows how to integrate MQTT directly into Dash for true real-time updates, maintain running statistics without database queries, and build responsive multi-page dashboards.

## The Polling Problem

Dash's standard approach to live data uses the `Interval` component:

```python
dcc.Interval(id='interval', interval=1000)  # Fire every second

@app.callback(Output('chart', 'figure'), Input('interval', 'n_intervals'))
def update_chart(n):
    data = db.find().sort('time', -1).limit(100)
    return build_figure(data)
```

Every second, every connected browser queries the database. With 10 engineers watching the dashboard during a test, that's 10 identical queries per second. The database becomes the bottleneck, and latency grows as load increases.

The fix: subscribe to the same MQTT stream that feeds the database. Data arrives at the dashboard the moment it's published—no polling, no database queries for live data.

## Architecture

The dashboard maintains two data paths:

```
MQTT Broker ──┬──▶ Dashboard (live updates)
              │
              └──▶ MongoDB (historical queries)
```

Live data flows through MQTT. Historical queries go to MongoDB. The callback checks the MQTT queue first; only when building charts from historical data does it touch the database.

## MQTT Client Integration

Dash runs in a single process, but MQTT requires a persistent connection with its own event loop. The solution: run the MQTT client in a background thread, communicate via thread-safe queues.

```python
import queue
import threading
import paho.mqtt.client as mqtt

# Thread-safe queues for different data streams
sensor_queue = queue.Queue()
event_queue = queue.Queue()

def on_message(client, userdata, msg):
    """Route messages to appropriate queues based on topic"""
    payload = json.loads(msg.payload.decode())

    if msg.topic.startswith("telemetry/sensors/"):
        sensor_queue.put(payload)
    elif msg.topic.startswith("telemetry/events/"):
        event_queue.put(payload)

def start_mqtt_client():
    """Start MQTT client in background thread"""
    client = mqtt.Client()
    client.on_message = on_message

    # Retry connection with backoff
    for attempt in range(10):
        try:
            client.connect("mqtt", 1883, 60)
            break
        except Exception as e:
            time.sleep(3)
    else:
        raise RuntimeError("Failed to connect to MQTT")

    # Subscribe to all telemetry topics
    client.subscribe("telemetry/#")

    # Run event loop in background
    thread = threading.Thread(target=client.loop_forever)
    thread.daemon = True
    thread.start()
```

Call `start_mqtt_client()` during app initialization, before the first request. The daemon thread ensures cleanup on shutdown.

## Queue-Based Callbacks

Callbacks drain the queue on each interval tick. If no new messages arrived, return `no_update` to prevent unnecessary re-renders:

```python
from dash import no_update

@app.callback(
    Output("live-voltage", "children"),
    Output("live-current", "children"),
    Input("interval-component", "n_intervals"),
)
def update_live_values(_):
    try:
        data = sensor_queue.get_nowait()
    except queue.Empty:
        return no_update, no_update

    voltage = data.get("voltage")
    current = data.get("current")

    return f"{voltage} V", f"{current} A"
```

Key patterns:

1. **`get_nowait()`**: Non-blocking queue read. Returns immediately if empty.
2. **`no_update`**: Tells Dash to skip updating these outputs. Prevents flicker and saves bandwidth.
3. **Tuple return**: Multiple outputs update atomically.

For charts that need multiple data points, drain the entire queue:

```python
@app.callback(
    Output('live-chart', 'figure'),
    Input('interval', 'n_intervals')
)
def update_chart(_):
    messages = []
    while True:
        try:
            messages.append(event_queue.get_nowait())
        except queue.Empty:
            break

    if not messages:
        return no_update

    # Append to existing chart data
    return build_incremental_figure(messages)
```

## Per-Run Message Filtering

Test systems organize data by "runs"—sequential test executions. The dashboard needs to filter messages by the currently selected run.

Use `defaultdict` to maintain per-run queues:

```python
from collections import defaultdict

run_filtered_queues = defaultdict(queue.Queue)

def route_message(topic, payload_str):
    """Route messages to per-run queues"""
    payload = json.loads(payload_str)
    run_number = payload.get('run_number')

    message_data = {
        'topic': topic,
        'payload': payload,
        'timestamp': time.time(),
        'run_number': run_number
    }

    # Add to general queue
    event_queue.put(message_data)

    # Add to run-specific queue
    if run_number:
        run_filtered_queues[run_number].put(message_data)
```

When the user selects a run in the UI, callbacks read from the appropriate queue:

```python
def get_run_queue(run_number):
    """Get message queue for specific run"""
    return run_filtered_queues[run_number]

def clear_run_queue(run_number):
    """Clear queue when switching runs"""
    while not run_filtered_queues[run_number].empty():
        try:
            run_filtered_queues[run_number].get_nowait()
        except queue.Empty:
            break
```

## In-Memory Statistics Tracking

Aggregating statistics from the database on every callback is expensive. Instead, maintain running statistics in memory, updated by each MQTT message.

```python
class RunStatistics:
    """Thread-safe statistics for a single test run"""

    def __init__(self, run_number):
        self.run_number = run_number
        self.start_time = time.time()
        self.lock = threading.Lock()

        # Counters
        self.error_count = 0
        self.message_count = 0
        self.total_value = 0

        # Performance tracking
        self._timestamps = deque(maxlen=100)

    def update(self, message):
        """Update statistics from new message"""
        with self.lock:
            self.message_count += 1
            self._timestamps.append(time.time())

            payload = message.get('payload', {})
            if payload.get('error'):
                self.error_count += 1
            if 'value' in payload:
                self.total_value += payload['value']

    @property
    def messages_per_second(self):
        """Calculate current message rate"""
        with self.lock:
            if len(self._timestamps) < 2:
                return 0.0
            time_span = self._timestamps[-1] - self._timestamps[0]
            return len(self._timestamps) / time_span if time_span > 0 else 0.0

    @property
    def uptime(self):
        """Formatted uptime string"""
        seconds = int(time.time() - self.start_time)
        hours, remainder = divmod(seconds, 3600)
        minutes, seconds = divmod(remainder, 60)
        return f"{hours:02d}:{minutes:02d}:{seconds:02d}"
```

A global tracker manages statistics for all runs:

```python
class StatisticsTracker:
    """Manages statistics across all runs"""

    def __init__(self):
        self.runs = {}
        self.lock = threading.Lock()

    def get_or_create(self, run_number):
        with self.lock:
            if run_number not in self.runs:
                self.runs[run_number] = RunStatistics(run_number)
            return self.runs[run_number]

    def process_message(self, message):
        """Route message to appropriate run statistics"""
        run_number = message.get('run_number')
        if run_number:
            stats = self.get_or_create(run_number)
            stats.update(message)

# Global instance
stats_tracker = StatisticsTracker()
```

Update the MQTT message handler to feed the tracker:

```python
def route_message(topic, payload_str):
    payload = json.loads(payload_str)
    message_data = {
        'topic': topic,
        'payload': payload,
        'timestamp': time.time(),
        'run_number': payload.get('run_number')
    }

    event_queue.put(message_data)
    stats_tracker.process_message(message_data)  # Update statistics
```

Callbacks read statistics directly—no database queries:

```python
@app.callback(
    Output("error-count", "children"),
    Output("message-rate", "children"),
    Input("interval", "n_intervals"),
    Input("run-dropdown", "value")
)
def update_stats(_, run_number):
    stats = stats_tracker.get_or_create(run_number)
    return (
        str(stats.error_count),
        f"{stats.messages_per_second:.1f}/s"
    )
```

## Multi-Page Layout

Dash supports multi-page apps through URL routing. Define page layouts as functions:

```python
def make_sensor_page():
    """Sensor monitoring page"""
    return html.Div([
        html.H2("Sensor Telemetry"),
        html.Div([
            html.Div(id="live-voltage", className="metric-card"),
            html.Div(id="live-current", className="metric-card"),
        ], className="metric-row"),
        dcc.Graph(id="voltage-plot")
    ])

def make_event_page():
    """Event monitoring page"""
    return html.Div([
        html.H2("Event Monitor"),
        html.Div(id="event-stats"),
        html.Div(id="event-log")
    ])
```

The main layout includes navigation and a content container:

```python
app.layout = html.Div([
    # Navigation
    html.Div([
        dcc.Link("Sensors", href="/sensors"),
        dcc.Link("Events", href="/events"),
    ], className="nav-bar"),

    # URL tracker
    dcc.Location(id='url', refresh=False),

    # Page content
    html.Div(id='page-content'),

    # Global interval for all pages
    dcc.Interval(id="interval-component", interval=1000)
])
```

A routing callback switches pages:

```python
@app.callback(
    Output('page-content', 'children'),
    Input('url', 'pathname')
)
def display_page(pathname):
    if pathname == '/events':
        return make_event_page()
    else:
        return make_sensor_page()
```

## Conditional Callback Updates

Page-specific callbacks should only run when their page is active. Use `PreventUpdate` to skip irrelevant callbacks:

```python
from dash.exceptions import PreventUpdate

@app.callback(
    Output("voltage-plot", "figure"),
    Input("interval-component", "n_intervals"),
    Input('url', 'pathname')
)
def update_voltage_plot(_, pathname):
    if pathname != '/sensors':
        raise PreventUpdate

    # Only runs when on sensors page
    return build_voltage_figure()
```

This prevents unnecessary database queries and chart rendering when the user is on a different page.

## Dark Theme Styling

A dark theme reduces eye strain during long monitoring sessions. Define a color palette:

```python
DARK_THEME = {
    'bg_primary': '#0d1117',
    'bg_secondary': '#161b22',
    'bg_tertiary': '#21262d',
    'text_primary': '#f0f6fc',
    'text_secondary': '#8b949e',
    'accent': '#58a6ff',
    'border': '#30363d',
    'success': '#3fb950',
    'warning': '#d29922',
    'danger': '#f85149'
}
```

Apply to layout components:

```python
html.Div(
    style={
        "backgroundColor": DARK_THEME['bg_primary'],
        "color": DARK_THEME['text_primary'],
    },
    children=[...]
)
```

Configure Plotly charts to match:

```python
fig.update_layout(
    plot_bgcolor=DARK_THEME['bg_primary'],
    paper_bgcolor=DARK_THEME['bg_primary'],
    font=dict(color=DARK_THEME['text_primary']),
    xaxis=dict(gridcolor=DARK_THEME['border']),
    yaxis=dict(gridcolor=DARK_THEME['border']),
)
```

For complete theming including Dash's debug tools, inject custom CSS via `app.index_string`:

{% raw %}
```python
app.index_string = '''
<!DOCTYPE html>
<html>
<head>
    {%metas%}
    <title>{%title%}</title>
    {%css%}
    <style>
        body {
            background-color: #0d1117 !important;
            margin: 0;
        }

        /* Theme Plotly modebar */
        .modebar {
            background: rgba(22, 27, 34, 0.9) !important;
        }
        .modebar-btn {
            color: #8b949e !important;
        }
        .modebar-btn:hover {
            color: #f0f6fc !important;
        }
    </style>
</head>
<body>
    {%app_entry%}
    <footer>
        {%config%}
        {%scripts%}
        {%renderer%}
    </footer>
</body>
</html>
'''
```
{% endraw %}

## Hybrid Data Strategy

Live data comes from MQTT; historical analysis requires MongoDB. Implement a hybrid callback that uses the appropriate source:

```python
@app.callback(
    Output("stats-panel", "children"),
    Input("interval", "n_intervals"),
    Input("run-dropdown", "value")
)
def update_stats_panel(_, selected_run):
    # Try real-time statistics first
    real_time_stats = stats_tracker.get_run_stats(selected_run)

    if real_time_stats and real_time_stats.message_count > 0:
        # Use in-memory statistics for active runs
        return build_realtime_stats_panel(real_time_stats)

    # Fall back to MongoDB for historical runs
    cached_data = get_cached_run_data(selected_run)
    if cached_data:
        return build_historical_stats_panel(cached_data)

    return build_empty_stats_panel()
```

Cache MongoDB queries to avoid repeated hits:

```python
run_data_cache = {}
cache_timestamps = {}
CACHE_DURATION = 30  # seconds

def get_cached_run_data(run_number):
    """Get run data from cache or MongoDB"""
    cache_key = str(run_number)
    current_time = time.time()

    # Check cache validity
    if (cache_key in run_data_cache and
        current_time - cache_timestamps.get(cache_key, 0) < CACHE_DURATION):
        return run_data_cache[cache_key]

    # Query MongoDB
    run_data = query_run_from_mongodb(run_number)

    # Update cache
    run_data_cache[cache_key] = run_data
    cache_timestamps[cache_key] = current_time

    return run_data
```

## Connection Status Monitoring

Display MQTT and database connection status in the UI:

```python
def get_mqtt_status():
    """Check MQTT connection"""
    global mqtt_client
    if mqtt_client and mqtt_client.is_connected():
        return "✓ Connected"
    return "✗ Disconnected"

def get_mongo_status(client):
    """Check MongoDB connection"""
    try:
        client.admin.command('ping')
        return "✓ Connected"
    except Exception:
        return "✗ Disconnected"
```

Display in the header:

```python
html.Div([
    html.Span("MQTT: "),
    html.Span(id="mqtt-status"),
    html.Span(" | MongoDB: "),
    html.Span(id="mongo-status"),
])

@app.callback(
    Output("mqtt-status", "children"),
    Output("mongo-status", "children"),
    Input("interval", "n_intervals")
)
def update_status(_):
    return get_mqtt_status(), get_mongo_status(mongo_client)
```

## Performance Considerations

**Queue Size Limits**: Unbounded queues can consume memory if the dashboard falls behind. Use `maxlen` on deques or implement queue trimming.

**Callback Frequency**: 1-second intervals balance responsiveness and load. Faster intervals increase browser load; slower intervals add perceived latency.

**Chart Updates**: Use `uirevision` to preserve zoom/pan state across updates:

```python
fig.update_layout(uirevision="static")
```

**Batch Processing**: When processing many messages per callback, batch database writes and chart updates rather than handling each message individually.

## Complete Example

Here's a minimal but complete dashboard combining all patterns:

```python
from dash import Dash, html, dcc, Output, Input, no_update
import queue
import threading
import paho.mqtt.client as mqtt

# Queues
data_queue = queue.Queue()

# MQTT setup
def on_message(client, userdata, msg):
    data_queue.put(json.loads(msg.payload.decode()))

def start_mqtt():
    client = mqtt.Client()
    client.on_message = on_message
    client.connect("mqtt", 1883)
    client.subscribe("telemetry/#")
    threading.Thread(target=client.loop_forever, daemon=True).start()

# Dash app
app = Dash(__name__)
app.layout = html.Div([
    html.H1("Live Telemetry"),
    html.Div(id="live-value"),
    dcc.Interval(id="interval", interval=1000)
])

@app.callback(
    Output("live-value", "children"),
    Input("interval", "n_intervals")
)
def update(n):
    try:
        data = data_queue.get_nowait()
        return f"Value: {data.get('value', 'N/A')}"
    except queue.Empty:
        return no_update

if __name__ == "__main__":
    start_mqtt()
    app.run(debug=True, host="0.0.0.0", port=8050)
```

## What's Next

This post covered Dash + MQTT integration. The next post dives into the ingestion layer: routing MQTT messages to MongoDB collections, handling malformed data, and building resilient message processing pipelines.

---

*This post is Part 1 of the Real-Time Telemetry series. Previous: [Architecture Overview](/posts/real-time-telemetry-dashboard-architecture). Next: [MQTT-to-MongoDB Ingestion Pipelines](/posts/mqtt-mongodb-ingestion-pipelines)*

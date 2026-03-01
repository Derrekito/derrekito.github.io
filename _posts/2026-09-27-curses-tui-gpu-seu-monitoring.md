---
title: "SEU-TUI: A Curses-Based Terminal Interface for GPU Single Event Upset Monitoring"
date: 2026-09-27 12:00:00 -0700
categories: [Reliability, GPU Computing]
tags: [python, curses, tui, nvidia, ecc, seu, radiation-effects, reliability-testing]
---

Single Event Upsets (SEUs) pose significant reliability challenges for GPU-based computing systems operating in high-radiation environments. This post describes the design and implementation of SEU-TUI, a terminal-based monitoring application that provides real-time visualization of GPU error correction data during cache march testing experiments.

## Problem Statement

Graphics Processing Units (GPUs) contain billions of transistors in their memory hierarchies and computational units. When deployed in environments with elevated radiation levels—such as high-altitude aircraft, spacecraft, or particle accelerator facilities—these transistors become susceptible to Single Event Effects (SEEs). A charged particle passing through a transistor junction can deposit sufficient charge to flip a stored bit, resulting in a Single Event Upset.

Modern NVIDIA GPUs incorporate Error Correction Code (ECC) memory and SRAM protection mechanisms that detect and, in many cases, correct these bit flips. However, monitoring these corrections during testing requires:

1. Real-time access to ECC counter data from `nvidia-smi`
2. Correlation with application-level error detection from cache march tests
3. Per-Streaming Multiprocessor (SM) breakdown of detected upsets
4. Historical tracking of volatile versus aggregate error counts

Existing tools provide either raw command-line output or web-based dashboards unsuitable for headless systems in shielded test facilities. A lightweight terminal interface addresses this gap by providing comprehensive monitoring without external dependencies.

## Technical Background

### Single Event Upsets

A Single Event Upset occurs when ionizing radiation deposits charge in a semiconductor device, causing a bit flip in memory or a logic transient in combinational circuits. SEUs are classified as:

- **Single Event Upset (SEU)**: A persistent bit flip in a memory element (latch, SRAM cell, register)
- **Single Event Transient (SET)**: A temporary voltage glitch in combinational logic that may propagate to storage elements

GPU architectures are particularly susceptible due to their high transistor density and large cache hierarchies. Modern GPUs contain:

- L1 caches per SM (typically 128KB)
- Shared L2 cache (several MB)
- Register files per SM
- Texture and constant caches

### Cache March Testing

Cache march tests are algorithmic sequences designed to detect memory faults. A march element consists of a sequence of read and write operations applied to each address in memory. The basic march test pattern involves:

```
{⇑(w0); ⇑(r0,w1); ⇑(r1,w0); ⇓(r0,w1); ⇓(r1,w0); ⇑(r0)}
```

Where `⇑` indicates ascending address order, `⇓` descending order, and the operations read (`r`) or write (`w`) values `0` or `1`.

When applied to GPU memory during radiation exposure, march tests detect upsets by comparing read values against expected patterns. The test application tracks:

- Total test iterations (loop counter)
- Tests containing errors
- Total SEU count across all SMs
- Total SET count across all SMs
- Per-SM upset breakdown

### ECC Error Counters

NVIDIA GPUs expose ECC statistics through the `nvidia-smi` utility. The relevant counters include:

| Counter Type | Description |
|-------------|-------------|
| SRAM Correctable | Single-bit errors corrected by ECC |
| SRAM Uncorrectable Parity | Multi-bit errors detected by parity |
| SRAM Uncorrectable SEC-DED | Double-bit errors detected by SEC-DED codes |
| DRAM Correctable | HBM/GDDR single-bit corrections |
| DRAM Uncorrectable | HBM/GDDR multi-bit errors |

Counters are reported in two categories:

- **Volatile**: Errors since last driver reload
- **Aggregate**: Lifetime error count (persistent across reboots on some GPUs)

## Architecture Overview

SEU-TUI employs a modular architecture separating data acquisition, parsing, and presentation concerns.

```
┌─────────────────────────────────────────────────────────────┐
│                        SEU-TUI                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    │
│   │ parseable.py│    │   data.py   │    │   ui.py     │    │
│   │             │    │             │    │             │    │
│   │ nvidia-smi  │───▶│ Queue-based │───▶│ Curses      │    │
│   │ XML Parser  │    │ Data Flow   │    │ Renderer    │    │
│   └─────────────┘    └─────────────┘    └─────────────┘    │
│          │                  ▲                  │            │
│          │                  │                  │            │
│          ▼                  │                  ▼            │
│   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    │
│   │ nvidia-smi  │    │ YAML Tailer │    │   input_    │    │
│   │ subprocess  │    │ (SEU data)  │    │  handler.py │    │
│   └─────────────┘    └─────────────┘    └─────────────┘    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

**parseable.py**: Executes `nvidia-smi -q` and parses the hierarchical output into a structured dictionary. The parser handles nvidia-smi's indentation-based format by maintaining a stack of parent dictionaries:

```python
def parse_output(lines):
    stack = [(-1, {})]
    for line in lines:
        indent = len(line) - len(line.lstrip(" "))
        text = line.strip()

        if ": " in text:
            # Key-value pair
            key, value = text.split(": ", 1)
            while len(stack) > 1 and indent <= stack[-1][0]:
                stack.pop()
            parent = stack[-1][1]
            parent[key] = value
        else:
            # Section heading
            while len(stack) > 1 and indent <= stack[-1][0]:
                stack.pop()
            parent = stack[-1][1]
            new_dict = {}
            parent[text] = new_dict
            stack.append((indent, new_dict))

    return stack[0][1]
```

**data.py**: Provides thread-safe data management through a `Queue` and `Event` mechanism. Data sources include:

- Standard input (for piped nvidia-smi output)
- YAML file tailing (for cache march test results)

The YAML tailer parses per-SM upset data from the test application's output format:

```python
def parse_values_line(line, columns):
    # Extract values from comma-separated line
    values = [v.strip() for v in line.split(",")]

    # Map to column definitions
    sm_data = {}
    for i in range(sm_count):
        sm_data[f'sm{i}'] = {
            'seu': parsed_values[columns.index(f'sm{i}_seu')],
            'set': parsed_values[columns.index(f'sm{i}_set')]
        }

    return {'sm_data': sm_data, 'tot_seu': total, ...}
```

**ui.py**: Implements the curses-based rendering engine with:

- Dynamic terminal size handling
- Color-coded error highlighting
- Box-drawing characters for visual organization
- Screenshot functionality for logging

**input_handler.py**: Manages keyboard input in a separate thread, handling:

- `q`: Application exit
- `h`: Help overlay toggle
- `s`: Screenshot capture

## TUI Display Layout

The interface presents GPU and SEU data in a dual-panel layout optimized for 80x24 terminal dimensions.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          CUDA Cache March Test                               │
├────────────────────────────────────┬─────────────────────────────────────────┤
│┌──────────────SEU Data─────────────┐│┌───────────GPU Info────────────────────┐│
││ Loop Counter: 1547                ││ │ Timestamp: 2026-09-27 14:32:01       ││
││ Tests With Errors: 3              ││ │ Memory: 24576 MiB / 40960 MiB        ││
││ Total SEU: 12     Total SET: 0    ││ │ Reset Required: No                   ││
│└───────────────────────────────────┘│└───────────────────────────────────────┘│
│┌───────────────SM Data─────────────┐│┌───────────ECC Errors──────────────────┐│
││ SM00: S:0 T:0   SM08: S:2 T:0     ││ │ Volatile          Aggregate          ││
││ SM01: S:0 T:0   SM09: S:0 T:0     ││ │ SRAM Corr: 45     SRAM Corr: 1203    ││
││ SM02: S:1 T:0   SM10: S:0 T:0     ││ │ SRAM Uncorr: 0    SRAM Uncorr: 0     ││
││ SM03: S:0 T:0   SM11: S:3 T:0     ││ │ DRAM Corr: 12     DRAM Corr: 892     ││
││ SM04: S:0 T:0   SM12: S:0 T:0     ││ │ DRAM Uncorr: 0    DRAM Uncorr: 0     ││
││ SM05: S:4 T:0   SM13: S:0 T:0     ││ │                                      ││
││ SM06: S:0 T:0   SM14: S:2 T:0     ││ │ SRAM Sources                         ││
││ SM07: S:0 T:0   SM15: S:0 T:0     ││ │ L2: 3  SM: 42  PCIE: 0  Other: 0     ││
│└───────────────────────────────────┘│└───────────────────────────────────────┘│
│┌──────────GPU Performance──────────┐│┌──────────Retired Pages────────────────┐│
││ PCI Replays: 0                    ││ │ Single Bit: 0                        ││
││ GPU Util: 98% | Mem Util: 45%     ││ │ Double Bit: 0                        ││
││ GPU Clock: 1410 MHz               ││ │ Pending: No                          ││
││ Power Draw: 250W / 300W           ││ │                                      ││
││ Temp: 72 C (Max: 83 C)            ││ │                                      ││
│└───────────────────────────────────┘│└───────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────────────────┘
                           Press 'h' for help | 'q' to quit | 's' to screenshot
```

### Panel Descriptions

**SEU Data Panel**: Displays aggregate statistics from the cache march test:
- Loop counter: Total test iterations completed
- Tests with errors: Number of iterations detecting at least one upset
- Total SEU/SET: Cumulative single-event upset and transient counts

**SM Data Panel**: Per-Streaming Multiprocessor breakdown showing SEU (`S:`) and SET (`T:`) counts. Non-zero values receive highlight coloring for rapid identification.

**GPU Info Panel**: System-level GPU status including memory utilization and reset status flags.

**ECC Errors Panel**: Volatile and aggregate error counts from nvidia-smi, with SRAM source breakdown (L2 cache, SM caches, PCIe, other).

**GPU Performance Panel**: Real-time performance metrics including utilization, clocks, power, and temperature.

**Retired Pages Panel**: Page retirement status indicating permanent hardware failures.

## Implementation Details

### Curses Initialization and Color Handling

The curses library requires explicit initialization and cleanup. The application uses `curses.wrapper()` to ensure proper terminal restoration:

```python
def curses_main(smi_file, seu_file, cols, exit_event):
    def main(stdscr):
        curses.use_default_colors()
        curses.curs_set(0)  # Hide cursor

        # Initialize color pairs
        curses.start_color()
        curses.init_pair(1, curses.COLOR_BLUE, -1)    # Headers
        curses.init_pair(2, curses.COLOR_GREEN, -1)   # Highlights
        curses.init_pair(3, curses.COLOR_YELLOW, -1)  # Warnings
        curses.init_pair(4, curses.COLOR_RED, -1)     # Errors
        curses.init_pair(5, curses.COLOR_CYAN, -1)    # Titles

        # Main render loop
        while not exit_event.is_set():
            draw_dashboard(stdscr, smi_data, seu_data, max_x, cols)
            time.sleep(0.05)

    curses.wrapper(main)
```

The `-1` background value preserves terminal transparency on supporting terminals.

### Safe String Rendering

Terminal boundaries require careful handling. The `safe_addstr()` function wraps curses operations with boundary checks and maintains a screen buffer for screenshots:

```python
def safe_addstr(stdscr, y, x, text, attr=0):
    try:
        max_y, max_x = stdscr.getmaxyx()
        if y >= 0 and y < max_y and x >= 0 and x < max_x:
            max_len = max_x - x
            display_text = text[:max_len] if len(text) > max_len else text
            stdscr.addstr(y, x, display_text, attr)

            # Update screen buffer for screenshots
            if len(screen_buffer) <= y:
                screen_buffer.extend([''] * (y - len(screen_buffer) + 1))
            screen_buffer[y] = screen_buffer[y][:x] + display_text

            return True
    except curses.error:
        pass
    return False
```

### Box Drawing with Unicode Characters

Visual containers use Unicode box-drawing characters for improved aesthetics:

```python
def draw_box_around(stdscr, start_y, start_x, height, width, title=None, attr=0):
    # Top border with corners
    safe_addstr(stdscr, start_y, start_x,
                "┌" + "─" * (width - 2) + "┐", attr)

    # Title insertion
    if title:
        title_pos = start_x + (width - len(title) - 4) // 2
        safe_addstr(stdscr, start_y, title_pos,
                    "┤ " + title + " ├", attr | curses.A_BOLD)

    # Vertical borders
    for i in range(1, height - 1):
        safe_addstr(stdscr, start_y + i, start_x, "│", attr)
        safe_addstr(stdscr, start_y + i, start_x + width - 1, "│", attr)

    # Bottom border
    safe_addstr(stdscr, start_y + height - 1, start_x,
                "└" + "─" * (width - 2) + "┘", attr)
```

### Data Update Mechanism

The application uses a producer-consumer pattern with thread-safe queues. Data threads (stdin reader, YAML tailer) push updates to a shared queue:

```python
# Producer (data.py)
def stdin_reader(queue, exit_event):
    while not exit_event.is_set():
        line = sys.stdin.readline()
        data = json.loads(line)
        queue.put({'smi_data': data})
        data_event.set()

# Consumer (ui.py - render loop)
while not data_queue.empty():
    data = data_queue.get_nowait()
    if 'smi_data' in data:
        current_smi_data = data['smi_data']
    elif 'seu_data' in data:
        current_seu_data = data['seu_data']
```

The `data_event` signals the render loop to refresh, reducing CPU usage during idle periods.

### Signal Handling and Cleanup

Proper signal handling ensures terminal restoration even during abnormal termination:

```python
def signal_handler(signum, _frame):
    logger.info(f"Received signal {signum}, shutting down")
    exit_event.set()
    cleanup()
    time.sleep(0.5)
    sys.exit(0)

signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGPIPE, signal.SIG_IGN)
```

The cleanup function restores terminal settings:

```python
def cleanup():
    sys.stdout.flush()
    sys.stderr.flush()
    if os.isatty(sys.stdin.fileno()):
        os.system('stty sane')
```

## Usage

The application supports two data input modes:

**Piped nvidia-smi output** (continuous monitoring):

```bash
./parseable.py | python3 -m src.main \
    --smi-file /dev/stdin \
    --seu-file /path/to/test_results.yml
```

**Tailed log files** (post-processing recorded data):

```bash
tail -f ecc_log.json | python3 -m src.main \
    --smi-file /dev/stdin \
    --seu-file seu_results.yml \
    --cols 8
```

Command-line options:

| Option | Description | Default |
|--------|-------------|---------|
| `--smi-file` | Path to SMI JSON or `-` for stdin | `nvidia_data_latest.json` |
| `--seu-file` | Path to SEU YAML file | Required |
| `--cols` | Columns for SM data display | 10 |
| `--log-level` | Logging verbosity | INFO |

## Conclusion

SEU-TUI demonstrates the continued relevance of curses-based interfaces for specialized monitoring applications. The modular architecture separates concerns effectively, allowing independent development of data parsers, display components, and input handling.

Key design decisions include:

- Thread-safe queue-based data flow prevents race conditions
- Unicode box drawing provides visual organization without external dependencies
- Color highlighting enables rapid identification of anomalous values
- Screenshot functionality supports documentation and post-analysis

The application addresses a specific need in radiation effects testing: lightweight, real-time monitoring of GPU reliability metrics in environments where graphical interfaces are impractical. The patterns demonstrated—curses safe rendering, signal-safe cleanup, producer-consumer data flow—apply broadly to terminal monitoring applications.

Source code: [seu-tui](https://github.com/derrekito/seu-tui)

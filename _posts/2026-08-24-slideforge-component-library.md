---
title: "SlideForge (Part 1): Component Library: Reusable Manim Primitives"
date: 2026-08-24
categories: [Presentations, Python]
tags: [manim, python, visualization, components, animation]
series: slideforge
series_order: 1
---

Building complex Manim animations from scratch for each presentation leads to duplicated effort and inconsistent styling. SlideForge's component library provides 20 modules of reusable primitives—grids, data structures, flowcharts, timelines, and domain-specific visualizations—that compose into sophisticated animations with minimal code.

This post surveys the component library and demonstrates how these building blocks accelerate animation development.

## Library Architecture

Components live in `src/components/`, each module providing related mobject classes:

```
src/components/
├── grids.py        # ColoredGrid, ThreadGrid, BitGrid, MemoryGrid
├── arrays.py       # Array, ArrayPointer, Matrix
├── containers.py   # ResourceContainer, SlotRow, UtilizationBar
├── stacks.py       # Stack, Queue, Deque
├── flows.py        # Pipe, DataPacket, ConveyorBelt, FunnelDiagram
├── tables.py       # DataTable with alignment control
├── timeline.py     # Timeline, WaveLane, PipelineStage
├── diagrams.py     # StackedHierarchy, SplitComparison, CycleDiagram
├── callouts.py     # Badge, Tooltip, KeyInsight, Callout
├── charts.py       # HBarChart, StackedBar, WaterfallChart
├── highlights.py   # HighlightBox, HeatStrip, ZoomInset
├── arrows.py       # DataFlow, BracketAnnotation, FlowArrow
├── nodes.py        # Graph, Tree, BinaryTree
├── networks.py     # NeuralNetwork, NeuralLayer
├── camera.py       # Beamer layout regions, zoom atomics
├── paths.py        # TracedPath, AnnotatedAxis
├── math_objects.py # LabeledNumberLine, EquationBox, SetDiagram
├── cuda.py         # Thread, Warp, ThreadBlock, Grid (domain-specific)
└── __init__.py     # Convenience re-exports
```

All components inherit from Manim's `VGroup` or `VMobject`, integrating seamlessly with standard animations.

## Grid Systems

Grids appear constantly in technical visualization—memory layouts, processor arrays, matrix operations, cellular automata. The `grids` module provides flexible grid primitives.

### ColoredGrid

A basic grid of colored cells with optional labels:

```python
from src.components.grids import ColoredGrid

grid = ColoredGrid(
    rows=4, cols=8,
    cell_size=0.5,
    colors=[RED, BLUE, GREEN, YELLOW],  # cycles through rows
    labels=["A", "B", "C", "D"],        # one per row
    show_indices=True,                   # column numbers
)
```

Cells are individually addressable for animation:

```python
# Highlight cell (2, 5)
self.play(grid.cells[2][5].animate.set_fill(WHITE, opacity=0.8))

# Animate row sweep
for col in range(8):
    self.play(
        grid.cells[1][col].animate.set_fill(YELLOW),
        run_time=0.1
    )
```

### MemoryGrid

Specialized for memory visualization with address labels and byte/word granularity:

```python
from src.components.grids import MemoryGrid

mem = MemoryGrid(
    rows=8, cols=4,
    cell_size=0.4,
    base_address=0x1000,
    word_size=4,  # 4 bytes per cell
    show_addresses=True,
)

# Highlight address range
mem.highlight_range(0x1000, 0x100F, color=BLUE)
```

### BitGrid

For bit-level visualization with configurable bit numbering:

```python
from src.components.grids import BitGrid

bits = BitGrid(
    width=32,
    bit_labels=True,      # show bit positions
    msb_first=True,       # bit 31 on left
    group_size=8,         # visual grouping
)

# Set specific bits
bits.set_bits([0, 1, 4, 7], color=GREEN)
bits.set_bits([8, 9, 10, 11], color=RED)
```

## Data Structures

Visualizing algorithms requires animatable data structure representations.

### Array and ArrayPointer

```python
from src.components.arrays import Array, ArrayPointer

arr = Array(
    values=[3, 1, 4, 1, 5, 9, 2, 6],
    cell_width=0.6,
    show_indices=True,
)

# Create pointers
i_ptr = ArrayPointer(arr, index=0, label="i", color=BLUE)
j_ptr = ArrayPointer(arr, index=7, label="j", color=RED)

# Animate pointer movement
self.play(i_ptr.animate_to(3))
self.play(j_ptr.animate_to(4))

# Swap animation
self.play(arr.animate_swap(3, 4))
```

### Stack, Queue, Deque

LIFO, FIFO, and double-ended queue visualizations:

```python
from src.components.stacks import Stack, Queue

stack = Stack(
    max_size=6,
    cell_height=0.5,
    show_labels=True,
)

# Push with animation
self.play(stack.push("A"))
self.play(stack.push("B"))
self.play(stack.push("C"))

# Pop with animation
value, anim = stack.pop()
self.play(anim)
print(f"Popped: {value}")  # "C"
```

### Matrix

Two-dimensional array with row/column labels and cell access:

```python
from src.components.arrays import Matrix

mat = Matrix(
    values=[
        [1, 2, 3],
        [4, 5, 6],
        [7, 8, 9],
    ],
    row_labels=["A", "B", "C"],
    col_labels=["X", "Y", "Z"],
)

# Highlight diagonal
for i in range(3):
    self.play(mat.cells[i][i].animate.set_fill(YELLOW, opacity=0.5))
```

## Flow Visualization

Data flow, pipelines, and process diagrams require specialized components.

### Pipe and DataPacket

```python
from src.components.flows import Pipe, DataPacket

pipe = Pipe(
    start=LEFT * 3,
    end=RIGHT * 3,
    width=0.3,
    color=BLUE_D,
)

packet = DataPacket(
    label="MSG",
    color=GREEN,
    size=0.25,
)

# Animate packet through pipe
self.play(packet.traverse(pipe, run_time=2))
```

### ConveyorBelt

For production/consumption visualizations:

```python
from src.components.flows import ConveyorBelt

belt = ConveyorBelt(
    length=6,
    height=0.4,
    slots=8,
)

# Add items to belt
belt.add_item("A", slot=0)
belt.add_item("B", slot=1)

# Animate belt movement
self.play(belt.advance(steps=2))
```

### FunnelDiagram

For aggregation/filtering visualizations:

```python
from src.components.flows import FunnelDiagram

funnel = FunnelDiagram(
    stages=["Raw Data", "Filtered", "Processed", "Output"],
    widths=[4, 3, 2, 1],
    colors=[BLUE, GREEN, YELLOW, RED],
)
```

## Tables and Charts

### DataTable

Flexible table with alignment control:

```python
from src.components.tables import DataTable

table = DataTable(
    headers=["Name", "Value", "Status"],
    rows=[
        ["Alpha", "42", "OK"],
        ["Beta", "17", "WARN"],
        ["Gamma", "99", "OK"],
    ],
    col_alignments=["left", "right", "center"],
    header_color=BLUE,
    stripe_colors=[DARK_GRAY, DARKER_GRAY],
)
```

### HBarChart and StackedBar

```python
from src.components.charts import HBarChart, StackedBar

chart = HBarChart(
    labels=["A", "B", "C", "D"],
    values=[30, 45, 20, 55],
    max_width=5,
    bar_height=0.4,
    colors=[RED, GREEN, BLUE, YELLOW],
)

# Animate bar growth
self.play(chart.animate_grow())

# Update values with animation
self.play(chart.animate_update([40, 35, 50, 25]))
```

## Diagrams and Callouts

### StackedHierarchy

For organizational charts, class hierarchies, or layered architectures:

```python
from src.components.diagrams import StackedHierarchy

hierarchy = StackedHierarchy(
    levels=[
        ["Application"],
        ["Service A", "Service B", "Service C"],
        ["Database", "Cache", "Queue"],
    ],
    colors=[RED, GREEN, BLUE],
    spacing=0.8,
)
```

### CycleDiagram

For state machines, lifecycles, or circular processes:

```python
from src.components.diagrams import CycleDiagram

cycle = CycleDiagram(
    states=["Init", "Running", "Paused", "Stopped"],
    radius=1.5,
    arrow_color=WHITE,
)

# Highlight current state
self.play(cycle.highlight_state("Running"))
```

### Callout and KeyInsight

Annotation components for highlighting important information:

```python
from src.components.callouts import Callout, KeyInsight

callout = Callout(
    text="Important: This value must be positive",
    target=some_mobject,
    direction=UP,
    color=YELLOW,
)

insight = KeyInsight(
    title="Key Insight",
    body="The algorithm runs in O(n log n) time",
    icon="lightbulb",
)
```

## Graph Structures

### Tree and BinaryTree

```python
from src.components.nodes import Tree, BinaryTree

tree = BinaryTree(
    values=[10, 5, 15, 3, 7, 12, 20],
    node_radius=0.3,
    level_spacing=1.0,
)

# Highlight path to node
path = tree.path_to(7)
self.play(*[node.animate.set_fill(YELLOW) for node in path])
```

### Graph

General graph with flexible layout:

```python
from src.components.nodes import Graph

graph = Graph(
    vertices=["A", "B", "C", "D", "E"],
    edges=[("A", "B"), ("A", "C"), ("B", "D"), ("C", "D"), ("D", "E")],
    layout="spring",  # or "circular", "tree", "grid"
)

# Animate edge traversal
self.play(graph.highlight_edge("A", "B"))
self.play(graph.highlight_edge("B", "D"))
```

## Timeline Components

### Timeline and WaveLane

For timing diagrams, protocol sequences, and scheduling visualization:

```python
from src.components.timeline import Timeline, WaveLane

timeline = Timeline(
    duration=10,
    tick_interval=1,
    labels=["T0", "T1", "T2", "..."],
)

wave = WaveLane(
    name="CLK",
    pattern="HLHLHLHLHL",  # High/Low
    timeline=timeline,
)

# Add multiple lanes
data_wave = WaveLane(
    name="DATA",
    pattern="..XXXXXX..",
    timeline=timeline,
)
```

### PipelineStage

For processor pipeline or build pipeline visualization:

```python
from src.components.timeline import PipelineStage

stages = [
    PipelineStage("Fetch", duration=1, color=RED),
    PipelineStage("Decode", duration=1, color=GREEN),
    PipelineStage("Execute", duration=2, color=BLUE),
    PipelineStage("Writeback", duration=1, color=YELLOW),
]

# Animate instruction flow through pipeline
for stage in stages:
    self.play(stage.activate())
    self.wait(stage.duration * 0.5)
```

## Composition Patterns

Components compose naturally through Manim's grouping:

```python
from src.components.grids import MemoryGrid
from src.components.arrays import ArrayPointer
from src.components.callouts import Callout

# Build a memory access visualization
memory = MemoryGrid(rows=8, cols=4, base_address=0x1000)
pointer = ArrayPointer(memory, index=0, label="ptr")
callout = Callout("Cache miss!", target=memory.cells[0][0])

# Group for coordinated animation
viz = VGroup(memory, pointer, callout)
viz.scale(0.8).move_to(ORIGIN)

# Animate together
self.play(FadeIn(memory))
self.play(pointer.animate_to(5))
self.play(FadeIn(callout))
```

## Theme Integration

All components respect the active theme for colors and fonts:

```python
class MyScene(ThemedSlide):
    theme = CustomTheme()

    def construct(self):
        # Components automatically use theme colors
        grid = ColoredGrid(rows=4, cols=4)
        # grid uses theme.primary, theme.secondary, etc.
```

Override per-component when needed:

```python
grid = ColoredGrid(
    rows=4, cols=4,
    colors=[RED, BLUE],  # explicit override
)
```

## Performance Considerations

Components are designed for animation performance:

1. **Lazy rendering**: Complex components defer mobject creation until first access
2. **Efficient updates**: Cell color changes don't recreate entire grids
3. **Batched animations**: Methods like `animate_grow()` return animation groups

For very large grids (100×100+), consider:

```python
# Use simplified rendering for large grids
grid = MemoryGrid(
    rows=100, cols=100,
    simplified=True,  # No per-cell labels
    batch_size=1000,  # Render in batches
)
```

## Summary

The SlideForge component library transforms animation development from pixel-pushing to composition. Instead of calculating coordinates and managing mobject lifecycles, you declare intent:

```python
# Before: 50 lines of mobject creation
# After:
memory = MemoryGrid(rows=8, cols=4, base_address=0x1000)
pointer = ArrayPointer(memory, index=0, label="ptr")
self.play(pointer.animate_to(5))
```

The next post covers SlideForge's build system—how the Makefile orchestrates multi-resolution rendering, parallel compilation, and incremental builds.

---
title: "SlideForge (Part 4): Mixin Composition: Isolating Animation Logic"
date: 2026-08-27
categories: [Presentations, Python]
tags: [python, manim, design-patterns, mixins, composition]
series: slideforge
series_order: 4
---

A 200-slide presentation with five major animation sequences could be implemented as a single monolithic scene class. But this approach creates problems: render times scale with total content, a bug in one animation blocks the entire build, and parallel rendering becomes impossible. SlideForge uses Python's multiple inheritance to compose animation logic from isolated mixins, each renderable independently.

This post examines the mixin composition pattern and how it enables incremental, parallel builds.

## The Monolithic Problem

A naive implementation puts everything in one class:

```python
class MyPresentation(ThemedSlide):
    def construct(self):
        # 50 static slides...
        self._show_static_slides()

        # Animation 1 (500 lines)
        # ... sorting algorithm visualization ...

        # More static slides...

        # Animation 2 (400 lines)
        # ... data flow diagram ...

        # Animation 3 (600 lines)
        # ... architecture walkthrough ...

        # etc.
```

Problems:

1. **Render time**: Every build re-evaluates all animations, even if only one changed
2. **Debugging**: A crash in Animation 3 prevents rendering Animations 1 and 2
3. **Parallelism**: Cannot render animations concurrently
4. **Testing**: Cannot test one animation in isolation

## The Mixin Pattern

SlideForge separates each animation into a mixin class:

```python
# src/deck/_anim_sorting.py
class SortingAnimationMixin:
    """Mixin providing sorting algorithm visualization."""

    def _run_sorting_animation(self):
        """Animate sorting algorithm execution."""
        arr = Array(values=[3, 1, 4, 1, 5, 9, 2, 6])
        self.play(FadeIn(arr))

        # ... 200 lines of sorting visualization ...

        self.play(FadeOut(arr))


# src/deck/_anim_dataflow.py
class DataFlowAnimationMixin:
    """Mixin providing data flow visualization."""

    def _run_dataflow_animation(self):
        """Animate data flowing through pipeline."""
        pipe = Pipe(start=LEFT * 4, end=RIGHT * 4)
        # ... 150 lines of flow visualization ...
```

The master deck composes mixins via multiple inheritance:

```python
# src/deck/_master.py
from src.deck._anim_sorting import SortingAnimationMixin
from src.deck._anim_dataflow import DataFlowAnimationMixin
from src.deck._anim_architecture import ArchitectureAnimationMixin

class MyPresentation(
    ThemedSlide,
    SortingAnimationMixin,
    DataFlowAnimationMixin,
    ArchitectureAnimationMixin,
):
    def construct(self):
        # Static slides...

        # Call mixin method
        self._run_sorting_animation()

        # More static slides...

        self._run_dataflow_animation()

        # etc.
```

## Standalone Rendering

Each mixin also has a standalone scene for independent rendering:

```python
# src/deck/_anim_sorting.py

class SortingAnimationMixin:
    def _run_sorting_animation(self):
        # ... animation code ...
        pass


class SortingStandalone(ThemedSlide, SortingAnimationMixin):
    """Standalone scene for rendering sorting animation only."""

    def construct(self):
        # Minimal setup
        self._install_chrome_overlays(chrome_page=15)

        # Run the animation
        self._run_sorting_animation()
```

The standalone scene:
1. Sets up chrome overlays for visual consistency
2. Calls the mixin's animation method
3. Nothing else—minimal overhead

### Makefile Targets

```make
.PHONY: render-sorting
render-sorting:
	$(DOCKER_RUN) manim $(MANIM_QUALITY) \
		src/deck/_anim_sorting.py SortingStandalone

.PHONY: render-dataflow
render-dataflow:
	$(DOCKER_RUN) manim $(MANIM_QUALITY) \
		src/deck/_anim_dataflow.py DataFlowStandalone

.PHONY: render-all-standalone
render-all-standalone:
	$(MAKE) -j4 render-sorting render-dataflow render-architecture
```

## The Stitcher

After standalone renders complete, the stitcher assembles the full deck:

```python
# scripts/stitch_deck.py

MIXIN_MAP = {
    "_run_sorting_animation": {
        "scene": "SortingStandalone",
        "source": "src/deck/_anim_sorting.py",
    },
    "_run_dataflow_animation": {
        "scene": "DataFlowStandalone",
        "source": "src/deck/_anim_dataflow.py",
    },
    # ...
}

def stitch(resolution):
    """Assemble full deck JSON from standalone renders."""
    manifest = load_manifest()

    # Load static pages JSON
    static_data = load_scene_json("StaticPagesOnly")

    # Load each mixin's JSON
    mixin_slides = {}
    for method, info in MIXIN_MAP.items():
        mixin_slides[method] = load_scene_json(info["scene"])

    # Assemble in manifest order
    all_slides = []
    static_idx = 0

    for slide_def in manifest["slides"]:
        if slide_def["type"] == "static":
            all_slides.append(static_data["slides"][static_idx])
            static_idx += 1

        elif slide_def["type"] == "animation":
            method = slide_def["mixin_method"]
            all_slides.extend(mixin_slides[method]["slides"])

    # Write assembled JSON
    output = {
        "slides": all_slides,
        "resolution": resolution,
    }
    write_json("slides/MyPresentation.json", output)
```

The stitcher reads the manifest to determine slide ordering, then concatenates the appropriate JSON segments.

## Manifest Structure

The manifest declares where each animation appears:

```yaml
# slides/manifest.yaml
pdf_base: assets/pages/presentation

slides:
  - type: static
    page: 1

  - type: static
    page: 2

  - type: builder
    pages: [3, 4, 5]
    camera: content

  - type: animation
    mixin_method: _run_sorting_animation
    chrome_page: 6

  - type: static
    page: 7

  - type: animation
    mixin_method: _run_dataflow_animation
    chrome_page: 12

  # ... 200+ slides
```

The `mixin_method` field maps to entries in `MIXIN_MAP`, linking manifest declarations to Python code.

## Static Pages Scene

Static slides also render independently:

```python
# src/deck/_static_pages.py

class StaticPagesOnly(ThemedSlide):
    """Render only static and builder slides (no animations)."""

    def construct(self):
        manifest = self._load_manifest()

        for slide_def in manifest["slides"]:
            if slide_def["type"] == "static":
                self._show_static_page(slide_def["page"])

            elif slide_def["type"] == "builder":
                self._show_builder_group(slide_def)

            # Skip animation slides
```

This scene renders quickly because it skips all Manim animations—just page image transitions.

## Benefits of Mixin Composition

### Parallel Rendering

With N mixins, render time approaches `max(mixin_times)` instead of `sum(mixin_times)`:

```bash
# Sequential: 10 + 8 + 12 + 9 + 11 = 50 minutes
make render-sorting && make render-dataflow && ...

# Parallel: max(10, 8, 12, 9, 11) ≈ 12 minutes
make -j5 render-all-standalone
```

GPU memory limits concurrency—four simultaneous renders might require 40GB VRAM.

### Incremental Rebuilds

Change one animation, rebuild only that mixin:

```bash
# Edit src/deck/_anim_sorting.py

# Rebuild only sorting (2 minutes)
make render-sorting

# Re-stitch (10 seconds)
make stitch

# Convert (20 seconds)
make convert
```

Total: ~3 minutes instead of 50.

### Isolated Testing

Test a single animation without the full deck:

```bash
manim -pql src/deck/_anim_sorting.py SortingStandalone
```

The `-p` flag opens a preview window. Iterate rapidly on one animation.

### Team Development

Different team members can work on different animations without conflicts:

```
Alice: editing _anim_sorting.py
Bob:   editing _anim_dataflow.py
Carol: editing _anim_architecture.py
```

No merge conflicts (different files). Each renders independently.

## Mixin Design Guidelines

### State Isolation

Mixins should not depend on state from other mixins:

```python
# BAD: depends on state from another mixin
class DataFlowMixin:
    def _run_dataflow_animation(self):
        # Assumes _sorting_result exists from SortingMixin
        arr = self._sorting_result  # Fails in standalone render

# GOOD: self-contained
class DataFlowMixin:
    def _run_dataflow_animation(self):
        # Creates its own data
        arr = Array(values=[1, 2, 3, 4, 5])
```

### Chrome Consistency

Standalones must install chrome overlays matching the master deck:

```python
class SortingStandalone(ThemedSlide, SortingAnimationMixin):
    def construct(self):
        # chrome_page must match manifest's chrome_page for this animation
        self._install_chrome_overlays(chrome_page=6)
        self._run_sorting_animation()
```

Mismatched chrome pages cause visual discontinuity when stitched.

### Camera State Reset

Reset camera state at mixin boundaries:

```python
class SortingAnimationMixin:
    def _run_sorting_animation(self):
        # Start from known state
        self.camera.frame.set(width=self._base_fw).move_to(ORIGIN)

        # ... animation ...

        # Return to known state
        self.play(self._cam_full_frame())
```

This ensures the next slide (static or animated) inherits a predictable camera position.

### Naming Convention

Mixin methods follow `_run_<name>_animation` pattern:

```python
_run_sorting_animation
_run_dataflow_animation
_run_architecture_animation
```

This convention:
- Indicates the method is called by the deck (not a helper)
- Groups animations in autocomplete
- Makes manifest mappings predictable

## Play Range Tracking

The master deck tracks animation indices for each mixin:

```python
class MyPresentation(ThemedSlide, SortingMixin, DataFlowMixin):
    def construct(self):
        play_ranges = {}

        # Track range for sorting
        start = self.renderer.num_plays
        self._run_sorting_animation()
        play_ranges["_run_sorting_animation"] = [start, self.renderer.num_plays]

        # Track range for dataflow
        start = self.renderer.num_plays
        self._run_dataflow_animation()
        play_ranges["_run_dataflow_animation"] = [start, self.renderer.num_plays]

        # Write for cache invalidation
        with open("media/play_ranges.json", "w") as f:
            json.dump(play_ranges, f)
```

This mapping enables selective cache invalidation—delete only the cached files belonging to a specific mixin.

## Composition vs. Inheritance

Why mixins instead of a class hierarchy?

```python
# Inheritance approach (rejected)
class BaseAnimation(ThemedSlide):
    pass

class SortingAnimation(BaseAnimation):
    pass

class DataFlowAnimation(SortingAnimation):  # Forced ordering
    pass
```

Problems with inheritance:
- Forced linear ordering
- Child classes inherit all parent state
- Cannot render independently

Mixins provide:
- Arbitrary composition order
- No implicit state sharing
- Independent rendering via standalones

## Summary

The mixin composition pattern transforms a monolithic presentation into composable units:

1. **Mixins** contain animation logic with no external dependencies
2. **Standalones** enable independent rendering and testing
3. **Master deck** composes mixins via multiple inheritance
4. **Stitcher** assembles standalone renders in manifest order

This architecture enables parallel builds, incremental updates, and team collaboration—essential for maintaining complex animated presentations.

The final post in this series covers the web frontend: Vite integration, overlay injection, and portable deployment.

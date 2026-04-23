---
title: "SlideForge (Part 0): A Hybrid Manim + Beamer Presentation System"
date: 2026-08-24
categories: [Presentations, Python]
tags: [manim, beamer, latex, python, presentations, animation]
series: slideforge
series_order: 0
---

Technical presentations often face a fundamental tension: static slides convey information efficiently but lack the dynamic visualization that complex concepts demand, while fully animated presentations require prohibitive production time. SlideForge bridges this gap by combining rasterized LaTeX Beamer slides with targeted Manim animations, producing browser-playable presentations where static content dominates but key concepts come alive through programmatic animation.

This post introduces the architecture and rationale behind SlideForge, the first in a series covering its component library, build system, and caching infrastructure.

## The Problem with Pure Approaches

### Static Slides Alone

Beamer produces beautiful, consistent slides with minimal effort. Mathematical notation renders perfectly. Code listings maintain proper syntax highlighting. But explaining a sorting algorithm's execution, a neural network's forward pass, or a protocol's message flow requires either dense diagrams or audience imagination.

### Full Animation Alone

Manim (Mathematical Animation Engine) creates stunning visualizations. Grant Sanderson's 3Blue1Brown videos demonstrate the pedagogical power of well-crafted animation. But creating a 30-minute technical presentation entirely in Manim requires:

- Implementing every bullet point, table, and code listing as mobjects
- Managing scene transitions manually
- Rebuilding the entire presentation for any text change
- Accepting render times measured in hours

For a typical conference talk with 60 slides and 3-4 animated sequences, the effort-to-payoff ratio becomes untenable.

## The Hybrid Architecture

SlideForge treats Beamer and Manim as complementary tools:

```
┌─────────────────────────────────────────────────────────────┐
│                    SlideForge Pipeline                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐      ┌──────────────┐     ┌────────────┐ │
│  │  Beamer PDF  │─────▶│  Rasterize   │────▶│ Page PNGs  │ │
│  │  (60 pages)  │      │  (pdftoppm)  │     │ (1920px)   │ │
│  └──────────────┘      └──────────────┘     └─────┬──────┘ │
│                                                    │        │
│  ┌──────────────┐      ┌──────────────┐          │        │
│  │ Animation    │─────▶│    Manim     │─────┐    │        │
│  │ Mixins (5)   │      │   Render     │     │    │        │
│  └──────────────┘      └──────────────┘     │    │        │
│                                              ▼    ▼        │
│                                        ┌──────────────┐    │
│                                        │   Stitch     │    │
│                                        │   (JSON)     │    │
│                                        └──────┬───────┘    │
│                                               │            │
│                                               ▼            │
│                                        ┌──────────────┐    │
│                                        │  HTML5 +     │    │
│                                        │  Reveal.js   │    │
│                                        └──────────────┘    │
│                                                            │
└─────────────────────────────────────────────────────────────┘
```

### Static Slides: Rasterized Beamer

The Beamer PDF is rasterized to PNG images at presentation resolution (1920×1080 for 1080p output). Each page becomes a full-frame background image. This preserves:

- LaTeX typography and mathematical notation
- Consistent theming across all static content
- Incremental builds (`\pause`, `\only<>`, etc.)
- Code listings with syntax highlighting

Editing a bullet point means recompiling the Beamer PDF and re-rasterizing—a 30-second operation rather than a multi-hour Manim render.

### Animation Slides: Manim Sequences

Complex visualizations are implemented as Manim scenes that render to WebM video. These animations:

- Play full-frame within the presentation flow
- Use chrome overlays (header/footer strips) cropped from the Beamer PDF for visual continuity
- Support forward/backward navigation with pre-rendered reversal
- Cache at the individual animation level for incremental rebuilds

### The Manifest

A YAML manifest defines slide order and type:

```yaml
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
    mixin_method: _run_algorithm_visualization
    chrome_page: 6
  - type: static
    page: 7
  # ... 200+ slides
```

Three slide types:

| Type | Description |
|------|-------------|
| `static` | Display a single rasterized PDF page |
| `builder` | Progressive reveal sequence (Beamer overlay pages) |
| `animation` | Full-frame Manim animation with chrome overlay |

The `builder` type handles Beamer's incremental builds. Pages 3, 4, 5 might represent the same slide with progressively revealed bullet points. SlideForge displays them as a single logical slide with step-through navigation.

## ThemedSlide: The Base Class

All SlideForge scenes inherit from `ThemedSlide`, which extends manim-slides' `Slide` class with:

### Camera-Aware Scaling

Manim's coordinate system uses abstract "Manim Units" (approximately 1 MU = 1 unit on screen at default zoom). When the camera zooms to a quadrant, text sized for full-frame appears enormous. The `_s()` method returns the current scale factor:

```python
def _s(self):
    """Scale factor: current camera width / default width."""
    return self.camera.frame.width / self._base_fw

def _scaled_text(self, text, font_size=24, **kw):
    """Create text scaled to current camera zoom."""
    t = Text(text, font_size=font_size, **kw)
    t.scale(self._s())
    return t
```

Content created with `_scaled_text()` maintains consistent visual size regardless of camera position.

### Chrome Overlays

Animation slides need visual continuity with static slides. Chrome overlays are thin strips (typically 10% top, 12% bottom) cropped from the Beamer PDF and rendered on top of the animation:

```python
def _install_chrome_overlays(self, chrome_source_page):
    """Load top/bottom chrome strips with camera-tracking updaters."""
    top_strip = ImageMobject(f"chrome/{chrome_source_page:02d}_top.png")
    bot_strip = ImageMobject(f"chrome/{chrome_source_page:02d}_bottom.png")

    def top_updater(m):
        cam = self.camera.frame
        m.set(width=cam.width, height=cam.height * 0.10)
        m.move_to(cam.get_edge_center(UP) + DOWN * cam.height * 0.05)

    top_strip.add_updater(top_updater)
    # ... similar for bottom
```

The updaters track camera movement, ensuring chrome stays anchored to frame edges during zoom and pan operations.

### Camera Atomics

Pre-built camera movements target common Beamer layout regions:

```python
# Zoom to content area (exclude chrome)
self.play(self._cam_content())

# Zoom to left/right columns (two-column layouts)
self.play(self._cam_left_column())
self.play(self._cam_right_column())

# Zoom to quadrants
self.play(self._cam_quadrant("UL"))  # Upper-left
self.play(self._cam_quadrant("DR"))  # Down-right

# Pan without zoom change
self.play(self._cam_pan_left_to_right())
```

These atomics derive target rectangles from theme-defined chrome fractions and column splits, ensuring animations align with Beamer's layout grid.

## Patches and Fixes

SlideForge patches several Manim and manim-slides behaviors:

### WebM Video Reversal

manim-slides generates reversed video files for smooth backward navigation. The upstream implementation hardcodes `libx264`, which is incompatible with WebM containers. SlideForge patches the reversal function to detect container format and select the appropriate codec:

```python
def _reverse_video_file_in_one_chunk(src_and_dest):
    src, dest = src_and_dest
    is_webm = src.suffix.lower() == ".webm"
    codec = "libvpx-vp9" if is_webm else "libx264"
    # ... PyAV reversal with correct codec
```

### VP9 Alpha Channel

Manim sets `-auto-alt-ref=1` for VP9 encoding, which silently disables alpha channel support. For transparent animations composited over backgrounds, this produces solid black instead of transparency. The patch forces `-auto-alt-ref=0` when transparency is enabled:

```python
if config.transparent:
    pix_fmt = "yuva420p"
    av_opts["auto-alt-ref"] = "0"  # Required for alpha
```

### Pango Kerning Fix

Pango's integer pixel-grid snapping produces uneven inter-glyph gaps at small font sizes. "Kernel" might render as "K er nel". The fix renders text at minimum 48pt, then scales down:

```python
_MIN_PANGO_FONT = 48

def _hires_text_init(self, *args, **kwargs):
    font_size = kwargs.get("font_size", 48)
    if font_size < _MIN_PANGO_FONT:
        kwargs["font_size"] = _MIN_PANGO_FONT
        _orig_text_init(self, *args, **kwargs)
        self.scale(font_size / _MIN_PANGO_FONT)
    else:
        _orig_text_init(self, *args, **kwargs)
```

This gives Pango more sub-pixel precision for glyph placement at the cost of slightly increased render time.

## Output Formats

SlideForge produces browser-playable HTML5 presentations via manim-slides' Reveal.js integration:

```bash
# Draft quality (720p, fast iteration)
make draft

# Publication quality (1080p)
make publish

# Archival quality (4K)
make publish-4k
```

Each quality tier produces an independent presentation. The same source renders at different resolutions without conflicts—720p drafts for review, 1080p for delivery, 4K for archival.

The final output is a self-contained directory:

```
output/
├── presentation.html
├── slides/
│   ├── 001.webm
│   ├── 002.webm
│   └── ...
└── assets/
    └── reveal.js/
```

No server required. Open `presentation.html` in a browser and present.

## When to Use SlideForge

SlideForge excels when:

- **Most content is static**: The 80/20 rule applies—80% of slides need no animation
- **Key concepts benefit from animation**: Algorithm execution, data flow, architecture evolution
- **Beamer investment exists**: Existing LaTeX templates, bibliographies, and workflows
- **Iteration speed matters**: Edit text in LaTeX, not Python

SlideForge is overkill when:

- Every slide requires unique animation (use pure Manim)
- No animations needed (use pure Beamer)
- Presentation is a one-off with no reuse (use PowerPoint)

## Series Roadmap

This post introduced SlideForge's architecture and rationale. The series continues with:

1. **Component Library** — 20 reusable Manim modules for grids, data structures, flowcharts, and more
2. **Build System** — The 800-line Makefile with multi-resolution pipelines and parallel rendering
3. **Cache Invalidation** — SHA-256 source hashing and selective mixin invalidation
4. **Mixin Composition** — Isolating animation logic for independent rendering and stitching
5. **Web Frontend** — Vite integration, overlay injection, and portable deployment

The full SlideForge source is available at [github.com/derrekito/slideforge](https://github.com/derrekito/slideforge).

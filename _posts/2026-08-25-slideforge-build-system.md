---
title: "SlideForge (Part 2): Build System: Multi-Resolution Pipelines and Parallel Rendering"
date: 2026-08-25
categories: [Presentations, DevOps]
tags: [makefile, docker, manim, build-system, automation]
series: slideforge
series_order: 2
---

Rendering a 200-slide presentation with embedded Manim animations involves orchestrating PDF rasterization, video encoding at multiple resolutions, cache management, and HTML generation. SlideForge's build system—an 800-line Makefile—handles this complexity while supporting incremental builds, parallel rendering, and quality tier management.

This post examines the build system architecture, from Docker containerization to the multi-resolution pipeline.

## Build System Requirements

A presentation build system must handle several challenges:

1. **Reproducibility**: Same source → same output, regardless of host environment
2. **Incremental builds**: Re-render only what changed
3. **Parallel execution**: Leverage multiple CPU cores and GPU
4. **Quality tiers**: Draft (fast), publish (quality), archival (4K)
5. **Dependency tracking**: Rebuild when sources change

Make provides the foundation—its dependency graph and incremental rebuild logic solve problems 2 and 5. Docker handles problem 1. Careful target design addresses 3 and 4.

## Docker Containerization

Manim has notoriously complex dependencies: Cairo, Pango, FFmpeg, LaTeX, specific Python versions, and numerous fonts. SlideForge containerizes the render environment:

```dockerfile
FROM manimcommunity/manim:stable

# Additional dependencies
RUN apt-get update && apt-get install -y \
    poppler-utils \
    ffmpeg \
    fonts-firacode \
    && rm -rf /var/lib/apt/lists/*

# Install manim-slides for presentation output
RUN pip install manim-slides==5.5.4

# Custom fonts
COPY assets/fonts/ /usr/local/share/fonts/slideforge/
RUN fc-cache -fv
```

The Makefile invokes Docker with GPU passthrough and memory limits:

```make
DOCKER_IMAGE := manim-with-slides
DOCKER_RUN := docker run --rm \
    --gpus all \
    --memory=50g \
    -e PYTHONPATH=/manim \
    -v "$(PWD):/manim" \
    $(DOCKER_IMAGE)
```

The `--gpus all` flag enables CUDA acceleration for Manim's OpenGL renderer. The 50GB memory limit prevents runaway renders from exhausting host RAM.

## Quality Tiers

SlideForge supports three quality presets:

| Tier | Resolution | FPS | Use Case |
|------|------------|-----|----------|
| Draft | 720p | 30 | Fast iteration, review |
| Publish | 1080p | 60 | Conference delivery |
| 4K | 2160p | 60 | Archival, large venues |

Quality is controlled via Manim's `-q` flag:

```make
DRAFT_QUALITY   := -qm   # medium = 720p30
PUBLISH_QUALITY := -qh   # high = 1080p60
4K_QUALITY      := -qk   # 4k = 2160p60
```

Each tier produces an independent presentation:

```make
.PHONY: draft publish publish-4k

draft: MANIM_QUALITY=$(DRAFT_QUALITY)
draft: render-deck convert-deck

publish: MANIM_QUALITY=$(PUBLISH_QUALITY)
publish: render-deck convert-deck

publish-4k: MANIM_QUALITY=$(4K_QUALITY)
publish-4k: render-deck convert-deck
```

The three tiers coexist without conflicts—each writes to quality-specific directories (`media/videos/_master/720p30/`, etc.).

## Pipeline Stages

A full build executes these stages:

```
┌─────────────────────────────────────────────────────────────┐
│                    Build Pipeline                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. RASTERIZE                                                │
│     Beamer PDF → PNG pages (1920px width)                   │
│     └── pdftoppm with anti-aliasing                         │
│                                                              │
│  2. EXTRACT CHROME                                           │
│     PNG pages → top/bottom strips                           │
│     └── ImageMagick crop operations                         │
│                                                              │
│  3. RENDER ANIMATIONS                                        │
│     Python mixins → WebM video segments                     │
│     └── Manim + manim-slides in Docker                      │
│                                                              │
│  4. STITCH                                                   │
│     Static + animation JSONs → unified deck JSON            │
│     └── Python stitcher with cache validation               │
│                                                              │
│  5. CONVERT                                                  │
│     Deck JSON → HTML5 + Reveal.js                           │
│     └── manim-slides convert                                │
│                                                              │
│  6. PACKAGE (optional)                                       │
│     HTML + assets → portable tarball                        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Stage 1: Rasterize

```make
BEAMER_PDF  := $(HOME)/Projects/latex-slides/output/presentation.pdf
PAGES_DIR   := assets/pages
PAGES_WIDTH := 1920

.PHONY: rasterize
rasterize: $(BEAMER_PDF)
	@echo "Rasterizing PDF to $(PAGES_DIR)..."
	@mkdir -p $(PAGES_DIR)
	pdftoppm -png -r 150 -aa yes -aaVector yes \
		$(BEAMER_PDF) $(PAGES_DIR)/$(PAGES_PREFIX)
	@echo "Rasterized $$(ls $(PAGES_DIR)/*.png | wc -l) pages"
```

The `-aa yes -aaVector yes` flags enable anti-aliasing for smooth edges. Resolution (`-r 150`) is calibrated for 1920px output width.

### Stage 2: Extract Chrome

Chrome strips (header/footer) are cropped from each page for overlay during animations:

```make
.PHONY: extract-chrome
extract-chrome: rasterize
	@echo "Extracting chrome strips..."
	@mkdir -p $(PAGES_DIR)/chrome
	@for page in $(PAGES_DIR)/$(PAGES_PREFIX)-*.png; do \
		base=$$(basename $$page .png); \
		convert $$page -crop 100%x10%+0+0 \
			$(PAGES_DIR)/chrome/$${base}_top.png; \
		convert $$page -crop 100%x12%+0+88% \
			$(PAGES_DIR)/chrome/$${base}_bottom.png; \
	done
```

The percentages (10% top, 12% bottom) match the Beamer theme's header/footer heights.

### Stage 3: Render

The render stage is the most complex, supporting both full-deck and standalone mixin rendering.

#### Full Deck Render

```make
.PHONY: render-deck
render-deck: check-docker ensure-image
	$(DOCKER_RUN) manim $(MANIM_QUALITY) \
		--disable_caching \
		--write_to_movie \
		-o SEESoCDeck \
		src/deck/_master.py SEESoCDeck
```

#### Standalone Mixin Render

For incremental builds, each animation mixin renders independently:

```make
.PHONY: render-serial-march
render-serial-march:
	$(DOCKER_RUN) manim $(MANIM_QUALITY) \
		src/deck/_anim_serial_march.py SerialMarchStandalone

.PHONY: render-cuda-exec
render-cuda-exec:
	$(DOCKER_RUN) manim $(MANIM_QUALITY) \
		src/deck/_anim_cuda_exec.py CUDAExecStandalone

# ... additional mixin targets
```

#### Parallel Rendering

Standalone mixins render in parallel:

```make
.PHONY: render-all-standalone
render-all-standalone:
	$(MAKE) -j4 \
		render-serial-march \
		render-cuda-exec \
		render-memory-coalescing \
		render-h100-arch \
		render-cache-march
```

The `-j4` flag runs four renders concurrently. GPU memory limits how many can run simultaneously—adjust based on available VRAM.

### Stage 4: Stitch

The stitcher assembles standalone renders into a unified deck:

```make
.PHONY: stitch
stitch:
	python3 scripts/stitch_deck.py \
		--resolution $(RESOLUTION)
```

The Python script:
1. Loads the manifest for slide ordering
2. Validates all required renders exist
3. Checks content hashes against cache
4. Assembles the final JSON

See the next post for cache invalidation details.

### Stage 5: Convert

manim-slides converts the JSON deck to HTML:

```make
.PHONY: convert-deck
convert-deck:
	$(DOCKER_RUN) manim-slides convert \
		--to html \
		slides/SEESoCDeck.json \
		output/SEESoCDeck.html
```

### Stage 6: Package

For portable distribution:

```make
.PHONY: package
package: build
	@echo "Creating portable package..."
	tar -czvf slideforge-presentation.tar.gz \
		-C output \
		--dereference \
		.
```

The `--dereference` flag resolves symlinks, producing a self-contained archive.

## Draft Mode Optimizations

Draft rendering prioritizes speed over quality:

```make
DOCKER_RUN_DRAFT := docker run --rm \
    --gpus all \
    --memory=50g \
    -e PYTHONPATH=/manim \
    -e SLIDEFORGE_DRAFT=1 \
    -v "$(PWD):/manim" \
    $(DOCKER_IMAGE)
```

The `SLIDEFORGE_DRAFT=1` environment variable triggers several optimizations in `slide_base.py`:

```python
def setup(self):
    self._draft = os.environ.get("SLIDEFORGE_DRAFT") == "1"
    self.skip_reversing = self._draft  # No backward video generation

def play(self, *args, **kwargs):
    if self._draft and "run_time" not in kwargs:
        kwargs["run_time"] = 1 / config.frame_rate
    super().play(*args, **kwargs)
```

In draft mode:
- **Single-frame animations**: Every `play()` call renders exactly one frame (the final state)
- **Skip reversal**: No reversed video generation for backward navigation
- **Lower resolution**: 720p instead of 1080p

This reduces render time from 45+ minutes to under 10 minutes for a typical deck.

## Dependency Tracking

Make's dependency graph handles file-level dependencies:

```make
# PNG pages depend on the PDF
$(PAGES_DIR)/%.png: $(BEAMER_PDF)
	$(MAKE) rasterize

# Chrome strips depend on page PNGs
$(PAGES_DIR)/chrome/%_top.png: $(PAGES_DIR)/%.png
	$(MAKE) extract-chrome

# Deck JSON depends on manifest and all source files
slides/SEESoCDeck.json: slides/manifest.yaml \
                         src/deck/_master.py \
                         $(wildcard src/deck/_anim_*.py) \
                         $(wildcard src/components/*.py)
	$(MAKE) stitch
```

However, Manim's internal caching doesn't integrate with Make's timestamps. The next post covers SlideForge's hash-based cache invalidation that bridges this gap.

## Cross-Platform Support

The Makefile detects the host OS and package manager:

```make
OS := $(shell uname -s)
ifeq ($(OS),Linux)
    DISTRO := $(shell lsb_release -si 2>/dev/null || echo Unknown)
    ifeq ($(DISTRO),Ubuntu)
        PKG_MANAGER := apt
        NODE_INSTALL := sudo apt install -y nodejs npm
    else ifeq ($(DISTRO),Arch)
        PKG_MANAGER := pacman
        NODE_INSTALL := sudo pacman -S nodejs npm
    endif
else ifeq ($(OS),Darwin)
    PKG_MANAGER := brew
    NODE_INSTALL := brew install node
endif
```

Prerequisite checks use this detection:

```make
.PHONY: check-prereqs
check-prereqs:
	@command -v node >/dev/null 2>&1 || \
		{ echo "Node.js not found. Install with: $(NODE_INSTALL)"; exit 1; }
	@command -v docker >/dev/null 2>&1 || \
		{ echo "Docker not found."; exit 1; }
```

## Vite Development Server

For rapid iteration, a Vite dev server provides hot reloading:

```make
VITE_PORT := 5173

.PHONY: dev
dev: web_setup
	cd $(WEB_DIR) && npm run dev -- --host 0.0.0.0 --port $(VITE_PORT)

.PHONY: view
view: web_setup
	@echo "Starting Vite dev server on port $(VITE_PORT)..."
	@cd $(WEB_DIR) && nohup npm run dev -- \
		--host 0.0.0.0 --port $(VITE_PORT) \
		> /tmp/vite.log 2>&1 &
	@sleep 2
	@sudo ufw allow $(VITE_PORT)/tcp comment "SlideForge Vite"
	@echo "Server running at http://$$(hostname -I | awk '{print $$1}'):$(VITE_PORT)"

.PHONY: view-stop
view-stop:
	@pkill -f "vite.*$(VITE_PORT)" || true
	@sudo ufw delete allow $(VITE_PORT)/tcp 2>/dev/null || true
```

The `view` target runs Vite in the background and opens the firewall port for LAN access—useful for previewing on tablets or phones.

## Target Summary

The complete target list:

| Target | Description |
|--------|-------------|
| `make help` | Show all targets |
| `make build-docker` | Build Docker image |
| `make rasterize` | PDF → PNG pages |
| `make extract-chrome` | Extract header/footer strips |
| `make draft` | Full render at 720p |
| `make publish` | Full render at 1080p |
| `make publish-4k` | Full render at 4K |
| `make render-<mixin>` | Render single animation |
| `make render-all-standalone` | Parallel mixin render |
| `make stitch` | Assemble deck JSON |
| `make convert` | JSON → HTML |
| `make dev` | Vite dev server (foreground) |
| `make view` | Vite dev server (background) |
| `make package` | Create portable tarball |
| `make clean` | Remove build artifacts |

## Build Times

Typical build times on a workstation (Ryzen 9, RTX 4090, NVMe):

| Operation | Time |
|-----------|------|
| Rasterize (74 pages) | 15 seconds |
| Extract chrome | 8 seconds |
| Draft render (full) | 8-12 minutes |
| Publish render (full) | 45-60 minutes |
| 4K render (full) | 2+ hours |
| Incremental (1 stale mixin) | 5-10 minutes |
| Stitch + convert | 30 seconds |

The incremental build capability is crucial—editing one animation shouldn't require re-rendering the entire deck.

## Summary

SlideForge's build system transforms a complex multi-tool pipeline into simple Make targets. Docker ensures reproducibility, quality tiers support different use cases, and parallel rendering leverages available hardware.

The next post covers the cache invalidation system—how SlideForge tracks source changes and selectively invalidates stale renders without rebuilding everything.

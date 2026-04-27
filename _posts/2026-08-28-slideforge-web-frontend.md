---
title: "SlideForge (Part 5): Web Frontend: Vite, Overlays, and Portable Deployment"
date: 2026-08-28
categories: [Presentations, Web Development]
tags: [vite, javascript, reveal.js, deployment, web]
series: slideforge
series_order: 5
---

SlideForge presentations ultimately run in a browser. The web frontend provides deck discovery, navigation controls, dynamic overlays, and portable packaging. This post covers the Vite-based development server, overlay injection system, and deployment strategies.

## Frontend Architecture

The web layer comprises:

```
web/
├── index.html           # Deck selector page
├── viewer.html          # Presentation viewer
├── src/
│   ├── main.js          # Entry point
│   ├── navigation.js    # Keyboard/touch controls
│   ├── overlays.js      # Dynamic HTML injection
│   └── styles.css       # Viewer styling
├── vite.config.js       # Build configuration
├── package.json
└── node_modules/
```

The frontend serves two purposes:
1. **Development**: Hot-reloading preview during iteration
2. **Production**: Self-contained distribution package

## Vite Development Server

Vite provides fast HMR (Hot Module Replacement) during development:

```javascript
// vite.config.js
import { defineConfig } from 'vite';

export default defineConfig({
  root: '.',
  server: {
    host: '0.0.0.0',
    port: 5173,
    strictPort: true,
  },
  build: {
    outDir: 'dist',
    rollupOptions: {
      input: {
        main: 'index.html',
        viewer: 'viewer.html',
      },
    },
  },
});
```

### Dynamic Deck Discovery

The deck selector page lists available presentations:

```javascript
// Middleware in vite.config.js
configureServer(server) {
  server.middlewares.use('/__api/decks', (req, res) => {
    const slidesDir = path.join(__dirname, '..', 'slides');
    const decks = fs.readdirSync(slidesDir)
      .filter(f => f.endsWith('.json'))
      .map(f => ({
        name: f.replace('.json', ''),
        path: `/slides/${f}`,
      }));
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify(decks));
  });
}
```

The index page fetches this list dynamically:

```javascript
// main.js
async function loadDeckList() {
  const response = await fetch('/__api/decks');
  const decks = await response.json();

  const container = document.getElementById('deck-list');
  decks.forEach(deck => {
    const link = document.createElement('a');
    link.href = `viewer.html?deck=${encodeURIComponent(deck.path)}`;
    link.textContent = deck.name;
    container.appendChild(link);
  });
}
```

### Symlink Resolution

Development requires access to rendered assets outside the web directory. Vite's `publicDir` doesn't follow symlinks, so we create them manually:

```make
.PHONY: dev-setup
dev-setup:
	@mkdir -p $(WEB_DIR)/slides $(WEB_DIR)/output $(WEB_DIR)/assets
	@ln -sfn $(PWD)/slides $(WEB_DIR)/slides
	@ln -sfn $(PWD)/output $(WEB_DIR)/output
	@ln -sfn $(PWD)/assets $(WEB_DIR)/assets
```

For production builds, symlinks are resolved:

```make
.PHONY: build
build:
	@echo "Building production bundle..."
	cd $(WEB_DIR) && npm run build
	@echo "Resolving symlinks..."
	@for link in $(WEB_DIR)/dist/slides $(WEB_DIR)/dist/output; do \
		if [ -L "$$link" ]; then \
			target=$$(readlink -f "$$link"); \
			rm "$$link"; \
			cp -r "$$target" "$$link"; \
		fi; \
	done
```

## The Viewer Application

The viewer wraps Reveal.js with custom controls:

```html
<!-- viewer.html -->
<!DOCTYPE html>
<html>
<head>
  <link rel="stylesheet" href="/node_modules/reveal.js/dist/reveal.css">
  <link rel="stylesheet" href="/src/styles.css">
</head>
<body>
  <div id="viewer-container">
    <div class="reveal">
      <div class="slides" id="slides-container"></div>
    </div>
    <div id="controls">
      <button id="prev">←</button>
      <span id="progress">1 / 100</span>
      <button id="next">→</button>
    </div>
  </div>
  <script type="module" src="/src/main.js"></script>
</body>
</html>
```

### Loading the Deck

```javascript
// main.js
async function loadDeck() {
  const params = new URLSearchParams(window.location.search);
  const deckPath = params.get('deck');

  if (!deckPath) {
    window.location.href = 'index.html';
    return;
  }

  const response = await fetch(deckPath);
  const deck = await response.json();

  // Build slide elements
  const container = document.getElementById('slides-container');
  deck.slides.forEach((slide, index) => {
    const section = document.createElement('section');
    section.dataset.slideIndex = index;

    if (slide.type === 'video') {
      section.innerHTML = `
        <video data-autoplay loop muted>
          <source src="${slide.file}" type="video/webm">
        </video>
      `;
    } else if (slide.type === 'image') {
      section.innerHTML = `<img src="${slide.file}" alt="Slide ${index}">`;
    }

    container.appendChild(section);
  });

  // Initialize Reveal.js
  Reveal.initialize({
    hash: true,
    controls: false,  // Using custom controls
    progress: false,
    transition: 'none',
  });
}
```

### Video Preloading

Manim videos require preloading for smooth transitions:

```javascript
// navigation.js
class VideoPreloader {
  constructor() {
    this.preloadedVideos = new Map();
    this.preloadRadius = 2;  // Preload ±2 slides
  }

  async preloadAround(currentIndex, slides) {
    const start = Math.max(0, currentIndex - this.preloadRadius);
    const end = Math.min(slides.length, currentIndex + this.preloadRadius + 1);

    for (let i = start; i < end; i++) {
      if (slides[i].type === 'video' && !this.preloadedVideos.has(i)) {
        await this.preloadVideo(slides[i].file, i);
      }
    }

    // Evict distant videos to save memory
    this.evictDistant(currentIndex);
  }

  async preloadVideo(src, index) {
    return new Promise((resolve) => {
      const video = document.createElement('video');
      video.src = src;
      video.preload = 'auto';
      video.oncanplaythrough = () => {
        this.preloadedVideos.set(index, video);
        resolve();
      };
      video.onerror = resolve;  // Don't block on errors
    });
  }

  evictDistant(currentIndex) {
    for (const [index, video] of this.preloadedVideos) {
      if (Math.abs(index - currentIndex) > this.preloadRadius * 2) {
        video.src = '';  // Release memory
        this.preloadedVideos.delete(index);
      }
    }
  }
}
```

### Keyboard Navigation

```javascript
// navigation.js
class NavigationController {
  constructor(reveal) {
    this.reveal = reveal;
    this.setupKeyboard();
    this.setupTouch();
  }

  setupKeyboard() {
    document.addEventListener('keydown', (e) => {
      switch (e.key) {
        case 'ArrowRight':
        case ' ':
        case 'PageDown':
          this.reveal.next();
          break;
        case 'ArrowLeft':
        case 'PageUp':
          this.reveal.prev();
          break;
        case 'Home':
          this.reveal.slide(0);
          break;
        case 'End':
          this.reveal.slide(this.reveal.getTotalSlides() - 1);
          break;
        case 'f':
          this.toggleFullscreen();
          break;
      }
    });
  }

  setupTouch() {
    let touchStartX = 0;

    document.addEventListener('touchstart', (e) => {
      touchStartX = e.touches[0].clientX;
    });

    document.addEventListener('touchend', (e) => {
      const touchEndX = e.changedTouches[0].clientX;
      const diff = touchStartX - touchEndX;

      if (Math.abs(diff) > 50) {  // Minimum swipe distance
        if (diff > 0) {
          this.reveal.next();
        } else {
          this.reveal.prev();
        }
      }
    });
  }

  toggleFullscreen() {
    if (document.fullscreenElement) {
      document.exitFullscreen();
    } else {
      document.documentElement.requestFullscreen();
    }
  }
}
```

## Overlay Injection

Some slides need dynamic HTML annotations—tooltips, badges, or interactive elements. The overlay system injects these without modifying the Manim render.

### Overlay Definition

Overlays are defined in a separate JSON file:

```json
// assets/overlays.json
{
  "overlays": [
    {
      "slide": 42,
      "elements": [
        {
          "type": "badge",
          "text": "New",
          "position": { "x": 85, "y": 10 },
          "color": "#ff6b6b"
        },
        {
          "type": "tooltip",
          "text": "Click for details",
          "target": { "x": 50, "y": 50 },
          "direction": "bottom"
        }
      ]
    },
    {
      "slide": 67,
      "elements": [
        {
          "type": "link",
          "text": "Documentation →",
          "url": "https://example.com/docs",
          "position": { "x": 10, "y": 90 }
        }
      ]
    }
  ]
}
```

Position values are percentages of the content area (excluding letterboxing).

### Injection Script

```python
# scripts/inject_overlays.py
"""Inject HTML overlays into Reveal.js HTML output."""

import json
from pathlib import Path
from bs4 import BeautifulSoup

def inject_overlays(html_path, overlays_path):
    with open(html_path) as f:
        soup = BeautifulSoup(f.read(), 'html.parser')

    with open(overlays_path) as f:
        overlays = json.load(f)

    for overlay_def in overlays['overlays']:
        slide_idx = overlay_def['slide']
        section = soup.select_one(f'section[data-slide-index="{slide_idx}"]')

        if not section:
            continue

        for element in overlay_def['elements']:
            html = render_overlay_element(element)
            section.append(BeautifulSoup(html, 'html.parser'))

    with open(html_path, 'w') as f:
        f.write(str(soup))


def render_overlay_element(element):
    """Render an overlay element to HTML."""
    x, y = element['position']['x'], element['position']['y']
    style = f'position: absolute; left: {x}%; top: {y}%;'

    if element['type'] == 'badge':
        return f'''
            <span class="overlay-badge" style="{style} background: {element['color']}">
                {element['text']}
            </span>
        '''
    elif element['type'] == 'tooltip':
        return f'''
            <div class="overlay-tooltip" style="{style}" data-direction="{element['direction']}">
                {element['text']}
            </div>
        '''
    elif element['type'] == 'link':
        return f'''
            <a class="overlay-link" href="{element['url']}" style="{style}" target="_blank">
                {element['text']}
            </a>
        '''
```

### Overlay Styling

```css
/* styles.css */
.overlay-badge {
  padding: 4px 12px;
  border-radius: 12px;
  color: white;
  font-size: 14px;
  font-weight: bold;
  transform: translate(-50%, -50%);
  z-index: 100;
}

.overlay-tooltip {
  background: rgba(0, 0, 0, 0.8);
  color: white;
  padding: 8px 16px;
  border-radius: 4px;
  font-size: 14px;
  z-index: 100;
}

.overlay-tooltip::after {
  content: '';
  position: absolute;
  border: 8px solid transparent;
}

.overlay-tooltip[data-direction="bottom"]::after {
  top: 100%;
  left: 50%;
  transform: translateX(-50%);
  border-top-color: rgba(0, 0, 0, 0.8);
}

.overlay-link {
  color: #4ecdc4;
  text-decoration: none;
  font-size: 16px;
  z-index: 100;
}

.overlay-link:hover {
  text-decoration: underline;
}
```

## Idle State Management

During presentation, cursor and controls should hide after inactivity:

```javascript
// main.js
class IdleManager {
  constructor(timeout = 3000) {
    this.timeout = timeout;
    this.timer = null;
    this.isIdle = false;

    this.setupListeners();
    this.resetTimer();
  }

  setupListeners() {
    ['mousemove', 'mousedown', 'keydown', 'touchstart'].forEach(event => {
      document.addEventListener(event, () => this.resetTimer());
    });
  }

  resetTimer() {
    if (this.isIdle) {
      this.setActive();
    }

    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.setIdle(), this.timeout);
  }

  setIdle() {
    this.isIdle = true;
    document.body.classList.add('idle');
  }

  setActive() {
    this.isIdle = false;
    document.body.classList.remove('idle');
  }
}
```

```css
/* styles.css */
body.idle {
  cursor: none;
}

body.idle #controls {
  opacity: 0;
  transition: opacity 0.3s;
}

body:not(.idle) #controls {
  opacity: 1;
}
```

## Production Build

The production build bundles everything for portable distribution:

```make
.PHONY: build
build: web_setup
	cd $(WEB_DIR) && npm run build
	@echo "Production build complete: $(WEB_DIR)/dist/"

.PHONY: package
package: build
	@echo "Creating portable package..."
	tar -czvf presentation.tar.gz \
		-C $(WEB_DIR)/dist \
		--dereference \
		.
	@echo "Package created: presentation.tar.gz"
```

The `--dereference` flag resolves symlinks, ensuring the tarball is self-contained.

### Package Contents

```
presentation.tar.gz
├── index.html
├── viewer.html
├── assets/
│   └── ...
├── slides/
│   └── SEESoCDeck.json
└── output/
    └── SEESoCDeck/
        ├── 001.webm
        ├── 002.webm
        └── ...
```

### Serving

The package requires only a static file server:

```bash
# Extract and serve
tar -xzf presentation.tar.gz
cd dist
python3 -m http.server 8000

# Or with Node
npx serve .
```

No special runtime—just HTTP and a modern browser.

## LAN Preview

For previewing on tablets or reviewing with colleagues:

```make
.PHONY: view
view: dev-setup
	@cd $(WEB_DIR) && nohup npm run dev -- \
		--host 0.0.0.0 --port $(VITE_PORT) \
		> /tmp/vite.log 2>&1 &
	@sleep 2
	@sudo ufw allow $(VITE_PORT)/tcp comment "SlideForge preview"
	@echo "Preview at http://$$(hostname -I | awk '{print $$1}'):$(VITE_PORT)"

.PHONY: view-stop
view-stop:
	@pkill -f "vite.*$(VITE_PORT)" || true
	@sudo ufw delete allow $(VITE_PORT)/tcp 2>/dev/null || true
	@echo "Preview server stopped"
```

This opens the firewall and prints the LAN URL for easy access from other devices.

## Summary

The SlideForge web frontend transforms rendered animations into browser-playable presentations:

1. **Vite dev server** provides hot reloading during development
2. **Dynamic deck discovery** lists available presentations
3. **Video preloading** ensures smooth playback
4. **Overlay injection** adds dynamic HTML without re-rendering
5. **Idle management** hides UI during presentation
6. **Portable packages** require only a static file server

This concludes the SlideForge series. The complete system—from Beamer PDF rasterization through Manim animation rendering to browser playback—demonstrates how hybrid architectures can leverage the strengths of multiple tools while mitigating their individual weaknesses.

The full SlideForge source is available at [github.com/derrekito/slideforge](https://github.com/derrekito/slideforge).

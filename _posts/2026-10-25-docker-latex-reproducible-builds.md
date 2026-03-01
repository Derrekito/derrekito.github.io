---
title: "Docker-Based LaTeX Compilation: Reproducible Technical Document Builds"
date: 2026-10-25 10:00:00 -0700
categories: [DevOps, Documentation]
tags: [docker, latex, minted, mermaid, pandoc, ci-cd, reproducibility]
---

Containerized LaTeX compilation environments solve the reproducibility crisis in technical document generation. This post presents a Docker-based approach that integrates TeX Live, syntax highlighting with minted, and diagram generation with Mermaid CLI.

## Problem Statement

LaTeX document compilation exhibits several failure modes that complicate collaborative workflows and automated pipelines:

**Dependency Hell**: A LaTeX document requiring `minted` for syntax highlighting needs Python, Pygments, and shell-escape enabled. Add Mermaid diagrams, and Node.js joins the dependency list. Each collaborator must install these tools at compatible versions.

**Environment Drift**: TeX Live 2023 produces different output than TeX Live 2024. Font availability varies by system. Package versions diverge across installations. Documents that compile on one machine fail on another.

**CI/CD Integration**: Continuous integration pipelines require reproducible builds. Installing a full TeX Live distribution during each pipeline run wastes time and bandwidth. Pre-built Docker images eliminate this overhead.

**Non-Root Execution**: Production environments often prohibit root access. Volume mounts create files with container UIDs, causing permission conflicts on host systems.

A containerized solution addresses all four concerns.

## Technical Background

### TeX Live Distribution

TeX Live provides a comprehensive TeX system including LaTeX, fonts, and thousands of packages. The `texlive/texlive:latest` Docker image contains the full distribution (~4GB), ensuring all standard packages are available without network fetches during compilation.

### Auxiliary Tool Chain

Modern technical documents leverage tools beyond core LaTeX:

| Tool | Purpose | Dependency |
|------|---------|------------|
| minted | Syntax highlighting | Python + Pygments |
| Mermaid CLI | Diagram generation | Node.js + Puppeteer |
| Pandoc | Document conversion | Haskell runtime (bundled) |
| ImageMagick | Image processing | System libraries |

Bundling these tools in a single container eliminates installation complexity.

## Architecture Overview

The Dockerfile follows a layered approach, ordered by change frequency to optimize build caching:

```dockerfile
FROM texlive/texlive:latest

ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /app
```

### Layer 1: System Dependencies

System packages install first as they change infrequently:

```dockerfile
RUN apt-get update && apt-get install -y \
  curl wget git make \
  imagemagick jq pandoc \
  python3 python3-pip python3-venv \
  chromium fontconfig \
  # Chromium dependencies for headless browser
  libnss3 libatk1.0-0 libatk-bridge2.0-0 \
  libcups2 libdrm2 libxkbcommon0 \
  libxcomposite1 libxdamage1 libxfixes3 \
  libxrandr2 libgbm1 libasound2t64 \
  sudo ca-certificates fonts-liberation \
  && rm -rf /var/lib/apt/lists/*
```

The Chromium dependencies support Puppeteer, which renders Mermaid diagrams to images.

### Layer 2: Font Installation

Custom fonts such as FiraCode enhance code listings:

```dockerfile
RUN mkdir -p /usr/share/fonts/truetype/firacode && \
  wget -O /tmp/Fira_Code_v6.2.zip \
  https://github.com/tonsky/FiraCode/releases/download/6.2/Fira_Code_v6.2.zip && \
  unzip -j /tmp/Fira_Code_v6.2.zip "ttf/*" \
    -d /usr/share/fonts/truetype/firacode && \
  rm /tmp/Fira_Code_v6.2.zip && \
  fc-cache -f -v
```

System-wide font installation ensures availability across all compilation modes.

### Layer 3: Node.js Runtime

Node.js 18 LTS provides the runtime for Mermaid CLI:

```dockerfile
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
  apt-get install -y nodejs && \
  npm install -g npm
```

## Non-Root User Handling

Running containers as root creates permission issues when mounting host volumes. Files created inside the container inherit the container's UID, often resulting in root-owned files on the host.

### UID Detection Strategy

The Dockerfile implements dynamic UID handling:

```dockerfile
RUN if id -u 1000 >/dev/null 2>&1; then \
      EXISTING_USER=$(id -un 1000); \
      echo "$EXISTING_USER ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/$EXISTING_USER; \
      chown -R $EXISTING_USER:$(id -gn 1000) /app; \
    else \
      useradd -m -s /bin/bash -u 1000 -g 1000 appuser && \
      echo "appuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/appuser && \
      chown -R appuser:appuser /app; \
    fi

USER 1000
```

This approach:

1. **Detects existing UID 1000**: The `texlive/texlive` base image may already contain a user at UID 1000
2. **Reuses or creates**: Existing users are reused; otherwise, `appuser` is created
3. **Grants sudo access**: Passwordless sudo enables package installation at runtime if needed
4. **Switches to non-root**: `USER 1000` runs all subsequent commands as the non-root user

### Volume Mount Compatibility

When running the container with matching host UID:

```bash
docker run --rm -v $(pwd):/app -u $(id -u):$(id -g) latex-env latexmk -pdf document.tex
```

Generated files inherit the host user's ownership, avoiding permission conflicts.

## Integration with Minted and Pygments

The minted package provides superior syntax highlighting compared to the listings package. It delegates highlighting to Pygments, a Python library supporting hundreds of languages.

### Python Virtual Environment Setup

```dockerfile
RUN python3 -m venv ~/venv && \
  ~/venv/bin/pip install --no-cache-dir \
  pandocfilters==1.5.1 \
  pygments==2.19.1
```

Version pinning ensures reproducible highlighting output across builds.

### LaTeX Configuration

Documents using minted require shell-escape:

```latex
\documentclass{article}
\usepackage{minted}

\begin{document}

\begin{minted}{python}
def fibonacci(n: int) -> int:
    if n <= 1:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)
\end{minted}

\end{document}
```

Compilation command:

```bash
latexmk -pdf -shell-escape document.tex
```

### PATH Configuration

The virtual environment must be in PATH:

```dockerfile
ENV PATH="/home/texlive/venv/bin:/home/texlive/.npm-global/bin:${PATH}"
```

## Mermaid Diagram Generation

Mermaid generates diagrams from text descriptions. The Mermaid CLI (`mmdc`) converts Mermaid code to images suitable for LaTeX inclusion.

### Node Package Installation

```dockerfile
RUN mkdir -p ~/.npm-global && \
  npm config set prefix ~/.npm-global && \
  npm install -g --no-progress \
  puppeteer@23.9.0 \
  @mermaid-js/mermaid-cli@11.4.2
```

### Puppeteer Configuration

Mermaid CLI uses Puppeteer to render diagrams in a headless browser. The container uses system Chromium rather than downloading a bundled version:

```dockerfile
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
```

This reduces image size and ensures compatibility with the container's graphics stack.

### Generating Diagrams

Create a Mermaid source file:

```text
graph TD
    A[Source Document] --> B[Pandoc]
    B --> C{Output Format}
    C -->|PDF| D[LaTeX]
    C -->|HTML| E[Web]
    D --> F[pdflatex]
```

Convert to PDF:

```bash
mmdc -i diagram.mmd -o diagram.pdf -b transparent
```

Include in LaTeX:

```latex
\begin{figure}[h]
\centering
\includegraphics[width=0.8\textwidth]{diagram.pdf}
\caption{Document processing pipeline}
\end{figure}
```

### Automated Conversion with Pandoc Filters

A Pandoc filter automates Mermaid rendering during document conversion:

```python
#!/usr/bin/env python3
"""pandoc-mermaid.py - Convert mermaid code blocks to images."""

import subprocess
import tempfile
import os
from pandocfilters import toJSONFilter, Image, Para

def mermaid_filter(key, value, format, meta):
    if key == 'CodeBlock':
        [[ident, classes, keyvals], code] = value
        if 'mermaid' in classes:
            with tempfile.NamedTemporaryFile(
                mode='w', suffix='.mmd', delete=False
            ) as f:
                f.write(code)
                input_path = f.name

            output_path = input_path.replace('.mmd', '.pdf')
            subprocess.run([
                'mmdc', '-i', input_path,
                '-o', output_path, '-b', 'transparent'
            ], check=True)

            return Para([Image(['', [], []], [], [output_path, ''])])

if __name__ == '__main__':
    toJSONFilter(mermaid_filter)
```

## Usage Examples

### Building a Single Document

```bash
docker run --rm \
  -v $(pwd):/app \
  -u $(id -u):$(id -g) \
  latex-env \
  latexmk -pdf -shell-escape document.tex
```

### Interactive Shell Access

```bash
docker run --rm -it \
  -v $(pwd):/app \
  -u $(id -u):$(id -g) \
  latex-env \
  bash
```

### Makefile Integration

```makefile
DOCKER_IMAGE := latex-env
DOCKER_RUN := docker run --rm -v $(PWD):/app -u $(shell id -u):$(shell id -g)

%.pdf: %.tex
	$(DOCKER_RUN) $(DOCKER_IMAGE) latexmk -pdf -shell-escape $<

clean:
	$(DOCKER_RUN) $(DOCKER_IMAGE) latexmk -C

.PHONY: clean
```

### Multi-Stage Compilation

Complex documents may require multiple passes or auxiliary tool execution:

```bash
docker run --rm \
  -v $(pwd):/app \
  -u $(id -u):$(id -g) \
  latex-env \
  bash -c "mmdc -i diagrams/*.mmd -o figures/ && latexmk -pdf -shell-escape main.tex"
```

## CI/CD Integration Patterns

### GitHub Actions

```yaml
name: Build LaTeX Document

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Build PDF
        run: |
          docker run --rm \
            -v ${{ github.workspace }}:/app \
            ghcr.io/username/latex-env:latest \
            latexmk -pdf -shell-escape document.tex

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: document-pdf
          path: document.pdf
```

### GitLab CI

```yaml
stages:
  - build

build-pdf:
  stage: build
  image: registry.gitlab.com/username/latex-env:latest
  script:
    - latexmk -pdf -shell-escape document.tex
  artifacts:
    paths:
      - document.pdf
    expire_in: 1 week
```

### Pre-Built Image Publishing

Publishing the image to a container registry avoids rebuilding in CI:

```bash
# Build and tag
docker build -t ghcr.io/username/latex-env:latest .

# Authenticate
echo $GITHUB_TOKEN | docker login ghcr.io -u username --password-stdin

# Push
docker push ghcr.io/username/latex-env:latest
```

### Caching Strategies

For repositories with frequent documentation updates, cache auxiliary files:

```yaml
- name: Cache LaTeX auxiliary files
  uses: actions/cache@v4
  with:
    path: |
      *.aux
      *.fdb_latexmk
      *.fls
    key: latex-aux-${{ hashFiles('**/*.tex') }}
```

## Health Check and Verification

The Dockerfile includes a health check to verify TeX Live availability:

```dockerfile
HEALTHCHECK CMD ["latexmk", "--version"] || exit 1
```

Verify container functionality:

```bash
docker run --rm latex-env latexmk --version
docker run --rm latex-env pygmentize -V
docker run --rm latex-env mmdc --version
```

## Conclusion

Containerized LaTeX compilation eliminates environment inconsistencies that plague traditional installations. The presented Dockerfile integrates TeX Live, Pygments for syntax highlighting, and Mermaid CLI for diagram generation into a single, reproducible image.

Key design decisions include:

- **Non-root execution** with dynamic UID detection for volume mount compatibility
- **Python virtual environment** for isolated Pygments installation
- **System Chromium** for Puppeteer to avoid bundled browser downloads
- **Layered build structure** optimizing Docker cache efficiency

The resulting container supports local development, CI/CD pipelines, and collaborative workflows without requiring contributors to install complex toolchains.

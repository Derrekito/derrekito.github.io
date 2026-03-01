---
title: "A Centralized Pandoc + LaTeX Documentation Pipeline"
date: 2027-02-28 10:00:00 -0700
categories: [Documentation, DevOps]
tags: [pandoc, latex, makefile, lualatex, mermaid, minted, documentation-pipeline]
---

Technical documentation across multiple projects often leads to duplicated tooling: each project maintains its own Pandoc configuration, LaTeX templates, filter scripts, and dependency management. This fragmentation creates maintenance burden, inconsistent output quality, and onboarding friction when contributors must learn project-specific build systems.

This post presents a centralized documentation pipeline that projects consume via git submodule or symlink, providing a unified Makefile.include pattern for PDF and DOCX generation from Markdown sources.

## Problem Statement

A typical multi-project organization accumulates documentation tooling debt:

| Problem | Impact |
|---------|--------|
| Duplicated Pandoc filters | Bug fixes require propagation across all projects |
| Per-project LaTeX templates | Inconsistent document styling and branding |
| Manual dependency management | New contributor setup takes hours instead of minutes |
| Scattered mermaid/minted configuration | Diagram and code rendering varies between documents |
| Version drift | Projects use different filter versions with different behaviors |

Centralizing the pipeline eliminates these issues by establishing a single source of truth for documentation tooling. Projects declare their content and project-specific assets; the pipeline handles everything else.

## Architecture Overview

The pipeline provides:

```text
manual-pipeline/
├── latex/
│   ├── templates/           # Document templates (plain, report, memorandum)
│   │   ├── plain/
│   │   ├── report/
│   │   └── memorandum/
│   └── filters/             # Pandoc filters
│       ├── include-files.lua
│       ├── md-links-to-refs.lua
│       ├── nobreak-codeblock.lua
│       ├── notebook-toggle.lua
│       ├── pandoc-mermaid.py
│       └── pandoc-minted.py
├── scripts/
│   ├── check_deps.sh        # Auto-dependency installation
│   ├── create_pdf.sh        # Main build orchestrator
│   └── preprocess-acronyms.sh
├── assets/
│   ├── Fonts/               # Bundled fonts (Fira Code)
│   └── logos/               # Default logos
├── config/
│   ├── mermaid-config.json
│   └── mermaid.css
└── Makefile.include         # The include file for projects
```

Projects include this pipeline and provide only their content:

```text
your-project/
├── manual/
│   ├── Makefile              # 4-line include pattern
│   ├── yourproject-manual.md # Main document
│   ├── docs/                 # Additional markdown files
│   ├── latex/
│   │   └── acronyms.tex      # Project-specific acronyms
│   └── assets/
│       └── logos/            # Project-specific logos
└── ...
```

## Integration Patterns

### Git Submodule Integration

For version-controlled projects requiring reproducible builds:

```bash
cd your-project
mkdir -p manual
git submodule add ~/Projects/manual-pipeline manual/pipeline
```

This pins the pipeline to a specific commit. Updates occur explicitly:

```bash
cd manual/pipeline
git pull origin main
cd ../..
git add manual/pipeline
git commit -m "Update documentation pipeline"
```

### Symlink Integration

For local development or shared network drives where submodule overhead is unnecessary:

```bash
cd your-project/manual
ln -s ~/Projects/manual-pipeline pipeline
```

Symlinks provide instant access to pipeline updates but sacrifice reproducibility. This approach suits single-developer workflows or centralized documentation servers.

## Makefile.include Architecture

The pipeline's core is `Makefile.include`, which projects include after setting required variables:

```makefile
# your-project/manual/Makefile
PROJECT_NAME := yourproject
MANUAL_DIR := $(shell pwd)
PIPELINE_DIR := $(MANUAL_DIR)/pipeline
include $(PIPELINE_DIR)/Makefile.include
```

### Required Variables

The include file validates required variables at parse time:

```makefile
ifndef PROJECT_NAME
$(error PROJECT_NAME is not set. Set it before including Makefile.include)
endif
ifndef MANUAL_DIR
$(error MANUAL_DIR is not set. Set it before including Makefile.include)
endif
ifndef PIPELINE_DIR
$(error PIPELINE_DIR is not set. Set it before including Makefile.include)
endif
```

### Derived Paths

Path conventions ensure consistent directory structure:

```makefile
MASTER_DOC ?= $(MANUAL_DIR)/$(PROJECT_NAME)-manual.md
BUILD_DIR := $(MANUAL_DIR)/build
OUTPUT_DIR := $(MANUAL_DIR)/output
VENV_DIR := $(MANUAL_DIR)/venv
SCRIPTS_DIR := $(PIPELINE_DIR)/scripts
```

### Automatic Dependency Tracking

The Makefile tracks all relevant source files for incremental builds:

```makefile
DOC_FILES := $(wildcard $(MANUAL_DIR)/docs/*.md)
LATEX_FILES := $(wildcard $(MANUAL_DIR)/latex/*.tex) \
               $(wildcard $(PIPELINE_DIR)/latex/templates/*.latex) \
               $(wildcard $(PIPELINE_DIR)/latex/templates/*/*.latex)
FILTER_FILES := $(wildcard $(PIPELINE_DIR)/latex/filters/*.lua) \
                $(wildcard $(PIPELINE_DIR)/latex/filters/*.py)
```

The PDF target depends on all these files:

```makefile
$(PDF_OUTPUT): $(SETUP_MARKER) $(MASTER_DOC) $(DOC_FILES) $(LATEX_FILES) $(FILTER_FILES) $(EXTRA_DEPS)
	@$(SCRIPTS_DIR)/create_pdf.sh $(MASTER_DOC) 1 pdf
```

Changes to any filter, template, or document trigger rebuilds.

### Available Targets

| Target | Description |
|--------|-------------|
| `make pdf` | Generate PDF manual (default) |
| `make docx` | Generate DOCX manual |
| `make setup` | Install dependencies (auto-runs on first build) |
| `make check-deps` | Verify system dependencies |
| `make clean` | Remove build artifacts |
| `make distclean` | Remove all generated files including venv |

## Pandoc Filter Chain

The pipeline applies filters in a specific order, each transforming the document AST:

```bash
pandoc input.md \
  --lua-filter=include-files.lua \
  --lua-filter=readme-only.lua \
  --lua-filter=notebook-toggle.lua \
  --lua-filter=nobreak-codeblock.lua \
  --lua-filter=md-links-to-refs.lua \
  --filter=pandoc-mermaid.py \
  --filter=pandoc-minted.py
```

### Filter Execution Order

1. **include-files.lua**: Expands `!include` directives before other processing
2. **readme-only.lua**: Strips README-specific content from included files
3. **notebook-toggle.lua**: Controls code block visibility based on document mode
4. **nobreak-codeblock.lua**: Prevents page breaks within short code blocks
5. **md-links-to-refs.lua**: Converts Markdown file links to LaTeX cross-references
6. **pandoc-mermaid.py**: Renders Mermaid diagrams to PDF images
7. **pandoc-minted.py**: Applies minted syntax highlighting

### include-files.lua

This filter enables modular document composition:

```markdown
# Main Document

!include docs/introduction.md
!include docs/architecture.md
!include-shift docs/api-reference.md
!include-headless docs/appendix.md
```

Directive variants:

| Directive | Behavior |
|-----------|----------|
| `!include path` | Include file as-is |
| `!include-shift path` | Shift all headings down one level |
| `!include-shift:N path` | Shift headings down N levels |
| `!include-headless path` | Strip first H1, shift remaining by 1 |

The filter strips YAML front matter from included files and prefixes heading IDs to prevent cross-file duplicates.

### md-links-to-refs.lua

Markdown links to other `.md` files become LaTeX cross-references:

```markdown
See [API Documentation](api.md#authentication) for details.
```

Becomes:

```latex
See \hyperref[authentication]{API Documentation} for details.
```

This enables internal linking that survives format conversion while remaining valid Markdown links for documentation viewers.

## Acronym Preprocessing

LaTeX's `acronym` package provides first-use expansion (`\ac{API}` becomes "Application Programming Interface (API)" on first use, then "API" thereafter). However, Pandoc interprets `\a` as a bell character escape sequence, corrupting the command.

The pipeline preprocesses acronyms before Pandoc sees them:

```bash
#!/bin/bash
# preprocess-acronyms.sh
sed -E '
  s/\\ac\{([^}]+)\}/`\\ac{\1}`{=latex}/g
  s/\\Ac\{([^}]+)\}/`\\Ac{\1}`{=latex}/g
  s/\\acf\{([^}]+)\}/`\\acf{\1}`{=latex}/g
  s/\\acs\{([^}]+)\}/`\\acs{\1}`{=latex}/g
  s/\\acl\{([^}]+)\}/`\\acl{\1}`{=latex}/g
  s/\\acp\{([^}]+)\}/`\\acp{\1}`{=latex}/g
' "$1"
```

This wraps acronym commands in raw LaTeX inline syntax:

```markdown
The \ac{API} provides...
```

Becomes:

```markdown
The `\ac{API}`{=latex} provides...
```

Pandoc passes raw LaTeX through unchanged.

### Defining Acronyms

Projects define acronyms in `manual/latex/acronyms.tex`:

```latex
\begin{acronym}
\acro{API}{Application Programming Interface}
\acro{CPU}{Central Processing Unit}
\acro{GPU}{Graphics Processing Unit}
\acro{SEU}{Single Event Upset}
\end{acronym}
```

Available commands in documents:

| Command | Output |
|---------|--------|
| `\ac{API}` | Full form first use, short form thereafter |
| `\Ac{API}` | Capitalized first letter |
| `\acf{API}` | Full form always |
| `\acs{API}` | Short form always |
| `\acl{API}` | Long form (expansion only) |
| `\acp{API}` | Plural form |

## Mermaid Diagram Integration

The `pandoc-mermaid.py` filter renders Mermaid code blocks to PDF images:

````markdown
```{.mermaid width="80%" center="true" caption="System Architecture"}
graph TD
    A[Client] --> B[API Gateway]
    B --> C[Service A]
    B --> D[Service B]
    C --> E[(Database)]
    D --> E
```
````

### Rendering Process

1. Hash diagram source for caching
2. Write `.mmd` file to build directory
3. Execute `mmdc` (Mermaid CLI) to generate PDF
4. Generate `\includegraphics` LaTeX command

### Available Options

| Option | Description |
|--------|-------------|
| `width` | LaTeX width (e.g., `80%`, `0.5\textwidth`) |
| `scale` | Scale factor (alternative to width) |
| `center` | Center in figure environment (`true`/`false`) |
| `caption` | Figure caption text |
| `theme` | Mermaid theme (passed to mmdc) |

The filter caches rendered diagrams by content hash, skipping regeneration when source is unchanged.

## Minted Code Highlighting

The `pandoc-minted.py` filter converts code blocks to minted environments:

````markdown
```python
def fibonacci(n: int) -> int:
    if n <= 1:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)
```
````

Becomes:

```latex
\begin{minted}[]{python}
def fibonacci(n: int) -> int:
    if n <= 1:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)
\end{minted}
```

Minted delegates to Pygments, supporting 500+ languages with accurate tokenization.

### Inline Code

The filter also handles inline code:

```markdown
Call `fibonacci(10)` to compute the tenth number.
```

Becomes:

```latex
Call \mintinline[]{python}{fibonacci(10)} to compute the tenth number.
```

### Document-Level Defaults

Set a default language in YAML front matter:

```yaml
---
pandoc-minted:
  language: python
---
```

Code blocks without explicit language inherit this default.

## Template Selection

The pipeline supports multiple document templates:

| Template | Description |
|----------|-------------|
| `plain` | Minimal article format |
| `report` | Formal report with cover page |
| `memorandum` | Internal memo format |
| `article` | Academic article format |

### Selection Methods

Templates are selected in priority order:

1. **Makefile variable**: `TEMPLATE := report`
2. **Command line**: `make pdf TEMPLATE=report`
3. **Front matter**: `template-name: report`
4. **Default**: `plain`

### Template Structure

Each template directory contains:

```text
templates/report/
├── template.latex    # Main Pandoc template
├── preamble.latex    # Template-specific preamble (optional)
└── titlepage.latex   # Custom title page (optional)
```

Templates reference shared partials via Pandoc's `${ partial() }` syntax:

```latex
${ partial("preamble.latex") }
${ partial("fonts.latex") }
${ partial("codeblocks.latex") }
```

## Auto-Setup and Dependency Management

The pipeline automatically installs dependencies on first build:

```bash
make pdf  # First run triggers setup
```

The `check_deps.sh` script handles:

1. **System packages**: pandoc, latexmk, lualatex, python3, node
2. **Python environment**: Virtual environment with pandocfilters, pygments
3. **Node packages**: @mermaid-js/mermaid-cli
4. **Fonts**: Fira Code (downloaded if missing)

### Cross-Platform Support

The script detects the operating system and uses the appropriate package manager:

```bash
if [ -f /etc/debian_version ]; then
    sudo apt-get install -y "$ubuntu_pkg"
elif [ -f /etc/fedora-release ]; then
    sudo dnf install -y "$fedora_pkg"
elif [ -f /etc/arch-release ]; then
    sudo pacman -Syu --noconfirm "$arch_pkg"
fi
```

### Docker Compatibility

In containerized environments, the script validates dependencies without attempting installation:

```bash
is_docker() {
  [ -f /.dockerenv ] || [ -f /run/.containerenv ]
}

if is_docker; then
    # Validate only, fail if missing
    if ! check_command "$cmd"; then
        missing+=("$cmd")
    fi
else
    # Install if missing
    install_system_package "$cmd" ...
fi
```

## TexLive 2025 Compatibility

The pipeline includes compatibility fixes for TexLive 2025 changes. The preamble handles deprecated packages and changed behaviors:

```latex
% Handle ifthen deprecation in some packages
\usepackage{ifthen}

% LuaTeX-specific fixes
\directlua{
  % Font loading adjustments for TL2025
}
```

These fixes are centralized in the pipeline, automatically benefiting all consuming projects when the pipeline updates.

## Multi-Project Usage Example

Consider an organization with three projects:

```text
~/Projects/
├── manual-pipeline/           # Shared pipeline
├── project-alpha/
│   └── manual/
│       ├── Makefile
│       ├── alpha-manual.md
│       └── pipeline -> ~/Projects/manual-pipeline
├── project-beta/
│   └── manual/
│       ├── Makefile
│       ├── beta-manual.md
│       └── pipeline -> ~/Projects/manual-pipeline
└── project-gamma/
    └── manual/
        ├── Makefile
        ├── gamma-manual.md
        └── pipeline/           # git submodule
```

All three projects share:
- Filter implementations and bug fixes
- Template styling and branding
- Dependency management logic
- Mermaid and minted configuration

Each project maintains only:
- Project-specific content (`*-manual.md`)
- Project-specific acronyms (`latex/acronyms.tex`)
- Project-specific assets (`assets/logos/`)

## Build Output

A typical build produces:

```text
manual/
├── build/
│   ├── yourproject-manual.tex    # Generated LaTeX
│   ├── yourproject-manual.log    # LuaLaTeX log
│   ├── mermaid_images/           # Rendered diagrams
│   ├── _minted-yourproject/      # Pygments cache
│   └── pandoc_output.log
└── output/
    └── yourproject-manual.pdf    # Final output
```

The `build/` directory contains intermediates for debugging; `output/` contains deliverables.

## Conclusion

Centralizing documentation tooling via a shared pipeline provides several advantages:

- **Single source of truth**: Filter bugs fix once, propagate everywhere
- **Consistent output**: All documents share styling and rendering quality
- **Reduced onboarding**: New contributors run `make pdf` without setup knowledge
- **Version control**: Submodule integration enables reproducible documentation builds
- **Extensibility**: New features benefit all consuming projects simultaneously

The Makefile.include pattern scales from single-project workflows to organization-wide documentation standards, providing the flexibility of project-specific content with the consistency of shared tooling.

## References

- [Pandoc User's Guide](https://pandoc.org/MANUAL.html)
- [Pandoc Lua Filters](https://pandoc.org/lua-filters.html)
- [Minted Package Documentation](https://ctan.org/pkg/minted)
- [Mermaid CLI Documentation](https://github.com/mermaid-js/mermaid-cli)
- [GNU Make Manual](https://www.gnu.org/software/make/manual/)

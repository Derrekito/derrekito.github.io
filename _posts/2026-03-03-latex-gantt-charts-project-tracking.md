---
title: "LaTeX Gantt Charts for Project Tracking: pgfgantt with Weekend Shading and Progress Bars"
date: 2026-03-03
categories: [Documentation, LaTeX]
tags: [latex, gantt, project-management, pgfgantt, tikz]
---

Gantt charts visualize project timelines, task dependencies, and progress at a glance. This post presents a modular LaTeX system using `pgfgantt` with custom enhancements: weekend shading, alternating row backgrounds, progress tracking, and a clean build pipeline.

## Why LaTeX for Gantt Charts?

- **Version control**: Track changes with git
- **Reproducibility**: Same input always produces same output
- **Automation**: Generate charts from data or integrate with CI
- **Quality**: Publication-ready PDF output
- **Customization**: Full control over every visual element

## Project Structure

```
project-tracking/
├── Makefile              # Build pipeline
├── .latexmkrc           # LaTeX compiler settings
├── .gitignore           # Ignore build artifacts
├── Settings/
│   ├── preamble.tex     # Package imports
│   ├── colors.tex       # Color definitions
│   ├── fonts.tex        # Font configuration
│   └── ganttconfig.tex  # pgfgantt customization
├── Charts/
│   ├── project-alpha.tex    # Individual chart content
│   └── project-beta.tex
├── project-alpha.tex    # Document wrapper
├── project-beta.tex
├── build/               # Compilation artifacts
└── output/              # Final PDFs
```

This separation keeps chart content (what tasks exist) separate from styling (how they look).

## Quick Start

### Minimal Working Example

```latex
\documentclass[tikz]{standalone}
\usepackage{pgfgantt}

\begin{document}
\begin{ganttchart}[
    hgrid,
    vgrid,
    x unit=0.8cm,
    y unit chart=0.6cm,
]{1}{12}
    \gantttitle{Project Timeline}{12} \\
    \gantttitlelist{1,...,12}{1} \\
    \ganttgroup{Phase 1}{1}{4} \\
    \ganttbar{Task A}{1}{2} \\
    \ganttbar{Task B}{2}{4} \\
    \ganttlink{elem1}{elem2}
    \ganttgroup{Phase 2}{5}{12} \\
    \ganttbar{Task C}{5}{8} \\
    \ganttbar{Task D}{9}{12}
\end{ganttchart}
\end{document}
```

Compile with:

```bash
latexmk -pdflua minimal.tex
```

## Settings Files

### preamble.tex

```latex
% Core packages
\usepackage{pgfgantt}
\usepackage{xcolor}
\usepackage{etoolbox}  % For patching commands

% Date handling
\usepackage{pgfcalendar}
```

### colors.tex

```latex
% Chart element colors
\definecolor{barblue}{RGB}{153,204,254}
\definecolor{groupblue}{RGB}{51,102,254}
\definecolor{linkred}{RGB}{165,0,33}

% Progress colors
\definecolor{progressgreen}{RGB}{76,175,80}
\definecolor{progressgray}{RGB}{189,189,189}

% Background colors
\definecolor{weekendgray}{RGB}{245,245,245}
\definecolor{altrowgray}{RGB}{250,250,250}
```

### fonts.tex

```latex
\usepackage{fontspec}
\setmainfont{TeX Gyre Heros}
\setsansfont{TeX Gyre Heros}
\renewcommand{\familydefault}{\sfdefault}
```

### ganttconfig.tex (The Core Customization)

This file contains the advanced pgfgantt customizations:

{% raw %}
```latex
% ============================================================
% Weekend Shading
% ============================================================
% Shade Saturday and Sunday columns in the chart

\makeatletter

% Patch ganttchart to insert custom drawing before/after grid
\patchcmd{\endganttchart}
  {\ifgtt@vgrid}
  {\gtt@before@grid\ifgtt@vgrid}
  {}{}
\patchcmd{\endganttchart}
  {\def\@tempa{none}}
  {\gtt@after@grid\def\@tempa{none}}
  {}{}

% Weekend detection flag
\newif\ifgtt@vgrid@weekend
\gtt@vgrid@weekendfalse

% Assemble vgrid style based on starting weekday
\newcommand*{\gtt@vgridweek@assemblestyle}{%
  \ifgtt@vgrid\ifgtt@vgrid@weekend
    \pgfcalendarjuliantoweekday{\gtt@startjulian}{\@tempcntb}%
    % Build pattern based on which day the chart starts
    \ifcase\@tempcntb  % Monday
      \edef\gtt@vgridstyle{*4{\gtt@vgridstyle@week},*1{\gtt@vgridstyle@weekend},*1{\gtt@vgridstyle@week},*1{\gtt@vgridstyle@weekend}}%
    \or  % Tuesday
      \edef\gtt@vgridstyle{*3{\gtt@vgridstyle@week},*1{\gtt@vgridstyle@weekend},*1{\gtt@vgridstyle@week},*1{\gtt@vgridstyle@weekend},*1{\gtt@vgridstyle@week}}%
    \or  % Wednesday
      \edef\gtt@vgridstyle{*2{\gtt@vgridstyle@week},*1{\gtt@vgridstyle@weekend},*1{\gtt@vgridstyle@week},*1{\gtt@vgridstyle@weekend},*2{\gtt@vgridstyle@week}}%
    \or  % Thursday
      \edef\gtt@vgridstyle{*1{\gtt@vgridstyle@week},*1{\gtt@vgridstyle@weekend},*1{\gtt@vgridstyle@week},*1{\gtt@vgridstyle@weekend},*3{\gtt@vgridstyle@week}}%
    \or  % Friday
      \edef\gtt@vgridstyle{*1{\gtt@vgridstyle@weekend},*1{\gtt@vgridstyle@week},*1{\gtt@vgridstyle@weekend},*4{\gtt@vgridstyle@week}}%
    \or  % Saturday
      \edef\gtt@vgridstyle{*1{\gtt@vgridstyle@week},*1{\gtt@vgridstyle@weekend},*4{\gtt@vgridstyle@week},*1{\gtt@vgridstyle@weekend}}%
    \or  % Sunday
      \edef\gtt@vgridstyle{*1{\gtt@vgridstyle@weekend},*4{\gtt@vgridstyle@week},*1{\gtt@vgridstyle@weekend},*1{\gtt@vgridstyle@week}}%
    \fi
  \fi\fi
}

% Draw weekend background shading
\newcommand*{\gtt@weekend@draw}{%
  \def\@tempa{none}%
  \ifx\gtt@weekend@background\@tempa\else
    \pgfcalendarjuliantoweekday{\gtt@startjulian}{\@tempcntb}%
    \global\advance\gtt@chartwidth by-1\relax%
    \foreach \x in {0,...,\gtt@chartwidth} {%
      \pgfmathsetcount{\@tempcnta}{mod(\x+\@tempcntb,7)}%
      % Weekdays 5 and 6 are Saturday and Sunday (0=Monday)
      \ifnum\@tempcnta>4\relax
        \expandafter\fill\expandafter[\gtt@weekend@background]
          (\x * \ganttvalueof{x unit}, \y@upper pt) rectangle
          (\x * \ganttvalueof{x unit} + \ganttvalueof{x unit}, \y@lower pt);%
      \fi
    }%
    \global\advance\gtt@chartwidth by1\relax%
    % Redraw canvas border
    \node [/pgfgantt/canvas, minimum width=\x@size pt,
      minimum height=\y@size pt, fill=none]
      at (\x@size pt / 2, \y@mid pt) {};%
  \fi
}

% Hook into chart rendering
\newcommand*{\gtt@before@grid}{\gtt@vgridweek@assemblestyle\gtt@weekend@draw}
\newcommand*{\gtt@after@grid}{}

% Register new pgfgantt keys
\ganttset{
  vgridweek/.code 2 args = {%
    \gtt@vgridtrue\gtt@vgrid@weekendtrue
    \def\gtt@vgridstyle@week{#1}%
    \def\gtt@vgridstyle@weekend{#2}%
  },
  weekend background/.store in = \gtt@weekend@background,
  weekend background = black!8,
}

% ============================================================
% Alternating Row Backgrounds
% ============================================================

\newcommand*{\gtt@altrow@background}{black!5}

\newcommand*{\gtt@altrow@draw}{%
  \pgfmathsetmacro{\rowheight}{\ganttvalueof{y unit chart}}%
  \pgfmathtruncatemacro{\numrows}{-\y@lower/\rowheight}%
  \foreach \row in {0,...,\numrows} {%
    \pgfmathtruncatemacro{\isodd}{mod(\row,2)}%
    \ifnum\isodd=1\relax
      \fill[\gtt@altrow@background]
        (0, -\row*\rowheight pt) rectangle
        (\gtt@chartwidth*\ganttvalueof{x unit}, -\row*\rowheight pt - \rowheight pt);%
    \fi
  }%
}

\makeatother
```
{% endraw %}

## Custom Macros

Add these to `ganttconfig.tex` for cleaner chart definitions:

### Section Separators

{% raw %}
```latex
\newcommand{\sectionsep}{%
  \ganttnewline[draw=black!50, line width=1.2pt]%
}
```
{% endraw %}

### Task with Progress and Assignee

{% raw %}
```latex
\NewDocumentCommand{\assignedtask}{m m m m m o}{%
  % #1 = Task name
  % #2 = Start date
  % #3 = End date
  % #4 = Progress (0-100)
  % #5 = Assignee initials
  % #6 = Optional: node name for linking
  \ganttbar[
    progress=#4,
    progress label text={\scriptsize #4\%},
    name={#6},
    bar label font=\mdseries\small
  ]{#1 (#5)}{#2}{#3}
}
```
{% endraw %}

### Leave/Vacation Marker

{% raw %}
```latex
\newcommand{\leave}[3]{%
  \ganttbar[
    bar/.append style={fill=red!20, draw=red!50},
    bar label font=\itshape\small
  ]{#1}{#2}{#3}%
}
```
{% endraw %}

## Chart Document Structure

### Document Wrapper (project-alpha.tex)

```latex
\documentclass[tikz]{standalone}
\usepackage{pdfpages}
\input{Settings/preamble}
\input{Settings/colors}
\input{Settings/fonts}
\input{Settings/ganttconfig}

% Chart date range
\edef\chartstart{2026-01-06}
\edef\chartend{2026-04-10}

\begin{document}
\input{Charts/project-alpha}
\end{document}
```

### Chart Content (Charts/project-alpha.tex)

```latex
\begin{ganttchart}[
    hgrid,
    vgridweek={draw=black!30}{draw=black!10, dashed},
    weekend background=black!8,
    x unit=0.18cm,
    y unit chart=0.55cm,
    y unit title=0.6cm,
    title height=1,
    bar height=0.6,
    bar top shift=0.2,
    group height=0.3,
    group top shift=0.35,
    bar/.append style={fill=barblue, draw=black!50},
    group/.append style={fill=groupblue, draw=black!70},
    link/.append style={-latex, linkred, thick},
    progress=today,
    progress label text=,
    today=2026-02-15,
    today rule/.style={draw=red!60, line width=1.5pt},
]{\chartstart}{\chartend}

\gantttitlecalendar{month=name, week} \\

% ---- Phase 1: Foundation ----
\sectionsep
\ganttgroup{1. Foundation}{2026-01-06}{2026-01-20} \\
\assignedtask{Requirements gathering}{2026-01-06}{2026-01-08}{100}{AB}[req] \\
\assignedtask{Architecture design}{2026-01-09}{2026-01-13}{100}{CD}[arch] \\
\assignedtask{Environment setup}{2026-01-13}{2026-01-15}{100}{AB}[env] \\
\assignedtask{Initial scaffolding}{2026-01-16}{2026-01-20}{80}{CD}[scaffold] \\
\ganttlink{req}{arch}
\ganttlink{arch}{env}
\ganttlink{env}{scaffold}

% ---- Phase 2: Core Development ----
\sectionsep
\ganttgroup[name=grp-core]{2. Core Development}{2026-01-21}{2026-02-28} \\
\assignedtask{Module A implementation}{2026-01-21}{2026-02-07}{60}{AB}[mod-a] \\
\assignedtask{Module B implementation}{2026-01-28}{2026-02-14}{40}{CD}[mod-b] \\
\assignedtask{Integration layer}{2026-02-10}{2026-02-21}{20}{AB}[integ] \\
\assignedtask{API development}{2026-02-17}{2026-02-28}{0}{CD}[api] \\
\ganttlink{scaffold}{mod-a}
\ganttlink{mod-a}{integ}
\ganttlink{mod-b}{integ}
\ganttlink{integ}{api}

% ---- Phase 3: Testing ----
\sectionsep
\ganttgroup[name=grp-test]{3. Testing}{2026-03-01}{2026-03-21} \\
\assignedtask{Unit test suite}{2026-03-01}{2026-03-07}{0}{AB}[unit] \\
\assignedtask{Integration tests}{2026-03-08}{2026-03-14}{0}{CD}[int-test] \\
\assignedtask{Performance testing}{2026-03-15}{2026-03-21}{0}{AB}[perf] \\
\ganttlink{grp-core}{grp-test}
\ganttlink{unit}{int-test}
\ganttlink{int-test}{perf}

% ---- Phase 4: Documentation ----
\sectionsep
\ganttgroup{4. Documentation}{2026-03-15}{2026-04-05} \\
\assignedtask{User documentation}{2026-03-15}{2026-03-28}{0}{CD}[user-doc] \\
\assignedtask{API reference}{2026-03-22}{2026-04-01}{0}{AB}[api-doc] \\
\assignedtask{Deployment guide}{2026-04-01}{2026-04-05}{0}{CD}[deploy-doc] \\

% ---- Milestones ----
\sectionsep
\ganttmilestone{Alpha Release}{2026-02-28} \\
\ganttmilestone{Beta Release}{2026-03-21} \\
\ganttmilestone{Final Release}{2026-04-10}

\end{ganttchart}
```

## Build System

### Makefile

```make
# Gantt Charts - LaTeX Build Pipeline
# ====================================

# Configuration
BUILD_DIR   := build
OUTPUT_DIR  := output
LATEX_ENGINE := -pdflua

# Chart documents (add new charts here)
CHARTS := project-alpha project-beta

# latexmk options
LATEXMK_OPTS := $(LATEX_ENGINE) \
	-output-directory=$(BUILD_DIR) \
	-shell-escape \
	-interaction=nonstopmode \
	-file-line-error

# Find all source files for dependency tracking
TEX_FILES := $(wildcard *.tex) $(wildcard Settings/*.tex) $(wildcard Charts/*.tex)

# Default target
.DEFAULT_GOAL := help

##@ Build Targets

pdf: $(OUTPUT_DIR)/project-alpha.pdf ## Build default chart

charts: $(foreach c,$(CHARTS),$(OUTPUT_DIR)/$(c).pdf) ## Build all charts

$(OUTPUT_DIR)/%.pdf: %.tex $(TEX_FILES) | $(BUILD_DIR) $(OUTPUT_DIR)
	@echo "Building $*.pdf..."
	@latexmk $(LATEXMK_OPTS) $<
	@cp $(BUILD_DIR)/$*.pdf $(OUTPUT_DIR)/
	@echo "Output: $(OUTPUT_DIR)/$*.pdf"

watch: | $(BUILD_DIR) $(OUTPUT_DIR) ## Continuous build on file changes
	@echo "Watching for changes (Ctrl+C to stop)..."
	@latexmk $(LATEXMK_OPTS) -pvc project-alpha.tex

##@ Cleanup

clean: ## Remove build artifacts
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR)
	@echo "Done."

distclean: clean ## Remove all generated files
	@echo "Removing output files..."
	@rm -rf $(OUTPUT_DIR)
	@echo "Done."

##@ Directories

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

$(OUTPUT_DIR):
	@mkdir -p $(OUTPUT_DIR)

##@ Utilities

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} \
		/^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

.PHONY: pdf charts watch clean distclean help
```

### .latexmkrc

```perl
# Use LuaLaTeX
$pdf_mode = 4;
$lualatex = 'lualatex -shell-escape -interaction=nonstopmode -file-line-error %O %S';

# Output directory
$out_dir = 'build';

# Clean extensions
$clean_ext = 'aux bbl bcf blg fdb_latexmk fls log out run.xml synctex.gz';
```

### .gitignore

```gitignore
build/
output/
*.aux
*.log
*.fls
*.fdb_latexmk
*.synctex.gz
```

## Usage

```bash
# Build single chart
make pdf

# Build all charts
make charts

# Watch for changes (live rebuild)
make watch

# Clean build artifacts
make clean

# Full clean including output
make distclean

# Show available targets
make help
```

## Key pgfgantt Options

| Option | Description |
|--------|-------------|
| `hgrid` | Horizontal grid lines |
| `vgrid` | Vertical grid lines |
| `x unit` | Width of one time unit |
| `y unit chart` | Height of chart rows |
| `bar height` | Height of task bars (0-1) |
| `group height` | Height of group bars |
| `progress` | Show progress on bars |
| `today` | Draw today line |
| `link/.append style` | Customize dependency arrows |

## Advanced: Date-Based Charts

The `\chartstart` and `\chartend` macros use ISO dates:

```latex
\edef\chartstart{2026-01-06}  % Monday
\edef\chartend{2026-04-10}

\begin{ganttchart}{\chartstart}{\chartend}
```

Tasks use the same format:

```latex
\ganttbar{Task Name}{2026-01-06}{2026-01-10}
```

The `\gantttitlecalendar` command auto-generates headers:

```latex
\gantttitlecalendar{month=name, week} \\  % Month names + week numbers
\gantttitlecalendar{year, month, day} \\  % Full date hierarchy
```

## Troubleshooting

### Weekend shading doesn't appear

Ensure you're using the `vgridweek` key:

```latex
vgridweek={draw=black!30}{draw=black!10, dashed},
weekend background=black!8,
```

### Links don't connect

Named elements must be defined before linking:

```latex
\ganttbar[name=task-a]{Task A}{1}{3} \\
\ganttbar[name=task-b]{Task B}{4}{6} \\
\ganttlink{task-a}{task-b}  % After both are defined
```

### Chart too wide/narrow

Adjust `x unit`:

```latex
x unit=0.15cm,  % Narrower (more days fit)
x unit=0.25cm,  % Wider (fewer days, more detail)
```

### Compilation slow

Use `latexmk` with `-pvc` for incremental builds, or pre-compile the preamble:

```latex
%&project-alpha  % Use precompiled format
```

## Summary

| Component | Purpose |
|-----------|---------|
| `Settings/` | Reusable styling and macros |
| `Charts/` | Individual chart content |
| `ganttconfig.tex` | Weekend shading, alternating rows |
| `\assignedtask` | Task with progress and assignee |
| `\sectionsep` | Visual phase separation |
| `Makefile` | Automated build pipeline |

This system scales from simple single-page charts to complex multi-project tracking. The modular structure means you can update styling in one place and regenerate all charts, while version control tracks every change to your project timeline.

---
title: "Batch SVG to TikZ Conversion for LaTeX Documents"
date: 2026-11-29 10:00:00 -0700
categories: [LaTeX, Tooling]
tags: [latex, tikz, svg, bash, scripting, graphics]
---

Converting vector graphics from SVG format to native TikZ code enables seamless integration with LaTeX documents while preserving editability and typographic consistency. This post examines a batch conversion wrapper script that streamlines the svg2tikz workflow for multi-file projects.

## Problem Statement

LaTeX documents frequently incorporate vector diagrams, flowcharts, and technical illustrations. Two primary approaches exist for including such graphics:

**External SVG inclusion** via `\includegraphics` or the `svg` package:
```latex
\usepackage{svg}
\includesvg[width=0.8\textwidth]{diagram}
```

**Native TikZ code** embedded directly or via `\input`:
```latex
\input{diagram.tex}
```

External SVG inclusion introduces several complications:

1. **Dependency on Inkscape**: The `svg` package shells out to Inkscape for PDF+LaTeX conversion during compilation, adding build complexity and time
2. **Font inconsistency**: Text within SVGs renders using embedded fonts rather than the document's typeface
3. **Difficult customization**: Modifying colors, line widths, or labels requires editing the original SVG
4. **Shell-escape requirement**: SVG conversion mandates `-shell-escape`, a security consideration in shared environments

Native TikZ code eliminates these issues. Graphics compile with the document, use document fonts, and remain editable as plain text.

## Technical Background

### TikZ vs. includegraphics

The `includegraphics` command from the `graphicx` package treats graphics as opaque objects. PDF and EPS files render correctly, but internal elements cannot be modified without regenerating the source file.

TikZ (from the German "TikZ ist kein Zeichenprogramm") provides a programmatic graphics language within LaTeX. Diagrams are defined using path operations:

```latex
\begin{tikzpicture}
\draw[thick, blue] (0,0) rectangle (3,2);
\node[anchor=center] at (1.5,1) {Label};
\end{tikzpicture}
```

Key advantages of TikZ:

| Aspect | includegraphics | TikZ |
|--------|-----------------|------|
| Font matching | Embedded only | Document fonts |
| Color schemes | Fixed | Uses `xcolor` definitions |
| Scaling | Rasterizes text at extremes | Vector at all scales |
| Version control | Binary diffs | Text diffs |
| Build dependencies | External tool chain | LaTeX only |

### Vector Fidelity

SVG and TikZ both represent graphics as vector operations. Conversion between formats preserves geometric fidelity. Bezier curves, paths, and transformations translate directly. However, SVG features without TikZ equivalents (filters, certain blend modes) may be approximated or dropped.

### The svg2tikz Tool

The `svg2tikz` utility parses SVG files and generates TikZ code. Installation proceeds via pipx:

```bash
pipx install svg2tikz
```

Basic usage:

```bash
svg2tikz --codeonly -o output.tex input.svg
```

The tool supports two output modes:

- **Code-only** (`--codeonly`): Generates a `tikzpicture` environment suitable for `\input{}` inclusion
- **Standalone** (`--standalone`): Generates a complete LaTeX document compilable to PDF

## Wrapper Script Design

Manual conversion of multiple SVG files becomes tedious. A wrapper script provides batch processing, skip logic for existing outputs, and progress reporting.

### Core Implementation

```bash
#!/usr/bin/env bash
# svg2tikz.sh - Convert SVG files to TikZ (.tex) using svg2tikz
#
# Usage:
#   svg2tikz.sh [directory]    Convert all .svg files in directory
#   svg2tikz.sh file.svg       Convert a single file
#   svg2tikz.sh -s [dir|file]  Standalone LaTeX document
#   svg2tikz.sh -h|--help      Show this help

set -euo pipefail

STANDALONE=false

usage() {
    sed -n '2,9s/^# //p' "$0"
    exit 0
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

if [[ "${1:-}" == "-s" ]]; then
    STANDALONE=true
    shift
fi

SVG2TIKZ="${SVG2TIKZ:-svg2tikz}"

if ! command -v "$SVG2TIKZ" &>/dev/null; then
    echo "Error: svg2tikz not found. Install with: pipx install svg2tikz" >&2
    exit 1
fi
```

### Error Handling

The `set -euo pipefail` directive enables strict error handling:

- `-e`: Exit immediately on command failure
- `-u`: Treat unset variables as errors
- `-o pipefail`: Pipeline fails if any component fails

This approach prevents silent failures that might leave partially converted files.

### Self-Documenting Usage

The usage function extracts documentation from the script header:

```bash
usage() {
    sed -n '2,9s/^# //p' "$0"
    exit 0
}
```

This technique keeps documentation synchronized with implementation. The `sed` command extracts lines 2-9, stripping the leading `# ` prefix.

### Environment Variable Override

```bash
SVG2TIKZ="${SVG2TIKZ:-svg2tikz}"
```

The `${VAR:-default}` syntax allows environment-based tool override. This pattern supports:

- Custom installations: `SVG2TIKZ=/opt/tools/svg2tikz ./svg2tikz.sh`
- Version testing: `SVG2TIKZ=svg2tikz-2.0 ./svg2tikz.sh`
- CI/CD environments with non-standard paths

### File Conversion Logic

```bash
convert_file() {
    local input="$1"
    local base="${input%.svg}"
    local outfile="${base}.tex"

    if [[ -f "$outfile" ]]; then
        echo "SKIP (exists): $(basename "$outfile")"
        return 0
    fi

    echo -n "Converting: $(basename "$input") -> $(basename "$outfile") ... "

    local mode_flag="--codeonly"
    $STANDALONE && mode_flag="--standalone"

    if "$SVG2TIKZ" $mode_flag -o "$outfile" "$input" 2>/dev/null; then
        echo "OK ($(du -h "$outfile" | cut -f1))"
    else
        echo "FAILED"
        rm -f "$outfile"
        return 1
    fi
}
```

Key design decisions:

1. **Skip existing files**: Prevents accidental overwrites and enables incremental conversion
2. **Progress output**: Reports source, target, and status on a single line
3. **File size reporting**: The `du -h` output indicates conversion success (non-empty file)
4. **Cleanup on failure**: Partial outputs are removed to prevent build errors

### Batch Processing

```bash
# Single file mode
if [[ -n "${1:-}" && -f "$1" ]]; then
    convert_file "$1"
    exit 0
fi

# Directory mode
dir="${1:-.}"

if [[ ! -d "$dir" ]]; then
    echo "Error: '$dir' is not a directory or file" >&2
    exit 1
fi

count=0
failed=0

for f in "$dir"/*.svg; do
    [[ -f "$f" ]] || continue

    if convert_file "$f"; then
        ((count++))
    else
        ((failed++))
    fi
done

echo ""
echo "Done: $count converted, $failed failed"
```

The script auto-detects single-file versus directory mode based on the argument type. Directory processing iterates over all `.svg` files, accumulating success and failure counts.

## Integration with LaTeX Workflow

### Code-Only Mode (Default)

Code-only output generates a `tikzpicture` environment without document preamble:

```latex
\begin{tikzpicture}[x=1pt, y=1pt]
  \path[draw=black, line width=0.5pt] (0,0) -- (100,50);
  % ... additional paths
\end{tikzpicture}
```

Include in a document with `\input`:

```latex
\documentclass{article}
\usepackage{tikz}

\begin{document}

\begin{figure}[h]
\centering
\input{diagram.tex}
\caption{System architecture diagram}
\end{figure}

\end{document}
```

Advantages:

- Document-level control over figure placement and captions
- Multiple diagrams share document packages and settings
- Diagram code remains separate for cleaner version control

### Standalone Mode

Standalone output generates a complete, compilable document:

```latex
\documentclass{standalone}
\usepackage{tikz}

\begin{document}
\begin{tikzpicture}[x=1pt, y=1pt]
  % ... paths
\end{tikzpicture}
\end{document}
```

Use cases for standalone mode:

- **Preview generation**: Compile individual diagrams to PDF for review
- **External inclusion**: Use `\includegraphics` on the compiled PDF
- **Testing**: Verify conversion results before integration

Generate standalone versions:

```bash
svg2tikz.sh -s diagrams/
```

Compile all standalone files:

```bash
for f in diagrams/*.tex; do
    pdflatex "$f"
done
```

### Makefile Integration

Automate conversion within a document build system:

```makefile
TIKZ_SOURCES := $(wildcard figures/*.svg)
TIKZ_OUTPUTS := $(TIKZ_SOURCES:.svg=.tex)

figures/%.tex: figures/%.svg
	svg2tikz.sh $<

tikz: $(TIKZ_OUTPUTS)

document.pdf: document.tex $(TIKZ_OUTPUTS)
	latexmk -pdf $<

clean:
	rm -f figures/*.tex
	latexmk -C

.PHONY: tikz clean
```

This configuration:

1. Converts SVG files on demand (only when source is newer)
2. Rebuilds the document when any diagram changes
3. Provides a `tikz` target for batch conversion without full compilation

## Practical Considerations

### Complex SVG Handling

Not all SVG features translate to TikZ. Problematic elements include:

| SVG Feature | TikZ Support | Workaround |
|-------------|--------------|------------|
| Gaussian blur | No | Remove or rasterize |
| Drop shadows | Partial | TikZ shadows library |
| Gradients | Limited | Solid fills or PGFplots shading |
| Embedded rasters | No | Separate `\includegraphics` |
| Text on path | Limited | Manual positioning |
| Clipping masks | Yes | Automatic conversion |

For complex graphics, consider a hybrid approach: convert structural elements to TikZ while keeping effects as a rasterized underlay.

### Path Simplification

Vector editors often generate verbose paths with excessive control points. Before conversion:

1. **Simplify paths**: Inkscape's Path > Simplify (Ctrl+L) reduces node count
2. **Convert objects to paths**: Shapes and text must be paths for conversion
3. **Ungroup elements**: Nested groups may not convert correctly
4. **Flatten transformations**: Apply transforms to coordinates rather than as attributes

### Manual Cleanup

Converted TikZ code may require adjustment:

```latex
% Before cleanup: absolute coordinates in points
\path[draw=black] (142.3622pt, 89.7638pt) -- (283.4646pt, 89.7638pt);

% After cleanup: relative coordinates in centimeters
\path[draw=black] (0,0) -- (5,0);
```

Common cleanup tasks:

- Convert absolute coordinates to relative
- Replace point units with centimeters or other LaTeX units
- Factor out repeated styles into TikZ styles
- Add semantic node names for cross-referencing

### Color Consistency

SVG colors convert as RGB values. For document-wide color schemes, replace hardcoded colors with `xcolor` definitions:

```latex
% In preamble
\definecolor{diagramblue}{RGB}{41,128,185}

% In diagram (manual edit)
\path[draw=diagramblue] ...
```

This enables global color changes without re-editing individual diagrams.

### Build Performance

Large TikZ diagrams slow compilation. Strategies for complex projects:

1. **Externalize**: Use TikZ externalization to cache compiled diagrams
   ```latex
   \usetikzlibrary{external}
   \tikzexternalize[prefix=cache/]
   ```

2. **Draft mode**: Replace diagrams with placeholders during writing
   ```latex
   \usepackage[draft]{graphicx}
   ```

3. **Selective compilation**: Build individual chapters with `\includeonly`

## Usage Examples

Convert all SVG files in the current directory:

```bash
svg2tikz.sh
```

Output:
```
Converting: flowchart.svg -> flowchart.tex ... OK (4.2K)
Converting: architecture.svg -> architecture.tex ... OK (8.7K)
SKIP (exists): logo.tex
Converting: network.svg -> network.tex ... FAILED

Done: 2 converted, 1 failed
```

Convert a specific directory with standalone output:

```bash
svg2tikz.sh -s figures/diagrams/
```

Override the svg2tikz binary location:

```bash
SVG2TIKZ=~/.local/bin/svg2tikz svg2tikz.sh figures/
```

## Conclusion

Batch conversion of SVG graphics to TikZ code integrates vector diagrams into LaTeX documents without external dependencies or font inconsistencies. The wrapper script presented here provides:

- **Batch processing** with automatic directory traversal
- **Incremental conversion** via skip logic for existing files
- **Dual output modes** for embedded code or standalone documents
- **Robust error handling** with progress reporting

The resulting TikZ code compiles with the document, uses document fonts, and remains editable as plain text. For projects with numerous diagrams, this approach reduces build complexity while improving maintainability.

---
title: "Part 4: LaTeX tcolorbox Environments for Technical Reports"
date: 2026-04-12 10:00:00 -0700
categories: [LaTeX, Documentation]
tags: [latex, tcolorbox, python, technical-writing, pdf]
series: "Executable Notebooks"
series_order: 4
---

Building a consistent visual language for technical reports using tcolorbox environments: results, validation status, warnings, and notes with a unified color scheme and Python helper functions.

> **Note:** Code examples in this post are simplified for illustration. The actual implementation may differ in details. A complete starter template is [available on Gumroad](https://derrekito.gumroad.com/).

## Problem Statement

Technical reports require visual hierarchy:
- Fitted parameters should stand out
- Validation results need pass/warning/fail colors
- Notes should be visually distinct from body text
- Style should be consistent across multiple documents

Hardcoding tcolorbox parameters leads to:
- 17 lines of boilerplate per box
- Inconsistent colors across documents
- Difficult style updates (find-replace across files)
- Verbose, unreadable notebook code

## Solution: Standardized Environments

Reusable tcolorbox environments are defined in a single `.tex` file, then called with one line.

### Before (Hardcoded)

```python
print(r"\begin{tcolorbox}[")
print(r"    enhanced,")
print(r"    colback=blue!5,")
print(r"    colframe=blue!60!black,")
print(r"    boxrule=1.5pt,")
print(r"    arc=1mm,")
print(r"    attach boxed title to top left={yshift=-2mm, xshift=5mm},")
print(r"    boxed title style={")
print(r"        colback=blue!60!black,")
print(r"        colframe=black!50,")
print(r"        boxrule=0.5pt,")
print(r"        arc=1mm")
print(r"    },")
print(r"    title={\textcolor{white}{\textbf{MY RESULT}}}")
print(r"]")
print("Content...")
print(r"\end{tcolorbox}")
```

### After (Standardized)

```python
begin_resultbox("MY RESULT")
print("Content...")
end_resultbox()
```

## Environment Definitions

Create `tcolorbox-environments.tex`:

```latex
% ========================================================================
% Standardized tcolorbox environments for notebooks
% ========================================================================

% Result box (blue) - Primary fitted parameters
\newtcolorbox{resultbox}[1][]{
    enhanced,
    colback=blue!5,
    colframe=blue!60!black,
    boxrule=1.5pt,
    arc=1mm,
    attach boxed title to top left={yshift=-2mm, xshift=5mm},
    boxed title style={
        colback=blue!60!black,
        colframe=black!50,
        boxrule=0.5pt,
        arc=1mm
    },
    #1
}

% Pass box (green) - Validation passes
\newtcolorbox{passbox}[1][]{
    enhanced,
    colback=green!5,
    colframe=green!70!black,
    boxrule=1.5pt,
    arc=1mm,
    attach boxed title to top left={yshift=-2mm, xshift=5mm},
    boxed title style={
        colback=green!70!black,
        colframe=black!50,
        boxrule=0.5pt,
        arc=1mm
    },
    #1
}

% Warning box (orange) - Borderline results
\newtcolorbox{warningbox}[1][]{
    enhanced,
    colback=yellow!10,
    colframe=orange!80!black,
    boxrule=1.5pt,
    arc=1mm,
    attach boxed title to top left={yshift=-2mm, xshift=5mm},
    boxed title style={
        colback=orange!80!black,
        colframe=black!50,
        boxrule=0.5pt,
        arc=1mm
    },
    #1
}

% Fail box (red) - Validation failures
\newtcolorbox{failbox}[1][]{
    enhanced,
    colback=red!5,
    colframe=red!70!black,
    boxrule=2.5pt,
    arc=1mm,
    attach boxed title to top left={yshift=-2mm, xshift=5mm},
    boxed title style={
        colback=red!70!black,
        colframe=black!50,
        boxrule=0.5pt,
        arc=1mm
    },
    #1
}
```

### Additional Environments

```latex
% Info box (blue, subtle) - Notes and explanations
\newtcolorbox{infobox}[1][]{
    enhanced,
    colback=blue!5,
    colframe=blue!40!black,
    boxrule=1pt,
    arc=1mm,
    attach boxed title to top left={yshift=-2mm, xshift=5mm},
    boxed title style={
        colback=blue!40!black,
        colframe=black!50,
        boxrule=0.5pt,
        arc=1mm
    },
    #1
}

% Summary box (gray) - Descriptive statistics
\newtcolorbox{summarybox}[1][]{
    colback=gray!5,
    colframe=gray!75,
    boxrule=1pt,
    arc=1mm,
    #1
}

% Note box (yellow/orange) - Inline warnings
\newtcolorbox{notebox}[1][]{
    colback=yellow!10,
    colframe=orange!60!black,
    boxrule=0.5pt,
    left=3mm,
    arc=1mm,
    #1
}

% Compact boxes (no titles)
\newtcolorbox{compactresult}[1][]{
    colback=blue!5,
    colframe=blue!60!black,
    boxrule=1pt,
    arc=1mm,
    left=2mm, right=2mm, top=2mm, bottom=2mm,
    #1
}

\newtcolorbox{compactnote}[1][]{
    colback=yellow!10,
    colframe=orange!60!black,
    boxrule=0.5pt,
    arc=1mm,
    left=3mm, right=3mm, top=2mm, bottom=2mm,
    #1
}
```

### Dynamic Color Box

For programmatic color selection:

```latex
% Status box - Color specified as parameter
% Usage: \begin{statusbox}{green!70!black}[title={...}]
\newtcolorbox{statusbox}[2][]{
    enhanced,
    colback=white,
    colframe=#2,
    boxrule=2.5pt,
    arc=2mm,
    attach boxed title to top left={yshift=-3mm, xshift=5mm},
    boxed title style={
        colback=#2,
        colframe=black,
        boxrule=1pt,
        arc=2mm
    },
    #1
}
```

## Color Scheme Reference

Consistent colors across all environments:

| Box Type | Frame Color | Background | Use Case |
|----------|-------------|------------|----------|
| **Result** | `blue!60!black` | `blue!5` | Fitted parameters |
| **Pass** | `green!70!black` | `green!5` | Validation passes |
| **Warning** | `orange!80!black` | `yellow!10` | Borderline results |
| **Fail** | `red!70!black` | `red!5` | Validation failures |
| **Info** | `blue!40!black` | `blue!5` | Notes, explanations |
| **Summary** | `gray!75` | `gray!5` | Data summaries |
| **Note** | `orange!60!black` | `yellow!10` | Inline warnings |

## Python Helper Functions

Create `print_helpers.py` to wrap the LaTeX:

```python
# Color constants
TCOLOR_PASS = "green!70!black"
TCOLOR_WARNING = "orange!80!black"
TCOLOR_FAIL = "red!70!black"
TCOLOR_RESULT = "blue!60!black"
TCOLOR_INFO = "blue!40!black"

def begin_resultbox(title="RESULT"):
    """Start a result box (blue) for primary findings."""
    print(r"\begin{resultbox}[title={\textcolor{white}{\textbf{" + title + r"}}}]")

def begin_passbox(title="PASS"):
    """Start a pass box (green) for validation passes."""
    print(r"\begin{passbox}[title={\textcolor{white}{\textbf{" + title + r"}}}]")

def begin_warningbox(title="WARNING"):
    """Start a warning box (orange) for borderline results."""
    print(r"\begin{warningbox}[title={\textcolor{white}{\textbf{" + title + r"}}}]")

def begin_failbox(title="FAIL"):
    """Start a fail box (red) for validation failures."""
    print(r"\begin{failbox}[title={\textcolor{white}{\textbf{" + title + r"}}}]")

def begin_infobox(title=None):
    """Start an info box (blue, subtle) for notes."""
    if title:
        print(r"\begin{infobox}[title={\textbf{" + title + r"}}]")
    else:
        print(r"\begin{infobox}")

def begin_statusbox(color, title="STATUS"):
    """Start a status box with dynamic color."""
    print(r"\begin{statusbox}{" + color + r"}[title={\textcolor{white}{\textbf{" + title + r"}}}]")

def end_resultbox():
    print(r"\end{resultbox}")

def end_passbox():
    print(r"\end{passbox}")

# ... etc for each environment
```

### Convenience Wrappers

```python
def print_in_resultbox(title, content_lines):
    """Print content in a complete result box."""
    begin_resultbox(title)
    if isinstance(content_lines, str):
        print(content_lines)
    else:
        for line in content_lines:
            print(line)
    end_resultbox()

def print_in_statusbox(status, title, content_lines):
    """Print content with dynamic pass/warning/fail color."""
    color_map = {
        "PASS": "green!70!black",
        "WARNING": "orange!80!black",
        "FAIL": "red!70!black"
    }
    color = color_map.get(status, "blue!60!black")
    begin_statusbox(color, title)
    if isinstance(content_lines, str):
        print(content_lines)
    else:
        for line in content_lines:
            print(line)
    end_statusbox()
```

## Notebook Usage

### Displaying Fitted Parameters

{% raw %}
```python
from src.print_helpers import begin_resultbox, end_resultbox

begin_resultbox("FITTED WEIBULL PARAMETERS")
print()
print(r"\begin{center}")
print(r"\begin{tabular}{lll}")
print(r"\toprule")
print(r"\textbf{Parameter} & \textbf{Value} & \textbf{Units} \\")
print(r"\midrule")
print(rf"$\sigma_{{\text{{sat}}}}$ & {sigma_sat:.3e} & cm$^2$/device \\")
print(rf"$\text{{LET}}_{{\text{{th}}}}$ & {let_th:.2f} & MeV$\cdot$cm$^2$/mg \\")
print(r"\bottomrule")
print(r"\end{tabular}")
print(r"\end{center}")
end_resultbox()
```
{% endraw %}

### Dynamic Validation Results

```python
from src.print_helpers import (
    begin_statusbox, end_statusbox,
    TCOLOR_PASS, TCOLOR_WARNING, TCOLOR_FAIL
)

# Determine status based on test
if dispersion_ratio < 1.5:
    color = TCOLOR_PASS
    status = "PASS"
elif dispersion_ratio < 2.0:
    color = TCOLOR_WARNING
    status = "WARNING"
else:
    color = TCOLOR_FAIL
    status = "FAIL"

begin_statusbox(color, f"OVERDISPERSION TEST: {status}")
print(rf"Dispersion ratio: $\phi = {dispersion_ratio:.3f}$")
print(rf"Classification: {'Acceptable' if status == 'PASS' else 'Review recommended'}")
end_statusbox()
```

### Nested Status Indicator

For prominent pass/fail display inside a box:

{% raw %}
```python
def print_status_indicator(status, icon):
    """Print a centered, prominent status indicator."""
    color_map = {
        "PASS": ("green!25", "green!70!black"),
        "WARNING": ("yellow!40!orange!60", "orange!80!black"),
        "FAIL": ("red!30", "red!70!black")
    }
    bg, frame = color_map.get(status, ("blue!10", "blue!60!black"))

    print(r"\begin{center}")
    print(r"\begin{tcolorbox}[")
    print(rf"    colback={bg},")
    print(rf"    colframe={frame},")
    print(r"    boxrule=2pt,")
    print(r"    arc=1mm,")
    print(r"    left=8mm, right=8mm, top=4mm, bottom=4mm,")
    print(r"    hbox")
    print(r"]")
    print(rf"\textbf{{\LARGE ${icon}$ {status}}}")
    print(r"\end{tcolorbox}")
    print(r"\end{center}")
```
{% endraw %}

Usage:

```python
print_status_indicator("PASS", r"\checkmark")
print_status_indicator("WARNING", r"\triangleright")
print_status_indicator("FAIL", r"\times")
```

## Complete Validation Check Example

A full validation function with dynamic styling:

{% raw %}
```python
def print_overdispersion_test(dispersion_ratio, variance, mean, n_obs):
    """Display overdispersion test with appropriate styling."""

    # Determine status
    if dispersion_ratio < 1.5:
        status, icon = "PASS", r"\checkmark"
        frame = "green!70!black"
        status_bg = "green!25"
        interpretation = "Variance consistent with Poisson"
        recommendation = "Proceed with Poisson statistics"
    elif dispersion_ratio < 2.0:
        status, icon = "WARNING", r"\triangleright"
        frame = "orange!80!black"
        status_bg = "yellow!40!orange!60"
        interpretation = "Mild overdispersion detected"
        recommendation = "Monitor goodness-of-fit metrics"
    else:
        status, icon = "FAIL", r"\times"
        frame = "red!70!black"
        status_bg = "red!30"
        interpretation = "Significant overdispersion"
        recommendation = "Consider Negative Binomial model"

    # Render the box
    print(r"\begin{tcolorbox}[")
    print(r"    enhanced, colback=white,")
    print(rf"    colframe={frame},")
    print(r"    boxrule=2pt, arc=2mm,")
    print(r"    attach boxed title to top left={yshift=-3mm, xshift=5mm},")
    print(r"    boxed title style={")
    print(rf"        colback={frame}, colframe=black, boxrule=1pt, arc=2mm")
    print(r"    },")
    print(r"    title={\textcolor{white}{\textbf{CHECK 1: OVERDISPERSION TEST}}}")
    print(r"]")

    # Dispersion ratio formula
    print(r"\noindent\textbf{Dispersion Ratio:}")
    print(rf"$$\phi = \frac{{s^2}}{{\hat{{\lambda}}}} = \frac{{{variance:.2f}}}{{{mean:.2f}}} = {dispersion_ratio:.3f}$$")

    # Status indicator
    print(r"\begin{center}")
    print(r"\begin{tcolorbox}[")
    print(rf"    colback={status_bg}, colframe={frame},")
    print(r"    boxrule=2pt, arc=1mm,")
    print(r"    left=8mm, right=8mm, top=4mm, bottom=4mm, hbox")
    print(r"]")
    print(rf"\textbf{{\LARGE ${icon}$ {status}}}")
    print(r"\end{tcolorbox}")
    print(r"\end{center}")

    # Interpretation and recommendation
    print(r"\noindent\textbf{Interpretation:} " + interpretation + r"\\")
    print(r"\noindent\textbf{Recommendation:} " + recommendation)

    print(r"\end{tcolorbox}")
```
{% endraw %}

## Template Integration

In the LaTeX template, load the environments:

```latex
% In template.latex preamble
\usepackage{tcolorbox}
\tcbuselibrary{skins,breakable}

% Load standardized environments
\input{tcolorbox-environments.tex}
```

Ensure the path is correct for the build system:

```bash
# In create_pdf.sh
export TEXINPUTS="${PIPELINE_DIR}/latex:"
```

## Benefits

1. **Consistency**: Same colors everywhere, update once
2. **Readability**: 3 lines instead of 17
3. **Maintainability**: Change style globally from one file
4. **Type safety**: Python functions with documentation
5. **Dynamic styling**: Pass/warning/fail colors based on data

## File Structure

```text
.pdf_pipeline/
├── latex/
│   ├── tcolorbox-environments.tex  # Environment definitions
│   └── template.latex               # Loads environments
└── docs/
    └── TCOLORBOX_USAGE.md           # Documentation

notebooks/
└── src/
    └── print_helpers.py             # Python wrappers
```

## Implementation Notes

### Avoiding Nesting Issues

tcolorbox can conflict with certain environments. For long boxes:

```latex
% Use breakable option for long boxes
\newtcolorbox{longbox}[1][]{
    breakable,  % Allow page breaks
    ...
}
```

### Custom One-Off Styling

Defaults can be overridden with the optional argument:

```latex
\begin{resultbox}[colframe=purple!60!black]
Custom purple frame for this box only
\end{resultbox}
```

### Debugging Color Issues

If colors appear incorrect, verify:
1. `xcolor` package is loaded
2. Color names use `!` syntax correctly: `green!70!black`
3. No conflicting color definitions exist

## Summary

Centralized tcolorbox environments convert verbose LaTeX boilerplate into clean, consistent styling. Key insights:

- **Define once**: All styling in `tcolorbox-environments.tex`
- **Wrap in Python**: Helper functions hide LaTeX complexity
- **Dynamic colors**: Status-based styling from runtime data
- **Document the scheme**: Color reference table for consistency

The full implementation is included in the [starter template on Gumroad](https://derrekito.gumroad.com/).

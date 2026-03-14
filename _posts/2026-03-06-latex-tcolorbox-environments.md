---
title: "Executable Notebooks (Part 4): LaTeX tcolorbox Environments for Technical Reports"
date: 2026-03-06
categories: [LaTeX, Documentation]
tags: [latex, tcolorbox, python, technical-writing, pdf]
series: "Executable Notebooks"
series_order: 4
---

Technical reports present multiple classes of information — fitted parameters, validation outcomes, warnings, and explanatory notes — that require distinct visual treatment. The `tcolorbox` package provides the mechanism, but using it directly in notebook code produces verbose, inconsistent output. This post defines a set of reusable tcolorbox environments and Python wrapper functions that reduce per-box boilerplate from 17 lines to one, enforce a consistent color scheme across documents, and support dynamic styling based on runtime data.

> **Note:** Code examples in this post are simplified for illustration. The actual implementation may differ in details. A complete starter template is [available on Gumroad](https://derrekito.gumroad.com/l/jtgyzf).

## The Problem with Inline Styling

In the executable notebook pipeline ([Part 1](/posts/executable-markdown-notebooks/)), Python code cells emit LaTeX via `print()`. The Pandoc toolchain captures stdout and compiles it into PDF. This works well for content, but styling each tcolorbox inline creates problems.

A single result box requires specifying colors, borders, title positioning, and arc radius every time:

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

Duplicating this across dozens of notebook cells produces three failure modes: color values drift between boxes when copied imprecisely, global style changes require find-and-replace across every notebook, and the notebook source becomes unreadable due to the LaTeX noise obscuring the actual analysis logic.

The solution separates environment definitions from usage. A single `.tex` file defines each box type once. Python helper functions wrap the `\begin` and `\end` calls. Notebook code reduces to:

```python
begin_resultbox("MY RESULT")
print("Content...")
end_resultbox()
```

## Environment Definitions

The environments divide into two categories: titled boxes with floating headers for primary content, and compact boxes without titles for inline annotations.

### Titled Boxes

Each titled box uses the `enhanced` skin to support the floating title feature. The `attach boxed title to top left` option positions a colored label above the box frame. The `#1` parameter passes through any optional overrides from the call site.

Create `tcolorbox-environments.tex`:

```latex
% ========================================================================
% Standardized tcolorbox environments for notebooks
% ========================================================================

% Result box (blue) - Primary fitted parameters and findings
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

% Warning box (orange) - Borderline results requiring review
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

% Fail box (red) - Validation failures; heavier border draws attention
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

The fail box uses a thicker `boxrule` (2.5pt vs 1.5pt) to create an immediate visual distinction from warnings. The color progression — blue for neutral results, green/orange/red for validation status — follows standard severity conventions and remains distinguishable in grayscale print.

### Compact and Utility Boxes

Not every annotation needs a floating title. Info boxes, summary boxes, and inline notes use simpler styling with lower visual weight:

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

% Summary box (gray) - Descriptive statistics, secondary data
\newtcolorbox{summarybox}[1][]{
    colback=gray!5,
    colframe=gray!75,
    boxrule=1pt,
    arc=1mm,
    #1
}

% Note box (yellow/orange) - Inline warnings and caveats
\newtcolorbox{notebox}[1][]{
    colback=yellow!10,
    colframe=orange!60!black,
    boxrule=0.5pt,
    left=3mm,
    arc=1mm,
    #1
}

% Compact result - Inline result without title
\newtcolorbox{compactresult}[1][]{
    colback=blue!5,
    colframe=blue!60!black,
    boxrule=1pt,
    arc=1mm,
    left=2mm, right=2mm, top=2mm, bottom=2mm,
    #1
}

% Compact note - Inline annotation without title
\newtcolorbox{compactnote}[1][]{
    colback=yellow!10,
    colframe=orange!60!black,
    boxrule=0.5pt,
    arc=1mm,
    left=3mm, right=3mm, top=2mm, bottom=2mm,
    #1
}
```

The info box uses `blue!40!black` rather than the result box's `blue!60!black` — a lighter frame that signals supplementary content. Summary and note boxes omit the `enhanced` skin entirely since they have no floating title, which reduces compilation overhead in documents with many boxes.

### Dynamic Color Box

Validation checks produce pass, warning, or fail outcomes determined at runtime. A fixed environment per status works for simple cases, but a single environment that accepts a color parameter handles arbitrary status logic without requiring a new `\newtcolorbox` definition for each:

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

The `statusbox` takes the color as its second mandatory argument (`#2`) and passes optional overrides through `#1`. Python code selects the color string at runtime and injects it directly.

## Color Scheme Reference

The following table documents the color assignments. Maintaining this reference prevents drift when adding new environments or modifying existing ones:

| Box Type | Frame Color | Background | Use Case |
|----------|-------------|------------|----------|
| **Result** | `blue!60!black` | `blue!5` | Fitted parameters, primary findings |
| **Pass** | `green!70!black` | `green!5` | Validation checks that pass |
| **Warning** | `orange!80!black` | `yellow!10` | Borderline results, review needed |
| **Fail** | `red!70!black` | `red!5` | Validation failures |
| **Info** | `blue!40!black` | `blue!5` | Notes, methodology explanations |
| **Summary** | `gray!75` | `gray!5` | Descriptive statistics, secondary data |
| **Note** | `orange!60!black` | `yellow!10` | Inline warnings, caveats |

All background tints use 5–10% saturation. Higher saturation makes body text harder to read, particularly in dense tables and mathematical expressions.

## Python Helper Functions

The notebook pipeline executes Python code and captures stdout as LaTeX. The helper functions bridge this boundary — each function emits the correct `\begin{...}` or `\end{...}` call with proper escaping and title formatting.

Create `print_helpers.py`:

```python
# Color constants matching tcolorbox-environments.tex
TCOLOR_PASS = "green!70!black"
TCOLOR_WARNING = "orange!80!black"
TCOLOR_FAIL = "red!70!black"
TCOLOR_RESULT = "blue!60!black"
TCOLOR_INFO = "blue!40!black"

def begin_resultbox(title="RESULT"):
    """Emit a result box opening with white bold title."""
    print(r"\begin{resultbox}[title={\textcolor{white}{\textbf{" + title + r"}}}]")

def begin_passbox(title="PASS"):
    """Emit a pass box opening with white bold title."""
    print(r"\begin{passbox}[title={\textcolor{white}{\textbf{" + title + r"}}}]")

def begin_warningbox(title="WARNING"):
    """Emit a warning box opening with white bold title."""
    print(r"\begin{warningbox}[title={\textcolor{white}{\textbf{" + title + r"}}}]")

def begin_failbox(title="FAIL"):
    """Emit a fail box opening with white bold title."""
    print(r"\begin{failbox}[title={\textcolor{white}{\textbf{" + title + r"}}}]")

def begin_infobox(title=None):
    """Emit an info box opening, optionally with a title."""
    if title:
        print(r"\begin{infobox}[title={\textbf{" + title + r"}}]")
    else:
        print(r"\begin{infobox}")

def begin_statusbox(color, title="STATUS"):
    """Emit a status box opening with dynamic color."""
    print(r"\begin{statusbox}{" + color + r"}[title={\textcolor{white}{\textbf{" + title + r"}}}]")

def end_resultbox():
    print(r"\end{resultbox}")

def end_passbox():
    print(r"\end{passbox}")

def end_warningbox():
    print(r"\end{warningbox}")

def end_failbox():
    print(r"\end{failbox}")

def end_infobox():
    print(r"\end{infobox}")

def end_statusbox():
    print(r"\end{statusbox}")
```

The color constants duplicate the values from `tcolorbox-environments.tex`. This duplication is intentional — the constants serve the `statusbox` path where Python selects the color at runtime, while the fixed environments carry their own colors internally. Keeping both in sync requires checking only two files.

### Convenience Wrappers

For simple cases where the box content is known upfront, a wrapper function handles the open-print-close sequence:

```python
def print_in_resultbox(title, content_lines):
    """Emit a complete result box with content."""
    begin_resultbox(title)
    if isinstance(content_lines, str):
        print(content_lines)
    else:
        for line in content_lines:
            print(line)
    end_resultbox()

def print_in_statusbox(status, title, content_lines):
    """Emit a complete status box with dynamic color."""
    color_map = {
        "PASS": TCOLOR_PASS,
        "WARNING": TCOLOR_WARNING,
        "FAIL": TCOLOR_FAIL
    }
    color = color_map.get(status, TCOLOR_RESULT)
    begin_statusbox(color, title)
    if isinstance(content_lines, str):
        print(content_lines)
    else:
        for line in content_lines:
            print(line)
    end_statusbox()
```

The `print_in_statusbox` function falls back to result blue if the status string does not match any known key. This prevents a missing color from producing an invalid LaTeX command.

## Usage in Notebooks

### Displaying Fitted Parameters

A common pattern: compute values in Python, then emit a LaTeX table inside a result box. The `begin_resultbox` / `end_resultbox` pair brackets the tabular output:

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

The double braces are Python f-string escapes — they produce single braces in the LaTeX output. This is the most common source of errors when mixing f-strings with LaTeX.

### Dynamic Validation Results

Validation checks determine their status at runtime and select the appropriate color. The `statusbox` environment handles this without conditional branching over separate box types:

```python
from src.print_helpers import (
    begin_statusbox, end_statusbox,
    TCOLOR_PASS, TCOLOR_WARNING, TCOLOR_FAIL
)

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

The threshold logic lives in Python where it belongs. The LaTeX layer receives only a color string and content — it has no knowledge of the validation rules.

### Nested Status Indicators

Some reports require a prominent pass/fail badge inside a larger box. A helper function emits a centered, inline tcolorbox with large text:

{% raw %}
```python
def print_status_indicator(status, icon):
    """Emit a centered pass/fail/warning badge."""
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

The `hbox` option shrinks the box to fit its content rather than spanning the text width. This produces a badge rather than a full-width bar. Usage:

```python
print_status_indicator("PASS", r"\checkmark")
print_status_indicator("WARNING", r"\triangleright")
print_status_indicator("FAIL", r"\times")
```

This indicator nests inside a `statusbox` or `resultbox` to combine a detailed report with a prominent visual verdict.

## Complete Validation Check Example

The following function combines all the patterns — dynamic color selection, mathematical formatting, a nested status indicator, and interpretive text — into a single validation report:

{% raw %}
```python
def print_overdispersion_test(dispersion_ratio, variance, mean, n_obs):
    """Emit a complete overdispersion test report with dynamic styling."""

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

    # Outer box with dynamic frame color
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

    # Nested status badge
    print(r"\begin{center}")
    print(r"\begin{tcolorbox}[")
    print(rf"    colback={status_bg}, colframe={frame},")
    print(r"    boxrule=2pt, arc=1mm,")
    print(r"    left=8mm, right=8mm, top=4mm, bottom=4mm, hbox")
    print(r"]")
    print(rf"\textbf{{\LARGE ${icon}$ {status}}}")
    print(r"\end{tcolorbox}")
    print(r"\end{center}")

    # Interpretation
    print(r"\noindent\textbf{Interpretation:} " + interpretation + r"\\")
    print(r"\noindent\textbf{Recommendation:} " + recommendation)

    print(r"\end{tcolorbox}")
```
{% endraw %}

This function uses raw tcolorbox commands rather than the predefined environments because it composes a nested layout — an outer titled box containing a formula, a centered badge, and interpretive text. The predefined environments handle the common single-level case; complex layouts like this one build directly on tcolorbox when the abstraction does not fit.

## Template Integration

The LaTeX template must load tcolorbox and the environment definitions. Add the following to the document preamble (typically in `template.latex`):

```latex
\usepackage{tcolorbox}
\tcbuselibrary{skins,breakable}

\input{tcolorbox-environments.tex}
```

The `skins` library enables the `enhanced` skin used by titled boxes. The `breakable` library allows long boxes to split across pages — without it, a box that exceeds the page height overflows into the margin.

The build script must include the directory containing `tcolorbox-environments.tex` in the TeX search path:

```bash
# In create_pdf.sh
export TEXINPUTS="${PIPELINE_DIR}/latex:"
```

The trailing colon preserves the default search path. Without it, standard packages become unfindable.

## Practical Notes

**Page breaks in long boxes.** Add the `breakable` option to any environment that might span more than a page. The `breakable` library must be loaded (see above). Breakable boxes incur a small compilation cost, so apply the option selectively rather than to every environment.

**Overriding defaults.** The `#1` passthrough parameter in each environment definition allows per-instance overrides without modifying the definition:

```latex
\begin{resultbox}[colframe=purple!60!black]
Custom purple frame for this instance only.
\end{resultbox}
```

**Color debugging.** If colors render incorrectly, verify that the `xcolor` package is loaded (tcolorbox loads it automatically, but explicit loads with conflicting options can interfere). The `!` mixing syntax (`green!70!black` means 70% green, 30% black) requires xcolor's `dvipsnames` or default color model.

**File organization.** The environment definitions live in the pipeline's `latex/` directory alongside `template.latex`. The Python helpers live in the notebook's `src/` directory. This separation keeps LaTeX concerns out of the notebook source tree and Python concerns out of the template.

```
.pdf_pipeline/
  latex/
    tcolorbox-environments.tex
    template.latex
notebooks/
  src/
    print_helpers.py
```

## Summary

Centralizing tcolorbox definitions into a single `.tex` file and wrapping them with Python helper functions converts verbose inline styling into single-line calls. The environment definitions encode the color scheme once; the Python layer handles title formatting, dynamic color selection, and the open/close lifecycle. Complex layouts that exceed the abstraction — nested boxes, conditional badges, combined formula-and-verdict reports — fall back to direct tcolorbox commands while still using the same color constants for consistency.

The full implementation is included in the [starter template on Gumroad](https://derrekito.gumroad.com/l/jtgyzf).

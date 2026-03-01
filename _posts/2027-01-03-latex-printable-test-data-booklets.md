---
title: "Generating Printable Test Data Booklets with LaTeX and LuaLaTeX"
date: 2027-01-03 10:00:00 -0700
categories: [Documentation, LaTeX]
tags: [latex, lualatex, booklet, printing, field-testing, data-collection]
---

Field data collection during radiation testing, beam experiments, and hardware validation often requires paper-based recording. Digital devices fail in high-radiation environments, batteries deplete during extended sessions, and electromagnetic interference corrupts electronic logging. A well-designed paper booklet—compact, durable, and purpose-built—remains an indispensable tool.

This post presents a LuaLaTeX solution for generating printable test data booklets with configurable layouts, cover pages, and proper imposition for saddle-stitch binding.

## Problem Statement

Paper-based data collection in field environments presents specific challenges:

**Environmental constraints**: Radiation beam halls, clean rooms, and outdoor test sites often prohibit or impair electronic devices. Tablets overheat, phones lose signal, and laptops run out of power.

**Reliability requirements**: Mission-critical experiments cannot depend on devices that might fail. A paper backup ensures data survival regardless of equipment malfunction.

**Ergonomic considerations**: Technicians wearing protective gear, working in confined spaces, or handling samples need compact, single-handed documentation tools. A pocket-sized booklet outperforms a clipboard.

**Reproducibility**: Each test session requires identical data collection forms. Manual photocopying introduces inconsistency; programmatic generation guarantees uniformity.

The solution: a LaTeX document that generates properly imposed booklets, ready for duplex printing and folding into pocket-sized field notebooks.

## Technical Background: Booklet Imposition

### Saddle-Stitch Binding

Saddle-stitch binding involves folding sheets in half and stapling along the spine. This technique produces compact booklets from standard printer paper without specialized binding equipment.

A single US Letter sheet (8.5" x 11"), printed in landscape orientation and folded, yields four half-letter pages (5.5" x 8.5" each). The challenge lies in **page imposition**—arranging content so that pages appear in correct reading order after folding.

### Imposition Mathematics

Consider an 8-page booklet made from two sheets:

| Sheet | Side | Left Position | Right Position |
|-------|------|---------------|----------------|
| 1 | Front | Page 8 | Page 1 |
| 1 | Back | Page 2 | Page 7 |
| 2 | Front | Page 6 | Page 3 |
| 2 | Back | Page 4 | Page 5 |

Manual calculation of these positions is error-prone. The LaTeX `booklet` package handles this automatically.

### The Booklet Package

The `booklet` package redefines page output to place two logical pages per physical sheet side:

```latex
\usepackage[print,twouparticle]{booklet}
```

Options explained:
- `print`: Enables booklet imposition (as opposed to `screen` mode for on-screen viewing)
- `twouparticle`: Places two article pages side-by-side on each physical page

Source and target dimensions must be specified:

```latex
\source{\magstep0}{8.5in}{11in}   % Original: portrait US Letter
\target{\magstep0}{11in}{8.5in}   % Target: landscape US Letter
```

The `\magstep0` parameter indicates no scaling (1:1 ratio). The source defines the logical page size (what the content sees), while the target defines the physical output size.

## LuaLaTeX Code Generation

### Rationale for Lua over Pure LaTeX Loops

LaTeX provides looping constructs through packages like `pgffor` or `multido`. However, these approaches suffer from several limitations when generating repetitive form content:

**Expansion complexity**: LaTeX's macro expansion rules create subtle bugs when loops interact with spacing commands and page breaks. Lua executes procedurally, eliminating expansion-order surprises.

**Readability**: Compare equivalent loops:

```latex
% Pure LaTeX approach
\foreach \i in {1,...,\value{linesperrun}} {%
  \vspace{0.3cm}\noindent\makebox[\BookletPageWidth]{\dotfill}\par%
}
```

```lua
-- Lua approach
for i = 1, tex.count.linesperrun do
  tex.sprint("\\vspace{0.3cm}\\noindent\\makebox[\\BookletPageWidth]{\\dotfill}\\par")
end
```

The Lua version requires no understanding of TeX's grouping semantics or when `%` is necessary to prevent spurious spaces.

**Conditional logic**: Complex conditionals (e.g., different spacing for the last run on a page) are straightforward in Lua but awkward in pure LaTeX.

**Debugging**: Lua errors provide line numbers and stack traces. LaTeX errors reference expansion contexts that may not correspond to source locations.

### Implementation Structure

The LuaLaTeX code defines two functions that generate the booklet content:

```lua
\begin{luacode}
-- Function: print_run()
-- Purpose: Print one run with a header and dotted lines for data entry.
function print_run()
  -- Print the run header with fill-in space
  tex.sprint("\\noindent Run \\#: \\\\ \\makebox[\\BookletPageWidth]{\\dotfill}\\par")
  -- Generate the specified number of data entry lines
  for i = 1, tex.count.linesperrun do
    tex.sprint("\\vspace{0.3cm}\\noindent\\makebox[\\BookletPageWidth]{\\dotfill}\\par")
  end
end

-- Function: print_booklet_page()
-- Purpose: Print one complete booklet page with multiple runs.
function print_booklet_page()
  -- Top margin prevents content from being clipped
  tex.sprint("\\vspace*{0.5in}")
  for run = 1, tex.count.runsperpage do
    print_run()
    -- Add spacing between runs except after the last one
    if run < tex.count.runsperpage then
      tex.sprint("\\vspace{0.4cm}")
    end
  end
end
\end{luacode}
```

The `tex.sprint()` function sends strings directly to the TeX engine for processing. The `tex.count.linesperrun` syntax accesses LaTeX counters from Lua.

A wrapper command exposes the Lua function to the document body:

```latex
\newcommand{\printpage}{\directlua{print_booklet_page()}}
```

## Layout Configuration

### Configurable Parameters

Three parameters control the booklet layout:

```latex
\newcount\runsperpage
\runsperpage=6

\newcount\linesperrun
\linesperrun=5

\newcommand{\BookletPageWidth}{5in}
```

**runsperpage**: The number of independent test runs recorded per page. Six runs fit comfortably on a half-letter page with standard margins.

**linesperrun**: Data entry lines per run. Five lines accommodate timestamp, measurement value, conditions, and notes.

**BookletPageWidth**: The effective content width. A landscape US Letter page (11" wide) split into two columns yields 5.5" per column. Setting the content width to 5" provides 0.25" margins on each side.

### Margin Calculations

The geometry package configures the physical page:

```latex
\usepackage[letterpaper,landscape]{geometry}
```

Combined with the booklet package's column splitting, each logical page occupies half the landscape width. The `BookletPageWidth` parameter should be set to:

```
BookletPageWidth = (physical_width / 2) - (2 * margin)
BookletPageWidth = (11in / 2) - (2 * 0.25in)
BookletPageWidth = 5.5in - 0.5in
BookletPageWidth = 5in
```

### Vertical Spacing

The Lua code inserts specific vertical spacing:

- `\vspace*{0.5in}`: Top margin on each page (starred version prevents suppression at page top)
- `\vspace{0.3cm}`: Between data entry lines within a run
- `\vspace{0.4cm}`: Between runs on the same page

These values optimize for handwriting legibility while maximizing data density.

## Cover Page Design

The first page of the booklet serves as a cover with essential metadata fields:

```latex
\begin{center}
  \Large\textbf{Test Data \& Notes}\\[0.75cm]
\end{center}
\noindent Date: \dotfill \hfill Day No: \dotfill\\[0.5cm]
\noindent Facility: \dotfill\\[0.5cm]
\noindent Title: \dotfill\\[0.5cm]
\noindent DUT: \dotfill
```

### Field Descriptions

**Date**: The calendar date of testing. Critical for correlating with facility beam schedules and environmental logs.

**Day No**: Sequential day count within a multi-day campaign. Useful when date changes mid-shift (overnight testing).

**Facility**: The test location (e.g., "NSRL Building 912", "TRIUMF BL2A"). Important for cross-referencing beam parameters.

**Title**: Experiment or test series name. Allows quick identification when booklets accumulate.

**DUT**: Device Under Test identifier. Serial numbers, sample IDs, or batch codes.

### Extending the Cover Page

Additional fields can be added for specific use cases:

```latex
\noindent Operator: \dotfill\\[0.5cm]
\noindent Beam Species: \dotfill \hfill Energy: \dotfill\\[0.5cm]
\noindent Flux Range: \dotfill\\[0.5cm]
\noindent Notes: \dotfill\\[0.5cm]
\noindent \phantom{Notes:} \dotfill
```

## Document Structure

The complete document body generates a four-page booklet (one sheet, folded):

```latex
\begin{document}

% Cover page
\begin{center}
  \Large\textbf{Test Data \& Notes}\\[0.75cm]
\end{center}
\noindent Date: \dotfill \hfill Day No: \dotfill\\[0.5cm]
% ... remaining cover fields ...

\clearpage

% Data collection pages
\printpage
\clearpage
\printpage
\clearpage
\printpage

\end{document}
```

Each `\printpage` call generates one logical page of data entry forms. Combined with the cover, this produces four pages—exactly what fits on one double-sided sheet when folded.

For longer booklets, add more `\printpage` blocks in multiples of four (to maintain proper sheet folding).

## Printing Workflow

### Compilation

LuaLaTeX is required due to the embedded Lua code:

```bash
lualatex main.tex
```

Standard `pdflatex` will fail with undefined `\directlua` errors.

### Printer Settings

Configure the printer for proper booklet output:

**Paper size**: US Letter (8.5" x 11")

**Orientation**: Landscape (the PDF is already landscape; do not rotate)

**Duplex mode**: Short-edge binding (flip on short edge). This is critical—long-edge binding produces upside-down backs.

**Scaling**: None (100% or "Actual size"). Scaling disrupts the careful margin calculations.

### Folding and Assembly

1. Print the PDF using the settings above
2. Collate sheets in order (if multiple sheets)
3. Fold the stack in half along the short axis, bringing the right edge to the left edge
4. Crease firmly along the fold
5. Staple twice along the spine, approximately 1" from top and bottom edges

A long-arm stapler simplifies reaching the spine on larger booklets. For single-sheet booklets, a standard stapler suffices.

### Quality Verification

Before mass production, verify the first booklet:

1. Pages appear in correct reading order (cover, page 2, page 3, back cover)
2. Content is not clipped at margins
3. Fold line falls between logical pages, not through content
4. Print quality is sufficient for handwritten entries

## Customization for Different Experiment Types

### Radiation Testing Configuration

Radiation effects testing typically involves repeated exposures with incremental fluence. A configuration optimized for this use case:

```latex
\runsperpage=8       % More runs, shorter duration each
\linesperrun=3       % Fewer measurements per run

% Custom run header
function print_run()
  tex.sprint("\\noindent Run \\#: \\rule{0.5in}{0.4pt} ")
  tex.sprint("Fluence: \\rule{1in}{0.4pt} ")
  tex.sprint("SEU Count: \\rule{0.75in}{0.4pt}\\par")
  for i = 1, tex.count.linesperrun do
    tex.sprint("\\vspace{0.2cm}\\noindent\\makebox[\\BookletPageWidth]{\\dotfill}\\par")
  end
end
```

### Environmental Chamber Testing

Thermal cycling and humidity testing benefit from temperature-focused layouts:

```latex
\runsperpage=4       % Longer thermal soak periods
\linesperrun=8       % More interim measurements

% Header with temperature field
function print_run()
  tex.sprint("\\noindent Temp: \\rule{0.75in}{0.4pt}$^{\\circ}$C ")
  tex.sprint("RH: \\rule{0.5in}{0.4pt}\\% ")
  tex.sprint("Time: \\rule{0.75in}{0.4pt}\\par")
  tex.sprint("\\vspace{0.2cm}")
  for i = 1, tex.count.linesperrun do
    tex.sprint("\\vspace{0.25cm}\\noindent\\makebox[\\BookletPageWidth]{\\dotfill}\\par")
  end
end
```

### Hardware Validation Checklist

For pass/fail testing, checkbox layouts replace fill-in lines:

```latex
function print_checkbox_run()
  tex.sprint("\\noindent\\textbf{Unit S/N:} \\rule{1.5in}{0.4pt}\\par")
  tex.sprint("\\vspace{0.2cm}")
  local checks = {"Power-on self-test", "Communication link", "Sensor calibration",
                  "Stress test (10 min)", "Final inspection"}
  for _, item in ipairs(checks) do
    tex.sprint("\\vspace{0.15cm}\\noindent$\\square$ " .. item .. "\\par")
  end
end
```

## Complete Source Listing

The full document source:

```latex
\documentclass{article}
\usepackage[print,twouparticle]{booklet}
\nofiles

% Booklet dimensions
\source{\magstep0}{8.5in}{11in}
\target{\magstep0}{11in}{8.5in}

\usepackage[letterpaper,landscape]{geometry}
\pagestyle{empty}

% Layout parameters
\newcount\runsperpage
\runsperpage=6

\newcount\linesperrun
\linesperrun=5

\newcommand{\BookletPageWidth}{5in}

% Lua code generation
\usepackage{luacode}

\begin{luacode}
function print_run()
  tex.sprint("\\noindent Run \\#: \\\\ \\makebox[\\BookletPageWidth]{\\dotfill}\\par")
  for i = 1, tex.count.linesperrun do
    tex.sprint("\\vspace{0.3cm}\\noindent\\makebox[\\BookletPageWidth]{\\dotfill}\\par")
  end
end

function print_booklet_page()
  tex.sprint("\\vspace*{0.5in}")
  for run = 1, tex.count.runsperpage do
    print_run()
    if run < tex.count.runsperpage then
      tex.sprint("\\vspace{0.4cm}")
    end
  end
end
\end{luacode}

\newcommand{\printpage}{\directlua{print_booklet_page()}}

\begin{document}

% Cover Page
\begin{center}
  \Large\textbf{Test Data \& Notes}\\[0.75cm]
\end{center}
\noindent Date: \dotfill \hfill Day No: \dotfill\\[0.5cm]
\noindent Facility: \dotfill\\[0.5cm]
\noindent Title: \dotfill\\[0.5cm]
\noindent DUT: \dotfill

\clearpage

% Data Pages
\printpage
\clearpage
\printpage
\clearpage
\printpage

\end{document}
```

## Conclusion

The combination of LaTeX's typographic precision, the booklet package's imposition handling, and LuaLaTeX's programmatic generation produces professional-quality field data collection booklets. The approach scales from simple note-taking forms to complex experiment-specific layouts, all while maintaining the reliability and reproducibility that paper-based systems provide in challenging field environments.

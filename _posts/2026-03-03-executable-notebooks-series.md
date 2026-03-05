---
title: "Executable Notebooks (Part 0): Series Overview"
date: 2026-03-03
categories: [Python, Documentation]
tags: [python, markdown, latex, pandoc, automation, reproducibility, series]
series: "Executable Notebooks"
series_order: 0
---

Technical analysis demands reproducibility. Results must trace back to source data through documented transformations. Traditional workflows fragment this chain: analysts explore in Jupyter, then manually transfer findings to Word or LaTeX documents. This series presents an alternative—a unified system where executable code and publication-quality prose coexist in plain Markdown files.

The framework described here emerged from radiation effects testing at national laboratories, where regulatory requirements mandate complete traceability from raw test data to final cross-section parameters. The same principles apply to any domain requiring auditable, reproducible technical documents.

## The Reproducibility Problem

Consider a typical analysis workflow. An engineer loads test data into a Jupyter notebook, fits a statistical model, generates plots, and interprets results. The notebook captures this exploration well. But the deliverable is a formal report—a PDF with institutional formatting, proper typography, citations, and appendices. The engineer now faces several problems:

1. **Manual transcription**: Copying results from notebook cells to a Word document introduces errors and breaks the audit trail.

2. **Version divergence**: The notebook evolves during review cycles, but the document lags behind. Which version generated the published numbers?

3. **Hidden state**: Jupyter's cell execution order matters. Running cells out of sequence produces different results. The saved notebook may not reflect the actual execution that produced the outputs.

4. **Format limitations**: Jupyter's PDF export handles basic cases but struggles with complex LaTeX, multi-file documents, or institutional templates.

5. **Collaboration friction**: JSON-based `.ipynb` files produce noisy diffs, making code review difficult.

These problems compound. A six-month-old report needs revision—can the original results be reproduced? Often, the answer is no.

## System Architecture

The executable notebook system addresses these problems through a layered pipeline:

```
Source Files        Preprocessor           Intermediate          Pandoc + Filters       Output
─────────────       ────────────           ────────────          ────────────────       ──────

Master.md      ──►  execute_and_expand.py  ──►  Master_executed.md  ──►  Lua/Python filters  ──►  PDF
    │                     │                          │                        │
    ▼                     ▼                          ▼                        ▼
!include          Execute Python         Fully expanded          Mermaid → PNG
directives        code blocks            Markdown with           Minted highlighting
                  Evaluate conditions    embedded outputs        Include resolution
section_01.md     Expand includes        and figures             LaTeX template
section_02.md     Track figures
common/theory.md
```

Each layer has a single responsibility:

**Preprocessor** (`execute_and_expand.py`): Parses Markdown, executes Python code blocks in sequence, evaluates conditional includes, and expands `!include` directives recursively. Output is pure Markdown with code outputs embedded.

**Pandoc filters**: Transform the expanded Markdown for LaTeX output. Lua filters handle fast operations (include resolution, notebook toggle). Python filters handle complex transformations (Mermaid diagram rendering, minted syntax highlighting).

**LaTeX compilation**: LuaLaTeX compiles the Pandoc output with institutional templates, custom environments, and bibliography processing.

## Code Block Semantics

The preprocessor recognizes several code block modifiers that control execution and output behavior:

**Standard block** — code executes, both code and output appear in PDF:

````python
```python
x = compute_result()
print(f"Result: {x}")
```
````

**Suppress** (`{.suppress}`) — execute but hide code from output:

````python
```python {.suppress}
import pandas as pd
df = pd.read_excel("data.xlsx")
```
````

**No execute** (`{.noexec}`) — display code without executing:

````python
```python {.noexec}
def example_function():
    pass  # This never runs
```
````

**LaTeX output** (`{.latex}`) — execute and treat output as raw LaTeX:

````python
```python {.latex}
print(r"\begin{resultbox}[title={Fitted Parameters}]")
print(rf"$\sigma_{{sat}} = {sigma:.2e}$ cm²/bit")
print(r"\end{resultbox}")
```
````

**No output** (`{.nooutput}`) — execute but suppress output display:

````python
```python {.nooutput}
fig.savefig("output/figure.pdf")
```
````

These modifiers compose. A block marked `{.suppress .nooutput}` executes silently—useful for data loading that produces verbose output.

## The Include Directive

Modular documents assemble from components via `!include` directives:

```markdown
# Main Report

!include sections/01_introduction.md
!include sections/02_methodology.md
!include sections/03_results.md

\appendix

!include common/theory/statistical_methods.md
!include common/theory/uncertainty_quantification.md
```

Includes resolve recursively—an included file may itself contain `!include` directives. This enables a library of reusable content:

```
common/
├── imports/
│   ├── standard_imports.md      # numpy, pandas, matplotlib
│   └── statistical_imports.md   # scipy.stats, bootstrap utilities
├── theory/
│   ├── weibull_theory.md        # Weibull function derivation
│   ├── bootstrap_theory.md      # Resampling methodology
│   └── deviance_test.md         # Goodness-of-fit testing
├── methods/
│   ├── data_validation.md       # Standard quality checks
│   └── uncertainty_reporting.md # CI formatting conventions
└── text/
    ├── test_facility.md         # Boilerplate facility descriptions
    └── acknowledgments.md       # Funding acknowledgments
```

A radiation testing notebook might include the Weibull theory appendix verbatim across multiple device reports—write once, maintain in one location.

## Persistent Execution State

All code blocks execute in a shared namespace. Variables defined in one block remain available in subsequent blocks:

````python
```python {.suppress}
# Block 1: Load data
import pandas as pd
df = pd.read_excel("test_data.xlsx")
n_samples = len(df)
```
````

Later in the document:

````python
```python
# Block 2: Reference earlier variables
print(f"Analysis of {n_samples} test points")
print(f"Fluence range: {df['fluence'].min():.2e} to {df['fluence'].max():.2e}")
```
````

This persistence enables natural document flow—introduce data early, reference it throughout. The preprocessor maintains a single `global_namespace` dictionary that accumulates state across all executed blocks.

## Figure Handling

The preprocessor patches `matplotlib.figure.Figure.savefig` to track saved figures. When a code block saves a PDF figure, the preprocessor automatically embeds a reference:

````python
```python {.suppress}
import matplotlib.pyplot as plt

fig, ax = plt.subplots()
ax.scatter(df['fluence'], df['cross_section'])
ax.set_xlabel(r'Fluence (ions/cm$^2$)')
ax.set_ylabel(r'Cross-Section (cm$^2$/bit)')
fig.savefig('output/cross_section_plot.pdf')
plt.close()
```
````

The executed Markdown automatically includes:

```markdown
![](output/cross_section_plot.pdf){width=80%}
```

This automation eliminates manual figure path management and ensures plots always reflect current code.

## Conditional Content

Include directives support runtime conditions based on execution state:

```markdown
!include results/detailed_analysis.md if show_details
!include results/summary_only.md if not show_details
```

The preprocessor evaluates `show_details` against the current namespace. This enables:

- **Configurable verbosity**: Set `notebook = True` for full derivations, `False` for executive summaries
- **Data-driven content**: Include device-specific sections based on which data files exist
- **Draft vs. final modes**: Include reviewer comments in drafts, exclude in final versions

## Directory Structure

A typical project organizes files by function:

```
project/
├── reports/
│   ├── Device_Master.md           # Main entry point
│   ├── Device_Sections/           # Report-specific sections
│   │   ├── 10_introduction.md
│   │   ├── 20_data_loading.md
│   │   ├── 30_analysis.md
│   │   └── 40_conclusions.md
│   ├── common/                    # Shared across reports
│   │   ├── imports/
│   │   ├── theory/
│   │   └── methods/
│   ├── scripts/
│   │   └── execute_and_expand.py
│   ├── src/                       # Python utilities
│   │   ├── plotting.py
│   │   └── statistics.py
│   ├── data/                      # Input data files
│   ├── output/                    # Generated figures (gitignored)
│   └── pdf/                       # Generated PDFs (gitignored)
├── .pdf_pipeline/                 # Conversion infrastructure
│   ├── latex/
│   │   ├── template.latex
│   │   ├── preamble.latex
│   │   ├── tcolorbox-environments.tex
│   │   └── filters/
│   │       ├── include-files.lua
│   │       ├── notebook-toggle.lua
│   │       ├── pandoc-mermaid.py
│   │       └── pandoc-minted.py
│   ├── assets/
│   │   └── logo.pdf
│   └── scripts/
│       └── build-pdf.sh
├── .validation/                   # Pre-commit hooks
│   └── scripts/
│       ├── formatting-validator.sh
│       ├── structural-validator.sh
│       └── citation-validator.sh
├── Makefile                       # Build automation
└── references/
    └── bibliography.bib
```

The numbered prefix convention (`10_`, `20_`, etc.) ensures consistent ordering when listing files and provides natural groupings:

| Range | Purpose |
|-------|---------|
| 00-09 | Setup, configuration |
| 10-19 | Introduction, background |
| 20-29 | Data loading, exploration |
| 30-39 | Analysis, modeling |
| 40-49 | Uncertainty quantification |
| 50-59 | Visualization |
| 60-69 | Conclusions, summary |

## Build Automation

A Makefile orchestrates the pipeline:

```make
NOTEBOOK ?= Device
SCRIPTS := reports/scripts
PIPELINE := .pdf_pipeline/scripts

.PHONY: report
report:
    @echo "Executing $(NOTEBOOK)..."
    python $(SCRIPTS)/execute_and_expand.py \
        reports/$(NOTEBOOK)_Master.md \
        --output reports/$(NOTEBOOK)_Master_executed.md
    @echo "Building PDF..."
    $(PIPELINE)/build-pdf.sh reports/$(NOTEBOOK)_Master_executed.md
    @echo "Done: reports/pdf/$(NOTEBOOK)_Master_executed.pdf"

.PHONY: clean
clean:
    rm -f reports/*_executed.md
    rm -rf reports/output/*
    rm -rf reports/pdf/*
```

Build a specific report:

```bash
make report NOTEBOOK=BrainChip
```

Or use interactive selection (requires `fzf`):

```bash
make report  # Presents menu of available Master files
```

## Comparison with Jupyter

| Aspect | Jupyter | This System |
|--------|---------|-------------|
| Source format | JSON (`.ipynb`) | Plain Markdown |
| Version control | Noisy diffs, merge conflicts | Clean text diffs |
| Execution order | Arbitrary (hidden state bugs) | Sequential, deterministic |
| Modular composition | Single file | `!include` hierarchy |
| Conditional content | Not supported | Runtime evaluation |
| PDF output | nbconvert (limited) | Full LaTeX control |
| Institutional templates | Difficult | Native support |
| Bibliography | Manual | BibTeX integration |
| Reproducibility | Cell order dependent | Guaranteed by design |

Jupyter excels at interactive exploration. This system excels at producing auditable deliverables from that exploration.

## Validation Pipeline

Technical documents accumulate errors. A pre-commit validation pipeline catches them before they enter version control:

**Formatting validation**: Enforces LaTeX math in prose (`$\sigma$`) and Unicode in Python code (`σ`), except for plot labels which require LaTeX.

**Structural validation**: Verifies all `!include` paths resolve to existing files.

**Citation validation**: Cross-references `\cite{}` commands against `bibliography.bib`.

**Clean checks**: Prevents committing generated files (`*_executed.md`, `output/*`).

These validators run automatically via git pre-commit hooks, providing immediate feedback during development.

## Technical Requirements

| Component | Purpose | Version |
|-----------|---------|---------|
| Python | Preprocessor, filters, analysis | 3.10+ |
| Pandoc | Markdown → LaTeX conversion | 3.0+ |
| TeX Live | PDF compilation | Full install |
| LuaLaTeX | Modern font support, Unicode | Via TeX Live |
| Node.js | Mermaid diagram rendering | 16+ (optional) |

The full TeX Live installation provides necessary packages for tcolorbox, minted, and other advanced LaTeX features. Minimal installations require manual package management.

## Limitations

**Not interactive**: The system optimizes for batch execution and document generation. For interactive exploration, use standard tools (IPython, vim-medieval) then run the full preprocessor for final output.

**Python-centric**: The preprocessor executes Python. Extension to other languages is architecturally possible but has not been implemented.

**LaTeX dependency**: PDF generation requires a working LaTeX installation. For simpler outputs (HTML, DOCX), Pandoc can target those formats directly with reduced fidelity.

**Single namespace**: All code blocks share state. This is a feature for document flow but requires discipline to avoid variable collisions in large documents.

## Series Contents

This series covers the complete system in four parts:

### Part 1: Reproducible Analysis Notebooks

The preprocessor implementation. Topics include code block parsing, execution with persistent state, include expansion, figure tracking, and the output assembly process.

[**Read Part 1 →**](/posts/executable-markdown-notebooks/)

### Part 2: Custom Pandoc Filters

Extending Pandoc for technical documents. Topics include Lua filters for performance-critical operations, Python filters for complex transformations, Mermaid diagram rendering, minted syntax highlighting, and filter composition.

[**Read Part 2 →**](/posts/custom-pandoc-filters/)

### Part 3: Pre-commit Validation

Quality gates for technical documents. Topics include formatting validation, structural integrity checks, citation verification, and git hook integration.

[**Read Part 3 →**](/posts/precommit-validation-technical-docs/)

### Part 4: LaTeX tcolorbox Environments

Visual hierarchy for technical reports. Topics include standardized environment definitions, color schemes, Python helper functions for dynamic styling, and integration with the preprocessing pipeline.

[**Read Part 4 →**](/posts/latex-tcolorbox-environments/)

Each post provides working code. A complete starter template is [available on Gumroad](https://derrekito.gumroad.com/).

## Summary

This system transforms Markdown from a documentation format into an executable analysis environment. The key architectural decisions:

1. **Plain text sources**: Markdown files version-control cleanly and diff readably.
2. **Explicit execution model**: Sequential block execution eliminates hidden state.
3. **Composable includes**: Modular content enables reuse across documents.
4. **Layered pipeline**: Each component (preprocessor, filters, LaTeX) handles one concern.
5. **Validation at commit**: Errors caught early cost less to fix.

The result is a workflow where analysis code and publication prose evolve together, where every number in a final PDF traces back to source data through documented transformations, and where six-month-old reports regenerate identically from version-controlled sources.

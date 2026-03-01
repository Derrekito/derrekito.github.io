---
title: "Part 0: Executable Notebooks - Series Overview"
date: 2026-03-15 10:00:00 -0700
categories: [Python, Documentation]
tags: [python, markdown, latex, pandoc, automation, reproducibility, series]
series: "Executable Notebooks"
series_order: 0
---

A custom notebook system for technical reports that executes Python code embedded in Markdown and generates publication-ready PDFs. No Jupyter required. This series covers the complete pipeline from executable Markdown to polished technical documents.

## Problem Statement

Technical analysis requires a workflow that:
- Embeds executable code alongside prose
- Generates professional PDFs with LaTeX formatting
- Supports modular, reusable content via includes
- Allows conditional content based on runtime data
- Keeps source files clean and version-controllable

Jupyter notebooks excel at exploration but are awkward for document generation. LaTeX excels at documents but is cumbersome for code execution. This series presents a system that combines both capabilities.

## Architecture Overview

```text
Data File (Excel/CSV)
    ↓
Master.md (with !include directives)
    ↓
execute_and_expand.py  ← Executes Python, evaluates conditions
    ↓
Master_executed.md (fully expanded)
    ↓
Pandoc + Custom Filters
    ↓
LuaLaTeX
    ↓
Final PDF
```

## Series Contents

### Part 1: Reproducible Analysis Notebooks

**[Read Part 1 →](/posts/executable-markdown-notebooks/)**

The core system: a Python preprocessor that executes code blocks, processes includes, and handles dynamic content assembly.

This post covers:
- Code block modifiers (`.suppress`, `.noexec`, `.latex`)
- The `!include` directive for modular documents
- Persistent state across code blocks
- Auto-embedding of matplotlib figures
- Data-driven document assembly

**Significance**: The preprocessor serves as the foundation. It transforms static Markdown into executable documents where code and prose coexist naturally.

---

### Part 2: Custom Pandoc Filters

**[Read Part 2 →](/posts/custom-pandoc-filters/)**

Pandoc transforms Markdown to LaTeX, but technical documents need custom handling for diagrams, syntax highlighting, and conditional display.

This post covers:
- Lua filters for speed (include files, notebook toggle)
- Python filters for complexity (Mermaid diagrams, minted highlighting)
- TikZ to PNG rendering for non-LaTeX outputs
- Caching for expensive operations
- Filter ordering and debugging

**Significance**: Filters bridge the gap between Markdown simplicity and LaTeX power. They handle transformations that Pandoc does not support natively.

---

### Part 3: Pre-commit Validation

**[Read Part 3 →](/posts/precommit-validation-technical-docs/)**

Technical documents accumulate subtle errors. A pre-commit validation pipeline catches them before they enter the repository.

This post covers:
- Formatting validation (LaTeX vs Unicode rules)
- Structural validation (`!include` path resolution)
- Citation validation (bibliography cross-reference)
- Clean checks (preventing generated file commits)
- Git hook integration

**Significance**: Validation at commit time is the cheapest place to catch errors. The cost of fixing increases exponentially once changes are merged.

---

### Part 4: LaTeX tcolorbox Environments

**[Read Part 4 →](/posts/latex-tcolorbox-environments/)**

Technical reports need visual hierarchy: results, validations, warnings. Standardized tcolorbox environments provide consistent styling with minimal code.

This post covers:
- Reusable environment definitions
- Color scheme reference
- Python helper functions
- Dynamic pass/warning/fail styling
- Integration with the preprocessing pipeline

**Significance**: Consistent visual language makes reports scannable. Readers immediately recognize fitted parameters vs validation results vs warnings.

---

## Technical Requirements

| Component | Purpose | Minimum |
|-----------|---------|---------|
| Python 3.10+ | Preprocessor, filters | Required |
| Pandoc 3.0+ | Markdown → LaTeX | Required |
| TeX Live | PDF compilation | Full install recommended |
| Node.js | Mermaid diagrams | Optional |

## Design Rationale

**Comparison with Jupyter**

| Feature | Jupyter | This System |
|---------|---------|-------------|
| Version control | Awkward (JSON) | Clean (Markdown) |
| Modular includes | No | Yes |
| Conditional content | No | Yes |
| LaTeX output | Limited | Native |
| PDF generation | nbconvert (limited) | Full LaTeX |
| Reproducibility | Cell order issues | Sequential by design |

**Rationale for Pandoc + LuaLaTeX**

- Pandoc handles Markdown parsing and AST transformation
- Lua filters are fast and native to Pandoc
- LuaLaTeX supports modern fonts and Unicode
- The pipeline is fully scriptable and automatable

**Rationale for Bash Validation**

- No dependencies beyond git and coreutils
- Fast for line-by-line text processing
- Integrates naturally with git hooks
- Easy to extend with new validators

## Limitations

- **Not interactive**: No cell-by-cell execution during development
- **Python only**: Extension to other languages is possible but has not been needed
- **Requires LaTeX**: Full TeX Live install for PDF generation
- **Single namespace**: All code shares state (feature and limitation)

For interactive development, vim-medieval or similar tools can execute individual blocks, then the full preprocessor runs for document generation.

## Getting Started

1. **Start with Part 1** to understand the preprocessor and code block modifiers
2. **Part 2** for custom Pandoc filters as needed
3. **Part 3** when ready to enforce quality gates
4. **Part 4** for polished visual output

Each post is self-contained with working code examples. A complete starter template with all features is [available on Gumroad](https://derrekito.gumroad.com/).

## Summary

This system transforms Markdown from a documentation format into an executable analysis environment. The key insight: treating `!include` directives as executable enables data-driven document assembly. Combined with Pandoc's flexibility and LaTeX's typesetting, reproducible, professional technical documents can be generated from plain text sources.

---

## Series Index

1. [Reproducible Analysis Notebooks](/posts/executable-markdown-notebooks/)
2. [Custom Pandoc Filters](/posts/custom-pandoc-filters/)
3. [Pre-commit Validation](/posts/precommit-validation-technical-docs/)
4. [LaTeX tcolorbox Environments](/posts/latex-tcolorbox-environments/)

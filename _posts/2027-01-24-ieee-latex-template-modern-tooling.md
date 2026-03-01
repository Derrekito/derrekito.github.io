---
title: "Enhanced IEEE Conference Paper Template with Modern LaTeX Tooling"
date: 2027-01-24 10:00:00 -0700
categories: [LaTeX, Academic Writing]
tags: [latex, ieee, docker, biblatex, microtype, minted, academic, reproducibility]
---

The standard IEEEtran template provides a solid foundation for conference papers but lacks integration with modern LaTeX tooling. This post describes an enhanced template that addresses typography, bibliography management, code formatting, and build reproducibility while maintaining IEEE format compliance.

## Problem Statement: Vanilla IEEEtran Limitations

The stock IEEEtran class handles layout and formatting but leaves authors to configure numerous auxiliary packages independently. Common pain points include:

- **No microtypography**: Text justification produces uneven spacing and occasional bad boxes
- **Legacy BibTeX**: Manual bibliography sorting, limited URL handling, inflexible citation styles
- **No code highlighting**: Verbatim environments offer no syntax coloring
- **Environment inconsistency**: Different TeX distributions produce different output
- **Monolithic source files**: Large single-file documents become unwieldy

An enhanced template addresses these issues through careful package selection and a modular project structure.

## Microtype Integration

The `microtype` package enables optical margin alignment (protrusion) and font expansion, producing visually superior justified text. Configuration requires attention to code listings:

```latex
\usepackage[
  babel=false,
  expansion=alltext,
  protrusion=alltext-nott,
  final
]{microtype}
```

Key options:

- **`expansion=alltext`**: Applies subtle font stretching/shrinking to improve line breaks across all text
- **`protrusion=alltext-nott`**: Enables character protrusion (hanging punctuation) except for typewriter fonts
- **`final`**: Forces microtype activation even in draft mode, ensuring consistent output during review

The `alltext-nott` protrusion setting prevents margin distortion in code blocks. Without this exclusion, monospaced characters would protrude into margins, disrupting the visual alignment of code listings.

## Biblatex vs BibTeX: Modern Bibliography Management

The traditional BibTeX workflow (`.bst` files, `\cite`, manual sorting) dates to the 1980s. Biblatex with the Biber backend provides significant advantages:

```latex
\usepackage[
  backend=biber,
  bibstyle=ieee,
  citestyle=numeric-comp
]{biblatex}

\addbibresource{bib/bibliography.bib}
\addbibresource{bib/nvidia.bib}
\addbibresource{bib/arm.bib}
```

### Advantages Over BibTeX

**Multiple bibliography files**: The `\addbibresource` command allows organizing references by topic. Vendor-specific citations (ARM architecture manuals, NVIDIA CUDA documentation) can reside in dedicated files, simplifying maintenance.

**Compressed citations**: The `citestyle=numeric-comp` option compresses consecutive citations. A sequence like `[1][2][3][4]` becomes `[1-4]`, conserving space in the strict IEEE page limits.

**Unicode support**: Biber handles UTF-8 natively. Author names with accents, Greek symbols in titles, and non-ASCII characters process correctly without escape sequences.

**Field aliasing**: Biblatex maps non-standard fields intelligently. An `archiveprefix = {arXiv}` entry works without custom `.bst` modifications.

### IEEEtriggeratref for Column Balancing

The template redefines `\IEEEtriggeratref` to work with Biblatex:

```latex
\makeatletter
\newcounter{IEEE@bibentries}
\renewcommand\IEEEtriggeratref[1]{%
  \renewbibmacro{finentry}{%
    \stepcounter{IEEE@bibentries}%
    \ifthenelse{\equal{\value{IEEE@bibentries}}{#1}}
    {\finentry\@IEEEtriggercmd}
    {\finentry}%
  }%
}
\makeatother
```

This macro triggers column balancing after a specified reference number, producing even columns on the final page. Usage: `\IEEEtriggeratref{42}` inserts a column break after reference 42.

## URL Handling with biburllcpenalty

Long URLs in references frequently cause overfull boxes. The `url` package alone cannot break URLs at arbitrary points. Biblatex provides penalty counters:

```latex
\usepackage{url}
\setcounter{biburllcpenalty}{4000}
```

The `biburllcpenalty` counter controls the penalty for breaking URLs after lowercase letters. A value of 4000 (on a scale where 10000 prohibits breaks) allows breaks at most lowercase characters while preferring natural break points like slashes and hyphens.

For more aggressive breaking, `biburlucpenalty` handles uppercase letters:

```latex
\setcounter{biburlucpenalty}{8000}
```

Higher values preserve URL readability but risk overfull boxes. The value 4000/8000 combination balances these concerns for typical conference paper URLs.

## Minted Code Blocks

The `minted` package uses Pygments for syntax highlighting, producing superior output compared to `listings`:

```latex
\usepackage{minted}

\setminted{
  fontsize=\footnotesize,
  framesep=3mm,
  baselinestretch=1.2,
  linenos,
  numbersep=0pt,
  bgcolor=gray!5,
  frame=single,
  fontfamily=tt,
  breaklines=true,
  tabsize=2,
  obeytabs=false
}
```

### Shell-Escape Implications

Minted requires `--shell-escape` because it invokes Pygments externally:

```bash
latexmk -pdflua -shell-escape paper.tex
```

Security considerations:

- **Controlled environments only**: Shell-escape allows arbitrary command execution. Building untrusted documents is inadvisable.
- **Docker isolation**: Containerized builds mitigate risk by limiting host access.
- **CI/CD awareness**: Build pipelines must explicitly enable shell-escape.

### Monospace Font Selection

The default Computer Modern Typewriter font lacks visual weight. The `newtxtt` package provides a heavier alternative:

```latex
\usepackage[zerostyle=b,scaled=.75]{newtxtt}
```

Options:

- **`zerostyle=b`**: Renders zeros with a diagonal slash, distinguishing `0` from `O`
- **`scaled=.75`**: Reduces font size to approximately match body text x-height

## Docker Build Workflow

Environment inconsistency produces the dreaded "works on my machine" scenario. Docker eliminates this by containerizing the TeX distribution.

### Makefile Integration

```makefile
DOCKER_IMAGE := latex-slides-env
DOCKER_CACHE_VOL := latex-cache
DOCKER_RUN := docker run --rm -u $(shell id -u):$(shell id -g) \
    -v "$(shell pwd):/app" \
    -v $(DOCKER_CACHE_VOL):/tmp \
    -e TEXMFVAR=/tmp/texmf-var \
    -w /app $(DOCKER_IMAGE)

%.pdf: %.tex docker-image
    @mkdir -p build output
    $(DOCKER_RUN) sh -c "latexmk -pdflua -use-make -shell-escape $< \
        -f -interaction=batchmode \
        -jobname=$(basename $@) \
        -output-directory=build \
        -out2dir=output"
```

### Build Features

**User mapping**: The `-u $(shell id -u):$(shell id -g)` flag ensures output files have correct ownership. Without this, files would be owned by root.

**Cache volume**: The `latex-cache` volume persists font caches and auxiliary files across builds. Subsequent compilations complete significantly faster.

**Separate directories**: Auxiliary files (`*.aux`, `*.log`, `*.bbl`) go to `build/`. Final PDFs go to `output/`. This separation simplifies cleanup and artifact collection.

**Automatic image building**: The `docker-image` target builds the container only if it does not exist, checking for a local Dockerfile or falling back to a sibling project.

### Reproducibility Guarantees

The Docker image pins:

- TeX Live version
- Pygments version (for minted)
- System fonts
- LuaTeX engine version

Builds from the same source on any machine with Docker produce byte-identical PDFs (modulo timestamp metadata).

## Modular Section Organization

Large papers benefit from file separation:

```text
paper.tex
sections/
    00_Titlepage.tex
    01_Abstract.tex
    10_Introduction.tex
    20_Background.tex
    30_Methodology.tex
    40_Results.tex
    50_Conclusion.tex
settings/
    paper-preamble.tex
    paper-colors.tex
    paper-minted.tex
bib/
    bibliography.bib
    nvidia.bib
    arm.bib
```

### Numbering Convention

The numeric prefixes (00, 01, 10, 20...) provide two benefits:

1. **Sort order**: File managers and command-line tools display sections in logical order
2. **Gap allowance**: The 10-increment spacing permits inserting new sections (e.g., `15_RelatedWork.tex`) without renumbering

### Main Document Structure

The root `paper.tex` remains minimal:

```latex
\documentclass[conference]{IEEEtran}

\input{settings/paper-preamble}

\addbibresource{bib/bibliography.bib}
\addbibresource{bib/nvidia.bib}
\addbibresource{bib/arm.bib}

\title{Paper Title}

\begin{document}
\maketitle

\input{sections/00_Titlepage}
\input{sections/01_Abstract}
\input{sections/10_Introduction}
\input{sections/20_Background}
\input{sections/30_Methodology}
\input{sections/40_Results}

\section*{Acknowledgments}
...

\IEEEtriggeratref{42}
\printbibliography

\end{document}
```

Changes to individual sections do not require touching the main file. Co-authors can work on separate sections with reduced merge conflicts.

## Column Balancing with pbalance

IEEE conference papers frequently end with unbalanced columns on the final page. The `pbalance` package addresses this:

```latex
\usepackage{pbalance}
```

Unlike `balance` or manual `\vfill` insertions, `pbalance` handles footnotes and floats correctly. The package automatically balances columns on the last page without author intervention.

For bibliography placement specifically, `\IEEEtriggeratref` provides finer control by inserting a column break at a specific reference number.

## Additional Conveniences

### Table Macros

Common column operations receive shorthand commands:

```latex
\newcommand{\mc}[2]{\multicolumn{#1}{c}{#2}}
\newcolumntype{a}{c}
\newcolumntype{b}{l}
\newcolumntype{d}{r}
\newcommand\Tstrut{\rule{0pt}{2.4ex}}
```

The `\Tstrut` command (table strut) adds vertical spacing after horizontal rules, preventing text from touching the line.

### Color Definitions

A centralized color file ensures consistency:

```latex
% settings/paper-colors.tex
\definecolor{MainBlue}{RGB}{13, 77, 140}
\definecolor{CodeGray}{HTML}{F6F6F6}
\definecolor{MediumGreen}{rgb}{0.37, 0.7, 0.66}
```

Semantic names (`MainBlue`, `CodeGray`) allow global color changes without searching for RGB values throughout the document.

## Summary

The enhanced template addresses common IEEEtran pain points:

| Limitation | Solution |
|------------|----------|
| Poor justification | microtype with protrusion/expansion |
| Legacy bibliography | Biblatex with Biber backend |
| URL overflow | biburllcpenalty counter |
| Plain code blocks | minted with Pygments |
| Environment drift | Docker-based builds |
| Monolithic sources | Modular section files |
| Unbalanced columns | pbalance package |

The result is a template that produces typographically superior output while maintaining IEEE compliance. Containerized builds ensure reproducibility across development machines and CI systems.

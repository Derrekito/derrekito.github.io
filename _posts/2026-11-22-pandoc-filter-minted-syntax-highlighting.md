---
title: "A Pandoc Filter for Minted Syntax Highlighting in LaTeX"
date: 2026-11-22 10:00:00 -0700
categories: [Python, Documentation]
tags: [pandoc, python, latex, minted, pygments, pandocfilters]
---

Pandoc's default LaTeX code output relies on verbatim environments or the listings package, both of which produce suboptimal syntax highlighting. This post presents a pandocfilters-based Python filter that intercepts code blocks during JSON AST processing and converts them to minted LaTeX output, leveraging Pygments for superior highlighting quality.

## Problem Statement

When converting Markdown to LaTeX, Pandoc generates code blocks using one of several approaches:

**Verbatim Environment**: Plain monospace text without highlighting:

```latex
\begin{verbatim}
def fibonacci(n):
    if n <= 1:
        return n
    return fibonacci(n-1) + fibonacci(n-2)
\end{verbatim}
```

**Listings Package**: Basic keyword highlighting with limited language support:

```latex
\begin{lstlisting}[language=Python]
def fibonacci(n):
    if n <= 1:
        return n
    return fibonacci(n-1) + fibonacci(n-2)
\end{lstlisting}
```

**Pandoc Highlighting**: Internal highlighting converted to styled environments:

```latex
\begin{Shaded}
\begin{Highlighting}[]
\KeywordTok{def} \FunctionTok{fibonacci}\NormalTok{(n):}
    \ControlFlowTok{if}\NormalTok{ n }\OperatorTok{<=} \DecValTok{1}\NormalTok{:}
        \ControlFlowTok{return}\NormalTok{ n}
\end{Highlighting}
\end{Shaded}
```

Each approach has limitations:

| Method | Highlighting Quality | Language Support | Customization |
|--------|---------------------|------------------|---------------|
| Verbatim | None | N/A | Minimal |
| Listings | Basic | ~80 languages | Moderate |
| Pandoc | Moderate | ~140 languages | Limited |
| Minted | Excellent | 500+ languages | Extensive |

The minted package delegates highlighting to Pygments, a Python library that supports hundreds of programming languages with accurate tokenization and extensive styling options.

## Technical Background

### Pandoc Filter Architecture

Pandoc processes documents through an Abstract Syntax Tree (AST). The pipeline follows this structure:

```text
Input Document → Reader → AST → Filters → Writer → Output
```

Filters intercept the AST between parsing and writing, enabling transformations that are format-aware. Pandoc supports two filter types:

1. **Lua Filters**: Native integration, fast execution, no external dependencies
2. **JSON Filters**: Language-agnostic via stdin/stdout JSON AST exchange

JSON filters receive the entire document AST as JSON on stdin and emit the transformed AST on stdout. The `pandocfilters` Python library simplifies this exchange.

### pandocfilters Library

The `pandocfilters` library provides utilities for walking and transforming the Pandoc AST:

```python
from pandocfilters import toJSONFilter, RawBlock, RawInline

def my_filter(key, value, format, meta):
    # key: element type ("CodeBlock", "Code", "Para", etc.)
    # value: element contents (structure varies by type)
    # format: output format ("latex", "html", etc.)
    # meta: document metadata from YAML front matter
    pass

if __name__ == '__main__':
    toJSONFilter(my_filter)
```

The `toJSONFilter` function handles JSON parsing, AST walking, and output generation. Filter functions return transformed elements or `None` to leave elements unchanged.

### Code Element Structure

Pandoc represents code elements with this structure:

**CodeBlock** (fenced code blocks):
```json
{
  "t": "CodeBlock",
  "c": [
    ["identifier", ["class1", "class2"], [["attr1", "value1"]]],
    "code contents"
  ]
}
```

**Code** (inline code):
```json
{
  "t": "Code",
  "c": [
    ["identifier", ["class1"], []],
    "inline code"
  ]
}
```

The first element is a triple: identifier, classes list, and key-value attributes. The second element contains the code text.

## Implementation Walkthrough

The filter comprises three functions: unpacking code elements, extracting metadata settings, and the main filter function.

### Code Element Unpacking

The `unpack_code` function extracts language, attributes, and contents from Pandoc's code element structure:

```python
def unpack_code(value, language):
    ''' Unpack the body and language of a pandoc code element.

    Args:
        value       contents of pandoc object
        language    default language
    '''
    [[_, classes, attributes], contents] = value

    if len(classes) > 0:
        language = classes[0]

    attributes = ', '.join('='.join(x) for x in attributes)

    return {'contents': contents, 'language': language,
            'attributes': attributes}
```

Key behaviors:

- **Language extraction**: The first class becomes the language identifier
- **Attribute formatting**: Key-value pairs convert to minted option syntax (`key=value, key=value`)
- **Default fallback**: If no class is specified, the passed default language is used

### Metadata Extraction

Document-level settings are configured via YAML front matter:

```yaml
---
title: "Document Title"
pandoc-minted:
  language: python
---
```

The `unpack_metadata` function parses these settings:

```python
def unpack_metadata(meta):
    ''' Unpack the metadata to get pandoc-minted settings.

    Args:
        meta    document metadata
    '''
    settings = meta.get('pandoc-minted', {})
    if settings.get('t', '') == 'MetaMap':
        settings = settings['c']

        # Get language.
        language = settings.get('language', {})
        if language.get('t', '') == 'MetaInlines':
            language = language['c'][0]['c']
        else:
            language = None

        return {'language': language}

    else:
        # Return default settings.
        return {'language': 'text'}
```

Pandoc metadata arrives in a typed format where `t` indicates the type (`MetaMap`, `MetaInlines`, etc.) and `c` contains the content. The function navigates this structure to extract the default language setting.

### Main Filter Function

The `minted` function performs the actual transformation:

```python
def minted(key, value, format, meta):
    ''' Use minted for code in LaTeX.

    Args:
        key     type of pandoc object
        value   contents of pandoc object
        format  target output format
        meta    document metadata
    '''
    if format != 'latex':
        return

    # Determine what kind of code object this is.
    if key == 'CodeBlock':
        template = Template(
            '\\begin{minted}[$attributes]{$language}\n$contents\n\end{minted}'
        )
        Element = RawBlock
    elif key == 'Code':
        template = Template('\\mintinline[$attributes]{$language}{$contents}')
        Element = RawInline
    else:
        return

    settings = unpack_metadata(meta)

    code = unpack_code(value, settings['language'])

    return [Element(format, template.substitute(code))]
```

Control flow:

1. **Format check**: Non-LaTeX output passes through unmodified
2. **Element type dispatch**: Different templates for blocks vs. inline code
3. **Template selection**: `RawBlock` for environments, `RawInline` for inline commands
4. **Settings merge**: Document defaults combine with element-specific settings
5. **Template substitution**: Python's `string.Template` generates final LaTeX

### Complete Filter Script

```python
#!/usr/bin/env python
''' A pandoc filter that has the LaTeX writer use minted for typesetting code.

Usage:
    pandoc --filter ./pandoc-minted.py -o myfile.tex myfile.md
'''

from string import Template
from pandocfilters import toJSONFilter, RawBlock, RawInline


def unpack_code(value, language):
    [[_, classes, attributes], contents] = value

    if len(classes) > 0:
        language = classes[0]

    attributes = ', '.join('='.join(x) for x in attributes)

    return {'contents': contents, 'language': language,
            'attributes': attributes}


def unpack_metadata(meta):
    settings = meta.get('pandoc-minted', {})
    if settings.get('t', '') == 'MetaMap':
        settings = settings['c']

        language = settings.get('language', {})
        if language.get('t', '') == 'MetaInlines':
            language = language['c'][0]['c']
        else:
            language = None

        return {'language': language}

    else:
        return {'language': 'text'}


def minted(key, value, format, meta):
    if format != 'latex':
        return

    if key == 'CodeBlock':
        template = Template(
            '\\begin{minted}[$attributes]{$language}\n$contents\n\end{minted}'
        )
        Element = RawBlock
    elif key == 'Code':
        template = Template('\\mintinline[$attributes]{$language}{$contents}')
        Element = RawInline
    else:
        return

    settings = unpack_metadata(meta)
    code = unpack_code(value, settings['language'])

    return [Element(format, template.substitute(code))]


if __name__ == '__main__':
    toJSONFilter(minted)
```

## Minted Integration Requirements

### Shell Escape

The minted package executes Pygments as an external process, requiring shell-escape mode:

```bash
pdflatex -shell-escape document.tex
# or
latexmk -pdf -shell-escape document.tex
```

Without shell-escape, minted fails with:

```text
! Package minted Error: You must invoke LaTeX with the -shell-escape flag.
```

### Pygments Installation

Pygments must be available in the system PATH:

```bash
pip install pygments

# Verify installation
pygmentize -V
```

### LaTeX Package Setup

The document preamble must load minted:

```latex
\documentclass{article}
\usepackage{minted}

\begin{document}
% minted environments will be inserted here
\end{document}
```

Optional configuration in the preamble:

```latex
\usepackage{minted}

% Set default style
\usemintedstyle{monokai}

% Global options
\setminted{
    frame=lines,
    framesep=2mm,
    fontsize=\small,
    linenos=true
}
```

## Metadata-Driven Configuration

### Default Language

Documents with predominantly one language can set a default:

```yaml
---
title: "Python Tutorial"
pandoc-minted:
  language: python
---
```

Code blocks without explicit language inherit this default:

````markdown
```
# This block will use python highlighting
def greet(name):
    print(f"Hello, {name}!")
```
````

### Override Per Block

Explicit language classes override the document default:

````markdown
```bash
#!/bin/bash
echo "This uses bash highlighting"
```

```sql
SELECT * FROM users WHERE active = true;
```
````

## Usage Examples

### Basic Conversion

```bash
pandoc input.md --filter ./pandoc-minted.py -o output.tex
```

### Input Markdown

````markdown
---
title: "Code Examples"
pandoc-minted:
  language: python
---

## Fibonacci Implementation

```python
def fibonacci(n: int) -> int:
    """Calculate nth Fibonacci number."""
    if n <= 1:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)
```

Inline code like `fibonacci(10)` also converts.

## Shell Commands

```bash
pip install pandocfilters pygments
```
````

### Output LaTeX

```latex
\section{Fibonacci Implementation}

\begin{minted}[]{python}
def fibonacci(n: int) -> int:
    """Calculate nth Fibonacci number."""
    if n <= 1:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)
\end{minted}

Inline code like \mintinline[]{python}{fibonacci(10)} also converts.

\section{Shell Commands}

\begin{minted}[]{bash}
pip install pandocfilters pygments
\end{minted}
```

### With Attributes

Fenced code blocks support attributes that pass through to minted:

````markdown
```{.python linenos=true frame=lines}
def example():
    return "highlighted with options"
```
````

Output:

```latex
\begin{minted}[linenos=true, frame=lines]{python}
def example():
    return "highlighted with options"
\end{minted}
```

### Comparison: Before and After

**Without Filter (Pandoc default)**:

```latex
\begin{Shaded}
\begin{Highlighting}[]
\KeywordTok{def}\NormalTok{ fibonacci(n: }\BuiltInTok{int}\NormalTok{) -> }\BuiltInTok{int}\NormalTok{:}
    \CommentTok{"""Calculate nth Fibonacci number."""}
    \ControlFlowTok{if}\NormalTok{ n <= }\DecValTok{1}\NormalTok{:}
        \ControlFlowTok{return}\NormalTok{ n}
    \ControlFlowTok{return}\NormalTok{ fibonacci(n }\OperatorTok{-} \DecValTok{1}\NormalTok{) + fibonacci(n }\OperatorTok{-} \DecValTok{2}\NormalTok{)}
\end{Highlighting}
\end{Shaded}
```

**With Filter (minted output)**:

```latex
\begin{minted}[]{python}
def fibonacci(n: int) -> int:
    """Calculate nth Fibonacci number."""
    if n <= 1:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)
\end{minted}
```

The minted output is cleaner, more maintainable, and produces superior PDF rendering through Pygments.

## Integration with Docker LaTeX Builds

The filter integrates with containerized LaTeX environments as described in [Docker-Based LaTeX Compilation](/devops/documentation/2026/10/25/docker-latex-reproducible-builds.html). The container must include:

1. **Python virtual environment** with pandocfilters and pygments
2. **Filter script** accessible in the container
3. **Shell-escape enabled** in latexmk configuration

### Makefile Integration

```makefile
DOCKER_IMAGE := latex-env
DOCKER_RUN := docker run --rm -v $(PWD):/app -u $(shell id -u):$(shell id -g)
FILTER := /app/filters/pandoc-minted.py

%.tex: %.md
	$(DOCKER_RUN) $(DOCKER_IMAGE) \
	    pandoc --filter $(FILTER) -o $@ $<

%.pdf: %.tex
	$(DOCKER_RUN) $(DOCKER_IMAGE) \
	    latexmk -pdf -shell-escape $<
```

### Pipeline Script

```bash
#!/bin/bash
# build-document.sh

INPUT="$1"
OUTPUT="${INPUT%.md}.pdf"

# Generate LaTeX with minted filter
pandoc "$INPUT" \
    --filter ./filters/pandoc-minted.py \
    --template=template.latex \
    -o "${INPUT%.md}.tex"

# Compile with shell-escape
latexmk -pdf -shell-escape "${INPUT%.md}.tex"

# Cleanup
latexmk -c
```

## Debugging

### Inspect AST Structure

Examine what Pandoc parses before filtering:

```bash
pandoc input.md -t json | python -m json.tool | head -50
```

### Filter Logging

Add debug output to stderr (stdout is reserved for AST output):

```python
import sys

def minted(key, value, format, meta):
    sys.stderr.write(f"Processing: {key}\n")
    # ... rest of function
```

### Common Issues

**Pygments not found**: Ensure pygmentize is in PATH. In Docker, verify the virtual environment is activated or PATH is configured.

**Shell-escape disabled**: The error message explicitly states the requirement. Add `-shell-escape` to the LaTeX compilation command.

**Empty attributes bracket**: The filter generates `[]` even when no attributes exist. This is valid minted syntax but can be removed with a conditional:

```python
if code['attributes']:
    attr_str = f"[{code['attributes']}]"
else:
    attr_str = ""
```

## Conclusion

The pandoc-minted filter bridges Pandoc's Markdown processing with minted's superior syntax highlighting. The implementation demonstrates pandocfilters patterns applicable to other filter development:

- Format-conditional processing via the `format` parameter
- Metadata extraction for document-level configuration
- Template-based output generation for maintainable code
- Proper element type handling with `RawBlock` and `RawInline`

Combined with containerized LaTeX builds, this filter enables reproducible, high-quality technical document generation from Markdown sources.

## References

- [pandocfilters Python Library](https://github.com/jgm/pandocfilters)
- [Minted Package Documentation](https://ctan.org/pkg/minted)
- [Pygments Documentation](https://pygments.org/docs/)
- [Pandoc Filters Manual](https://pandoc.org/filters.html)

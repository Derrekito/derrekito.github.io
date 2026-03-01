---
title: "Part 1: PDF Extraction with MinerU"
date: 2026-02-28 10:00:00 -0700
categories: [AI, Document Processing]
tags: [pdf, mineru, document-processing, python, knowledge-graph]
series: pdf-to-knowledge-graph
series_order: 1
---

*Part 1 of the [PDF to Knowledge Graph series](/posts/local-pdf-to-knowledge-graph-series/).*

PDF extraction is deceptively difficult. Standard libraries produce reasonable results on simple documents but fail catastrophically on technical papers with multi-column layouts, embedded equations, and complex tables. This post presents MinerU, a deep learning-based solution that preserves document structure.

## Problem Statement

Consider a typical research paper:
- Two-column layout with figures spanning columns
- LaTeX equations in inline and display mode
- Tables with merged cells and nested headers
- Footnotes, citations, and cross-references
- Headers and footers to be ignored

Standard extraction libraries (PyPDF2, pdfplumber, pypdf) treat the page as a linear stream, producing:

```text
The transformer architecture [1] revolu-   We propose a modification to the
tionized NLP through self-attention.       attention mechanism that reduces...
```

Two columns interleaved. Equations become `x = y 2 + z`. Tables collapse into word salad. The text is technically "extracted" but unusable for downstream processing.

## MinerU: Layout-Aware Extraction

[MinerU](https://github.com/opendatalab/MinerU) (formerly magic-pdf) uses deep learning models to:

1. **Detect layout regions** (text blocks, figures, tables, equations)
2. **Determine reading order** across columns and pages
3. **Extract equations** as LaTeX notation
4. **Convert tables** to Markdown format
5. **Preserve hierarchy** (headings, lists, paragraphs)

The result is clean Markdown suitable for LLM processing.

## Installation

### Via pip

```bash
pip install mineru
```

### Via conda (recommended for complex dependencies)

```bash
conda create -n mineru python=3.10
conda activate mineru
conda install -c conda-forge mineru
```

### Verification

```bash
mineru --help
```

MinerU downloads model weights on first run (~2GB). Adequate disk space must be available.

## Basic Usage

### Command Line

```bash
# Convert single PDF
mineru -p paper.pdf -o ./output -m auto

# The output structure:
# output/
#   paper/
#     auto/
#       paper.md        # Markdown output
#       images/         # Extracted figures
```

### Programmatic Conversion

```python
import os
import subprocess
import time
import shutil

CONVERTER_OUTPUT_DIR = "./mineru_outputs"

def run_mineru(pdf_path: str) -> str | None:
    """
    Convert PDF to Markdown using MinerU.
    Returns path to the generated markdown file, or None on failure.
    """
    pdf_name = os.path.basename(pdf_path).replace(".pdf", "")
    pdf_size_mb = os.path.getsize(pdf_path) / (1024 * 1024)
    print(f"[INFO] PDF: {pdf_name} ({pdf_size_mb:.1f} MB)")

    # MinerU creates: {output_dir}/{pdf_name}/auto/{pdf_name}.md
    base_folder = os.path.join(CONVERTER_OUTPUT_DIR, pdf_name)
    method_folder = os.path.join(base_folder, "auto")
    expected_md_path = os.path.join(method_folder, f"{pdf_name}.md")

    # Try 'mineru' command (v2.x), fall back to 'magic-pdf' (v1.x)
    for cmd_name in ["mineru", "magic-pdf"]:
        if shutil.which(cmd_name):
            cmd = [cmd_name, "-p", pdf_path, "-o", CONVERTER_OUTPUT_DIR, "-m", "auto"]
            print(f"[INFO] Running: {cmd_name} -m auto")

            start = time.time()

            # Stream output for progress visibility
            process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1
            )

            # Print progress lines
            for line in process.stdout:
                line = line.strip()
                if line and any(x in line for x in ["Predict", "Processing", "Batch", "INFO"]):
                    print(f"      {line}")

            process.wait()
            elapsed = time.time() - start

            if process.returncode != 0:
                print(f"[ERROR] {cmd_name} failed (exit {process.returncode})")
                continue

            # Check for markdown file
            if os.path.exists(expected_md_path):
                md_size_kb = os.path.getsize(expected_md_path) / 1024
                print(f"[INFO] Converted in {elapsed:.1f}s -> {md_size_kb:.0f} KB markdown")
                return expected_md_path

            # Fallback: search for any .md file
            for root, _, files in os.walk(base_folder):
                for f in files:
                    if f.endswith(".md"):
                        return os.path.join(root, f)

            print(f"[WARN] {cmd_name} completed but no .md file found")
            return None

    print("[ERROR] Neither 'mineru' nor 'magic-pdf' found in PATH")
    return None
```

## Output Quality

For a technical paper, MinerU produces clean Markdown:

```markdown
# Attention Is All You Need

Ashish Vaswani, Noam Shazeer, Niki Parmar...

Abstract — The dominant sequence transduction models are based on complex
recurrent or convolutional neural networks...

## I. INTRODUCTION

Recurrent neural networks, long short-term memory [1] and gated recurrent [2]
neural networks in particular, have been firmly established as state of the
art approaches in sequence modeling...

| Model | BLEU | Training Cost |
|-------|------|---------------|
| Transformer (base) | 27.3 | $3.3 \times 10^{18}$ |
| Transformer (big) | 28.4 | $2.3 \times 10^{19}$ |
```

Key observations:
- **LaTeX preserved**: Equations remain as `$...$` and `$$...$$`
- **Tables intact**: Converted to Markdown tables
- **Structure maintained**: Headings, paragraphs, lists preserved
- **Citations kept**: `[1-3]` reference markers remain

## Handling Different Document Types

### Research Papers

Default settings work well:

```bash
mineru -p paper.pdf -o ./output -m auto
```

### Textbooks with Complex Layout

For documents with marginal notes, sidebars, or unusual layouts:

```bash
mineru -p textbook.pdf -o ./output -m auto --layout-model doclayout_yolo
```

### Scanned Documents

MinerU includes OCR support:

```bash
mineru -p scanned.pdf -o ./output -m ocr
```

## Batch Processing

Process an entire directory:

```python
import os
from pathlib import Path

def batch_convert(input_dir: str, output_dir: str):
    """Convert all PDFs in a directory."""
    pdfs = list(Path(input_dir).glob("*.pdf"))
    print(f"Found {len(pdfs)} PDFs")

    results = {"success": [], "failed": []}

    for i, pdf in enumerate(pdfs):
        print(f"\n[{i+1}/{len(pdfs)}] {pdf.name}")
        md_path = run_mineru(str(pdf))

        if md_path:
            results["success"].append(pdf.name)
        else:
            results["failed"].append(pdf.name)

    print(f"\n{'='*50}")
    print(f"Success: {len(results['success'])}")
    print(f"Failed:  {len(results['failed'])}")

    if results["failed"]:
        print("\nFailed PDFs:")
        for name in results["failed"]:
            print(f"  - {name}")

    return results

# Usage
batch_convert("./papers", "./converted")
```

## Common Issues and Solutions

### Out of Memory

MinerU's models require significant RAM. For large documents:

```bash
# Reduce batch size (slower but less memory)
mineru -p large.pdf -o ./output -m auto --batch-size 1
```

Or process page ranges:

```bash
# First 50 pages only
mineru -p large.pdf -o ./output -m auto --start-page 0 --end-page 50
```

### Equation Extraction Failures

Some equation styles confuse the detector. Consider:

1. Pre-processing with image enhancement
2. Using OCR mode for heavily formatted equations
3. Post-processing with regex to fix common patterns

### Table Detection Issues

Borderless tables are challenging. For better results:

```bash
mineru -p doc.pdf -o ./output -m auto --table-model tablemaster
```

## Performance Benchmarks

On an NVIDIA RTX 3090:

| Document Type | Pages | Time | Output Size |
|---------------|-------|------|-------------|
| Research paper | 12 | 8s | 45 KB |
| Technical spec | 85 | 52s | 320 KB |
| Textbook chapter | 40 | 28s | 180 KB |
| Scanned document | 20 | 35s | 95 KB |

CPU-only processing is 5-10x slower but functional.

## Integration with the Pipeline

The extracted Markdown feeds directly into LLM extraction:

```python
def process_pdf(pdf_path: str):
    """Complete PDF processing: convert then extract."""
    # Stage 1: PDF to Markdown
    md_path = run_mineru(pdf_path)
    if not md_path:
        return None

    # Stage 2: Read markdown for LLM processing
    with open(md_path, "r", encoding="utf-8") as f:
        markdown_text = f.read()

    return markdown_text
```

The next post covers [structured extraction with Instructor](/posts/structured-llm-extraction-instructor/).

## Summary

PDF extraction quality determines everything downstream. MinerU's deep learning approach handles complex technical documents that defeat traditional libraries. The clean Markdown output—with preserved equations, tables, and structure—provides the foundation for reliable knowledge extraction.

Key points:
- **Use MinerU over PyPDF2/pdfplumber** for technical documents
- **LaTeX equations survive** as extractable notation
- **Tables convert to Markdown** suitable for LLM processing
- **Batch processing scales** to large document collections

---

*Next: [Part 2 - Structured LLM Extraction with Instructor](/posts/structured-llm-extraction-instructor/)*

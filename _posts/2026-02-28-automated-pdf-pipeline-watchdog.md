---
title: "Part 4: Automated PDF Pipeline with Watchdog"
date: 2026-02-28 10:00:00 -0700
categories: [AI, Automation]
tags: [watchdog, python, automation, pdf, knowledge-graph]
series: pdf-to-knowledge-graph
series_order: 4
---

*Part 4 of the [PDF to Knowledge Graph series](/posts/local-pdf-to-knowledge-graph-series/).*

Manual processing does not scale. Hundreds of PDFs require processing, and more arrive regularly. This post presents a file-watching system that automatically processes new PDFs through the complete pipeline—conversion, extraction, and graph ingestion—without human intervention.

## Motivation

Consider the workflow without automation:

1. Download PDF
2. Run MinerU conversion
3. Wait for completion
4. Run extraction script
5. Verify ingestion
6. Repeat for every document

With Watchdog, the workflow becomes:

1. Drop PDF in folder
2. (Remaining steps execute automatically)

## Watchdog: Filesystem Monitoring

[Watchdog](https://github.com/gorakhargosh/watchdog) is a Python library that monitors filesystem events—file creation, modification, deletion. When a new PDF appears, the handler processes it immediately.

### Installation

```bash
pip install watchdog
```

## File Watcher Implementation

### Basic Structure

```python
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
import time
import os

WATCH_DIR = "./input_pdfs"

class NewPDFHandler(FileSystemEventHandler):
    def on_created(self, event):
        if event.is_directory:
            return

        if event.src_path.endswith(".pdf"):
            pdf_name = os.path.basename(event.src_path)
            print(f"\n{'='*60}")
            print(f"NEW PDF DETECTED: {pdf_name}")
            print(f"{'='*60}")

            # Process the PDF
            self.process_pdf(event.src_path)

    def process_pdf(self, pdf_path):
        # Implementation follows
        pass


if __name__ == "__main__":
    os.makedirs(WATCH_DIR, exist_ok=True)

    print(f"Watching {WATCH_DIR} for new PDFs...")
    print("Press Ctrl+C to stop")

    observer = Observer()
    observer.schedule(NewPDFHandler(), path=WATCH_DIR, recursive=False)
    observer.start()

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nShutting down...")
        observer.stop()

    observer.join()
```

### Handling File Completion

A critical detail: when a file is created, it may still be copying. Processing an incomplete file fails. The system must wait for the file to stabilize:

```python
import time

def wait_for_file_complete(path: str, check_interval: float = 0.5, stable_time: float = 2.0):
    """Wait for a file to finish being written."""
    last_size = -1
    stable_count = 0

    while stable_count < (stable_time / check_interval):
        try:
            current_size = os.path.getsize(path)
            if current_size == last_size:
                stable_count += 1
            else:
                stable_count = 0
                last_size = current_size
        except OSError:
            stable_count = 0

        time.sleep(check_interval)

    return True
```

### Complete PDF Handler

```python
class NewPDFHandler(FileSystemEventHandler):
    def on_created(self, event):
        if event.is_directory:
            return

        if event.src_path.endswith(".pdf"):
            pdf_name = os.path.basename(event.src_path)
            print(f"\n{'='*60}")
            print(f"NEW PDF DETECTED: {pdf_name}")
            print(f"{'='*60}")

            # Wait for file copy to complete
            print("[WAIT] Ensuring file is complete...")
            wait_for_file_complete(event.src_path)

            # Stage 1: Convert PDF to Markdown
            print("[STAGE 1/2] PDF -> Markdown")
            md_path = run_mineru(event.src_path)

            if md_path and os.path.exists(md_path):
                # Stage 2: Extract to Knowledge Graph
                with open(md_path, "r", encoding="utf-8") as f:
                    text = f.read()

                print("[STAGE 2/2] Markdown -> Knowledge Graph")
                extract_knowledge(text, source_name=pdf_name)

                print(f"[DONE] {pdf_name} processed successfully")
            else:
                print(f"[ERROR] Could not convert {pdf_name}")
```

## Batch Processing for Initial Corpus

For existing PDF collections, batch processing is more appropriate than watching:

```python
#!/usr/bin/env python3
"""
Batch process all PDFs in input_pdfs directory.

Usage:
    python batch_process.py                    # Process all
    python batch_process.py --limit 5          # First 5 only
    python batch_process.py --skip-existing    # Skip already converted
    python batch_process.py --conversion-only  # Only convert, no LLM
"""
import os
import argparse
import time

WATCH_DIR = "./input_pdfs"
CONVERTER_OUTPUT_DIR = "./mineru_outputs"

def get_pending_pdfs(skip_existing: bool = False) -> list[str]:
    """Get list of PDFs to process."""
    pdfs = sorted([f for f in os.listdir(WATCH_DIR) if f.endswith('.pdf')])

    if skip_existing:
        pending = []
        for pdf in pdfs:
            pdf_name = pdf.replace('.pdf', '')
            md_path = os.path.join(
                CONVERTER_OUTPUT_DIR,
                pdf_name,
                'auto',
                f'{pdf_name}.md'
            )
            if not os.path.exists(md_path):
                pending.append(pdf)
            else:
                print(f"[SKIP] {pdf} (already converted)")
        return pending

    return pdfs


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=0,
                        help="Maximum number of PDFs to process")
    parser.add_argument("--skip-existing", action="store_true",
                        help="Skip PDFs that have already been converted")
    parser.add_argument("--conversion-only", action="store_true",
                        help="Only run PDF conversion, skip LLM extraction")
    args = parser.parse_args()

    pdfs = get_pending_pdfs(skip_existing=args.skip_existing)

    if args.limit > 0:
        pdfs = pdfs[:args.limit]

    total = len(pdfs)
    print(f"Processing {total} PDFs...")

    results = {"success": [], "failed": []}
    start_time = time.time()

    for i, pdf in enumerate(pdfs):
        pdf_path = os.path.join(WATCH_DIR, pdf)

        print(f"\n[{i+1}/{total}] {pdf}")

        # Convert
        md_path = run_mineru(pdf_path)

        if not md_path:
            print(f"[FAIL] Conversion failed")
            results["failed"].append(pdf)
            continue

        if args.conversion_only:
            results["success"].append(pdf)
            continue

        # Extract
        try:
            with open(md_path, 'r', encoding='utf-8') as f:
                text = f.read()

            extract_knowledge(text, source_name=pdf)
            results["success"].append(pdf)
        except Exception as e:
            print(f"[FAIL] Extraction failed: {e}")
            results["failed"].append(pdf)

    elapsed = time.time() - start_time

    print(f"\n{'='*60}")
    print(f"BATCH COMPLETE")
    print(f"{'='*60}")
    print(f"Total time: {elapsed:.1f}s ({elapsed/60:.1f} minutes)")
    print(f"Success: {len(results['success'])}")
    print(f"Failed:  {len(results['failed'])}")

    if results["failed"]:
        print("\nFailed PDFs:")
        for name in results["failed"]:
            print(f"  - {name}")


if __name__ == "__main__":
    main()
```

### Batch Processing Strategies

**Resume on Failure**

Use `--skip-existing` to resume after a crash:

```bash
# Initial run - processes 50 PDFs, crashes at #37
python batch_process.py

# Resume - skips the 36 already converted
python batch_process.py --skip-existing
```

**Staged Processing**

For large collections, separate conversion from extraction:

```bash
# Stage 1: Convert all PDFs (faster, less resource-intensive)
python batch_process.py --conversion-only

# Stage 2: Run extraction on converted files
python batch_process.py --skip-existing
```

**Testing with Limits**

Verify pipeline functionality before committing to full processing:

```bash
# Test with 3 PDFs first
python batch_process.py --limit 3
```

## Error Handling and Recovery

Robust pipelines handle failures gracefully:

```python
import traceback
from datetime import datetime

LOG_FILE = "./pipeline_errors.log"

def log_error(pdf_name: str, stage: str, error: Exception):
    """Log error with context for debugging."""
    timestamp = datetime.now().isoformat()
    entry = f"""
{'='*60}
[{timestamp}] ERROR in {stage}
PDF: {pdf_name}
Exception: {type(error).__name__}: {str(error)}
{'='*60}
{traceback.format_exc()}
"""
    with open(LOG_FILE, "a") as f:
        f.write(entry)

    print(f"[ERROR] {stage} failed for {pdf_name}. See {LOG_FILE}")


class RobustPDFHandler(FileSystemEventHandler):
    def on_created(self, event):
        if not event.src_path.endswith(".pdf"):
            return

        pdf_name = os.path.basename(event.src_path)

        try:
            wait_for_file_complete(event.src_path)
        except Exception as e:
            log_error(pdf_name, "file_wait", e)
            return

        try:
            md_path = run_mineru(event.src_path)
        except Exception as e:
            log_error(pdf_name, "conversion", e)
            return

        if not md_path:
            log_error(pdf_name, "conversion", Exception("No markdown output"))
            return

        try:
            with open(md_path, "r", encoding="utf-8") as f:
                text = f.read()
            extract_knowledge(text, source_name=pdf_name)
        except Exception as e:
            log_error(pdf_name, "extraction", e)
            return

        print(f"[SUCCESS] {pdf_name}")
```

## Progress Tracking

For batch processing, track progress persistently:

```python
import json
from pathlib import Path

PROGRESS_FILE = "./batch_progress.json"

def load_progress() -> dict:
    """Load processing progress."""
    if Path(PROGRESS_FILE).exists():
        with open(PROGRESS_FILE) as f:
            return json.load(f)
    return {"processed": [], "failed": [], "skipped": []}

def save_progress(progress: dict):
    """Save processing progress."""
    with open(PROGRESS_FILE, "w") as f:
        json.dump(progress, f, indent=2)

def batch_with_progress():
    """Batch process with persistent progress tracking."""
    progress = load_progress()
    already_done = set(progress["processed"] + progress["failed"])

    pdfs = [f for f in os.listdir(WATCH_DIR)
            if f.endswith('.pdf') and f not in already_done]

    print(f"Previously processed: {len(already_done)}")
    print(f"Remaining: {len(pdfs)}")

    for pdf in pdfs:
        pdf_path = os.path.join(WATCH_DIR, pdf)

        try:
            md_path = run_mineru(pdf_path)
            if md_path:
                with open(md_path) as f:
                    extract_knowledge(f.read(), source_name=pdf)
                progress["processed"].append(pdf)
            else:
                progress["failed"].append(pdf)
        except Exception as e:
            print(f"[ERROR] {pdf}: {e}")
            progress["failed"].append(pdf)

        # Save after each file (enables resume)
        save_progress(progress)

    return progress
```

## Systemd Integration

For production deployment, run the watcher as a system service:

### Service File

Create `/etc/systemd/system/pdf-pipeline.service`:

```ini
[Unit]
Description=PDF Knowledge Graph Pipeline
After=network.target

[Service]
Type=simple
User=derrekito
WorkingDirectory=/home/derrekito/Projects/knowledge_graph_db
Environment="PATH=/home/derrekito/.local/bin:/usr/bin"
ExecStart=/home/derrekito/.local/bin/python graph_builder.py
Restart=always
RestartSec=10

# Logging
StandardOutput=append:/var/log/pdf-pipeline.log
StandardError=append:/var/log/pdf-pipeline.log

[Install]
WantedBy=multi-user.target
```

### Managing the Service

```bash
# Install and start
sudo systemctl daemon-reload
sudo systemctl enable pdf-pipeline
sudo systemctl start pdf-pipeline

# Check status
sudo systemctl status pdf-pipeline

# View logs
sudo journalctl -u pdf-pipeline -f

# Restart after changes
sudo systemctl restart pdf-pipeline
```

### Log Rotation

Create `/etc/logrotate.d/pdf-pipeline`:

```text
/var/log/pdf-pipeline.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 derrekito derrekito
}
```

## Complete Watcher Script

```python
#!/usr/bin/env python3
"""
Knowledge Graph Pipeline: Automatic PDF Processing

Watches input_pdfs/ for new files and automatically:
1. Converts PDF to Markdown (MinerU)
2. Extracts entities and relations (LLM)
3. Stores in graph database (Kuzu)

Usage:
    python graph_builder.py
"""
import os
import sys
import time
import subprocess
import shutil
import kuzu
from datetime import datetime
from typing import List, Literal
from pydantic import BaseModel, Field
import instructor
from openai import OpenAI
from rapidfuzz import process, fuzz
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# === CONFIGURATION ===
WATCH_DIR = "./input_pdfs"
CONVERTER_OUTPUT_DIR = "./mineru_outputs"
DB_PATH = "./kuzu_graph_db"
LLM_MODEL = "qwen2.5:72b"
LLM_TIMEOUT = 120


# === SCHEMA ===
class Entity(BaseModel):
    id: str = Field(..., description="Unique technical name")
    type: Literal["Paper", "Algorithm", "Metric", "Library", "Function"]
    summary: str = Field(..., description="One sentence definition")

class Relation(BaseModel):
    source: str
    target: str
    label: Literal["PROPOSES", "USES", "IMPROVES", "IMPLEMENTS", "CITES"]

class Extraction(BaseModel):
    entities: List[Entity]
    relations: List[Relation]


# === LLM CLIENT ===
client = instructor.patch(OpenAI(
    base_url="http://localhost:11434/v1",
    api_key="ollama",
))


# === DATABASE ===
class KnowledgeBase:
    def __init__(self):
        self.db = kuzu.Database(DB_PATH)
        self.conn = kuzu.Connection(self.db)
        self._init_schema()

    def _init_schema(self):
        try:
            self.conn.execute(
                "CREATE NODE TABLE Entity(id STRING, type STRING, summary STRING, PRIMARY KEY (id))"
            )
            self.conn.execute(
                "CREATE REL TABLE RELATED(FROM Entity TO Entity, label STRING)"
            )
        except RuntimeError:
            pass

    def get_all_entity_ids(self):
        try:
            results = self.conn.execute("MATCH (n:Entity) RETURN n.id").get_as_df()
            return results["n.id"].tolist() if not results.empty else []
        except Exception:
            return []

    def add_data(self, data: Extraction):
        existing_ids = self.get_all_entity_ids()
        id_map = {}

        for entity in data.entities:
            resolved_id = entity.id
            if existing_ids:
                match, score, _ = process.extractOne(
                    entity.id, existing_ids, scorer=fuzz.ratio
                )
                if score > 92:
                    resolved_id = match
                    print(f"   Merged: '{entity.id}' -> '{match}'")

            id_map[entity.id] = resolved_id
            self.conn.execute(
                "MERGE (n:Entity {id: $id}) ON CREATE SET n.type = $type, n.summary = $summary",
                {"id": resolved_id, "type": entity.type, "summary": entity.summary}
            )

        for rel in data.relations:
            if rel.source in id_map and rel.target in id_map:
                src, tgt = id_map[rel.source], id_map[rel.target]
                if src != tgt:
                    self.conn.execute(
                        "MATCH (a:Entity {id: $src}), (b:Entity {id: $tgt}) "
                        "MERGE (a)-[:RELATED {label: $label}]->(b)",
                        {"src": src, "tgt": tgt, "label": rel.label}
                    )


# === CONVERTER ===
def run_mineru(pdf_path: str) -> str | None:
    pdf_name = os.path.basename(pdf_path).replace(".pdf", "")
    expected_md = os.path.join(CONVERTER_OUTPUT_DIR, pdf_name, "auto", f"{pdf_name}.md")

    for cmd in ["mineru", "magic-pdf"]:
        if shutil.which(cmd):
            result = subprocess.run(
                [cmd, "-p", pdf_path, "-o", CONVERTER_OUTPUT_DIR, "-m", "auto"],
                capture_output=True, text=True
            )
            if result.returncode == 0 and os.path.exists(expected_md):
                return expected_md
    return None


# === EXTRACTION ===
def extract_knowledge(text: str, source_name: str = "unknown"):
    chunks = [c for c in text.split("\n## ") if len(c) >= 100]
    if not chunks:
        return

    kb = KnowledgeBase()

    for idx, chunk in enumerate(chunks):
        try:
            extraction = client.chat.completions.create(
                model=LLM_MODEL,
                response_model=Extraction,
                timeout=LLM_TIMEOUT,
                messages=[
                    {"role": "system", "content": "Extract technical entities and relations. Normalize names."},
                    {"role": "user", "content": f"Extract from:\n\n{chunk[:4000]}"}
                ]
            )
            kb.add_data(extraction)
            print(f"[{idx+1}/{len(chunks)}] +{len(extraction.entities)} entities")
        except Exception as e:
            print(f"[{idx+1}/{len(chunks)}] FAILED: {str(e)[:50]}")


# === WATCHDOG ===
def wait_for_file_complete(path: str, timeout: float = 60.0):
    """Wait for file to finish copying."""
    last_size = -1
    stable_time = 0
    start = time.time()

    while time.time() - start < timeout:
        try:
            size = os.path.getsize(path)
            if size == last_size:
                stable_time += 0.5
                if stable_time >= 2.0:
                    return True
            else:
                stable_time = 0
                last_size = size
        except OSError:
            pass
        time.sleep(0.5)

    return False


class PDFHandler(FileSystemEventHandler):
    def on_created(self, event):
        if not event.src_path.endswith(".pdf"):
            return

        pdf_name = os.path.basename(event.src_path)
        timestamp = datetime.now().strftime("%H:%M:%S")

        print(f"\n[{timestamp}] New PDF: {pdf_name}")

        if not wait_for_file_complete(event.src_path):
            print(f"[ERROR] Timeout waiting for {pdf_name}")
            return

        md_path = run_mineru(event.src_path)
        if md_path:
            with open(md_path) as f:
                extract_knowledge(f.read(), pdf_name)
            print(f"[DONE] {pdf_name}")
        else:
            print(f"[ERROR] Conversion failed for {pdf_name}")


if __name__ == "__main__":
    os.makedirs(WATCH_DIR, exist_ok=True)
    os.makedirs(CONVERTER_OUTPUT_DIR, exist_ok=True)

    print(f"{'='*60}")
    print(f"PDF Knowledge Graph Pipeline")
    print(f"{'='*60}")
    print(f"Watch directory: {WATCH_DIR}")
    print(f"Model: {LLM_MODEL}")
    print(f"Database: {DB_PATH}")
    print(f"Press Ctrl+C to stop")
    print(f"{'='*60}")

    observer = Observer()
    observer.schedule(PDFHandler(), WATCH_DIR)
    observer.start()

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nShutting down...")
        observer.stop()

    observer.join()
```

## Summary

Automation transforms the pipeline from a manual tool into infrastructure. Documents are dropped, knowledge is retrieved—the system handles all intermediate processing.

Key points:
- **Watchdog for real-time processing**: Process new documents as they arrive
- **Batch for backlog processing**: Handle existing collections efficiently
- **Progress tracking**: Resume after failures without reprocessing
- **Systemd for production**: Run as a reliable system service
- **Robust error handling**: Log failures, continue processing

The next post covers [visualizing the graph with vis.js](/posts/knowledge-graph-visualization-visjs/).

---

*Next: [Part 5 - Interactive Visualization with vis.js](/posts/knowledge-graph-visualization-visjs/)*

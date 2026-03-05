---
title: "PDF to Knowledge Graph (Part 2): Structured LLM Extraction with Instructor"
date: 2026-02-23
categories: [AI, LLM]
tags: [ollama, llm, instructor, pydantic, extraction, knowledge-graph]
series: pdf-to-knowledge-graph
series_order: 2
---

*Part 2 of the [PDF to Knowledge Graph series](/posts/local-pdf-to-knowledge-graph-series/).*

Large language models understand text remarkably well but produce frustratingly inconsistent output. Requesting "a list of entities" may yield JSON, bullet points, prose, or a creative interpretation of "list." The previous post converted PDFs to clean Markdown; this post extracts structured knowledge from that text using schema-enforced LLM calls.

## The Structured Output Problem

Consider extracting entities from a research paper abstract:

```python
response = llm.complete("""
Extract technical entities from this text. Return as JSON.

Text: "BERT uses the Transformer architecture with bidirectional
attention. It achieves state-of-the-art results on GLUE benchmark,
improving on ELMo's contextualized representations."
""")
```

The model might return any of these formats:

```json
{"entities": ["BERT", "Transformer", "GLUE", "ELMo"]}
```

```json
[
  {"name": "BERT", "type": "model"},
  {"name": "Transformer", "type": "architecture"},
  {"name": "GLUE", "type": "benchmark"},
  {"name": "ELMo", "type": "model"}
]
```

```text
The main entities mentioned are:
- BERT: A language model using bidirectional training
- Transformer: The underlying architecture
- GLUE: A benchmark for evaluation
- ELMo: A prior contextualized embedding approach
```

Each format requires different parsing logic. Run the same prompt twice—different structure. Add a new document type—new edge cases. The parsing code grows to handle every variation, and brittle regex patterns proliferate.

This problem compounds in pipelines. Downstream graph storage expects specific fields. Visualization expects relationship types. When the LLM invents a new output format, the entire pipeline fails.

## Instructor: Type-Safe LLM Outputs

[Instructor](https://github.com/jxnl/instructor) solves this by patching LLM clients to enforce Pydantic schemas. The developer defines the output structure; Instructor validates compliance. Invalid outputs trigger automatic retries with error context.

```python
from pydantic import BaseModel, Field
from typing import Literal, List
import instructor
from openai import OpenAI

# Define the schema
class Entity(BaseModel):
    """A technical concept extracted from text."""
    id: str = Field(..., description="Canonical name (e.g., 'BERT', 'CNN')")
    type: Literal["Paper", "Algorithm", "Metric", "Library", "Dataset"]
    summary: str = Field(..., description="One-sentence technical definition")

class Extraction(BaseModel):
    """Complete extraction from a text chunk."""
    entities: List[Entity]

# Patch the client
client = instructor.patch(OpenAI(
    base_url="http://localhost:11434/v1",
    api_key="ollama"
))

# Call with schema enforcement
result = client.chat.completions.create(
    model="qwen2.5:32b",
    response_model=Extraction,  # <-- Schema enforcement
    messages=[{
        "role": "user",
        "content": "Extract entities from: BERT uses the Transformer architecture..."
    }]
)

# result is guaranteed to be an Extraction instance
for entity in result.entities:
    print(f"{entity.id}: {entity.type} - {entity.summary}")
```

No JSON parsing. No validation code. No exception handling for malformed output. Either a valid `Extraction` object returns or the call raises an exception after exhausting retries.

## How Instructor Enforces Schemas

Instructor operates through several mechanisms:

**Function calling**: For models supporting OpenAI-style function calling, Instructor generates a JSON schema from the Pydantic model and passes it as the function specification. The model produces JSON matching the schema.

**JSON mode with validation**: For models supporting JSON mode but not function calling, Instructor instructs the model to output JSON, then validates against the Pydantic schema. Validation failures trigger retries with the error message included in the prompt.

**Retry with context**: When output fails validation, Instructor constructs a new prompt including the previous output and the validation error. This error-correction loop often succeeds within 2-3 attempts.

```python
# Instructor's internal retry loop (simplified)
for attempt in range(max_retries):
    response = llm.generate(prompt, json_mode=True)
    try:
        return Extraction.model_validate_json(response)
    except ValidationError as e:
        prompt = f"""Previous output was invalid:
{response}

Validation error: {e}

Please fix and try again."""
```

## Schema Design for Knowledge Graphs

Effective schemas balance expressiveness with LLM capability. Overly complex schemas confuse the model; overly simple schemas lose information.

### Entity Schema

```python
from pydantic import BaseModel, Field
from typing import Literal

class Entity(BaseModel):
    """A node in the knowledge graph."""

    id: str = Field(
        ...,
        description="Unique canonical name. Use standard abbreviations: "
                    "'CNN' not 'Convolutional Neural Network', "
                    "'BERT' not 'Bidirectional Encoder Representations'"
    )

    type: Literal["Paper", "Algorithm", "Metric", "Library", "Function", "Dataset"]

    summary: str = Field(
        ...,
        description="One sentence technical definition. "
                    "Should be understandable without reading the source."
    )
```

Key design decisions:

**`Literal` types constrain values**: The LLM cannot invent entity types. This ensures consistent categorization and simplifies downstream processing.

**Field descriptions guide extraction**: These descriptions become part of the prompt. Specific guidance ("Use standard abbreviations") directly improves output quality.

**Canonical IDs prevent duplicates**: Instructing the model to use standard names reduces post-processing deduplication work.

### Relationship Schema

```python
class Relation(BaseModel):
    """An edge in the knowledge graph."""

    source: str = Field(
        ...,
        description="ID of the source entity (must be an entity you extracted)"
    )

    target: str = Field(
        ...,
        description="ID of the target entity (must be an entity you extracted)"
    )

    label: Literal["PROPOSES", "USES", "IMPROVES", "IMPLEMENTS", "CITES", "EVALUATES_ON"]
```

Constraining relationship labels to a fixed vocabulary creates a consistent ontology. The graph becomes queryable: "find all algorithms that IMPROVE other algorithms."

### Complete Extraction Schema

```python
class Extraction(BaseModel):
    """Result of extracting knowledge from a text chunk."""
    entities: List[Entity]
    relations: List[Relation]
```

The combined schema extracts both nodes and edges in a single LLM call, maintaining referential integrity—relationships reference entities from the same extraction.

### Domain Customization

The schema should reflect the target domain:

**Machine Learning Research**:
```python
type: Literal["Paper", "Algorithm", "Architecture", "Dataset", "Metric", "Loss"]
label: Literal["PROPOSES", "USES", "IMPROVES", "TRAINED_ON", "EVALUATED_ON", "EXTENDS"]
```

**Biomedical Literature**:
```python
type: Literal["Disease", "Drug", "Gene", "Protein", "Pathway", "Cell"]
label: Literal["TREATS", "CAUSES", "INHIBITS", "EXPRESSES", "BINDS", "REGULATES"]
```

**Software Documentation**:
```python
type: Literal["Service", "API", "Database", "Class", "Function", "Pattern"]
label: Literal["CALLS", "DEPENDS_ON", "INHERITS", "IMPLEMENTS", "STORES_IN"]
```

**Legal Documents**:
```python
type: Literal["Statute", "Case", "Party", "Obligation", "Right", "Court"]
label: Literal["CITES", "OVERRULES", "INTERPRETS", "GRANTS", "RESTRICTS", "APPEALS_TO"]
```

## Ollama Integration

Ollama provides a local inference server with an OpenAI-compatible API. This enables Instructor integration without cloud dependencies:

```python
import instructor
from openai import OpenAI

# Configuration
OLLAMA_BASE_URL = "http://localhost:11434/v1"
LLM_MODEL = "qwen2.5:32b"
LLM_TIMEOUT = 120  # Seconds per extraction

# Create patched client
client = instructor.patch(OpenAI(
    base_url=OLLAMA_BASE_URL,
    api_key="ollama"  # Required by client, ignored by Ollama
))
```

Verify Ollama availability before processing:

```python
import urllib.request
import json

def check_ollama():
    """Verify Ollama is running and model is available."""
    try:
        response = urllib.request.urlopen(
            "http://localhost:11434/api/tags",
            timeout=5
        )
        data = json.loads(response.read().decode())
        models = [m["name"] for m in data.get("models", [])]

        if LLM_MODEL not in models:
            print(f"Model '{LLM_MODEL}' not found. Available: {models}")
            print(f"Run: ollama pull {LLM_MODEL}")
            return False
        return True
    except Exception as e:
        print(f"Ollama not responding: {e}")
        return False
```

## Chunking Strategies

Documents exceed context windows. Chunking divides text into processable segments while preserving semantic coherence.

### Header-Based Chunking

Technical documents organize content hierarchically. Splitting on headers respects author-defined boundaries:

```python
def chunk_by_headers(text: str, min_size: int = 100) -> list[str]:
    """Split markdown by ## headers, filtering small chunks."""
    chunks = text.split("\n## ")

    # First chunk may not start with ##
    if chunks and not text.startswith("## "):
        chunks[0] = chunks[0]  # Keep as-is
    else:
        chunks = ["## " + c for c in chunks]

    # Filter noise
    return [c for c in chunks if len(c) >= min_size]
```

Header-based chunking preserves:
- **Semantic boundaries**: Related concepts stay together
- **Context headers**: Section titles provide extraction context
- **Logical structure**: Authors organize content intentionally

Best for: Research papers, documentation, specifications, reports.

### Token-Based Chunking

Unstructured text lacks reliable boundaries. Token-based chunking with overlap prevents context loss at boundaries:

```python
def chunk_by_tokens(
    text: str,
    max_tokens: int = 1500,
    overlap: int = 200
) -> list[str]:
    """Split text into overlapping token windows."""
    from tiktoken import encoding_for_model

    enc = encoding_for_model("gpt-4")
    tokens = enc.encode(text)

    chunks = []
    start = 0

    while start < len(tokens):
        end = min(start + max_tokens, len(tokens))
        chunk_tokens = tokens[start:end]
        chunks.append(enc.decode(chunk_tokens))

        if end >= len(tokens):
            break
        start = end - overlap

    return chunks
```

Token counts matter because:
- Context windows have hard token limits
- Very long chunks increase latency and cost
- Overlap (10-15%) prevents entity loss at boundaries

Best for: Transcripts, prose, unstructured notes, web scrapes.

### Hybrid Chunking

Combine strategies: split by headers, then subdivide oversized sections:

```python
def chunk_hybrid(text: str, max_tokens: int = 2000) -> list[str]:
    """Header-based with token limit fallback."""
    from tiktoken import encoding_for_model
    enc = encoding_for_model("gpt-4")

    header_chunks = chunk_by_headers(text)
    final_chunks = []

    for chunk in header_chunks:
        tokens = enc.encode(chunk)
        if len(tokens) <= max_tokens:
            final_chunks.append(chunk)
        else:
            # Subdivide oversized sections
            sub_chunks = chunk_by_tokens(chunk, max_tokens, overlap=150)
            final_chunks.extend(sub_chunks)

    return final_chunks
```

## System Prompt Engineering

The system prompt shapes extraction behavior:

```python
SYSTEM_PROMPT = """You are a knowledge graph engineer extracting technical entities and relationships from academic text.

EXTRACTION RULES:
1. Entity IDs must be canonical names: use "CNN" not "Convolutional Neural Network"
2. Only extract entities explicitly mentioned in the text
3. Do not infer or add entities from general knowledge
4. Each relationship must connect entities you extracted
5. Summaries should be one sentence that defines the concept

ENTITY TYPES:
- Paper: Published research work
- Algorithm: Named computational method
- Architecture: Model structure or design pattern
- Dataset: Named data collection
- Metric: Evaluation measure
- Library: Software package or framework

RELATIONSHIP TYPES:
- PROPOSES: Paper introduces algorithm/architecture
- USES: Entity employs another entity
- IMPROVES: Entity extends or enhances another
- EVALUATES_ON: Paper/algorithm tested on dataset
- IMPLEMENTS: Library provides algorithm"""
```

Prompt engineering principles:

**Be explicit about constraints**: "Only extract entities explicitly mentioned" prevents hallucination of related concepts.

**Provide examples in descriptions**: The Field descriptions serve as few-shot guidance.

**Define the ontology**: List valid types and relationships with definitions.

**Explain the output purpose**: "knowledge graph engineer" frames the task appropriately.

## Complete Extraction Pipeline

```python
#!/usr/bin/env python3
"""
Structured knowledge extraction from markdown using Instructor and Ollama.
"""

import time
from typing import Literal, List
from pydantic import BaseModel, Field
import instructor
from openai import OpenAI

# === CONFIGURATION ===
OLLAMA_BASE_URL = "http://localhost:11434/v1"
LLM_MODEL = "qwen2.5:32b"
LLM_TIMEOUT = 120

# === SCHEMA ===
class Entity(BaseModel):
    id: str = Field(..., description="Canonical technical name")
    type: Literal["Paper", "Algorithm", "Architecture", "Dataset", "Metric", "Library"]
    summary: str = Field(..., description="One sentence definition")

class Relation(BaseModel):
    source: str = Field(..., description="Source entity ID")
    target: str = Field(..., description="Target entity ID")
    label: Literal["PROPOSES", "USES", "IMPROVES", "EVALUATES_ON", "IMPLEMENTS"]

class Extraction(BaseModel):
    entities: List[Entity]
    relations: List[Relation]

# === CLIENT ===
client = instructor.patch(OpenAI(
    base_url=OLLAMA_BASE_URL,
    api_key="ollama"
))

SYSTEM_PROMPT = """You are a knowledge graph engineer. Extract technical entities and relationships.

Rules:
1. Use canonical names (CNN not Convolutional Neural Network)
2. Only extract explicitly mentioned entities
3. Relations must connect extracted entities
4. One sentence summaries"""

# === EXTRACTION ===
def extract_from_chunk(chunk: str) -> Extraction | None:
    """Extract entities and relations from a single chunk."""
    try:
        return client.chat.completions.create(
            model=LLM_MODEL,
            response_model=Extraction,
            timeout=LLM_TIMEOUT,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": f"Extract from:\n\n{chunk[:4000]}"}
            ]
        )
    except Exception as e:
        print(f"Extraction failed: {e}")
        return None

def extract_from_document(text: str) -> tuple[List[Entity], List[Relation]]:
    """Extract from entire document, aggregating results."""
    chunks = [c for c in text.split("\n## ") if len(c) >= 100]

    all_entities = []
    all_relations = []

    print(f"Processing {len(chunks)} chunks with {LLM_MODEL}")

    for i, chunk in enumerate(chunks):
        start = time.time()
        result = extract_from_chunk(chunk)
        elapsed = time.time() - start

        if result:
            all_entities.extend(result.entities)
            all_relations.extend(result.relations)
            print(f"[{i+1}/{len(chunks)}] {elapsed:.1f}s | "
                  f"+{len(result.entities)} entities, +{len(result.relations)} relations")
        else:
            print(f"[{i+1}/{len(chunks)}] {elapsed:.1f}s | FAILED")

    return all_entities, all_relations

# === MAIN ===
if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("Usage: python extract.py <markdown_file>")
        sys.exit(1)

    with open(sys.argv[1], "r", encoding="utf-8") as f:
        text = f.read()

    entities, relations = extract_from_document(text)

    print(f"\n=== RESULTS ===")
    print(f"Entities: {len(entities)}")
    print(f"Relations: {len(relations)}")

    print("\n--- Entities ---")
    for e in entities:
        print(f"  [{e.type}] {e.id}: {e.summary}")

    print("\n--- Relations ---")
    for r in relations:
        print(f"  {r.source} --[{r.label}]--> {r.target}")
```

## Error Handling Strategies

Production pipelines require robust error handling:

```python
from instructor.exceptions import InstructorRetryException

def safe_extract(
    chunk: str,
    max_retries: int = 3,
    timeout: int = 120
) -> Extraction:
    """Extract with comprehensive error handling."""

    for attempt in range(max_retries):
        try:
            return client.chat.completions.create(
                model=LLM_MODEL,
                response_model=Extraction,
                timeout=timeout,
                max_retries=2,  # Instructor's internal retries
                messages=[
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": f"Extract from:\n\n{chunk[:4000]}"}
                ]
            )

        except InstructorRetryException as e:
            print(f"  Attempt {attempt+1}: Schema validation failed")
            if attempt == max_retries - 1:
                print(f"  Giving up after {max_retries} attempts")

        except TimeoutError:
            print(f"  Attempt {attempt+1}: Timeout after {timeout}s")

        except Exception as e:
            print(f"  Attempt {attempt+1}: {type(e).__name__}: {str(e)[:100]}")

    # Return empty extraction on total failure
    return Extraction(entities=[], relations=[])
```

Handling strategies:

**Empty result over exception**: A failed chunk should not crash the pipeline. Return empty extraction and continue.

**Log failures with context**: Record which chunks failed for manual review.

**Tune timeouts per model**: Larger models need longer timeouts. 72B models may require 180+ seconds for complex chunks.

## Model Selection

Extraction quality varies significantly by model:

| Model | VRAM | Speed | Quality | Notes |
|-------|------|-------|---------|-------|
| qwen2.5:72b | 48GB+ | ~60s/chunk | Excellent | Best extraction quality |
| qwen2.5:32b | 24GB+ | ~30s/chunk | Very Good | Recommended balance |
| qwen2.5:7b | 8GB+ | ~10s/chunk | Good | Sufficient for simple schemas |
| llama3.1:70b | 48GB+ | ~60s/chunk | Excellent | Strong reasoning |
| llama3.1:8b | 8GB+ | ~10s/chunk | Good | Lightweight option |
| mixtral:8x7b | 32GB+ | ~25s/chunk | Very Good | Good for diverse content |
| deepseek-r1:32b | 24GB+ | ~40s/chunk | Excellent | Strong at structured output |

For knowledge extraction, prioritize quality over speed. Each document is processed once; the graph persists indefinitely. A 10x slower model that produces 20% better extractions is the correct tradeoff.

Quantization affects quality. Prefer Q8 or higher for extraction tasks. Q4 quantization may produce more hallucinations and miss subtle relationships.

## Entity Resolution

Extracted entities require normalization before graph insertion. The same concept may appear with different names:

- "Transformer" vs "Transformers" vs "transformer architecture"
- "BERT" vs "BERT model" vs "Bidirectional Encoder"
- "ImageNet" vs "ImageNet-1K" vs "ILSVRC"

Fuzzy matching identifies duplicates:

```python
from rapidfuzz import process, fuzz

def resolve_entity_id(
    new_id: str,
    existing_ids: list[str],
    threshold: float = 92.0
) -> str:
    """Match new entity to existing if similar enough."""
    if not existing_ids:
        return new_id

    match, score, _ = process.extractOne(
        new_id,
        existing_ids,
        scorer=fuzz.ratio
    )

    if score >= threshold:
        print(f"  Resolved: '{new_id}' -> '{match}' (score: {score:.1f})")
        return match

    return new_id
```

High threshold (92+) prevents false merges. "BERT" and "RoBERTa" are distinct despite similarity. Lower thresholds (85-90) suit domains with more naming variation.

## Performance Optimization

### Parallel Extraction

Independent chunks can be processed concurrently:

```python
from concurrent.futures import ThreadPoolExecutor, as_completed

def extract_parallel(
    chunks: list[str],
    max_workers: int = 4
) -> list[Extraction]:
    """Extract from multiple chunks concurrently."""

    results = []

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {
            executor.submit(safe_extract, chunk): i
            for i, chunk in enumerate(chunks)
        }

        for future in as_completed(futures):
            idx = futures[future]
            try:
                result = future.result()
                results.append((idx, result))
            except Exception as e:
                print(f"Chunk {idx} failed: {e}")
                results.append((idx, Extraction(entities=[], relations=[])))

    # Sort by original order
    results.sort(key=lambda x: x[0])
    return [r[1] for r in results]
```

Limit parallelism based on GPU VRAM. Running 4 concurrent extractions on a 32B model requires 4x the memory of sequential processing. For local Ollama with a single GPU, 2-3 workers is often optimal.

### Caching

Cache extractions to avoid reprocessing:

```python
import hashlib
import json
from pathlib import Path

CACHE_DIR = Path(".extraction_cache")

def get_cache_key(chunk: str, model: str) -> str:
    """Generate deterministic cache key."""
    content = f"{model}:{chunk}"
    return hashlib.sha256(content.encode()).hexdigest()[:16]

def cached_extract(chunk: str) -> Extraction:
    """Extract with filesystem cache."""
    CACHE_DIR.mkdir(exist_ok=True)

    key = get_cache_key(chunk, LLM_MODEL)
    cache_path = CACHE_DIR / f"{key}.json"

    if cache_path.exists():
        data = json.loads(cache_path.read_text())
        return Extraction.model_validate(data)

    result = safe_extract(chunk)
    cache_path.write_text(result.model_dump_json())

    return result
```

Cache invalidation: include model name and prompt version in the cache key. Schema changes require cache clearing.

## Summary

Instructor transforms LLM output from unpredictable text into reliable typed objects. Combined with Ollama's local inference, this enables building knowledge extraction pipelines without cloud dependencies or parsing fragility.

Key principles:

1. **Schema design shapes extraction quality**: Constrained `Literal` types, descriptive `Field` annotations, and clear ontology definitions guide the model toward consistent output.

2. **Chunking preserves context**: Header-based splitting respects document structure. Token limits prevent context overflow.

3. **Failure isolation protects pipelines**: Empty results from failed chunks are preferable to crashed processes.

4. **Quality over speed for extraction**: Documents are processed once; extracted knowledge persists. Invest in the best model that fits available hardware.

5. **Entity resolution normalizes variations**: Fuzzy matching merges equivalent entities before graph insertion.

The next post covers [storing extractions in Kuzu](/posts/knowledge-graph-kuzu/), an embedded graph database that enables efficient querying of the extracted knowledge.

---

*Next: [Part 3 - Graph Storage with Kuzu](/posts/knowledge-graph-kuzu/)*

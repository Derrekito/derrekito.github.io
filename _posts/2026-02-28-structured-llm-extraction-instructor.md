---
title: "Part 2: Structured LLM Extraction with Instructor"
date: 2026-02-28 10:00:00 -0700
categories: [AI, LLM]
tags: [ollama, llm, instructor, pydantic, extraction, knowledge-graph]
series: pdf-to-knowledge-graph
series_order: 2
---

*Part 2 of the [PDF to Knowledge Graph series](/posts/local-pdf-to-knowledge-graph-series/).*

Large language models understand text remarkably well but produce frustratingly inconsistent output. Requesting "a list of entities" may yield JSON, bullet points, prose, or a creative interpretation of "list." Instructor solves this through Pydantic schema enforcement—the LLM's output must match the specified schema or the call fails and retries.

## Problem Statement

Consider extracting entities from text using raw LLM prompting:

```python
response = llm.complete("""
Extract entities from this text. Return JSON.
Text: "BERT uses the Transformer architecture..."
""")
```

Possible outputs:
```json
{"entities": ["BERT", "Transformer"]}
```
```json
[{"name": "BERT", "type": "model"}, {"name": "Transformer", "type": "architecture"}]
```
```text
The entities are: BERT (a model) and Transformer (an architecture).
```

Each output format requires different parsing logic. Edge cases multiply. Validation becomes a constant battle.

## Instructor: Schema Enforcement

[Instructor](https://github.com/jxnl/instructor) patches the OpenAI client to enforce Pydantic models. The schema defines the structure; Instructor ensures compliance:

```python
from pydantic import BaseModel
import instructor
from openai import OpenAI

class Entity(BaseModel):
    name: str
    type: str

class Extraction(BaseModel):
    entities: list[Entity]

client = instructor.patch(OpenAI(...))

result = client.chat.completions.create(
    model="gpt-4",
    response_model=Extraction,  # <-- Schema enforcement
    messages=[{"role": "user", "content": "Extract from: BERT uses Transformer..."}]
)

# result is guaranteed to be an Extraction instance
print(result.entities[0].name)  # "BERT"
```

No parsing. No validation. Either a valid `Extraction` is returned or an exception is raised.

## Configuration with Ollama

Ollama provides an OpenAI-compatible API, enabling seamless integration with Instructor:

```python
import instructor
from openai import OpenAI

# Point to local Ollama instance
client = instructor.patch(OpenAI(
    base_url="http://localhost:11434/v1",
    api_key="ollama",  # Required but ignored by Ollama
))

# Model configuration
LLM_MODEL = "qwen2.5:72b"  # Or smaller: qwen2.5:7b, llama3.1:8b
LLM_TIMEOUT = 120  # Seconds per extraction
```

Verify Ollama is running:

```bash
ollama list  # Should show your models
curl http://localhost:11434/v1/models  # API check
```

## Extraction Schema Design

The schema defines the extraction targets. Design should reflect the target domain.

### Entity Types

```python
from typing import Literal
from pydantic import BaseModel, Field

class Entity(BaseModel):
    """A concept, paper, algorithm, or other extractable entity."""
    id: str = Field(
        ...,
        description="Unique technical name (e.g., 'Transformer', 'ReLU', 'BERT')"
    )
    type: Literal["Paper", "Algorithm", "Metric", "Library", "Function"]
    summary: str = Field(
        ...,
        description="One sentence technical definition"
    )
```

The `Literal` type constrains values. The `Field` descriptions guide the LLM.

### Relationship Types

```python
class Relation(BaseModel):
    """A relationship between two entities."""
    source: str
    target: str
    label: Literal["PROPOSES", "USES", "IMPROVES", "IMPLEMENTS", "CITES"]
```

### Complete Extraction Schema

```python
class Extraction(BaseModel):
    """Complete extraction result from a text chunk."""
    entities: list[Entity]
    relations: list[Relation]
```

### Domain Customization

Types should be adapted for the target field:

**Medical/Biology:**
```python
type: Literal["Disease", "Drug", "Gene", "Protein", "Pathway"]
label: Literal["TREATS", "CAUSES", "INHIBITS", "EXPRESSES", "BINDS"]
```

**Software Engineering:**
```python
type: Literal["Service", "API", "Database", "Pattern", "Framework"]
label: Literal["CALLS", "DEPENDS_ON", "STORES_IN", "IMPLEMENTS", "EXTENDS"]
```

**Legal Documents:**
```python
type: Literal["Statute", "Case", "Party", "Obligation", "Right"]
label: Literal["CITES", "OVERRULES", "INTERPRETS", "GRANTS", "RESTRICTS"]
```

## Extraction Function Implementation

```python
def extract_knowledge(markdown_text: str, source_name: str = "unknown"):
    """Extract entities and relations from markdown text."""

    # Split by headers to keep context local
    chunks = markdown_text.split("\n## ")

    # Filter tiny chunks (< 100 chars are usually noise)
    valid_chunks = [(i, c) for i, c in enumerate(chunks) if len(c) >= 100]

    if not valid_chunks:
        print("[WARN] No valid chunks found")
        return []

    all_extractions = []
    print(f"[INFO] Processing {len(valid_chunks)} chunks with {LLM_MODEL}")

    for idx, (chunk_num, chunk) in enumerate(valid_chunks):
        try:
            extraction = client.chat.completions.create(
                model=LLM_MODEL,
                response_model=Extraction,
                timeout=LLM_TIMEOUT,
                messages=[
                    {
                        "role": "system",
                        "content": (
                            "You are a knowledge graph engineer. "
                            "Extract technical entities and their relationships. "
                            "Normalize names (use 'CNN' not 'Convolutional Neural Networks'). "
                            "Only extract entities explicitly mentioned in the text."
                        )
                    },
                    {
                        "role": "user",
                        "content": f"Extract entities and relations from:\n\n{chunk[:4000]}"
                    }
                ]
            )

            all_extractions.append(extraction)
            n_entities = len(extraction.entities)
            n_relations = len(extraction.relations)
            print(f"[{idx+1}/{len(valid_chunks)}] +{n_entities} entities, +{n_relations} relations")

        except Exception as e:
            print(f"[{idx+1}/{len(valid_chunks)}] FAILED: {str(e)[:100]}")

    return all_extractions
```

## Chunking Strategies

Document splitting strategy affects extraction quality.

### Header-Based Chunking (Recommended for Technical Documents)

```python
chunks = text.split("\n## ")
```

**Advantages:**
- Preserves semantic boundaries
- Authors organize content logically
- Related concepts remain together

**Best for:** Research papers, documentation, specifications

### Token-Based Chunking

```python
from tiktoken import encoding_for_model

def chunk_by_tokens(text: str, max_tokens: int = 1500, overlap: int = 200):
    """Split text into overlapping token chunks."""
    enc = encoding_for_model("gpt-4")
    tokens = enc.encode(text)

    chunks = []
    start = 0
    while start < len(tokens):
        end = start + max_tokens
        chunk_tokens = tokens[start:end]
        chunks.append(enc.decode(chunk_tokens))
        start = end - overlap

    return chunks
```

**Best for:** Unstructured text, transcripts, prose

### Paragraph-Based Chunking

```python
def chunk_by_paragraphs(text: str, paragraphs_per_chunk: int = 5):
    """Group paragraphs into chunks."""
    paragraphs = text.split("\n\n")
    chunks = []
    for i in range(0, len(paragraphs), paragraphs_per_chunk):
        chunk = "\n\n".join(paragraphs[i:i + paragraphs_per_chunk])
        if len(chunk) >= 100:
            chunks.append(chunk)
    return chunks
```

**Best for:** Essays, articles, general documents

## Error Handling

Instructor retries on schema violations, but some failures require explicit handling:

```python
from instructor.exceptions import InstructorRetryException

def safe_extract(chunk: str, max_retries: int = 3):
    """Extract with explicit retry handling."""
    for attempt in range(max_retries):
        try:
            return client.chat.completions.create(
                model=LLM_MODEL,
                response_model=Extraction,
                timeout=LLM_TIMEOUT,
                max_retries=2,  # Instructor's internal retries
                messages=[
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": f"Extract from:\n\n{chunk[:4000]}"}
                ]
            )
        except InstructorRetryException:
            print(f"  Retry {attempt + 1}/{max_retries}: Schema violation")
        except TimeoutError:
            print(f"  Retry {attempt + 1}/{max_retries}: Timeout")
        except Exception as e:
            print(f"  Retry {attempt + 1}/{max_retries}: {type(e).__name__}")

    return Extraction(entities=[], relations=[])  # Empty on total failure
```

## Model Selection

Extraction quality varies by model:

| Model | VRAM | Speed | Quality | Notes |
|-------|------|-------|---------|-------|
| qwen2.5:72b | 48GB+ | Slow | Excellent | Best extraction quality |
| qwen2.5:32b | 24GB+ | Medium | Very Good | Good balance |
| qwen2.5:7b | 8GB+ | Fast | Good | Sufficient for simple schemas |
| llama3.1:70b | 48GB+ | Slow | Excellent | Strong reasoning |
| llama3.1:8b | 8GB+ | Fast | Good | Lightweight option |
| mixtral:8x7b | 32GB+ | Medium | Very Good | Good for diverse content |

For knowledge extraction, quality should be prioritized over speed—each document is processed once.

## Prompt Engineering Guidelines

### Name Normalization

```python
"Normalize entity names: use 'CNN' not 'Convolutional Neural Network', "
"'BERT' not 'Bidirectional Encoder Representations from Transformers'"
```

### Hallucination Constraints

```python
"Only extract entities explicitly mentioned in the text. "
"Do not infer or add entities from general knowledge."
```

### Relationship Extraction Guidance

```python
"For each relationship, both source and target must be entities you extracted. "
"Do not create relationships to entities not in your entity list."
```

### Few-Shot Examples

```python
"""
Example extraction from: "BERT improves on ELMo by using bidirectional training."

entities:
- id: "BERT", type: "Algorithm", summary: "Bidirectional language model"
- id: "ELMo", type: "Algorithm", summary: "Contextualized word embeddings"

relations:
- source: "BERT", target: "ELMo", label: "IMPROVES"
"""
```

## Complete Extraction Pipeline

```python
#!/usr/bin/env python3
"""
Structured extraction from markdown using Instructor and Ollama.
"""

from typing import Literal, List
from pydantic import BaseModel, Field
import instructor
from openai import OpenAI

# Configuration
LLM_MODEL = "qwen2.5:32b"
LLM_TIMEOUT = 120

# Schema
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

# Client
client = instructor.patch(OpenAI(
    base_url="http://localhost:11434/v1",
    api_key="ollama",
))

SYSTEM_PROMPT = """You are a knowledge graph engineer extracting technical entities and relationships.

Rules:
1. Normalize names (CNN not Convolutional Neural Network)
2. Only extract explicitly mentioned entities
3. Relations must connect entities you extracted
4. Summaries should be one sentence definitions"""

def extract_from_markdown(text: str) -> List[Extraction]:
    """Extract all entities and relations from markdown text."""
    chunks = [c for c in text.split("\n## ") if len(c) >= 100]

    results = []
    for i, chunk in enumerate(chunks):
        try:
            extraction = client.chat.completions.create(
                model=LLM_MODEL,
                response_model=Extraction,
                timeout=LLM_TIMEOUT,
                messages=[
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": f"Extract from:\n\n{chunk[:4000]}"}
                ]
            )
            results.append(extraction)
            print(f"[{i+1}/{len(chunks)}] {len(extraction.entities)} entities")
        except Exception as e:
            print(f"[{i+1}/{len(chunks)}] Failed: {e}")

    return results

# Usage
if __name__ == "__main__":
    with open("document.md") as f:
        text = f.read()

    extractions = extract_from_markdown(text)

    # Aggregate results
    all_entities = [e for ext in extractions for e in ext.entities]
    all_relations = [r for ext in extractions for r in ext.relations]

    print(f"\nTotal: {len(all_entities)} entities, {len(all_relations)} relations")
```

## Summary

Instructor transforms LLM extraction from a parsing challenge to a type-safe operation. Combined with Ollama's local inference, reliable structured extraction is achievable without cloud dependencies.

Key points:
- **Schema definition with Pydantic**: Types, constraints, and descriptions guide extraction
- **Strategic chunking**: Respecting document structure yields coherent extraction
- **Graceful failure handling**: Empty results are preferable to crashed pipelines
- **Model selection for quality**: Extraction is a one-time cost; accuracy should be prioritized

The next post covers [storing extractions in Kuzu](/posts/knowledge-graph-kuzu/).

---

*Next: [Part 3 - Graph Storage with Kuzu](/posts/knowledge-graph-kuzu/)*

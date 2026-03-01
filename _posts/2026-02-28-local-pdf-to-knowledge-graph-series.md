---
title: "Part 0: From PDFs to Knowledge Graphs - Series Overview"
date: 2026-02-28 10:00:00 -0700
categories: [AI, Knowledge Graphs]
tags: [knowledge-graph, ollama, pdf, graphrag, llm, series]
series: pdf-to-knowledge-graph
series_order: 0
---

Technical documentation exists in a paradox: more is generated than ever, yet extracting actionable knowledge remains stubbornly manual. Research papers, specifications, internal documentation—these artifacts contain structured knowledge trapped in unstructured formats. This series presents a complete, local-first pipeline for liberating that knowledge into queryable graph structures.

## Problem Statement

Traditional document management fails knowledge workers in predictable ways. Full-text search returns documents, not answers. Keyword matching misses semantic relationships. Manual curation does not scale. The result is institutional knowledge fragmented across PDFs, understood fully by no one, and rediscovered repeatedly at significant cost.

Knowledge graphs offer a structural solution. By representing information as entities and relationships, documents transform from opaque artifacts into navigable knowledge structures. The challenge lies in construction: manually building graphs is prohibitively expensive, while cloud-based solutions raise legitimate concerns about data sovereignty, cost, and vendor dependency.

This series addresses that gap with a fully local pipeline requiring no external APIs, no cloud services, and no ongoing costs beyond hardware.

## Architecture Overview

The pipeline comprises six stages, each covered in a dedicated post:

```text
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│    PDF      │──▶│   MinerU    │──▶│  Markdown   │
│  Documents  │    │  Extraction │    │    Text     │
└─────────────┘    └─────────────┘    └─────────────┘
                                            │
                                            ▼
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│    Kuzu     │◀──│ Instructor  │◀──│   Ollama    │
│    Graph    │    │   Schema    │    │     LLM     │
└─────────────┘    └─────────────┘    └─────────────┘
       │
       ▼
┌─────────────┐    ┌─────────────┐
│   vis.js    │    │  LLM Query  │
│    Visual   │    │  Interface  │
└─────────────┘    └─────────────┘
```

Each component was selected for specific technical merits:

| Component  | Function              | Selection Rationale                                  |
| ---------- | --------------------- | ---------------------------------------------------- |
| MinerU     | PDF → Markdown        | Superior LaTeX preservation, complex layout handling |
| Ollama     | Local LLM inference   | OpenAI-compatible API, consumer hardware support     |
| Instructor | Structured extraction | Pydantic schema enforcement, reliable output         |
| Kuzu       | Graph storage         | Embedded (serverless), Cypher support, performant    |
| vis.js     | Visualization         | Browser-native, interactive, no server required      |

## Series Contents

### Part 1: PDF Extraction with MinerU

**[Read Part 1 →](/posts/pdf-extraction-mineru/)**

PDF extraction is the critical first stage—and the most frequently underestimated. Standard libraries (PyPDF2, pdfplumber) struggle with multi-column layouts, embedded equations, and complex tables. MinerU, developed by OpenDataLab, addresses these limitations through deep learning-based layout analysis.

This post covers:

- Installation and configuration
- Handling LaTeX equations (preserved as `$...$` notation)
- Table extraction to Markdown format
- Multi-column layout reconstruction
- Batch processing strategies

**Significance**: Garbage in, garbage out. No amount of sophisticated downstream processing compensates for mangled extraction. MinerU's layout-aware approach preserves document structure that naive text extraction destroys.

---

### Part 2: Structured LLM Extraction with Instructor

**[Read Part 2 →](/posts/structured-llm-extraction-instructor/)**

Large language models excel at understanding text but struggle with consistent output formats. Instructor solves this through Pydantic schema enforcement—the LLM must produce output conforming to the specified structure or the call fails and retries.

This post covers:

- Designing extraction schemas (entities, relationships, types)
- Configuring Instructor with Ollama's OpenAI-compatible API
- Chunking strategies for optimal extraction
- Handling extraction failures gracefully
- Domain-specific schema customization

**Significance**: Unstructured LLM output requires parsing, validation, and error handling. Instructor eliminates this entirely—a Pydantic model is defined, and extraction either succeeds with valid data or fails explicitly.

---

### Part 3: Graph Storage with Kuzu

**[Read Part 3 →](/posts/knowledge-graph-kuzu/)**

Graph databases model relationships natively, but most (Neo4j, Amazon Neptune) require server infrastructure. Kuzu is an embedded graph database—no server, no Docker, just a library and a file. It supports Cypher queries and handles millions of nodes on modest hardware.

This post covers:

- Schema design for knowledge representation
- Entity resolution through fuzzy matching (RapidFuzz)
- MERGE operations for idempotent ingestion
- Cypher query patterns for knowledge retrieval
- Performance considerations

**Significance**: The choice of Kuzu eliminates operational complexity. The knowledge graph is a single file, trivially backed up, requiring no running services. This simplicity enables experimentation without infrastructure commitment.

---

### Part 4: Automated Pipeline with Watchdog

**[Read Part 4 →](/posts/automated-pdf-pipeline-watchdog/)**

Manual processing does not scale. This post presents a file-watching system that automatically processes new PDFs through the complete pipeline: conversion, extraction, and graph ingestion.

This post covers:

- Watchdog for filesystem monitoring
- Robust error handling and recovery
- Batch processing for initial corpus ingestion
- Progress tracking and logging
- Systemd integration for production deployment

**Significance**: Automation transforms the pipeline from a tool into infrastructure. Drop a PDF, retrieve knowledge—no manual intervention required.

---

### Part 5: Interactive Visualization with vis.js

**[Read Part 5 →](/posts/knowledge-graph-visualization-visjs/)**

Graphs are inherently visual structures, yet most graph databases offer only textual query interfaces. This post generates interactive HTML visualizations directly from Kuzu, explorable in any browser.

This post covers:

- Exporting graph data for visualization
- Node coloring by entity type
- Edge styling by relationship type
- Size encoding for connectivity
- Filtering subgraphs by concept
- Tooltips and interactive navigation

**Significance**: Visualization reveals structure invisible in tabular query results. Clusters emerge. Isolates become apparent. The graph becomes explorable rather than merely queryable.

---

### Part 6: RAG with Knowledge Graphs

**[Read Part 6 →](/posts/rag-knowledge-graphs/)**

Retrieval-Augmented Generation (RAG) grounds LLM responses in retrieved context. Most RAG systems use vector similarity over text chunks. Graph-based RAG retrieves structured relationships, enabling more precise and verifiable answers.

This post covers:

- Keyword-based entity retrieval
- Relationship expansion for context building
- Prompt engineering for grounded responses
- Cypher generation from natural language
- Combining graph structure with LLM reasoning

**Significance**: Traditional RAG returns "documents about X." Graph RAG returns "what the documents say about how X relates to Y, Z, and W"—structured knowledge rather than relevant text.

---

## Technical Requirements

The complete pipeline runs on consumer hardware:

| Resource   | Minimum         | Recommended                     |
| ---------- | --------------- | ------------------------------- |
| GPU VRAM   | 8GB (7B models) | 24GB+ (32B-70B models)          |
| System RAM | 16GB            | 32GB+                           |
| Storage    | 50GB            | 200GB+ (for model weights)      |
| OS         | Linux, macOS    | Linux (best Ollama performance) |

Software dependencies:

- Python 3.10+
- Ollama
- MinerU (via pip or conda)
- CUDA toolkit (for GPU inference)

## Design Decisions and Trade-offs

Several architectural choices merit explicit discussion:

**Local-first over cloud APIs**: Cloud LLM APIs (OpenAI, Anthropic, Google) offer superior models but introduce data sovereignty concerns, usage costs, and availability dependencies. For technical documentation—often containing proprietary information—local processing is a feature, not a limitation.

**Kuzu over Neo4j**: Neo4j is the industry standard but requires server infrastructure. For single-user knowledge bases under millions of nodes, Kuzu's embedded architecture eliminates operational overhead without sacrificing query capability.

**Instructor over raw prompting**: Unstructured LLM output requires parsing logic that inevitably encounters edge cases. Instructor's schema enforcement moves validation to the API boundary, where failures can be retried automatically.

**Chunking by headers over fixed windows**: Technical documents have inherent structure (sections, subsections). Respecting this structure keeps related concepts together, improving extraction coherence over arbitrary token windows.

**Fuzzy matching over embeddings for entity resolution**: Embedding-based similarity requires additional infrastructure (vector database, embedding model). For entity names, fuzzy string matching (RapidFuzz) achieves sufficient accuracy with minimal complexity.

## Limitations and Future Directions

This pipeline has known limitations worth acknowledging:

1. **Extraction quality varies by domain**: The default schema targets ML/AI papers. Other domains require schema customization.

2. **No cross-document coreference**: Entity resolution operates on names only. "The authors" in different papers creates no link.

3. **Relationship types are coarse**: Five relationship types capture common patterns but miss domain-specific nuances.

4. **No incremental updates**: Re-extracting a modified PDF creates duplicate entities unless manually resolved.

5. **Visualization scales poorly**: vis.js handles hundreds of nodes well; thousands require filtering or alternative approaches.

Future work might address these through:

- Few-shot schema adaptation per domain
- Embedding-based coreference resolution
- Hierarchical relationship taxonomies
- Content-addressed entity identification
- Server-side graph rendering for large graphs

## Getting Started

The recommended path through this series:

1. **Start with Part 1** (MinerU) to validate PDF extraction quality on target documents
2. **Proceed to Part 2** (Instructor) to design extraction schemas for the target domain
3. **Part 3** (Kuzu) to understand storage and querying
4. **Part 4** (Watchdog) when ready to automate
5. **Parts 5-6** (Visualization, RAG) for knowledge access

Each post is self-contained with complete code. Clone the [companion repository](https://github.com/derrekito/knowledge_graph_db) for the full implementation.

## Summary

Knowledge graphs transform document collections from search targets into reasoning substrates. The pipeline presented here demonstrates that sophisticated knowledge extraction no longer requires cloud infrastructure or commercial tooling. Consumer hardware running open models can process technical documentation into queryable graph structures, entirely locally, at zero marginal cost.

The result is document intelligence infrastructure with complete ownership—no API keys, no usage limits, no data leaving the network. For organizations with sensitive technical documentation, this local-first approach may be the only viable path to automated knowledge extraction.

The series begins with [Part 1: PDF Extraction with MinerU →](/posts/pdf-extraction-mineru/)

---

## Series Index

1. [PDF Extraction with MinerU](/posts/pdf-extraction-mineru/)
2. [Structured LLM Extraction with Instructor](/posts/structured-llm-extraction-instructor/)
3. [Graph Storage with Kuzu](/posts/knowledge-graph-kuzu/)
4. [Automated Pipeline with Watchdog](/posts/automated-pdf-pipeline-watchdog/)
5. [Interactive Visualization with vis.js](/posts/knowledge-graph-visualization-visjs/)
6. [RAG with Knowledge Graphs](/posts/rag-knowledge-graphs/)

---
title: "Part 6: RAG with Knowledge Graphs"
date: 2026-02-28 10:00:00 -0700
categories: [AI, RAG]
tags: [rag, knowledge-graph, llm, ollama, graphrag]
series: pdf-to-knowledge-graph
series_order: 6
---

*Part 6 of the [PDF to Knowledge Graph series](/posts/local-pdf-to-knowledge-graph-series/).*

Retrieval-Augmented Generation (RAG) grounds LLM responses in retrieved context rather than relying solely on parametric memory. Most RAG systems use vector similarity over text chunks—effective but limited. Graph-based RAG retrieves structured relationships, enabling more precise and verifiable answers about how concepts connect.

## Vector RAG vs. Graph RAG

### Traditional Vector RAG

```text
Query: "What improves on BERT?"

1. Embed query
2. Find similar text chunks by cosine similarity
3. Return chunks mentioning BERT
4. LLM synthesizes answer from chunks
```

**Limitation**: Returns documents *about* BERT, not necessarily documents describing improvements *to* BERT. The relationship is implicit in the text, requiring the LLM to infer it.

### Graph RAG

```text
Query: "What improves on BERT?"

1. Extract entities from query (BERT)
2. Traverse graph: MATCH (x)-[:IMPROVES]->(BERT)
3. Return structured relationships
4. LLM explains relationships in context
```

**Advantage**: Returns entities with explicit IMPROVES relationships to BERT. The relationship is structural, not inferred.

## Query Interface

### Keyword-Based Entity Retrieval

A simple but effective approach—extract keywords and match against entity IDs and summaries:

```python
import kuzu
from openai import OpenAI

DB_PATH = "./kuzu_graph_db"
LLM_MODEL = "qwen2.5:32b"

client = OpenAI(
    base_url="http://localhost:11434/v1",
    api_key="ollama"
)


def extract_keywords(query: str) -> list[str]:
    """Extract meaningful keywords from query."""
    # Simple approach: filter short words and stopwords
    stopwords = {'what', 'which', 'how', 'does', 'the', 'and', 'for', 'are', 'is'}
    words = query.lower().split()
    return [w for w in words if len(w) > 3 and w not in stopwords]


def get_relevant_context(conn, query: str, max_entities: int = 20) -> str:
    """Retrieve relevant entities and relations for a query."""

    keywords = extract_keywords(query)

    # Get all entities
    all_entities = conn.execute("""
        MATCH (n:Entity)
        RETURN n.id AS id, n.type AS type, n.summary AS summary
    """).get_as_df()

    # Score entities by keyword overlap
    scored = []
    for _, row in all_entities.iterrows():
        score = 0
        text = f"{row['id']} {row['summary']}".lower()
        for kw in keywords:
            if kw in text:
                score += 1
        if score > 0:
            scored.append((score, row))

    # Sort by score and take top matches
    scored.sort(key=lambda x: -x[0])
    top_entities = [row for _, row in scored[:max_entities]]

    if not top_entities:
        return "No relevant entities found in the knowledge graph."

    # Get relations between top entities
    entity_ids = [e['id'] for e in top_entities]

    relations = []
    for e in entity_ids:
        rels = conn.execute("""
            MATCH (a:Entity {id: $id})-[r:RELATED]->(b:Entity)
            RETURN a.id AS source, r.label AS rel, b.id AS target
        """, {"id": e}).get_as_df()

        for _, row in rels.iterrows():
            relations.append(f"{row['source']} --[{row['rel']}]--> {row['target']}")

    # Format context
    context_parts = ["## Relevant Entities\n"]
    for e in top_entities:
        context_parts.append(f"- **{e['id']}** ({e['type']}): {e['summary']}")

    if relations:
        context_parts.append("\n## Relationships\n")
        for rel in relations[:30]:
            context_parts.append(f"- {rel}")

    return "\n".join(context_parts)
```

### Relationship Expansion

Given seed entities, expand outward to gather context:

```python
def expand_from_entities(conn, entity_ids: list[str], hops: int = 2) -> dict:
    """Expand from seed entities by N hops."""

    current = set(entity_ids)
    all_entities = set(entity_ids)
    all_relations = []

    for _ in range(hops):
        new_entities = set()

        for eid in current:
            # Outgoing relations
            out = conn.execute("""
                MATCH (a:Entity {id: $id})-[r:RELATED]->(b:Entity)
                RETURN a.id AS source, r.label AS label, b.id AS target
            """, {"id": eid}).get_as_df()

            for _, row in out.iterrows():
                all_relations.append(dict(row))
                new_entities.add(row['target'])

            # Incoming relations
            inc = conn.execute("""
                MATCH (a:Entity)-[r:RELATED]->(b:Entity {id: $id})
                RETURN a.id AS source, r.label AS label, b.id AS target
            """, {"id": eid}).get_as_df()

            for _, row in inc.iterrows():
                all_relations.append(dict(row))
                new_entities.add(row['source'])

        current = new_entities - all_entities
        all_entities = all_entities.union(new_entities)

    # Get entity details
    entities = []
    for eid in all_entities:
        result = conn.execute("""
            MATCH (n:Entity {id: $id})
            RETURN n.id AS id, n.type AS type, n.summary AS summary
        """, {"id": eid}).get_as_df()
        if not result.empty:
            entities.append(dict(result.iloc[0]))

    return {
        'entities': entities,
        'relations': all_relations
    }
```

## Prompt Engineering for Grounded Responses

### System Prompt

```python
SYSTEM_PROMPT = """You are a research assistant with access to a knowledge graph
extracted from technical documents. Use the provided context to answer questions
accurately.

Guidelines:
1. Only make claims supported by the provided context
2. Cite specific entity names when making claims
3. If the context doesn't contain relevant information, say so clearly
4. Distinguish between what the graph explicitly states and what can be inferred"""
```

### Query Function

```python
def query_with_context(query: str, context: str) -> str:
    """Ask the LLM a question with graph context."""

    user_prompt = f"""## Knowledge Graph Context

{context}

## Question

{query}

## Instructions

Answer the question based on the knowledge graph context above. Be specific and
cite entity names when possible. If the context doesn't contain the answer,
say so rather than speculating."""

    response = client.chat.completions.create(
        model=LLM_MODEL,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt}
        ],
        temperature=0.3  # Lower temperature for factual responses
    )

    return response.choices[0].message.content
```

### Complete Query Script

{% raw %}
```python
#!/usr/bin/env python3
"""
LLM-powered Knowledge Graph Query Interface.

Usage:
    python query_kg.py "What algorithms improve on Transformers?"
    python query_kg.py "Which papers discuss bootstrap methods?"
    python query_kg.py "How is dropout used?" --verbose
"""

import argparse
import kuzu
from openai import OpenAI

DB_PATH = "./kuzu_graph_db"
LLM_MODEL = "qwen2.5:32b"

client = OpenAI(
    base_url="http://localhost:11434/v1",
    api_key="ollama"
)

SYSTEM_PROMPT = """You are a research assistant with access to a knowledge graph
extracted from technical documents. Use the provided context to answer questions
accurately. If the context doesn't contain relevant information, say so.
Always cite specific entities from the context when making claims."""


def extract_keywords(query: str) -> list[str]:
    stopwords = {'what', 'which', 'how', 'does', 'the', 'and', 'for', 'are', 'is'}
    words = query.lower().split()
    return [w for w in words if len(w) > 3 and w not in stopwords]


def get_relevant_context(conn, query: str, max_entities: int = 20) -> str:
    keywords = extract_keywords(query)

    all_entities = conn.execute("""
        MATCH (n:Entity)
        RETURN n.id AS id, n.type AS type, n.summary AS summary
    """).get_as_df()

    scored = []
    for _, row in all_entities.iterrows():
        score = sum(1 for kw in keywords if kw in f"{row['id']} {row['summary']}".lower())
        if score > 0:
            scored.append((score, row))

    scored.sort(key=lambda x: -x[0])
    top_entities = [row for _, row in scored[:max_entities]]

    if not top_entities:
        return "No relevant entities found in the knowledge graph."

    entity_ids = [e['id'] for e in top_entities]

    relations = []
    for eid in entity_ids:
        rels = conn.execute("""
            MATCH (a:Entity {id: $id})-[r:RELATED]->(b:Entity)
            RETURN a.id AS source, r.label AS rel, b.id AS target
        """, {"id": eid}).get_as_df()
        for _, row in rels.iterrows():
            relations.append(f"{row['source']} --[{row['rel']}]--> {row['target']}")

    context_parts = ["## Relevant Entities\n"]
    for e in top_entities:
        context_parts.append(f"- **{e['id']}** ({e['type']}): {e['summary']}")

    if relations:
        context_parts.append("\n## Relationships\n")
        for rel in relations[:30]:
            context_parts.append(f"- {rel}")

    return "\n".join(context_parts)


def query_with_context(query: str, context: str) -> str:
    user_prompt = f"""## Knowledge Graph Context

{context}

## Question

{query}

## Instructions

Answer based on the knowledge graph context. Cite entity names when possible."""

    response = client.chat.completions.create(
        model=LLM_MODEL,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt}
        ],
        temperature=0.3
    )

    return response.choices[0].message.content


def main():
    parser = argparse.ArgumentParser(description='Query knowledge graph with LLM')
    parser.add_argument('query', type=str, help='Natural language question')
    parser.add_argument('--verbose', action='store_true', help='Show retrieved context')
    args = parser.parse_args()

    db = kuzu.Database(DB_PATH)
    conn = kuzu.Connection(db)

    print("Searching knowledge graph...")
    context = get_relevant_context(conn, args.query)

    if args.verbose:
        print("\n" + "="*60)
        print("RETRIEVED CONTEXT")
        print("="*60)
        print(context)
        print("="*60 + "\n")

    print("Generating answer...\n")
    answer = query_with_context(args.query, context)

    print("="*60)
    print("ANSWER")
    print("="*60)
    print(answer)


if __name__ == '__main__':
    main()
```
{% endraw %}

## Example Queries

```bash
# Ask about relationships
python query_kg.py "What algorithms improve on Transformers?"

# Ask about citations
python query_kg.py "Which papers cite BERT?"

# Ask about implementations
python query_kg.py "What libraries implement attention mechanisms?"

# Show retrieved context
python query_kg.py "How is dropout used?" --verbose
```

### Sample Output

```text
$ python query_kg.py "What methods does the BERT paper propose?"

Searching knowledge graph...
Generating answer...

============================================================
ANSWER
============================================================
Based on the knowledge graph, the BERT paper proposes several key methods:

1. **Masked Language Modeling (MLM)**: BERT uses bidirectional training by
   masking random tokens and predicting them from context.

2. **Next Sentence Prediction (NSP)**: A pretraining task that helps the
   model understand sentence relationships.

The knowledge graph shows:
- BERT --[PROPOSES]--> Masked Language Modeling
- BERT --[PROPOSES]--> Next Sentence Prediction
- BERT --[USES]--> Transformer
- BERT --[IMPROVES]--> ELMo

These methods enabled BERT to achieve state-of-the-art results on multiple
NLP benchmarks at the time of publication.
```

## Advanced: Cypher Query Generation

For complex queries, the LLM can generate Cypher directly:

{% raw %}
```python
def generate_cypher(natural_query: str) -> str:
    """Have LLM generate a Cypher query from natural language."""

    schema_description = """
    Node: Entity(id: STRING, type: STRING, summary: STRING)
    - type is one of: Paper, Algorithm, Metric, Library, Function

    Relationship: RELATED(label: STRING)
    - label is one of: PROPOSES, USES, IMPROVES, IMPLEMENTS, CITES
    """

    prompt = f"""Convert this natural language question to a Cypher query.

Schema:
{schema_description}

Question: {natural_query}

Return ONLY the Cypher query, no explanation."""

    response = client.chat.completions.create(
        model=LLM_MODEL,
        messages=[{"role": "user", "content": prompt}],
        temperature=0
    )

    return response.choices[0].message.content.strip()


# Example usage
query = "Find all algorithms that BERT uses"
cypher = generate_cypher(query)
# Returns: MATCH (b:Entity {id: 'BERT'})-[:RELATED {label: 'USES'}]->(a:Entity {type: 'Algorithm'}) RETURN a

results = conn.execute(cypher).get_as_df()
```
{% endraw %}

### Cypher with Validation

Generated Cypher may fail. Handle gracefully:

```python
def execute_generated_cypher(conn, natural_query: str) -> tuple[str, any]:
    """Generate and execute Cypher with error handling."""

    cypher = generate_cypher(natural_query)

    try:
        results = conn.execute(cypher).get_as_df()
        return cypher, results
    except Exception as e:
        # Fall back to keyword search
        print(f"Cypher failed ({e}), falling back to keyword search")
        context = get_relevant_context(conn, natural_query)
        return None, context
```

## Hybrid Approaches

Combine graph structure with vector similarity for best results:

### Entity-Guided Vector Search

1. Find relevant entities in graph
2. Use entity IDs to filter vector search
3. Retrieve text chunks mentioning those entities
4. Combine structured and unstructured context

### Graph-Enhanced Chunking

1. During ingestion, tag chunks with extracted entities
2. Store entity-chunk associations
3. At query time, retrieve chunks via entity graph traversal

## Performance Considerations

### Caching Frequent Queries

```python
from functools import lru_cache

@lru_cache(maxsize=100)
def cached_entity_lookup(entity_id: str) -> dict:
    """Cache entity lookups."""
    result = conn.execute("""
        MATCH (n:Entity {id: $id})
        RETURN n.id AS id, n.type AS type, n.summary AS summary
    """, {"id": entity_id}).get_as_df()
    return dict(result.iloc[0]) if not result.empty else None
```

### Limiting Expansion

Large graphs can explode during expansion. Always impose limits:

```python
def safe_expand(conn, seed_ids: list[str], max_entities: int = 100):
    """Expand with entity limit."""
    expanded = set(seed_ids)

    for eid in list(expanded):
        if len(expanded) >= max_entities:
            break

        neighbors = conn.execute("""
            MATCH (a:Entity {id: $id})-[:RELATED]-(b:Entity)
            RETURN b.id AS id
        """, {"id": eid}).get_as_df()

        for _, row in neighbors.iterrows():
            if len(expanded) >= max_entities:
                break
            expanded.add(row['id'])

    return expanded
```

## Summary

Graph RAG provides structured, verifiable retrieval that complements traditional vector search. By querying explicit relationships rather than text similarity, answers become more precise and their provenance becomes traceable.

Key points:
- **Graph retrieval is structural**: Query relationships directly, not implicitly
- **Keywords identify seed entities**: Simple extraction works surprisingly well
- **Expansion gathers context**: Hop outward from seeds to build relevant subgraph
- **Cypher generation enables natural queries**: LLM translates questions to graph queries
- **Grounding improves accuracy**: Context from structured knowledge reduces hallucination

This concludes the PDF to Knowledge Graph series. The complete pipeline—from PDF extraction through RAG—runs entirely locally, requires no cloud services, and transforms documents from opaque artifacts into queryable knowledge structures.

---

## Series Index

1. [PDF Extraction with MinerU](/posts/pdf-extraction-mineru/)
2. [Structured LLM Extraction with Instructor](/posts/structured-llm-extraction-instructor/)
3. [Graph Storage with Kuzu](/posts/knowledge-graph-kuzu/)
4. [Automated Pipeline with Watchdog](/posts/automated-pdf-pipeline-watchdog/)
5. [Interactive Visualization with vis.js](/posts/knowledge-graph-visualization-visjs/)
6. [RAG with Knowledge Graphs](/posts/rag-knowledge-graphs/) (this post)

---

*The complete code for this series is available at [github.com/derrekito/knowledge_graph_db](https://github.com/derrekito/knowledge_graph_db).*

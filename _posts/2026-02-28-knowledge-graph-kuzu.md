---
title: "Part 3: Building Knowledge Graphs with Kuzu"
date: 2026-02-28 10:00:00 -0700
categories: [AI, Knowledge Graphs]
tags: [kuzu, knowledge-graph, cypher, graph-database, python]
series: pdf-to-knowledge-graph
series_order: 3
---

*Part 3 of the [PDF to Knowledge Graph series](/posts/local-pdf-to-knowledge-graph-series/).*

Graph databases excel at relationship-heavy data, but most require server infrastructure. Kuzu is an embedded graph database—no server, no Docker, just a Python library and a file. It supports Cypher queries and handles millions of nodes on modest hardware. This post covers schema design, entity resolution, and query patterns for knowledge graphs.

## Kuzu Compared to Neo4j

| Feature | Neo4j | Kuzu |
|---------|-------|------|
| Deployment | Server required | Embedded (library) |
| Setup | Docker/install | `pip install kuzu` |
| Query language | Cypher | Cypher |
| Persistence | Database server | Single directory |
| Scaling | Cluster-capable | Single machine |
| Use case | Production systems | Research, prototypes, single-user |

For knowledge graphs built from personal document collections, Kuzu eliminates operational complexity without sacrificing query power.

## Installation

```bash
pip install kuzu
```

No server configuration or port management required.

## Database Setup

```python
import kuzu

DB_PATH = "./kuzu_graph_db"

# Create or open database
db = kuzu.Database(DB_PATH)
conn = kuzu.Connection(db)
```

The database is a directory containing Kuzu's storage files. Backup is performed by copying the directory.

## Schema Design

Knowledge graphs require two table types: nodes (entities) and edges (relationships).

### Entity Table

```python
def init_schema(conn):
    """Create schema if it doesn't exist."""
    try:
        conn.execute("""
            CREATE NODE TABLE Entity(
                id STRING,
                type STRING,
                summary STRING,
                PRIMARY KEY (id)
            )
        """)
        print("Created Entity table")
    except RuntimeError as e:
        if "already exists" in str(e):
            pass  # Schema exists, continue
        else:
            raise
```

Properties:
- `id`: Unique identifier (e.g., "BERT", "Transformer")
- `type`: Entity category (Paper, Algorithm, Metric, etc.)
- `summary`: One-sentence description
- `PRIMARY KEY (id)`: Prevents duplicate entities

### Relationship Table

```python
    try:
        conn.execute("""
            CREATE REL TABLE RELATED(
                FROM Entity TO Entity,
                label STRING
            )
        """)
        print("Created RELATED table")
    except RuntimeError as e:
        if "already exists" in str(e):
            pass
        else:
            raise
```

Properties:
- `FROM Entity TO Entity`: Connects two entities
- `label`: Relationship type (USES, PROPOSES, IMPROVES, etc.)

## The KnowledgeBase Class

A wrapper class encapsulates database operations:

```python
import kuzu
from rapidfuzz import process, fuzz

class KnowledgeBase:
    def __init__(self, db_path: str = "./kuzu_graph_db"):
        self.db = kuzu.Database(db_path)
        self.conn = kuzu.Connection(self.db)
        self._init_schema()

    def _init_schema(self):
        """Initialize schema if needed."""
        try:
            self.conn.execute("""
                CREATE NODE TABLE Entity(
                    id STRING,
                    type STRING,
                    summary STRING,
                    PRIMARY KEY (id)
                )
            """)
        except RuntimeError:
            pass

        try:
            self.conn.execute("""
                CREATE REL TABLE RELATED(
                    FROM Entity TO Entity,
                    label STRING
                )
            """)
        except RuntimeError:
            pass

    def get_all_entity_ids(self) -> list[str]:
        """Get all existing entity IDs."""
        try:
            results = self.conn.execute(
                "MATCH (n:Entity) RETURN n.id"
            ).get_as_df()

            if results.empty:
                return []
            return results["n.id"].tolist()
        except Exception:
            return []
```

## Entity Resolution with Fuzzy Matching

The same concept appears with different names across documents: "Convolutional Neural Network", "CNN", "ConvNet". Without resolution, the graph fragments into disconnected synonyms.

RapidFuzz provides fast fuzzy string matching:

```python
from rapidfuzz import process, fuzz

def add_entity(self, entity_id: str, entity_type: str, summary: str) -> str:
    """Add entity with deduplication. Returns resolved ID."""
    existing_ids = self.get_all_entity_ids()

    resolved_id = entity_id

    # Check for fuzzy matches
    if existing_ids:
        match, score, _ = process.extractOne(
            entity_id,
            existing_ids,
            scorer=fuzz.ratio
        )

        # Threshold: 92% similarity
        if score > 92:
            resolved_id = match
            print(f"   Merged: '{entity_id}' -> '{match}'")

    # Upsert (insert or update)
    self.conn.execute(
        """
        MERGE (n:Entity {id: $id})
        ON CREATE SET n.type = $type, n.summary = $summary
        """,
        {"id": resolved_id, "type": entity_type, "summary": summary}
    )

    return resolved_id
```

### Threshold Selection Rationale

| Comparison | Score | Match? |
|------------|-------|--------|
| "CNN" vs "CNN" | 100% | Yes |
| "BERT" vs "bert" | 100% | Yes (case-insensitive) |
| "ConvNet" vs "CNN" | 40% | No |
| "Transformer" vs "Transformers" | 95% | Yes |
| "BERT" vs "RoBERTa" | 60% | No |

A 92% threshold catches pluralization and minor variations while avoiding false merges.

## Adding Relationships

```python
def add_relation(self, source: str, target: str, label: str):
    """Add relationship between entities."""
    # Prevent self-loops (often extraction errors)
    if source == target:
        return

    self.conn.execute(
        """
        MATCH (a:Entity {id: $src}), (b:Entity {id: $tgt})
        MERGE (a)-[:RELATED {label: $label}]->(b)
        """,
        {"src": source, "tgt": target, "label": label}
    )
```

`MERGE` is idempotent—running the same insertion twice does not create duplicates.

## Processing Extractions

Integration with the Instructor extraction from Part 2:

```python
def add_extraction(self, extraction):
    """Add all entities and relations from an extraction."""
    # Map original IDs to resolved IDs
    id_map = {}

    # Add entities with deduplication
    for entity in extraction.entities:
        resolved_id = self.add_entity(
            entity.id,
            entity.type,
            entity.summary
        )
        id_map[entity.id] = resolved_id

    # Add relations using resolved IDs
    for rel in extraction.relations:
        if rel.source in id_map and rel.target in id_map:
            self.add_relation(
                id_map[rel.source],
                id_map[rel.target],
                rel.label
            )
```

## Querying the Graph

Kuzu uses Cypher, the standard graph query language.

### Find All Entities of a Type

```python
results = conn.execute("""
    MATCH (n:Entity {type: 'Algorithm'})
    RETURN n.id, n.summary
""").get_as_df()

print(results)
#        n.id                        n.summary
# 0  Transformer  Self-attention architecture for sequences
# 1        BERT  Bidirectional pre-trained language model
# 2         CNN  Convolutional neural network for images
```

### Find Paper Contributions

```python
results = conn.execute("""
    MATCH (p:Entity {type: 'Paper'})-[:RELATED {label: 'PROPOSES'}]->(a)
    RETURN p.id AS paper, a.id AS contribution
""").get_as_df()
```

### Find Citation Chains

```python
# 2-hop citation paths
results = conn.execute("""
    MATCH (a:Entity)-[:RELATED {label: 'CITES'}]->(b)
          -[:RELATED {label: 'CITES'}]->(c)
    RETURN a.id AS citing, b.id AS intermediate, c.id AS cited
""").get_as_df()
```

### Find All Connections to a Concept

```python
results = conn.execute("""
    MATCH (n:Entity {id: 'Transformer'})-[r:RELATED]-(m)
    RETURN n.id, r.label, m.id AS connected, m.type
""").get_as_df()
```

### Count Relationships by Type

```python
results = conn.execute("""
    MATCH ()-[r:RELATED]->()
    RETURN r.label AS relationship, count(*) AS count
    ORDER BY count DESC
""").get_as_df()
```

### Find Most Connected Entities

```python
results = conn.execute("""
    MATCH (n:Entity)-[r:RELATED]-()
    RETURN n.id, n.type, count(r) AS connections
    ORDER BY connections DESC
    LIMIT 10
""").get_as_df()
```

## Graph Statistics

```python
def get_stats(self) -> dict:
    """Get graph statistics."""
    entity_count = self.conn.execute(
        "MATCH (n:Entity) RETURN count(n) AS count"
    ).get_as_df()["count"][0]

    relation_count = self.conn.execute(
        "MATCH ()-[r:RELATED]->() RETURN count(r) AS count"
    ).get_as_df()["count"][0]

    type_counts = self.conn.execute("""
        MATCH (n:Entity)
        RETURN n.type AS type, count(*) AS count
        ORDER BY count DESC
    """).get_as_df()

    return {
        "entities": entity_count,
        "relations": relation_count,
        "by_type": type_counts.to_dict("records")
    }
```

## Complete KnowledgeBase Class

```python
import kuzu
from rapidfuzz import process, fuzz

class KnowledgeBase:
    def __init__(self, db_path: str = "./kuzu_graph_db"):
        self.db = kuzu.Database(db_path)
        self.conn = kuzu.Connection(self.db)
        self._init_schema()

    def _init_schema(self):
        try:
            self.conn.execute(
                "CREATE NODE TABLE Entity(id STRING, type STRING, summary STRING, PRIMARY KEY (id))"
            )
        except RuntimeError:
            pass

        try:
            self.conn.execute(
                "CREATE REL TABLE RELATED(FROM Entity TO Entity, label STRING)"
            )
        except RuntimeError:
            pass

    def get_all_entity_ids(self) -> list[str]:
        try:
            results = self.conn.execute("MATCH (n:Entity) RETURN n.id").get_as_df()
            return results["n.id"].tolist() if not results.empty else []
        except Exception:
            return []

    def add_entity(self, entity_id: str, entity_type: str, summary: str) -> str:
        existing_ids = self.get_all_entity_ids()
        resolved_id = entity_id

        if existing_ids:
            match, score, _ = process.extractOne(entity_id, existing_ids, scorer=fuzz.ratio)
            if score > 92:
                resolved_id = match

        self.conn.execute(
            "MERGE (n:Entity {id: $id}) ON CREATE SET n.type = $type, n.summary = $summary",
            {"id": resolved_id, "type": entity_type, "summary": summary}
        )
        return resolved_id

    def add_relation(self, source: str, target: str, label: str):
        if source != target:
            self.conn.execute(
                "MATCH (a:Entity {id: $src}), (b:Entity {id: $tgt}) MERGE (a)-[:RELATED {label: $label}]->(b)",
                {"src": source, "tgt": target, "label": label}
            )

    def add_extraction(self, extraction):
        id_map = {}
        for entity in extraction.entities:
            id_map[entity.id] = self.add_entity(entity.id, entity.type, entity.summary)

        for rel in extraction.relations:
            if rel.source in id_map and rel.target in id_map:
                self.add_relation(id_map[rel.source], id_map[rel.target], rel.label)

    def query(self, cypher: str):
        return self.conn.execute(cypher).get_as_df()

    def get_stats(self) -> dict:
        entities = self.conn.execute("MATCH (n:Entity) RETURN count(n)").get_as_df().iloc[0, 0]
        relations = self.conn.execute("MATCH ()-[r]->() RETURN count(r)").get_as_df().iloc[0, 0]
        return {"entities": entities, "relations": relations}
```

## Performance Considerations

### Indexing

Kuzu automatically indexes primary keys. For additional query patterns:

```python
# For frequent queries by type
conn.execute("CREATE INDEX entity_type_idx ON Entity(type)")
```

### Batch Operations

For large imports, batch the operations:

```python
def add_extractions_batch(self, extractions: list):
    """Add multiple extractions efficiently."""
    # Collect all entities first
    all_entities = []
    for ext in extractions:
        all_entities.extend(ext.entities)

    # Resolve all IDs
    existing = set(self.get_all_entity_ids())
    id_map = {}

    for entity in all_entities:
        resolved = entity.id
        if existing:
            match, score, _ = process.extractOne(entity.id, list(existing), scorer=fuzz.ratio)
            if score > 92:
                resolved = match
        id_map[entity.id] = resolved
        existing.add(resolved)

    # Batch insert entities
    for entity in all_entities:
        self.conn.execute(
            "MERGE (n:Entity {id: $id}) ON CREATE SET n.type = $type, n.summary = $summary",
            {"id": id_map[entity.id], "type": entity.type, "summary": entity.summary}
        )

    # Batch insert relations
    for ext in extractions:
        for rel in ext.relations:
            if rel.source in id_map and rel.target in id_map:
                self.add_relation(id_map[rel.source], id_map[rel.target], rel.label)
```

## Summary

Kuzu provides graph database functionality without operational overhead. Combined with fuzzy entity resolution, a clean, queryable knowledge graph emerges from LLM extractions.

Key points:
- **Embedded architecture**: No server, no Docker, just a library
- **Cypher queries**: Standard graph query language
- **Entity resolution importance**: Fuzzy matching prevents fragmentation
- **MERGE for idempotency**: Safe to reprocess documents

The next post covers [automating the pipeline with Watchdog](/posts/automated-pdf-pipeline-watchdog/).

---

*Next: [Part 4 - Automated Pipeline with Watchdog](/posts/automated-pdf-pipeline-watchdog/)*

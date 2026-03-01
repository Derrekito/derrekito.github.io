---
title: "Part 5: Knowledge Graph Visualization with vis.js"
date: 2026-02-28 10:00:00 -0700
categories: [AI, Visualization]
tags: [vis.js, knowledge-graph, visualization, javascript, python]
series: pdf-to-knowledge-graph
series_order: 5
---

*Part 5 of the [PDF to Knowledge Graph series](/posts/local-pdf-to-knowledge-graph-series/).*

Graphs are inherently visual structures, yet most graph databases offer only textual query interfaces. A list of nodes and edges reveals little about the shape of knowledge. This post presents methods for generating interactive HTML visualizations directly from Kuzu, explorable in any browser without server infrastructure.

## Motivation

Tabular query results display data but obscure structure:

```text
source          | relation  | target
----------------|-----------|---------------
Transformer     | PROPOSES  | Self-Attention
BERT            | USES      | Transformer
GPT             | USES      | Transformer
RoBERTa         | IMPROVES  | BERT
```

The same data, when visualized, reveals that Transformer serves as a hub connecting multiple concepts. Clusters emerge. Isolated nodes become apparent. Relationships spanning the graph become traceable.

## vis.js: Browser-Native Graph Rendering

[vis.js](https://visjs.org/) is a JavaScript library for network visualization. It runs entirely in the browser without requiring a server or build step—only an HTML file. For knowledge graphs containing fewer than several thousand nodes, it provides smooth, interactive exploration.

## Visualization Pipeline

### Step 1: Export Graph Data

First, extract nodes and edges from Kuzu:

```python
import kuzu
import json

DB_PATH = "./kuzu_graph_db"

def export_graph_data(conn) -> dict:
    """Export graph data from Kuzu to a dictionary."""

    # Get all entities
    entities_df = conn.execute("""
        MATCH (n:Entity)
        RETURN n.id AS id, n.type AS type, n.summary AS summary
    """).get_as_df()

    # Get all relations
    relations_df = conn.execute("""
        MATCH (a:Entity)-[r:RELATED]->(b:Entity)
        RETURN a.id AS source, b.id AS target, r.label AS label
    """).get_as_df()

    return {
        'entities': entities_df.to_dict('records'),
        'relations': relations_df.to_dict('records')
    }

# Usage
db = kuzu.Database(DB_PATH)
conn = kuzu.Connection(db)
data = export_graph_data(conn)

print(f"Entities: {len(data['entities'])}")
print(f"Relations: {len(data['relations'])}")
```

### Step 2: Build vis.js Nodes

Transform entities into vis.js node objects with visual encoding:

```python
from collections import Counter

def build_nodes(data: dict) -> list:
    """Build vis.js node objects with visual properties."""

    nodes = []
    for entity in data['entities']:
        # Color by entity type
        color_map = {
            'Paper': '#4CAF50',      # Green
            'Algorithm': '#2196F3',  # Blue
            'Metric': '#FF9800',     # Orange
            'Library': '#9C27B0',    # Purple
            'Function': '#E91E63',   # Pink
        }
        color = color_map.get(entity['type'], '#9E9E9E')

        # Size by connection count (more connected = larger)
        connections = sum(
            1 for r in data['relations']
            if r['source'] == entity['id'] or r['target'] == entity['id']
        )
        size = 15 + min(connections * 3, 30)  # Cap at 45px

        # Rich tooltip with HTML
        tooltip = f"<b>{entity['id']}</b><br>"
        tooltip += f"Type: {entity['type']}<br>"
        if entity.get('summary'):
            tooltip += f"{entity['summary'][:150]}"

        nodes.append({
            'id': entity['id'],
            'label': entity['id'][:30],  # Truncate long names
            'title': tooltip,
            'color': color,
            'size': size,
            'shape': 'dot'
        })

    return nodes
```

### Step 3: Build vis.js Edges

Transform relations into styled edges:

```python
def build_edges(data: dict) -> list:
    """Build vis.js edge objects with visual properties."""

    edge_colors = {
        'PROPOSES': '#4CAF50',   # Green - contribution
        'USES': '#2196F3',       # Blue - dependency
        'IMPROVES': '#FF9800',   # Orange - enhancement
        'IMPLEMENTS': '#9C27B0', # Purple - realization
        'CITES': '#757575',      # Gray - reference
    }

    edges = []
    for rel in data['relations']:
        edges.append({
            'from': rel['source'],
            'to': rel['target'],
            'label': rel['label'],
            'color': edge_colors.get(rel['label'], '#9E9E9E'),
            'arrows': 'to',
            'smooth': {'type': 'curvedCW', 'roundness': 0.2}
        })

    return edges
```

### Step 4: Generate HTML

Assemble all components into a standalone HTML file:

{% raw %}
```python
def generate_html(data: dict, output_path: str, title: str = "Knowledge Graph"):
    """Generate interactive HTML visualization."""

    nodes = build_nodes(data)
    edges = build_edges(data)

    # Statistics for header
    type_counts = Counter(e['type'] for e in data['entities'])
    rel_counts = Counter(r['label'] for r in data['relations'])

    html = f"""<!DOCTYPE html>
<html>
<head>
    <title>{title}</title>
    <script src="https://unpkg.com/vis-network/standalone/umd/vis-network.min.js"></script>
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: #f8f9fa;
        }}
        #header {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px 30px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }}
        h1 {{ font-size: 28px; font-weight: 600; }}
        .subtitle {{ font-size: 14px; opacity: 0.9; margin-top: 5px; }}
        #stats {{
            background: white;
            padding: 15px 30px;
            border-bottom: 1px solid #e0e0e0;
            display: flex;
            gap: 30px;
        }}
        .stat {{ display: flex; flex-direction: column; }}
        .stat-value {{
            font-size: 24px;
            font-weight: bold;
            color: #667eea;
        }}
        .stat-label {{
            font-size: 11px;
            color: #757575;
            text-transform: uppercase;
        }}
        #network {{
            width: 100%;
            height: calc(100vh - 140px);
            background: white;
        }}
        .legend {{
            position: absolute;
            top: 120px;
            right: 20px;
            background: white;
            padding: 15px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            font-size: 12px;
        }}
        .legend h4 {{ margin: 0 0 10px 0; font-size: 13px; }}
        .legend-item {{ margin: 6px 0; display: flex; align-items: center; }}
        .legend-color {{
            width: 16px;
            height: 16px;
            margin-right: 8px;
            border-radius: 50%;
        }}
    </style>
</head>
<body>
    <div id="header">
        <h1>{title}</h1>
        <div class="subtitle">Interactive Knowledge Graph Visualization</div>
    </div>
    <div id="stats">
        <div class="stat">
            <div class="stat-value">{len(nodes)}</div>
            <div class="stat-label">Entities</div>
        </div>
        <div class="stat">
            <div class="stat-value">{len(edges)}</div>
            <div class="stat-label">Relations</div>
        </div>
        <div class="stat">
            <div class="stat-value">{type_counts.get('Paper', 0)}</div>
            <div class="stat-label">Papers</div>
        </div>
        <div class="stat">
            <div class="stat-value">{type_counts.get('Algorithm', 0)}</div>
            <div class="stat-label">Algorithms</div>
        </div>
    </div>
    <div class="legend">
        <h4>Entity Types</h4>
        <div class="legend-item"><span class="legend-color" style="background: #4CAF50;"></span>Paper</div>
        <div class="legend-item"><span class="legend-color" style="background: #2196F3;"></span>Algorithm</div>
        <div class="legend-item"><span class="legend-color" style="background: #FF9800;"></span>Metric</div>
        <div class="legend-item"><span class="legend-color" style="background: #9C27B0;"></span>Library</div>
        <div class="legend-item"><span class="legend-color" style="background: #E91E63;"></span>Function</div>
        <h4 style="margin-top: 15px;">Relations</h4>
        <div class="legend-item"><span class="legend-color" style="background: #4CAF50;"></span>PROPOSES</div>
        <div class="legend-item"><span class="legend-color" style="background: #2196F3;"></span>USES</div>
        <div class="legend-item"><span class="legend-color" style="background: #FF9800;"></span>IMPROVES</div>
        <div class="legend-item"><span class="legend-color" style="background: #757575;"></span>CITES</div>
    </div>
    <div id="network"></div>
    <script>
        var nodes = new vis.DataSet({json.dumps(nodes)});
        var edges = new vis.DataSet({json.dumps(edges)});

        var container = document.getElementById('network');
        var data = {{ nodes: nodes, edges: edges }};
        var options = {{
            physics: {{
                barnesHut: {{
                    gravitationalConstant: -4000,
                    centralGravity: 0.2,
                    springLength: 200,
                    springConstant: 0.02,
                    damping: 0.1
                }},
                stabilization: {{ iterations: 150 }}
            }},
            interaction: {{
                hover: true,
                tooltipDelay: 100,
                navigationButtons: true,
                keyboard: true
            }},
            nodes: {{ font: {{ size: 11 }}, borderWidth: 2 }},
            edges: {{ font: {{ size: 9 }}, width: 1.5 }}
        }};

        var network = new vis.Network(container, data, options);

        // Double-click to focus on a node
        network.on("doubleClick", function(params) {{
            if (params.nodes.length > 0) {{
                network.focus(params.nodes[0], {{
                    scale: 1.5,
                    animation: {{ duration: 500 }}
                }});
            }}
        }});
    </script>
</body>
</html>"""

    with open(output_path, 'w') as f:
        f.write(html)
```
{% endraw %}

## Subgraph Filtering

Full graphs can be overwhelming. Filtering enables focus on specific concepts:

```python
def filter_by_concept(data: dict, concept: str) -> dict:
    """Filter graph to entities related to a concept."""
    concept_lower = concept.lower()

    # Find entities matching the concept
    matching = set()
    for entity in data['entities']:
        if concept_lower in entity['id'].lower():
            matching.add(entity['id'])
        if concept_lower in entity.get('summary', '').lower():
            matching.add(entity['id'])

    # Expand to neighbors (1-hop)
    for rel in data['relations']:
        if rel['source'] in matching:
            matching.add(rel['target'])
        if rel['target'] in matching:
            matching.add(rel['source'])

    # Filter to matching entities
    return {
        'entities': [e for e in data['entities'] if e['id'] in matching],
        'relations': [r for r in data['relations']
                      if r['source'] in matching and r['target'] in matching]
    }
```

### Multi-hop Expansion

For deeper exploration, multiple hops can be expanded:

```python
def expand_hops(data: dict, seed_ids: set, hops: int = 2) -> set:
    """Expand from seed nodes by N hops."""
    current = seed_ids.copy()

    for _ in range(hops):
        neighbors = set()
        for rel in data['relations']:
            if rel['source'] in current:
                neighbors.add(rel['target'])
            if rel['target'] in current:
                neighbors.add(rel['source'])
        current = current.union(neighbors)

    return current
```

## Complete Visualizer Script

```python
#!/usr/bin/env python3
"""
Knowledge Graph Visualizer - Generate interactive HTML from Kuzu database.

Usage:
    python visualize_kg.py
    python visualize_kg.py --filter weibull
    python visualize_kg.py --output my_graph.html
"""

import argparse
import json
import kuzu
from pathlib import Path
from collections import Counter

DB_PATH = "./kuzu_graph_db"


def export_graph_data(conn) -> dict:
    """Export graph data from Kuzu."""
    entities_df = conn.execute("""
        MATCH (n:Entity)
        RETURN n.id AS id, n.type AS type, n.summary AS summary
    """).get_as_df()

    relations_df = conn.execute("""
        MATCH (a:Entity)-[r:RELATED]->(b:Entity)
        RETURN a.id AS source, b.id AS target, r.label AS label
    """).get_as_df()

    return {
        'entities': entities_df.to_dict('records'),
        'relations': relations_df.to_dict('records')
    }


def filter_by_concept(data: dict, concept: str) -> dict:
    """Filter to concept neighborhood."""
    concept_lower = concept.lower()

    matching = set()
    for entity in data['entities']:
        if concept_lower in entity['id'].lower():
            matching.add(entity['id'])
        if concept_lower in entity.get('summary', '').lower():
            matching.add(entity['id'])

    # 1-hop expansion
    for rel in data['relations']:
        if rel['source'] in matching:
            matching.add(rel['target'])
        if rel['target'] in matching:
            matching.add(rel['source'])

    return {
        'entities': [e for e in data['entities'] if e['id'] in matching],
        'relations': [r for r in data['relations']
                      if r['source'] in matching and r['target'] in matching]
    }


def generate_html(data: dict, output_path: Path, title: str = "Knowledge Graph"):
    """Generate interactive HTML visualization."""

    # Build nodes
    nodes = []
    for entity in data['entities']:
        color_map = {
            'Paper': '#4CAF50',
            'Algorithm': '#2196F3',
            'Metric': '#FF9800',
            'Library': '#9C27B0',
            'Function': '#E91E63',
        }
        color = color_map.get(entity['type'], '#9E9E9E')

        connections = sum(
            1 for r in data['relations']
            if r['source'] == entity['id'] or r['target'] == entity['id']
        )
        size = 15 + min(connections * 3, 30)

        tooltip = f"<b>{entity['id']}</b><br>Type: {entity['type']}<br>"
        if entity.get('summary'):
            tooltip += entity['summary'][:150]

        nodes.append({
            'id': entity['id'],
            'label': entity['id'][:30],
            'title': tooltip,
            'color': color,
            'size': size,
            'shape': 'dot'
        })

    # Build edges
    edge_colors = {
        'PROPOSES': '#4CAF50',
        'USES': '#2196F3',
        'IMPROVES': '#FF9800',
        'IMPLEMENTS': '#9C27B0',
        'CITES': '#757575',
    }

    edges = []
    for rel in data['relations']:
        edges.append({
            'from': rel['source'],
            'to': rel['target'],
            'label': rel['label'],
            'color': edge_colors.get(rel['label'], '#9E9E9E'),
            'arrows': 'to',
            'smooth': {'type': 'curvedCW', 'roundness': 0.2}
        })

    type_counts = Counter(e['type'] for e in data['entities'])

    # Generate HTML (template omitted for brevity - see full example above)
    # ...

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(html)


def main():
    parser = argparse.ArgumentParser(description='Visualize knowledge graph')
    parser.add_argument('--filter', type=str, help='Filter by concept')
    parser.add_argument('--output', type=Path, default=Path('kg_visualization.html'))
    args = parser.parse_args()

    db = kuzu.Database(DB_PATH)
    conn = kuzu.Connection(db)

    print("Exporting graph data...")
    data = export_graph_data(conn)
    print(f"  Entities: {len(data['entities'])}")
    print(f"  Relations: {len(data['relations'])}")

    title = "Knowledge Graph"
    if args.filter:
        print(f"Filtering by: {args.filter}")
        data = filter_by_concept(data, args.filter)
        title = f"Knowledge Graph - {args.filter.title()}"
        print(f"  Filtered to {len(data['entities'])} entities")

    generate_html(data, args.output, title)
    print(f"\nVisualization saved to: {args.output}")
    print(f"Open in browser: file://{args.output.absolute()}")


if __name__ == '__main__':
    main()
```

## Usage Examples

```bash
# Full graph
python visualize_kg.py

# Filter to specific concept
python visualize_kg.py --filter "neural network"
python visualize_kg.py --filter transformer

# Custom output location
python visualize_kg.py --output build/my_graph.html
```

## Interaction Features

The generated visualization supports:

- **Drag nodes** to rearrange the layout
- **Zoom** with scroll wheel or pinch gesture
- **Hover** for entity details tooltip
- **Double-click** to zoom and center on a node
- **Navigation buttons** in corner for pan/zoom
- **Keyboard navigation** with arrow keys

## Physics Configuration

The `barnesHut` physics algorithm arranges nodes naturally:

```javascript
physics: {
    barnesHut: {
        gravitationalConstant: -4000,  // Node repulsion
        centralGravity: 0.2,           // Pull toward center
        springLength: 200,             // Edge length target
        springConstant: 0.02,          // Edge rigidity
        damping: 0.1                   // Motion dampening
    },
    stabilization: { iterations: 150 }  // Initial settling
}
```

Parameter adjustments for different graph densities:
- **Sparse graphs**: Lower repulsion (-2000), shorter springs (150)
- **Dense graphs**: Higher repulsion (-6000), longer springs (300)

## Scalability Considerations

vis.js handles hundreds of nodes smoothly. Beyond approximately 2000 nodes:

- **Filtering becomes essential**: Concept filtering shows relevant subgraphs
- **Disable labels**: Set `nodes: { font: { size: 0 } }` for large graphs
- **Reduce physics iterations**: Enables faster initial load
- **Consider alternatives**: For very large graphs, server-side rendering tools such as Gephi or Cytoscape are recommended

## Summary

Visualization transforms a knowledge graph from an abstract database into an explorable map of concepts. Clusters reveal themselves. Hub concepts become obvious. The structure of knowledge becomes tangible.

Key points:
- **vis.js runs in browser**: No server required, only an HTML file
- **Color-code by type**: Provides immediate visual categorization
- **Size by connectivity**: Important concepts stand out
- **Filter for focus**: Concept-centered views enable targeted exploration
- **Rich tooltips**: Provide detail on demand without clutter

The next post covers [RAG with knowledge graphs](/posts/rag-knowledge-graphs/).

---

*Next: [Part 6 - RAG with Knowledge Graphs](/posts/rag-knowledge-graphs/)*

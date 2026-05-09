from collections import deque
from enum import Enum
from typing import Optional

from .models import CTEChunk, ChunkType


class NodeType(Enum):
    CTE = "cte"
    TABLE = "table"
    ASSEMBLY = "assembly"


class DependencyGraph:

    def __init__(self):
        self._nodes: dict[str, NodeType] = {}
        self._adj: dict[str, set[str]] = {}
        self._reverse_adj: dict[str, set[str]] = {}
        self._recursive_ctes: set[str] = set()

    def add_node(self, name: str, node_type: NodeType):
        self._nodes[name] = node_type
        if name not in self._adj:
            self._adj[name] = set()
        if name not in self._reverse_adj:
            self._reverse_adj[name] = set()

    def add_edge(self, source: str, target: str):
        if source not in self._nodes:
            self.add_node(source, NodeType.CTE)
        if target not in self._nodes:
            self.add_node(target, NodeType.TABLE)

        self._adj.setdefault(source, set()).add(target)
        self._reverse_adj.setdefault(target, set()).add(source)

    def upstream_of(self, node: str, max_depth: int = 10) -> list[str]:
        if node not in self._reverse_adj:
            return []
        visited = set()
        result = []
        queue = deque([(node, 0)])
        visited.add(node)
        while queue:
            current, depth = queue.popleft()
            if depth >= max_depth:
                continue
            for pred in self._reverse_adj.get(current, set()):
                if pred not in visited:
                    visited.add(pred)
                    result.append(pred)
                    queue.append((pred, depth + 1))
        return result

    def downstream_of(self, node: str) -> list[str]:
        if node not in self._adj:
            return []
        visited = set()
        result = []
        queue = deque([node])
        visited.add(node)
        while queue:
            current = queue.popleft()
            for succ in self._adj.get(current, set()):
                if succ not in visited:
                    visited.add(succ)
                    result.append(succ)
                    queue.append(succ)
        return result

    def detect_cycle(self) -> list[str]:
        in_degree = {n: 0 for n in self._nodes}
        for src in self._adj:
            for tgt in self._adj[src]:
                if tgt in in_degree:
                    in_degree[tgt] += 1

        queue = deque([n for n, d in in_degree.items() if d == 0])
        sorted_count = 0
        while queue:
            node = queue.popleft()
            sorted_count += 1
            for succ in self._adj.get(node, set()):
                if succ in in_degree:
                    in_degree[succ] -= 1
                    if in_degree[succ] == 0:
                        queue.append(succ)

        if sorted_count < len(self._nodes):
            return [n for n in self._nodes if in_degree.get(n, 0) > 0]
        return []

    def nodes(self) -> dict[str, NodeType]:
        return dict(self._nodes)

    def edges(self) -> list[tuple[str, str]]:
        result = []
        for src in self._adj:
            for tgt in self._adj[src]:
                result.append((src, tgt))
        return result

    def to_dict(self) -> dict:
        return {
            "nodes": {name: nt.value for name, nt in self._nodes.items()},
            "edges": self.edges(),
            "recursive_ctes": list(self._recursive_ctes),
        }

    @classmethod
    def from_dict(cls, data: dict) -> "DependencyGraph":
        graph = cls()
        for name, type_str in data.get("nodes", {}).items():
            graph.add_node(name, NodeType(type_str))
        for src, tgt in data.get("edges", []):
            graph.add_edge(src, tgt)
        graph._recursive_ctes = set(data.get("recursive_ctes", []))
        return graph

    @classmethod
    def from_cte_chunks(cls, chunks: list[CTEChunk]) -> "DependencyGraph":
        graph = cls()

        for chunk in chunks:
            if chunk.chunk_type == ChunkType.cte:
                graph.add_node(chunk.cte_name, NodeType.CTE)
            elif chunk.chunk_type == ChunkType.assembly:
                graph.add_node(chunk.cte_name, NodeType.ASSEMBLY)

        for chunk in chunks:
            for cte_dep in chunk.depends_on_ctes:
                graph.add_edge(chunk.cte_name, cte_dep)
            for table_dep in chunk.depends_on_tables:
                if table_dep not in graph._nodes:
                    graph.add_node(table_dep, NodeType.TABLE)
                graph.add_edge(chunk.cte_name, table_dep)

        return graph

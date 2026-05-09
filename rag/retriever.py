import logging
import numpy as np

from .models import SearchResult, ChunkType, VectorStatus
from .dependency_graph import DependencyGraph, NodeType
from .vector_index import VectorIndex
from .index_manager import IndexManager
from .model_registry import ModelRegistry

logger = logging.getLogger(__name__)


class ContextExpander:

    def __init__(self, dep_graph: DependencyGraph, index_manager: IndexManager):
        self._dep_graph = dep_graph
        self._index_mgr = index_manager

    def expand(self, hits: list[SearchResult], max_depth: int = 3) -> list[SearchResult]:
        if not hits:
            return hits

        node_names = set()
        for hit in hits:
            meta = hit.metadata
            cte_name = meta.get("cte_name", "")
            if cte_name:
                node_names.add(cte_name)
            table_name = meta.get("table_name", "")
            if table_name:
                node_names.add(table_name)
            if hit.chunk_type == ChunkType.cte and cte_name:
                node_names.add(cte_name)
            if hit.chunk_type == ChunkType.ddl and table_name:
                node_names.add(table_name)

        upstream_ids = set()
        for name in node_names:
            upstreams = self._dep_graph.upstream_of(name, max_depth=max_depth)
            for up in upstreams:
                upstream_ids.add(up)

        if not upstream_ids:
            return hits

        context_results = []
        for idx in self._index_mgr._indices.values():
            for chunk_id, meta in idx._metadata.items():
                extra = meta.extra if meta else {}
                cte_name = extra.get("cte_name", "")
                if cte_name in upstream_ids:
                    text = self._get_chunk_text(chunk_id)
                    if text:
                        context_results.append(SearchResult(
                            chunk_id=chunk_id,
                            chunk_text=text,
                            score=0.0,
                            source="context",
                            chunk_type=meta.chunk_type,
                            metadata=extra,
                        ))

        for hit in hits:
            hit.context = context_results

        return hits

    def _get_chunk_text(self, chunk_id: str) -> str:
        for idx in self._index_mgr._indices.values():
            meta = idx.get_metadata(chunk_id)
            if meta is not None:
                extra = meta.extra
                if "chunk_text" in extra:
                    return extra["chunk_text"]
                parts = chunk_id.split("::")
                if len(parts) >= 2:
                    return parts[-1]
        return ""


class ResultMerger:

    def merge(self, hit_groups: dict[str, list[SearchResult]], top_k: int = 5) -> list[SearchResult]:
        all_hits: list[SearchResult] = []
        for hits in hit_groups.values():
            all_hits.extend(hits)

        best: dict[str, SearchResult] = {}
        for hit in all_hits:
            if hit.chunk_id not in best or hit.score > best[hit.chunk_id].score:
                best[hit.chunk_id] = hit

        sorted_hits = sorted(best.values(), key=lambda h: h.score, reverse=True)
        return sorted_hits[:top_k]


class MultiIndexRetriever:

    _QUERY_PROMPT_MAP: dict = {
        "data_dict": "query",
        "ddl": "query",
        "sql": "query",
    }

    def __init__(self, index_manager: IndexManager):
        self._index_mgr = index_manager
        self._expander = ContextExpander(index_manager.get_dep_graph(), index_manager)
        self._merger = ResultMerger()
        self._registered: dict[str, dict] = {}

    def register(self, name: str, index: VectorIndex, model_name: str, weight: float = 1.0):
        self._registered[name] = {
            "index": index,
            "model_name": model_name,
            "weight": weight,
        }

    def search(self, query: str, top_k: int = 5,
               indices: list[str] = None,
               include_related: bool = True,
               status_filter: list[VectorStatus] = None) -> list[SearchResult]:
        hit_groups: dict[str, list[SearchResult]] = {}

        target_indices = indices if indices else list(self._index_mgr._indices.keys())

        for idx_name in target_indices:
            idx = self._index_mgr.get_index(idx_name)
            if idx is None or idx.count == 0:
                continue

            idx_cfg = self._index_mgr._config.get("indices", {}).get(idx_name, {})
            model_name = idx_cfg.get("model_name", "")

            prompt_name = self._QUERY_PROMPT_MAP.get(idx_name, "")
            try:
                query_vec = ModelRegistry.encode(model_name, [query], prompt_name=prompt_name)
                raw_hits = idx.search(np.array(query_vec, dtype=np.float32), top_k * 2, status_filter)
                hits = self._to_search_results(raw_hits, idx, idx_name)
                hit_groups[idx_name] = hits
            except Exception as e:
                logger.warning(f"索引{idx_name}检索失败: {e}")

        merged = self._merger.merge(hit_groups, top_k)

        if include_related:
            merged = self._expander.expand(merged)

        return merged

    def search_by_index(self, query: str, index_name: str, top_k: int = 5) -> list[SearchResult]:
        idx = self._index_mgr.get_index(index_name)
        if idx is None:
            return []

        idx_cfg = self._index_mgr._config.get("indices", {}).get(index_name, {})
        model_name = idx_cfg.get("model_name", "")
        prompt_name = self._QUERY_PROMPT_MAP.get(index_name, "")

        if not model_name:
            logger.warning(f"索引{index_name}无对应模型")
            return []

        query_vec = ModelRegistry.encode(model_name, [query], prompt_name=prompt_name)
        raw_hits = idx.search(np.array(query_vec, dtype=np.float32), top_k)
        return self._to_search_results(raw_hits, idx, index_name)

    def _to_search_results(self, raw_hits: list[tuple], idx: VectorIndex, idx_name: str) -> list[SearchResult]:
        results = []
        for chunk_id, score in raw_hits:
            meta = idx.get_metadata(chunk_id)
            extra = meta.extra if meta else {}
            chunk_text = extra.get("chunk_text", chunk_id)
            chunk_type = meta.chunk_type if meta else ChunkType.table
            results.append(SearchResult(
                chunk_id=chunk_id,
                chunk_text=chunk_text,
                score=score,
                source=idx_name,
                chunk_type=chunk_type,
                metadata=extra,
            ))
        return results

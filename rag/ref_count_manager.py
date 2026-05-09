import json
import logging
from pathlib import Path

from .index_manager import IndexManager
from .dependency_graph import DependencyGraph

logger = logging.getLogger(__name__)


class RefCountManager:

    def __init__(self, index_manager: IndexManager, dep_graph: DependencyGraph):
        self._index_mgr = index_manager
        self._dep_graph = dep_graph
        self._ref_map: dict[str, dict] = {}

    def initialize(self):
        self._ref_map = {}
        for name, idx in self._index_mgr._indices.items():
            for chunk_id, meta in idx.get_all_metadata().items():
                self._ref_map[chunk_id] = {
                    "ref_count": meta.ref_count,
                    "referenced_by": list(meta.referenced_by),
                    "ref_types": {},
                }

        for src, tgt in self._dep_graph.edges():
            for name, idx in self._index_mgr._indices.items():
                for chunk_id, meta in idx.get_all_metadata().items():
                    extra = meta.extra
                    cte_name = extra.get("cte_name", "")
                    if cte_name == src:
                        if tgt not in self._ref_map:
                            self._ref_map[tgt] = {
                                "ref_count": 0,
                                "referenced_by": [],
                                "ref_types": {},
                            }
                        entry = self._ref_map[tgt]
                        if chunk_id not in entry["referenced_by"]:
                            entry["referenced_by"].append(chunk_id)
                            entry["ref_count"] += 1
                            entry["ref_types"][chunk_id] = "dependency"

    def add_reference(self, source_id: str, target_id: str, ref_type: str = "direct"):
        if target_id not in self._ref_map:
            self._ref_map[target_id] = {
                "ref_count": 0,
                "referenced_by": [],
                "ref_types": {},
            }
        entry = self._ref_map[target_id]
        if source_id not in entry["referenced_by"]:
            entry["referenced_by"].append(source_id)
            entry["ref_count"] += 1
            entry["ref_types"][source_id] = ref_type

        for name, idx in self._index_mgr._indices.items():
            meta = idx.get_metadata(target_id)
            if meta is not None:
                if source_id not in meta.referenced_by:
                    meta.referenced_by.append(source_id)
                    meta.ref_count += 1

    def remove_reference(self, source_id: str, target_id: str):
        entry = self._ref_map.get(target_id)
        if entry is None:
            return
        if source_id in entry["referenced_by"]:
            entry["referenced_by"].remove(source_id)
            entry["ref_count"] = max(0, entry["ref_count"] - 1)
            entry["ref_types"].pop(source_id, None)

        for name, idx in self._index_mgr._indices.items():
            meta = idx.get_metadata(target_id)
            if meta is not None:
                if source_id in meta.referenced_by:
                    meta.referenced_by.remove(source_id)
                    meta.ref_count = max(0, meta.ref_count - 1)

    def get_ref_count(self, chunk_id: str) -> int:
        entry = self._ref_map.get(chunk_id)
        if entry is None:
            return 0
        return entry["ref_count"]

    def can_delete(self, chunk_id: str) -> bool:
        return self.get_ref_count(chunk_id) == 0

    def get_dependents(self, chunk_id: str) -> list[str]:
        entry = self._ref_map.get(chunk_id)
        if entry is None:
            return []
        return list(entry["referenced_by"])

    def cascade_remove(self, chunk_id: str) -> list[str]:
        affected = []
        for target_id, entry in list(self._ref_map.items()):
            if chunk_id in entry["referenced_by"]:
                entry["referenced_by"].remove(chunk_id)
                entry["ref_count"] = max(0, entry["ref_count"] - 1)
                entry["ref_types"].pop(chunk_id, None)
                affected.append(target_id)

                for name, idx in self._index_mgr._indices.items():
                    meta = idx.get_metadata(target_id)
                    if meta is not None:
                        if chunk_id in meta.referenced_by:
                            meta.referenced_by.remove(chunk_id)
                            meta.ref_count = max(0, meta.ref_count - 1)

        self._ref_map.pop(chunk_id, None)
        return affected

    def save(self, path: str):
        p = Path(path)
        p.parent.mkdir(parents=True, exist_ok=True)
        with open(p, "w", encoding="utf-8") as f:
            json.dump(self._ref_map, f, ensure_ascii=False, indent=2)

    def load(self, path: str):
        p = Path(path)
        if not p.exists():
            logger.warning(f"引用计数文件不存在: {path}")
            return
        with open(p, "r", encoding="utf-8") as f:
            self._ref_map = json.load(f)

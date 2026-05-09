import json
import logging
from pathlib import Path

from .models import SearchResult, ChunkType
from .index_manager import IndexManager
from .retriever import MultiIndexRetriever

logger = logging.getLogger(__name__)

_DEFAULT_CONFIG = {
    "indices": {
        "data_dict": {
            "model_name": "BAAI/bge-large-zh-v1.5",
            "model_dim": 1024,
            "index_path": "",
        },
        "ddl": {
            "model_name": "BAAI/bge-large-zh-v1.5",
            "model_dim": 1024,
            "index_path": "",
        },
        "sql": {
            "model_name": "jina-code-embeddings-0.5b",
            "model_dim": 896,
            "index_path": "",
        },
    },
    "models": {
        "BAAI/bge-large-zh-v1.5": {"dim": 1024},
        "jina-code-embeddings-0.5b": {"dim": 896},
    },
    "dep_graph_path": "indices/dep_graph.json",
    "source_hash_path": "indices/source_hashes.json",
}


class RAGGateway:

    def __init__(self, config_path: str = ""):
        config = dict(_DEFAULT_CONFIG)
        if config_path and Path(config_path).exists():
            with open(config_path, "r", encoding="utf-8") as f:
                user_config = json.load(f)
            config.update(user_config)

        self._config = config
        self._index_mgr = IndexManager(config)
        self._retriever = MultiIndexRetriever(self._index_mgr)

    def build(self, yaml_path: str = "", ddl_path: str = "", sql_dir: str = "", er_file: str = ""):
        build_config = {}
        if yaml_path:
            build_config["data_dict"] = {"yaml_path": yaml_path, "er_file": er_file}
        if ddl_path:
            build_config["ddl"] = {"ddl_path": ddl_path}
        if sql_dir:
            build_config["sql"] = {"sql_dir": sql_dir}

        self._index_mgr.build_all(build_config)
        self._index_mgr.save_all()
        logger.info("索引构建完成")

    def search(self, query: str, top_k: int = 5, include_related: bool = True) -> list[SearchResult]:
        return self._retriever.search(query, top_k=top_k, include_related=include_related)

    def stats(self) -> dict:
        index_stats = self._index_mgr.stats()
        return {name: info.to_dict() for name, info in index_stats.items()}

    def save(self):
        self._index_mgr.save_all()

    def load(self):
        self._index_mgr.load_all()

    def search_compatible(self, query: str, top_k: int = 5, include_related: bool = True) -> list[dict]:
        results = self.search(query, top_k=top_k, include_related=include_related)
        compatible = []
        for r in results:
            entry = {
                "table": r.metadata.get("table_name", ""),
                "domain": r.metadata.get("domain", ""),
                "comment": r.metadata.get("comment", r.chunk_text),
                "score": r.score,
                "chunk_id": r.chunk_id,
                "chunk_type": r.chunk_type.value,
                "source": r.source,
            }
            if r.context:
                entry["context"] = [c.to_dict() if isinstance(c, SearchResult) else c for c in r.context]
            compatible.append(entry)
        return compatible

import os
import json
import hashlib
import logging
from pathlib import Path
from typing import Optional
import numpy as np

from .models import (
    CTEChunk, DDLChunk, VectorMetadata, VectorStatus,
    ChunkType, IndexInfo,
)
from .cte_parser import CTEParser
from .ddl_parser import DDLParser
from .dependency_graph import DependencyGraph, NodeType
from .vector_index import VectorIndex
from .model_registry import ModelRegistry as _ModelRegistry

logger = logging.getLogger(__name__)


class _IndexModelRegistry:
    """适配层：将P0的ModelRegistry适配为IndexManager所需的encode接口"""

    _INDEX_PROMPT_MAP: dict = {
        "data_dict": "passage",
        "ddl": "passage",
        "sql": "nl2code_document",
    }

    def __init__(self):
        self._registered: set[str] = set()

    def register(self, name: str, dim: int = 0, model_fn=None):
        self._registered.add(name)

    def get(self, name: str) -> bool:
        return name in self._registered

    def encode(self, model_name: str, texts: list[str], index_name: str = "") -> np.ndarray:
        prompt_name = self._INDEX_PROMPT_MAP.get(index_name, "")
        embeddings = _ModelRegistry.encode(model_name, texts, prompt_name=prompt_name)
        return np.array(embeddings, dtype=np.float32)


class IndexManager:

    def __init__(self, config: dict):
        self._config = config
        self._indices: dict[str, VectorIndex] = {}
        self._dep_graph = DependencyGraph()
        self._model_registry = _IndexModelRegistry()
        self._cte_parser = CTEParser()
        self._ddl_parser = DDLParser()
        self._source_hashes: dict[str, str] = {}

        indices_cfg = config.get("indices", {})
        for name, idx_cfg in indices_cfg.items():
            model_name = idx_cfg.get("model_name", "")
            dim = idx_cfg.get("model_dim", 768)
            index_path = idx_cfg.get("index_path", "")

            vi = VectorIndex(name=name, dim=dim, index_path=index_path)
            self._indices[name] = vi

        models_cfg = config.get("models", {})
        for model_name, model_cfg in models_cfg.items():
            self._model_registry.register(
                name=model_name,
                dim=model_cfg.get("dim", 768),
                model_fn=model_cfg.get("fn"),
            )

    def build_data_dict_index(self, yaml_path: str, er_file: str = ""):
        idx = self._indices.get("data_dict")
        if idx is None:
            logger.warning("data_dict索引未配置")
            return

        if not os.path.exists(yaml_path):
            logger.warning(f"YAML文件不存在: {yaml_path}")
            return

        with open(yaml_path, "r", encoding="utf-8") as f:
            content = f.read()

        source_hash = hashlib.md5(content.encode()).hexdigest()
        self._source_hashes["data_dict"] = source_hash

        lines = content.strip().split("\n")
        chunk_ids = []
        chunk_texts = []
        for line in lines:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            chunk_id = f"data_dict::{hashlib.md5(line.encode()).hexdigest()[:12]}"
            chunk_ids.append(chunk_id)
            chunk_texts.append(line)

        if not chunk_ids:
            return

        model_name = self._config.get("indices", {}).get("data_dict", {}).get("model_name", "")
        if model_name and self._model_registry.get(model_name):
            embeddings = self._model_registry.encode(model_name, chunk_texts, index_name="data_dict")
        else:
            embeddings = np.random.rand(len(chunk_ids), idx._dim).astype(np.float32)

        metadatas = [
            VectorMetadata(
                chunk_id=cid,
                chunk_type=ChunkType.table,
                source_hash=source_hash,
            )
            for cid in chunk_ids
        ]
        idx.add(chunk_ids, embeddings, metadatas)

    def build_ddl_index(self, ddl_path: str):
        idx = self._indices.get("ddl")
        if idx is None:
            logger.warning("ddl索引未配置")
            return

        if not os.path.exists(ddl_path):
            logger.warning(f"DDL文件不存在: {ddl_path}")
            return

        with open(ddl_path, "r", encoding="utf-8") as f:
            content = f.read()

        source_hash = hashlib.md5(content.encode()).hexdigest()
        self._source_hashes["ddl"] = source_hash

        ddl_chunks = self._ddl_parser.parse(content)
        if not ddl_chunks:
            return

        chunk_ids = [c.chunk_id for c in ddl_chunks]
        chunk_texts = [c.chunk_text for c in ddl_chunks]

        model_name = self._config.get("indices", {}).get("ddl", {}).get("model_name", "")
        if model_name and self._model_registry.get(model_name):
            embeddings = self._model_registry.encode(model_name, chunk_texts, index_name="ddl")
        else:
            embeddings = np.random.rand(len(chunk_ids), idx._dim).astype(np.float32)

        metadatas = [
            VectorMetadata(
                chunk_id=c.chunk_id,
                chunk_type=ChunkType.ddl,
                source_hash=source_hash,
            )
            for c in ddl_chunks
        ]
        idx.add(chunk_ids, embeddings, metadatas)

    def build_sql_index(self, sql_dir: str, etl_dir: str = ""):
        idx = self._indices.get("sql")
        ddl_idx = self._indices.get("ddl")
        if idx is None:
            logger.warning("sql索引未配置")
            return

        sql_path = Path(sql_dir)
        if not sql_path.exists():
            logger.warning(f"SQL目录不存在: {sql_dir}")
            return

        all_cte_chunks: list[CTEChunk] = []
        all_ddl_chunks: list[DDLChunk] = []
        all_source = []

        for sql_file in sorted(sql_path.rglob("*.sql")):
            etl_id = sql_file.stem
            if etl_dir:
                rel = sql_file.relative_to(etl_dir)
                etl_id = str(rel.with_suffix(""))

            with open(sql_file, "r", encoding="utf-8") as f:
                content = f.read()
            all_source.append(content)

            cte_chunks = self._cte_parser.parse(content, etl_id=etl_id)
            all_cte_chunks.extend(cte_chunks)

            ddl_chunks = self._ddl_parser.parse(content)
            all_ddl_chunks.extend(ddl_chunks)

        source_hash = hashlib.md5("".join(all_source).encode()).hexdigest()
        self._source_hashes["sql"] = source_hash

        self._dep_graph = DependencyGraph.from_cte_chunks(all_cte_chunks)

        if all_cte_chunks:
            chunk_ids = [c.chunk_id for c in all_cte_chunks]
            chunk_texts = [c.chunk_text for c in all_cte_chunks]

            model_name = self._config.get("indices", {}).get("sql", {}).get("model_name", "")
            if model_name and self._model_registry.get(model_name):
                embeddings = self._model_registry.encode(model_name, chunk_texts, index_name="sql")
                logger.info(f"SQL索引编码完成: emb_shape={embeddings.shape}, idx_dim={idx._dim}, faiss_dim={idx._index.d}")
            else:
                embeddings = np.random.rand(len(chunk_ids), idx._dim).astype(np.float32)

            metadatas = [
                VectorMetadata(
                    chunk_id=c.chunk_id,
                    chunk_type=c.chunk_type,
                    source_hash=source_hash,
                    extra={
                        "cte_name": c.cte_name,
                        "etl_id": c.etl_id,
                        "depends_on_tables": c.depends_on_tables,
                        "depends_on_ctes": c.depends_on_ctes,
                        "output_fields": c.output_fields,
                    },
                )
                for c in all_cte_chunks
            ]
            idx.add(chunk_ids, embeddings, metadatas)

        if all_ddl_chunks and ddl_idx is not None:
            ddl_chunk_ids = [c.chunk_id for c in all_ddl_chunks]
            ddl_chunk_texts = [c.chunk_text for c in all_ddl_chunks]

            ddl_model = self._config.get("indices", {}).get("ddl", {}).get("model_name", "")
            if ddl_model and self._model_registry.get(ddl_model):
                ddl_embeddings = self._model_registry.encode(ddl_model, ddl_chunk_texts, index_name="ddl")
            else:
                ddl_embeddings = np.random.rand(len(ddl_chunk_ids), ddl_idx._dim).astype(np.float32)

            ddl_metas = [
                VectorMetadata(
                    chunk_id=c.chunk_id,
                    chunk_type=ChunkType.ddl,
                    source_hash=source_hash,
                )
                for c in all_ddl_chunks
            ]
            ddl_idx.add(ddl_chunk_ids, ddl_embeddings, ddl_metas)

    def build_all(self, config: dict):
        data_dict_cfg = config.get("data_dict", {})
        if data_dict_cfg:
            self.build_data_dict_index(
                yaml_path=data_dict_cfg.get("yaml_path", ""),
                er_file=data_dict_cfg.get("er_file", ""),
            )

        ddl_cfg = config.get("ddl", {})
        if ddl_cfg:
            self.build_ddl_index(ddl_path=ddl_cfg.get("ddl_path", ""))

        sql_cfg = config.get("sql", {})
        if sql_cfg:
            self.build_sql_index(
                sql_dir=sql_cfg.get("sql_dir", ""),
                etl_dir=sql_cfg.get("etl_dir", ""),
            )

    def get_index(self, name: str) -> Optional[VectorIndex]:
        return self._indices.get(name)

    def get_dep_graph(self) -> DependencyGraph:
        return self._dep_graph

    def _resolve_index_path(self, name: str) -> str:
        idx_cfg = self._config.get("indices", {}).get(name, {})
        index_path = idx_cfg.get("index_path", "")
        if index_path:
            return index_path
        skills_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        return os.path.join(skills_dir, "rag", "indices", name)

    def save_all(self):
        for name, idx in self._indices.items():
            index_path = self._resolve_index_path(name)
            idx.save(index_path)

        dep_path = self._config.get("dep_graph_path", "")
        if not dep_path:
            dep_path = os.path.join(self._resolve_index_path("data_dict"), "..", "dep_graph.json")
        p = Path(dep_path)
        p.parent.mkdir(parents=True, exist_ok=True)
        with open(dep_path, "w", encoding="utf-8") as f:
            json.dump(self._dep_graph.to_dict(), f, ensure_ascii=False, indent=2)

        hash_path = self._config.get("source_hash_path", "")
        if not hash_path:
            hash_path = os.path.join(self._resolve_index_path("data_dict"), "..", "source_hashes.json")
        p = Path(hash_path)
        p.parent.mkdir(parents=True, exist_ok=True)
        with open(hash_path, "w", encoding="utf-8") as f:
            json.dump(self._source_hashes, f, ensure_ascii=False, indent=2)

    def load_all(self):
        for name, idx in self._indices.items():
            index_path = self._resolve_index_path(name)
            if Path(index_path).exists():
                idx.load(index_path)

        dep_path = self._config.get("dep_graph_path", "")
        if not dep_path:
            dep_path = os.path.join(self._resolve_index_path("data_dict"), "..", "dep_graph.json")
        if os.path.exists(dep_path):
            with open(dep_path, "r", encoding="utf-8") as f:
                self._dep_graph = DependencyGraph.from_dict(json.load(f))

        hash_path = self._config.get("source_hash_path", "")
        if not hash_path:
            hash_path = os.path.join(self._resolve_index_path("data_dict"), "..", "source_hashes.json")
        if os.path.exists(hash_path):
            with open(hash_path, "r", encoding="utf-8") as f:
                self._source_hashes = json.load(f)

    def stats(self) -> dict[str, IndexInfo]:
        result = {}
        for name, idx in self._indices.items():
            idx_cfg = self._config.get("indices", {}).get(name, {})
            result[name] = IndexInfo(
                name=name,
                model_name=idx_cfg.get("model_name", ""),
                model_dim=idx._dim,
                vector_count=idx.count,
                index_path=idx_cfg.get("index_path", ""),
            )
        return result

    def rebuild_if_stale(self):
        hash_path = self._config.get("source_hash_path", "indices/source_hashes.json")
        if not os.path.exists(hash_path):
            self.build_all(self._config)
            self.save_all()
            return

        with open(hash_path, "r", encoding="utf-8") as f:
            old_hashes = json.load(f)

        stale = False

        data_dict_cfg = self._config.get("data_dict", {})
        if data_dict_cfg:
            yaml_path = data_dict_cfg.get("yaml_path", "")
            if os.path.exists(yaml_path):
                with open(yaml_path, "r", encoding="utf-8") as f:
                    new_hash = hashlib.md5(f.read().encode()).hexdigest()
                if new_hash != old_hashes.get("data_dict", ""):
                    stale = True

        ddl_cfg = self._config.get("ddl", {})
        if ddl_cfg:
            ddl_path = ddl_cfg.get("ddl_path", "")
            if os.path.exists(ddl_path):
                with open(ddl_path, "r", encoding="utf-8") as f:
                    new_hash = hashlib.md5(f.read().encode()).hexdigest()
                if new_hash != old_hashes.get("ddl", ""):
                    stale = True

        sql_cfg = self._config.get("sql", {})
        if sql_cfg:
            sql_dir = sql_cfg.get("sql_dir", "")
            sql_path = Path(sql_dir)
            if sql_path.exists():
                combined = []
                for sf in sorted(sql_path.rglob("*.sql")):
                    with open(sf, "r", encoding="utf-8") as f:
                        combined.append(f.read())
                new_hash = hashlib.md5("".join(combined).encode()).hexdigest()
                if new_hash != old_hashes.get("sql", ""):
                    stale = True

        if stale:
            logger.info("检测到源数据变更，执行全量重建")
            self.build_all(self._config)
            self.save_all()

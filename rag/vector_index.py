import json
import pickle
import logging
import numpy as np
import faiss
from pathlib import Path
from typing import Optional

from .models import VectorMetadata, VectorStatus, ChunkType

logger = logging.getLogger(__name__)


class VectorIndex:

    def __init__(self, name: str, dim: int, index_path: str = ""):
        self._name = name
        self._dim = dim
        self._idmap: list[str] = []
        self._metadata: dict[str, VectorMetadata] = {}
        self._chunk_to_faiss: dict[str, int] = {}
        self._faiss_to_chunk: dict[int, str] = {}
        self._next_faiss_id: int = 0

        if index_path and Path(index_path).exists():
            self.load(index_path)
        else:
            base = faiss.IndexFlatIP(dim)
            self._index = faiss.IndexIDMap(base)

    def add(self, chunk_ids: list[str], embeddings: np.ndarray, metadatas: list[VectorMetadata] = None):
        if len(chunk_ids) != embeddings.shape[0]:
            raise ValueError("chunk_ids与embeddings长度不匹配")
        if embeddings.shape[1] != self._dim:
            raise ValueError(f"embeddings维度{embeddings.shape[1]}与索引维度{self._dim}不匹配")

        logger.debug(f"VectorIndex.add: name={self._name}, n={len(chunk_ids)}, emb_shape={embeddings.shape}, emb_dtype={embeddings.dtype}, faiss_dim={self._index.d}")

        ids_to_remove = []
        for chunk_id in chunk_ids:
            if chunk_id in self._chunk_to_faiss:
                ids_to_remove.append(self._chunk_to_faiss[chunk_id])

        if ids_to_remove:
            sel = faiss.IDSelectorArray(np.array(ids_to_remove, dtype=np.int64))
            self._index.remove_ids(sel)
            for cid in chunk_ids:
                if cid in self._chunk_to_faiss:
                    old_fid = self._chunk_to_faiss[cid]
                    del self._faiss_to_chunk[old_fid]
                    del self._chunk_to_faiss[cid]

        faiss_ids = []
        for chunk_id in chunk_ids:
            fid = self._next_faiss_id
            self._next_faiss_id += 1
            faiss_ids.append(fid)
            self._chunk_to_faiss[chunk_id] = fid
            self._faiss_to_chunk[fid] = chunk_id
            self._idmap.append(chunk_id)

        vecs = embeddings.astype(np.float32)
        ids_arr = np.array(faiss_ids, dtype=np.int64)
        self._index.add_with_ids(vecs, ids_arr)

        for i, chunk_id in enumerate(chunk_ids):
            if metadatas and i < len(metadatas):
                self._metadata[chunk_id] = metadatas[i]
            elif chunk_id not in self._metadata:
                self._metadata[chunk_id] = VectorMetadata(chunk_id=chunk_id)

    def search(self, query_vec: np.ndarray, top_k: int, status_filter: list[VectorStatus] = None) -> list[tuple[str, float]]:
        if self._index.ntotal == 0:
            return []

        query = query_vec.reshape(1, -1).astype(np.float32)
        search_k = top_k * 2 if status_filter else top_k
        search_k = min(search_k, self._index.ntotal)
        if search_k <= 0:
            return []

        scores, ids = self._index.search(query, search_k)

        results = []
        for i in range(search_k):
            faiss_id = int(ids[0][i])
            if faiss_id < 0:
                continue
            chunk_id = self._faiss_to_chunk.get(faiss_id)
            if chunk_id is None:
                continue
            if status_filter:
                meta = self._metadata.get(chunk_id)
                if meta and meta.status not in status_filter:
                    continue
            results.append((chunk_id, float(scores[0][i])))
            if len(results) >= top_k:
                break

        return results

    def remove(self, chunk_ids: list[str]):
        ids_to_remove = []
        for chunk_id in chunk_ids:
            if chunk_id not in self._chunk_to_faiss:
                continue
            faiss_id = self._chunk_to_faiss[chunk_id]
            ids_to_remove.append(faiss_id)

        if ids_to_remove:
            sel = faiss.IDSelectorArray(np.array(ids_to_remove, dtype=np.int64))
            self._index.remove_ids(sel)

        for chunk_id in chunk_ids:
            if chunk_id in self._chunk_to_faiss:
                fid = self._chunk_to_faiss[chunk_id]
                del self._faiss_to_chunk[fid]
                del self._chunk_to_faiss[chunk_id]
            self._metadata.pop(chunk_id, None)
            if chunk_id in self._idmap:
                self._idmap.remove(chunk_id)

    def update_status(self, chunk_id: str, status: VectorStatus):
        if chunk_id in self._metadata:
            self._metadata[chunk_id].status = status

    def get_metadata(self, chunk_id: str) -> Optional[VectorMetadata]:
        return self._metadata.get(chunk_id)

    def get_all_metadata(self) -> dict[str, VectorMetadata]:
        return dict(self._metadata)

    def save(self, path: str):
        p = Path(path)
        p.mkdir(parents=True, exist_ok=True)

        faiss.write_index(self._index, str(p / "index.faiss"))

        with open(p / "idmap.pkl", "wb") as f:
            pickle.dump({
                "idmap": self._idmap,
                "chunk_to_faiss": self._chunk_to_faiss,
                "faiss_to_chunk": {int(k): v for k, v in self._faiss_to_chunk.items()},
                "next_faiss_id": self._next_faiss_id,
            }, f)

        meta_dict = {k: v.to_dict() for k, v in self._metadata.items()}
        with open(p / "metadata.json", "w", encoding="utf-8") as f:
            json.dump(meta_dict, f, ensure_ascii=False, indent=2)

    def load(self, path: str):
        p = Path(path)

        self._index = faiss.read_index(str(p / "index.faiss"))

        with open(p / "idmap.pkl", "rb") as f:
            data = pickle.load(f)
            self._idmap = data["idmap"]
            self._chunk_to_faiss = data["chunk_to_faiss"]
            self._faiss_to_chunk = {int(k): v for k, v in data["faiss_to_chunk"].items()}
            self._next_faiss_id = data["next_faiss_id"]

        with open(p / "metadata.json", "r", encoding="utf-8") as f:
            meta_dict = json.load(f)
            self._metadata = {k: VectorMetadata.from_dict(v) for k, v in meta_dict.items()}

    @property
    def count(self) -> int:
        return len(self._chunk_to_faiss)

    @property
    def active_count(self) -> int:
        return sum(1 for m in self._metadata.values() if m.status == VectorStatus.active)

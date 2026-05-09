import logging
from datetime import datetime

from .models import VectorStatus
from .index_manager import IndexManager

logger = logging.getLogger(__name__)


class VectorStateManager:

    VALID_TRANSITIONS = {
        VectorStatus.active: {VectorStatus.archived, VectorStatus.pending_deletion},
        VectorStatus.archived: {VectorStatus.active, VectorStatus.pending_deletion},
        VectorStatus.pending_deletion: {VectorStatus.active, VectorStatus.deleted},
        VectorStatus.deleted: set(),
    }

    def __init__(self, index_manager: IndexManager):
        self._index_mgr = index_manager

    def transition(self, chunk_id: str, target_status: VectorStatus) -> bool:
        for name, idx in self._index_mgr._indices.items():
            meta = idx.get_metadata(chunk_id)
            if meta is not None:
                current = meta.status
                if target_status not in self.VALID_TRANSITIONS.get(current, set()):
                    logger.warning(
                        f"非法状态流转: {current.value}→{target_status.value} for {chunk_id}"
                    )
                    return False
                idx.update_status(chunk_id, target_status)
                meta.status = target_status
                meta.updated_at = datetime.now().isoformat()
                return True
        logger.warning(f"chunk未找到: {chunk_id}")
        return False

    def archive(self, chunk_id: str) -> bool:
        return self.transition(chunk_id, VectorStatus.archived)

    def reactivate(self, chunk_id: str) -> bool:
        return self.transition(chunk_id, VectorStatus.active)

    def mark_pending_deletion(self, chunk_id: str) -> bool:
        return self.transition(chunk_id, VectorStatus.pending_deletion)

    def confirm_deletion(self, chunk_id: str) -> bool:
        return self.transition(chunk_id, VectorStatus.deleted)

    def rollback_deletion(self, chunk_id: str) -> bool:
        return self.transition(chunk_id, VectorStatus.active)

    def batch_archive(self, chunk_ids: list[str]) -> dict[str, bool]:
        results = {}
        for cid in chunk_ids:
            results[cid] = self.archive(cid)
        return results

    def get_by_status(self, status: VectorStatus) -> list[str]:
        result = []
        for name, idx in self._index_mgr._indices.items():
            for chunk_id, meta in idx.get_all_metadata().items():
                if meta.status == status:
                    result.append(chunk_id)
        return result

    def get_stale_chunks(self) -> list[str]:
        stale = []
        for name, idx in self._index_mgr._indices.items():
            for chunk_id, meta in idx.get_all_metadata().items():
                if meta.status == VectorStatus.active and meta.source_hash:
                    source_hash = self._index_mgr._source_hashes.get(name, "")
                    if meta.source_hash != source_hash:
                        stale.append(chunk_id)
        return stale

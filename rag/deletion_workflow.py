import logging

from .models import VectorStatus, DeletionResult, ImpactReport
from .vector_state_manager import VectorStateManager
from .ref_count_manager import RefCountManager
from .impact_assessor import ImpactAssessor
from .index_manager import IndexManager

logger = logging.getLogger(__name__)


class DeletionWorkflow:

    def __init__(self, state_manager: VectorStateManager,
                 ref_manager: RefCountManager,
                 impact_assessor: ImpactAssessor,
                 index_manager: IndexManager):
        self._state_mgr = state_manager
        self._ref_mgr = ref_manager
        self._assessor = impact_assessor
        self._index_mgr = index_manager

    def submit_deletion(self, chunk_id: str) -> ImpactReport:
        self._state_mgr.mark_pending_deletion(chunk_id)
        report = self._assessor.assess(chunk_id)
        return report

    def approve_deletion(self, chunk_id: str, approved: bool = True) -> DeletionResult:
        if not approved:
            self._state_mgr.rollback_deletion(chunk_id)
            return DeletionResult(
                chunk_id=chunk_id,
                success=True,
                orphaned=False,
                message="已回滚到active状态",
            )
        return self.execute_deletion(chunk_id)

    def execute_deletion(self, chunk_id: str, force: bool = False) -> DeletionResult:
        ref_count = self._ref_mgr.get_ref_count(chunk_id)

        if ref_count > 0 and not force:
            return DeletionResult(
                chunk_id=chunk_id,
                success=False,
                orphaned=True,
                message=f"引用计数={ref_count}，无法安全删除，需强制或审批",
            )

        cascaded = self._ref_mgr.cascade_remove(chunk_id)

        for name, idx in self._index_mgr._indices.items():
            meta = idx.get_metadata(chunk_id)
            if meta is not None:
                idx.remove([chunk_id])
                break

        self._state_mgr.confirm_deletion(chunk_id)

        orphaned = ref_count > 0
        message = "强制删除完成" if force else "安全删除完成"
        if orphaned:
            message = "孤儿删除完成（仍有引用已被级联移除）"

        return DeletionResult(
            chunk_id=chunk_id,
            success=True,
            orphaned=orphaned,
            cascaded=cascaded,
            message=message,
        )

    def sync_downstream(self, deleted_chunk_id: str) -> list[str]:
        affected = []

        dep_graph = self._index_mgr.get_dep_graph()
        downstream = dep_graph.downstream_of(deleted_chunk_id)
        affected.extend(downstream)

        dependents = self._ref_mgr.get_dependents(deleted_chunk_id)
        for dep_id in dependents:
            if dep_id not in affected:
                affected.append(dep_id)

        return affected

    def batch_submit(self, chunk_ids: list[str]) -> list[ImpactReport]:
        return [self.submit_deletion(cid) for cid in chunk_ids]

    def batch_approve(self, chunk_ids: list[str], approved: bool = True) -> list[DeletionResult]:
        return [self.approve_deletion(cid, approved) for cid in chunk_ids]

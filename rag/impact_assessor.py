from .models import ImpactReport
from .ref_count_manager import RefCountManager
from .dependency_graph import DependencyGraph


class ImpactAssessor:

    def __init__(self, ref_manager: RefCountManager, dep_graph: DependencyGraph):
        self._ref_mgr = ref_manager
        self._dep_graph = dep_graph

    def assess(self, chunk_id: str) -> ImpactReport:
        req_impacts = self._assess_requirement_impact(chunk_id)
        table_impacts = self._assess_table_impact(chunk_id)
        sql_impacts = self._assess_sql_impact(chunk_id)

        total = len(req_impacts) + len(table_impacts) + len(sql_impacts)
        can_delete = self._ref_mgr.can_delete(chunk_id)
        needs_approval = total > 0 or not can_delete

        return ImpactReport(
            target_id=chunk_id,
            requirement_impacts=req_impacts,
            table_impacts=table_impacts,
            sql_impacts=sql_impacts,
            total_impact_count=total,
            can_delete=can_delete,
            needs_approval=needs_approval,
        )

    def assess_batch(self, chunk_ids: list[str]) -> list[ImpactReport]:
        return [self.assess(cid) for cid in chunk_ids]

    def _assess_requirement_impact(self, chunk_id: str) -> list[str]:
        entry = self._ref_mgr._ref_map.get(chunk_id)
        if entry is None:
            return []
        result = []
        for src_id, ref_type in entry.get("ref_types", {}).items():
            if ref_type == "requirement":
                result.append(src_id)
        return result

    def _assess_table_impact(self, chunk_id: str) -> list[str]:
        return self._dep_graph.downstream_of(chunk_id)

    def _assess_sql_impact(self, chunk_id: str) -> list[str]:
        entry = self._ref_mgr._ref_map.get(chunk_id)
        if entry is None:
            return []
        result = []
        for src_id, ref_type in entry.get("ref_types", {}).items():
            if ref_type == "knowledge":
                result.append(src_id)
        return result

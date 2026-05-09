from dataclasses import dataclass, field
from enum import Enum
from typing import Any


class ChunkType(Enum):
    cte = "cte"
    assembly = "assembly"
    ddl = "ddl"
    table = "table"


class VectorStatus(Enum):
    active = "active"
    archived = "archived"
    deleted = "deleted"
    pending_deletion = "pending_deletion"


@dataclass
class CTEChunk:
    chunk_id: str
    cte_name: str
    etl_id: str
    chunk_text: str
    depends_on_tables: list = field(default_factory=list)
    depends_on_ctes: list = field(default_factory=list)
    output_fields: list = field(default_factory=list)
    chunk_type: ChunkType = ChunkType.cte

    def to_dict(self) -> dict:
        return {
            "chunk_id": self.chunk_id,
            "cte_name": self.cte_name,
            "etl_id": self.etl_id,
            "chunk_text": self.chunk_text,
            "depends_on_tables": self.depends_on_tables,
            "depends_on_ctes": self.depends_on_ctes,
            "output_fields": self.output_fields,
            "chunk_type": self.chunk_type.value,
        }

    @classmethod
    def from_dict(cls, d: dict) -> "CTEChunk":
        return cls(
            chunk_id=d["chunk_id"],
            cte_name=d["cte_name"],
            etl_id=d["etl_id"],
            chunk_text=d["chunk_text"],
            depends_on_tables=d.get("depends_on_tables", []),
            depends_on_ctes=d.get("depends_on_ctes", []),
            output_fields=d.get("output_fields", []),
            chunk_type=ChunkType(d.get("chunk_type", "cte")),
        )


@dataclass
class DDLChunk:
    chunk_id: str
    table_name: str
    chunk_text: str
    column_count: int = 0
    fk_count: int = 0
    chunk_type: ChunkType = ChunkType.ddl

    def to_dict(self) -> dict:
        return {
            "chunk_id": self.chunk_id,
            "table_name": self.table_name,
            "chunk_text": self.chunk_text,
            "column_count": self.column_count,
            "fk_count": self.fk_count,
            "chunk_type": self.chunk_type.value,
        }

    @classmethod
    def from_dict(cls, d: dict) -> "DDLChunk":
        return cls(
            chunk_id=d["chunk_id"],
            table_name=d["table_name"],
            chunk_text=d["chunk_text"],
            column_count=d.get("column_count", 0),
            fk_count=d.get("fk_count", 0),
            chunk_type=ChunkType(d.get("chunk_type", "ddl")),
        )


@dataclass
class VectorMetadata:
    chunk_id: str
    status: VectorStatus = VectorStatus.active
    version: int = 1
    source_hash: str = ""
    ref_count: int = 0
    referenced_by: list = field(default_factory=list)
    updated_at: str = ""
    chunk_type: ChunkType = ChunkType.table
    extra: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "chunk_id": self.chunk_id,
            "status": self.status.value,
            "version": self.version,
            "source_hash": self.source_hash,
            "ref_count": self.ref_count,
            "referenced_by": self.referenced_by,
            "updated_at": self.updated_at,
            "chunk_type": self.chunk_type.value,
            "extra": self.extra,
        }

    @classmethod
    def from_dict(cls, d: dict) -> "VectorMetadata":
        return cls(
            chunk_id=d["chunk_id"],
            status=VectorStatus(d.get("status", "active")),
            version=d.get("version", 1),
            source_hash=d.get("source_hash", ""),
            ref_count=d.get("ref_count", 0),
            referenced_by=d.get("referenced_by", []),
            updated_at=d.get("updated_at", ""),
            chunk_type=ChunkType(d.get("chunk_type", "table")),
            extra=d.get("extra", {}),
        )


@dataclass
class SearchResult:
    chunk_id: str
    chunk_text: str
    score: float = 0.0
    source: str = "direct"
    chunk_type: ChunkType = ChunkType.table
    metadata: dict = field(default_factory=dict)
    context: list = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "chunk_id": self.chunk_id,
            "chunk_text": self.chunk_text,
            "score": self.score,
            "source": self.source,
            "chunk_type": self.chunk_type.value,
            "metadata": self.metadata,
            "context": self.context,
        }

    @classmethod
    def from_dict(cls, d: dict) -> "SearchResult":
        return cls(
            chunk_id=d["chunk_id"],
            chunk_text=d["chunk_text"],
            score=d.get("score", 0.0),
            source=d.get("source", "direct"),
            chunk_type=ChunkType(d.get("chunk_type", "table")),
            metadata=d.get("metadata", {}),
            context=d.get("context", []),
        )


@dataclass
class ImpactReport:
    target_id: str
    requirement_impacts: list = field(default_factory=list)
    table_impacts: list = field(default_factory=list)
    sql_impacts: list = field(default_factory=list)
    total_impact_count: int = 0
    can_delete: bool = False
    needs_approval: bool = True

    def to_dict(self) -> dict:
        return {
            "target_id": self.target_id,
            "requirement_impacts": self.requirement_impacts,
            "table_impacts": self.table_impacts,
            "sql_impacts": self.sql_impacts,
            "total_impact_count": self.total_impact_count,
            "can_delete": self.can_delete,
            "needs_approval": self.needs_approval,
        }

    @classmethod
    def from_dict(cls, d: dict) -> "ImpactReport":
        return cls(
            target_id=d["target_id"],
            requirement_impacts=d.get("requirement_impacts", []),
            table_impacts=d.get("table_impacts", []),
            sql_impacts=d.get("sql_impacts", []),
            total_impact_count=d.get("total_impact_count", 0),
            can_delete=d.get("can_delete", False),
            needs_approval=d.get("needs_approval", True),
        )


@dataclass
class DeletionResult:
    chunk_id: str
    success: bool
    orphaned: bool = False
    cascaded: list = field(default_factory=list)
    message: str = ""

    def to_dict(self) -> dict:
        return {
            "chunk_id": self.chunk_id,
            "success": self.success,
            "orphaned": self.orphaned,
            "cascaded": self.cascaded,
            "message": self.message,
        }

    @classmethod
    def from_dict(cls, d: dict) -> "DeletionResult":
        return cls(
            chunk_id=d["chunk_id"],
            success=d["success"],
            orphaned=d.get("orphaned", False),
            cascaded=d.get("cascaded", []),
            message=d.get("message", ""),
        )


@dataclass
class DeletionProgress:
    chunk_id: str
    step: str = ""
    status: str = "pending"
    report: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "chunk_id": self.chunk_id,
            "step": self.step,
            "status": self.status,
            "report": self.report,
        }

    @classmethod
    def from_dict(cls, d: dict) -> "DeletionProgress":
        return cls(
            chunk_id=d["chunk_id"],
            step=d.get("step", ""),
            status=d.get("status", "pending"),
            report=d.get("report", {}),
        )


@dataclass
class IndexInfo:
    name: str
    model_name: str
    model_dim: int = 0
    vector_count: int = 0
    index_path: str = ""

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "model_name": self.model_name,
            "model_dim": self.model_dim,
            "vector_count": self.vector_count,
            "index_path": self.index_path,
        }

    @classmethod
    def from_dict(cls, d: dict) -> "IndexInfo":
        return cls(
            name=d["name"],
            model_name=d["model_name"],
            model_dim=d.get("model_dim", 0),
            vector_count=d.get("vector_count", 0),
            index_path=d.get("index_path", ""),
        )

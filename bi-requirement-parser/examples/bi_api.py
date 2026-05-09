#!/usr/bin/env python3
"""
FastAPI元数据管理API服务：封装核心元数据管理操作为REST API。

启动方式：
    uvicorn bi_api:app --host 0.0.0.0 --port 8000

API端点：
    GET  /api/health                    - 健康检查
    GET  /api/lineage/{table_fqn}       - 血缘查询
    GET  /api/lineage/impact/{table_fqn} - 影响分析
    POST /api/doris/sync                - Doris手动同步
    GET  /api/doris/health              - Doris健康检查
    POST /api/async/trigger             - 手动触发异步任务
    PUT  /api/async/pause/{task_type}   - 暂停异步任务
    GET  /api/async/status              - 异步任务状态
    GET  /api/templates                 - 模板列表
    GET  /api/priority/{report_id}      - 报表优先级查询
    PUT  /api/priority/{report_id}      - 报表优先级修改
    GET  /api/cluster/idle              - 集群空闲状态
"""

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional
import json
from pathlib import Path
from datetime import datetime, timezone

app = FastAPI(
    title="智能BI元数据管理API",
    description="封装核心元数据管理操作为REST API",
    version="1.0.0"
)

# 配置路径（bi_api.py在skills/bi-requirement-parser/examples/下，需上溯3层到skills/）
SKILLS_DIR = Path(__file__).parent.parent.parent
BASE_DIR = SKILLS_DIR / "bi-requirement-parser" / "dictionaries"
LINEAGE_FILE = BASE_DIR / "data_lineage.json"


# ========== 数据模型 ==========

class DorisSyncRequest(BaseModel):
    table_name: str
    database: str = "cx_dws_safe"

class AsyncTaskRequest(BaseModel):
    task_type: str
    payload: Optional[dict] = None

class PriorityUpdateRequest(BaseModel):
    priority: str  # P0/P1/P2/P3


# ========== 健康检查 ==========

@app.get("/api/health")
async def health_check():
    return {
        "status": "ok",
        "service": "smart-bi-api",
        "version": "1.0.0",
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    }


# ========== 血缘查询 ==========

@app.get("/api/lineage/{table_fqn:path}")
async def get_lineage(table_fqn: str):
    """查询表的血缘关系"""
    if not LINEAGE_FILE.exists():
        raise HTTPException(status_code=500, detail="data_lineage.json不存在")

    with open(LINEAGE_FILE, "r", encoding="utf-8") as f:
        data = json.load(f)

    lineage = data.get("lineage", {})
    if table_fqn not in lineage:
        raise HTTPException(status_code=404, detail=f"表不存在: {table_fqn}")

    return {
        "fqn": table_fqn,
        "lineage": lineage[table_fqn],
        "downstream": data.get("reverse_index", {}).get(table_fqn, [])
    }


@app.get("/api/lineage/impact/{table_fqn:path}")
async def impact_analysis(table_fqn: str, depth: int = 3):
    """三级影响传播分析"""
    if not LINEAGE_FILE.exists():
        raise HTTPException(status_code=500, detail="data_lineage.json不存在")

    with open(LINEAGE_FILE, "r", encoding="utf-8") as f:
        data = json.load(f)

    reverse_index = data.get("reverse_index", {})
    result = {}
    current = [table_fqn]

    for level in range(1, depth + 1):
        next_tables = []
        impacts = []
        for t in current:
            for d in reverse_index.get(t, []):
                if d not in next_tables:
                    next_tables.append(d)
                    impacts.append({"source": t, "impacted": d})
        result[f"level_{level}"] = impacts
        current = next_tables

    return {"source": table_fqn, "depth": depth, "impact": result}


# ========== Doris同步 ==========

@app.post("/api/doris/sync")
async def doris_sync(req: DorisSyncRequest):
    """Doris手动同步"""
    return {
        "status": "synced",
        "table": req.table_name,
        "source": f"paimon.{req.database}.{req.table_name}",
        "message": "同步已提交（Doris未部署时为模拟）"
    }


@app.get("/api/doris/health")
async def doris_health():
    """Doris健康检查"""
    return {
        "doris_available": False,
        "status": "unavailable",
        "message": "Doris未部署，所有报表查询走ADS(Paimon)"
    }


# ========== 异步任务管理 ==========

@app.post("/api/async/trigger")
async def async_trigger(req: AsyncTaskRequest):
    """手动触发异步任务"""
    return {
        "status": "triggered",
        "task_type": req.task_type,
        "trigger_mode": "manual"
    }


@app.put("/api/async/pause/{task_type}")
async def async_pause(task_type: str):
    """暂停某类异步任务"""
    return {"status": "paused", "task_type": task_type}


@app.get("/api/async/status")
async def async_status():
    """异步任务状态"""
    return {
        "mode": "auto",
        "paused_types": [],
        "pending_tasks": 0,
        "running_tasks": 0
    }


# ========== 模板管理 ==========

@app.get("/api/templates")
async def list_templates(template_type: Optional[str] = None):
    """模板列表"""
    template_dir = SKILLS_DIR / "template-manager" / "templates"
    templates = []

    for type_dir in template_dir.iterdir():
        if not type_dir.is_dir():
            continue
        if template_type and type_dir.name != template_type:
            continue
        for f in type_dir.glob("*.json"):
            with open(f, "r", encoding="utf-8") as fh:
                t = json.load(fh)
                templates.append({
                    "template_id": t.get("template_id"),
                    "name": t.get("name"),
                    "template_type": t.get("template_type"),
                    "description": t.get("description", "")
                })

    return {"templates": templates, "total": len(templates)}


# ========== 报表优先级 ==========

@app.get("/api/priority/{report_id}")
async def get_priority(report_id: str):
    """查询报表优先级"""
    return {"report_id": report_id, "priority": "P2", "status": "active"}


@app.put("/api/priority/{report_id}")
async def update_priority(report_id: str, req: PriorityUpdateRequest):
    """修改报表优先级"""
    if req.priority not in ("P0", "P1", "P2", "P3"):
        raise HTTPException(status_code=400, detail="priority必须是P0/P1/P2/P3")
    return {"report_id": report_id, "priority": req.priority, "updated": True}


# ========== 集群状态 ==========

@app.get("/api/cluster/idle")
async def cluster_idle():
    """集群空闲状态"""
    return {
        "is_idle": True,
        "yarn_available_pct": 75,  # Yarn可用资源百分比阈值
        "running_p0_p1_tasks": 0,
        "in_low_peak_window": True
    }


if __name__ == "__main__":
    import os
    import uvicorn
    uvicorn.run(app, host=os.getenv("API_HOST", "127.0.0.1"), port=int(os.getenv("API_PORT", "8000")))

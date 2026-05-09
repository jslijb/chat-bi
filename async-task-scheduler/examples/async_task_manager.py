#!/usr/bin/env python3
"""
异步任务调度器：管理集群空闲时执行的辅助任务，支持手动维护。

用法：
    python async_task_manager.py --action status|trigger|pause|resume|mode|retry|cancel [options]
"""

import argparse
import json
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from enum import Enum


class TaskType(Enum):
    INDEX_REBUILD = ("index_rebuild", 1, "RAG索引重建")
    LINEAGE_INFER = ("lineage_infer", 2, "血缘关系推断")
    SCORE_CALC = ("score_calc", 3, "高频提升评分计算")
    PRIORITY_ADJUST = ("priority_adjust", 4, "报表优先级升降级")
    DWP_CLEANUP = ("dwp_cleanup", 5, "DWP临时表TTL清理")
    CONSISTENCY_CHECK = ("consistency_check", 6, "数据一致性校验")

    def __init__(self, type_id, priority, description):
        self.type_id = type_id
        self.priority = priority
        self.description = description


class TaskStatus(Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class AsyncTaskManager:
    """异步任务管理器"""

    def __init__(self, state_file: str):
        self.state_file = Path(state_file)
        self.state = self._load_state()

    def _load_state(self) -> dict:
        if self.state_file.exists():
            with open(self.state_file, "r", encoding="utf-8") as f:
                return json.load(f)
        return {
            "mode": "auto",  # auto/manual
            "paused_types": [],
            "tasks": {},
            "cluster_idle": False
        }

    def _save_state(self):
        with open(self.state_file, "w", encoding="utf-8") as f:
            json.dump(self.state, f, ensure_ascii=False, indent=2)

    def _now(self) -> str:
        return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    def status(self) -> str:
        """查看所有任务状态"""
        lines = [f"全局模式: {self.state['mode']}", f"暂停的任务类型: {self.state.get('paused_types', [])}", ""]
        lines.append(f"{'任务ID':<36} {'类型':<20} {'状态':<12} {'优先级':<6} {'触发方式':<8} {'创建时间'}")
        lines.append("-" * 100)

        for task_id, task in self.state.get("tasks", {}).items():
            lines.append(
                f"{task_id:<36} {task['task_type']:<20} {task['status']:<12} "
                f"{task['priority']:<6} {task.get('trigger_mode', 'auto'):<8} {task['created_at']}"
            )

        return "\n".join(lines)

    def trigger(self, task_type: str, payload: dict = None) -> str:
        """手动触发任务"""
        task_id = str(uuid.uuid4())

        # 查找优先级
        DEFAULT_TASK_PRIORITY = 99  # 未知任务类型的默认优先级（最低）
        priority = DEFAULT_TASK_PRIORITY
        for tt in TaskType:
            if tt.type_id == task_type:
                priority = tt.priority
                break

        task = {
            "task_id": task_id,
            "task_type": task_type,
            "status": TaskStatus.PENDING.value,
            "priority": priority,
            "payload": payload or {},
            "created_at": self._now(),
            "started_at": None,
            "completed_at": None,
            "error_msg": None,
            "retry_count": 0,
            "trigger_mode": "manual"
        }

        self.state["tasks"][task_id] = task
        self._save_state()

        return f"任务已触发: {task_id} (type={task_type}, priority={priority})"

    def pause(self, task_type: str) -> str:
        """暂停某类任务自动触发"""
        paused = self.state.get("paused_types", [])
        if task_type not in paused:
            paused.append(task_type)
            self.state["paused_types"] = paused
            self._save_state()
        return f"已暂停: {task_type}"

    def resume(self, task_type: str) -> str:
        """恢复某类任务自动触发"""
        paused = self.state.get("paused_types", [])
        if task_type in paused:
            paused.remove(task_type)
            self.state["paused_types"] = paused
            self._save_state()
        return f"已恢复: {task_type}"

    def set_mode(self, mode: str) -> str:
        """全局切换自动/手动模式"""
        if mode not in ("auto", "manual"):
            return f"错误: mode必须是auto或manual"
        self.state["mode"] = mode
        self._save_state()
        return f"全局模式已切换: {mode}"

    def retry(self, task_id: str) -> str:
        """重试失败任务"""
        task = self.state["tasks"].get(task_id)
        if not task:
            return f"错误: 任务不存在: {task_id}"
        if task["status"] != TaskStatus.FAILED.value:
            return f"错误: 任务状态不是failed: {task['status']}"

        task["status"] = TaskStatus.PENDING.value
        task["retry_count"] += 1
        task["error_msg"] = None
        self._save_state()
        return f"已重试: {task_id} (retry_count={task['retry_count']})"

    def cancel(self, task_id: str) -> str:
        """取消待执行任务"""
        task = self.state["tasks"].get(task_id)
        if not task:
            return f"错误: 任务不存在: {task_id}"
        if task["status"] != TaskStatus.PENDING.value:
            return f"错误: 任务状态不是pending: {task['status']}"

        task["status"] = TaskStatus.CANCELLED.value
        self._save_state()
        return f"已取消: {task_id}"


def main():
    parser = argparse.ArgumentParser(description="异步任务调度器")
    parser.add_argument("--state", default="async_task_state.json", help="状态文件路径")
    parser.add_argument("--action", required=True,
                       choices=["status", "trigger", "pause", "resume", "mode", "retry", "cancel"])
    parser.add_argument("--task-type", help="任务类型")
    parser.add_argument("--task-id", help="任务ID")
    parser.add_argument("--mode", help="模式(auto/manual)")
    parser.add_argument("--payload", help="任务参数(JSON)")
    args = parser.parse_args()

    manager = AsyncTaskManager(args.state)

    if args.action == "status":
        print(manager.status())

    elif args.action == "trigger":
        if not args.task_type:
            print("错误: 需要指定--task-type")
            sys.exit(1)
        payload = json.loads(args.payload) if args.payload else {}
        print(manager.trigger(args.task_type, payload))

    elif args.action == "pause":
        if not args.task_type:
            print("错误: 需要指定--task-type")
            sys.exit(1)
        print(manager.pause(args.task_type))

    elif args.action == "resume":
        if not args.task_type:
            print("错误: 需要指定--task-type")
            sys.exit(1)
        print(manager.resume(args.task_type))

    elif args.action == "mode":
        if not args.mode:
            print("错误: 需要指定--mode (auto/manual)")
            sys.exit(1)
        print(manager.set_mode(args.mode))

    elif args.action == "retry":
        if not args.task_id:
            print("错误: 需要指定--task-id")
            sys.exit(1)
        print(manager.retry(args.task_id))

    elif args.action == "cancel":
        if not args.task_id:
            print("错误: 需要指定--task-id")
            sys.exit(1)
        print(manager.cancel(args.task_id))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
报表优先级管理引擎：自动升降级、依赖传播、归档恢复。

用法：
    python priority_manager.py --action adjust|status|migrate|archive [options]
"""

import argparse
import json
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path


PRIORITY_ORDER = {"P0": 0, "P1": 1, "P2": 2, "P3": 3, "ARCHIVED": 4}

DAILY_ACCESS_UPGRADE_THRESHOLD = 30
DOWNGRADE_INACTIVITY_DAYS = 30
ARCHIVE_INACTIVITY_DAYS = 60


class PriorityManager:
    """报表优先级管理器"""

    def __init__(self, state_file: str):
        self.state_file = Path(state_file)
        self.state = self._load_state()

    def _load_state(self) -> dict:
        if self.state_file.exists():
            with open(self.state_file, "r", encoding="utf-8") as f:
                return json.load(f)
        return {"reports": {}}

    def _save_state(self):
        with open(self.state_file, "w", encoding="utf-8") as f:
            json.dump(self.state, f, ensure_ascii=False, indent=2)

    def _now(self) -> str:
        return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    def auto_adjust(self) -> list:
        """执行自动升降级（每日凌晨批量执行）"""
        changes = []
        now = datetime.now(timezone.utc)

        for report_id, report in self.state["reports"].items():
            if report.get("status") == "archived":
                continue

            current_priority = report.get("priority", "P2")
            last_access = report.get("last_access_at")
            access_count_30d = report.get("access_count_30d", 0)
            leader_access_days = report.get("leader_access_consecutive_days", 0)

            # 升级规则1: A类领导连续3天访问 → P0
            if leader_access_days >= 3 and current_priority != "P0":
                changes.append({
                    "report_id": report_id,
                    "action": "upgrade",
                    "from": current_priority,
                    "to": "P0",
                    "reason": f"A类领导连续{leader_access_days}天访问"
                })
                report["priority"] = "P0"
                continue

            # 升级规则2: 30天日均访问>30次 → 升一级（最高P1）
            if access_count_30d > DAILY_ACCESS_UPGRADE_THRESHOLD * 30 and PRIORITY_ORDER.get(current_priority, 2) > 1:
                new_priority = [p for p, v in PRIORITY_ORDER.items() if v == PRIORITY_ORDER.get(current_priority, 2) - 1]
                new_priority = new_priority[0] if new_priority else current_priority
                if PRIORITY_ORDER.get(new_priority, 2) >= 1:  # 最高P1
                    changes.append({
                        "report_id": report_id,
                        "action": "upgrade",
                        "from": current_priority,
                        "to": new_priority,
                        "reason": f"30天日均访问{access_count_30d/30:.0f}次>30次"
                    })
                    report["priority"] = new_priority
                    continue

            # 降级规则1: 30天无访问 → 降一级
            if last_access:
                last_access_dt = datetime.fromisoformat(last_access.replace("Z", "+00:00"))
                days_since_access = (now - last_access_dt).days

                if days_since_access >= ARCHIVE_INACTIVITY_DAYS and current_priority == "P3":
                    # 60天无访问且P3 → 归档
                    changes.append({
                        "report_id": report_id,
                        "action": "archive",
                        "from": current_priority,
                        "to": "ARCHIVED",
                        "reason": f"60天无访问且为P3"
                    })
                    report["priority"] = "ARCHIVED"
                    report["status"] = "archived"
                elif days_since_access >= DOWNGRADE_INACTIVITY_DAYS and PRIORITY_ORDER.get(current_priority, 2) < 3:
                    new_priority = [p for p, v in PRIORITY_ORDER.items() if v == PRIORITY_ORDER.get(current_priority, 2) + 1]
                    new_priority = new_priority[0] if new_priority else current_priority
                    changes.append({
                        "report_id": report_id,
                        "action": "downgrade",
                        "from": current_priority,
                        "to": new_priority,
                        "reason": f"30天无访问({days_since_access}天)"
                    })
                    report["priority"] = new_priority

        self._save_state()
        return changes

    def status(self) -> dict:
        """查看所有报表优先级状态"""
        summary = {"P0": 0, "P1": 0, "P2": 0, "P3": 0, "ARCHIVED": 0}
        for report in self.state["reports"].values():
            p = report.get("priority", "P2")
            if p in summary:
                summary[p] += 1

        return {
            "summary": summary,
            "total": len(self.state["reports"]),
            "reports": self.state["reports"]
        }


def main():
    parser = argparse.ArgumentParser(description="报表优先级管理引擎")
    parser.add_argument("--state", default="priority_state.json", help="状态文件路径")
    parser.add_argument("--action", required=True, choices=["adjust", "status"])
    args = parser.parse_args()

    manager = PriorityManager(args.state)

    if args.action == "adjust":
        changes = manager.auto_adjust()
        if changes:
            print(f"优先级调整: {len(changes)}个变更")
            for c in changes:
                print(f"  {c['report_id']}: {c['action']} {c['from']}→{c['to']} ({c['reason']})")
        else:
            print("无优先级变更")

    elif args.action == "status":
        result = manager.status()
        print(f"报表总数: {result['total']}")
        print(f"优先级分布: P0={result['summary']['P0']}, P1={result['summary']['P1']}, "
              f"P2={result['summary']['P2']}, P3={result['summary']['P3']}, "
              f"ARCHIVED={result['summary']['ARCHIVED']}")


if __name__ == "__main__":
    main()

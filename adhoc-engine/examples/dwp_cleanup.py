#!/usr/bin/env python3
"""
DWP临时表自动清理：分级TTL管理、模式聚合续期、回收站恢复、存储告警。

TTL规则：
  cache=0(不落盘), pattern=7天, saved=30天, transition=90天

用法：
    python dwp_cleanup.py --action scan|cleanup|extend|alert [options]
"""

import argparse
import json
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path


# TTL规则（天数）
TTL_RULES = {
    "cache": 0,        # 不持久化，查询完即删
    "pattern": 7,      # 常用查询模式缓存
    "saved": 30,       # 用户主动保存的临时表
    "transition": 90,  # 过渡期临时表（待转正式）
}

# 存储告警阈值
STORAGE_ALERT_THRESHOLD_PCT = 10
EXPIRE_WARNING_DAYS = 3
RECYCLE_BIN_RETENTION_SECONDS = 86400  # DWP层总占用超集群存储10%触发告警


class DwpCleanupManager:
    """DWP临时表清理管理器"""

    def __init__(self, state_file: str):
        self.state_file = Path(state_file)
        self.state = self._load_state()

    def _load_state(self) -> dict:
        if self.state_file.exists():
            with open(self.state_file, "r", encoding="utf-8") as f:
                return json.load(f)
        return {"tables": {}, "recycle_bin": {}, "total_storage_mb": 0, "cluster_storage_mb": 0}

    def _save_state(self):
        with open(self.state_file, "w", encoding="utf-8") as f:
            json.dump(self.state, f, ensure_ascii=False, indent=2)

    def _now(self) -> datetime:
        return datetime.now(timezone.utc)

    def scan(self) -> list:
        """扫描DWP层临时表，返回即将过期的表"""
        now = self._now()
        expiring = []

        for table_name, meta in self.state["tables"].items():
            table_type = meta.get("type", "pattern")
            ttl_days = TTL_RULES.get(table_type, 7)
            created_at = datetime.fromisoformat(meta["created_at"].replace("Z", "+00:00"))
            last_access = datetime.fromisoformat(meta.get("last_access_at", meta["created_at"]).replace("Z", "+00:00"))

            # 基于最后访问时间计算过期
            expire_at = last_access + timedelta(days=ttl_days)
            days_until_expire = (expire_at - now).days

            if days_until_expire <= EXPIRE_WARNING_DAYS:  # 3天内过期
                expiring.append({
                    "table": table_name,
                    "type": table_type,
                    "ttl_days": ttl_days,
                    "days_until_expire": days_until_expire,
                    "created_at": meta["created_at"],
                    "last_access_at": meta.get("last_access_at"),
                    "creator": meta.get("creator", "unknown")
                })

        return expiring

    def cleanup(self) -> dict:
        """执行清理：过期表→回收站(24h可恢复)→物理删除"""
        now = self._now()
        cleaned = {"to_recycle_bin": [], "physically_deleted": []}

        # 从回收站中删除超过24小时的表
        for table_name, meta in list(self.state["recycle_bin"].items()):
            recycled_at = datetime.fromisoformat(meta["recycled_at"].replace("Z", "+00:00"))
            if (now - recycled_at).total_seconds() > RECYCLE_BIN_RETENTION_SECONDS:  # 24小时
                cleaned["physically_deleted"].append(table_name)
                del self.state["recycle_bin"][table_name]

        # 过期表移入回收站
        for table_name, meta in list(self.state["tables"].items()):
            table_type = meta.get("type", "pattern")
            ttl_days = TTL_RULES.get(table_type, 7)
            last_access = datetime.fromisoformat(meta.get("last_access_at", meta["created_at"]).replace("Z", "+00:00"))

            expire_at = last_access + timedelta(days=ttl_days)
            if now >= expire_at:
                # 移入回收站
                self.state["recycle_bin"][table_name] = {
                    **meta,
                    "recycled_at": now.strftime("%Y-%m-%dT%H:%M:%SZ")
                }
                del self.state["tables"][table_name]
                cleaned["to_recycle_bin"].append(table_name)

        self._save_state()
        return cleaned

    def extend(self, table_name: str, days: int = 30) -> str:
        """手动续期临时表"""
        if table_name not in self.state["tables"]:
            return f"错误: 临时表不存在: {table_name}"

        meta = self.state["tables"][table_name]
        now = self._now()
        meta["last_access_at"] = now.strftime("%Y-%m-%dT%H:%M:%SZ")

        if days >= 30:
            meta["type"] = "saved"
        elif days >= 7:
            meta["type"] = "pattern"

        if days != 30:
            meta["extend_days"] = days
            meta["extend_at"] = now.strftime("%Y-%m-%dT%H:%M:%SZ")

        self._save_state()

        effective_ttl = TTL_RULES.get(meta["type"], 7)
        return f"已续期: {table_name} (type={meta['type']}, TTL={effective_ttl}天, extend={days}天)"

    def alert(self) -> dict:
        """检查存储告警"""
        total = self.state.get("total_storage_mb", 0)
        cluster = self.state.get("cluster_storage_mb", 0)
        if cluster <= 0:
            return {
                "dwp_storage_mb": total,
                "cluster_storage_mb": 0,
                "percentage": 0.0,
                "alert": False,
                "threshold_pct": STORAGE_ALERT_THRESHOLD_PCT
            }
        pct = (total / cluster) * 100

        return {
            "dwp_storage_mb": total,
            "cluster_storage_mb": cluster,
            "percentage": round(pct, 2),
            "alert": pct > STORAGE_ALERT_THRESHOLD_PCT,
            "threshold_pct": STORAGE_ALERT_THRESHOLD_PCT
        }


def main():
    parser = argparse.ArgumentParser(description="DWP临时表自动清理")
    parser.add_argument("--state", default="dwp_state.json", help="状态文件路径")
    parser.add_argument("--action", required=True, choices=["scan", "cleanup", "extend", "alert"])
    parser.add_argument("--table", help="表名（extend动作）")
    parser.add_argument("--days", type=int, default=30, help="续期天数")
    args = parser.parse_args()

    manager = DwpCleanupManager(args.state)

    if args.action == "scan":
        expiring = manager.scan()
        if expiring:
            print(f"即将过期的临时表: {len(expiring)}个")
            for t in expiring:
                print(f"  {t['table']}: type={t['type']}, TTL={t['ttl_days']}天, "
                      f"剩余{t['days_until_expire']}天, 创建者={t['creator']}")
        else:
            print("无即将过期的临时表")

    elif args.action == "cleanup":
        result = manager.cleanup()
        print(f"移入回收站: {len(result['to_recycle_bin'])}个")
        for t in result["to_recycle_bin"]:
            print(f"  {t}")
        print(f"物理删除: {len(result['physically_deleted'])}个")
        for t in result["physically_deleted"]:
            print(f"  {t}")

    elif args.action == "extend":
        if not args.table:
            print("错误: 需要指定--table")
            sys.exit(1)
        print(manager.extend(args.table, args.days))

    elif args.action == "alert":
        result = manager.alert()
        print(f"DWP存储: {result['dwp_storage_mb']}MB / {result['cluster_storage_mb']}MB ({result['percentage']}%)")
        if result["alert"]:
            print(f"[ALERT] DWP存储超过{result['threshold_pct']}%阈值！")
        else:
            print("存储正常")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
ADS层查询路由（ReportStorageRouter）：根据报表复杂度自动选择ADS(Paimon)或Doris存储引擎。

路由规则：
- 维度数>=5 或 需要实时下钻 或 高并发查询 → Doris
- 其他 → ADS(Paimon)

用法：
    python report_storage_router.py --dimensions 5 --metrics 8 --drill-down true --concurrency high
"""

import argparse
import json
from typing import Optional


DORIS_DIMENSION_THRESHOLD = 5


def route_storage(
    dimension_count: int,
    metric_count: int = 0,
    drill_down: bool = False,
    concurrency: str = "normal",
    realtime: bool = False,
    manual_override: Optional[str] = None
) -> dict:
    """
    根据报表复杂度路由到ADS或Doris存储引擎。

    Returns:
        dict: {"storage_engine": "ADS"|"Doris", "database": "cx_ads_safe"|"doris_db",
               "reason": "路由原因", "routed_at": "ISO时间"}
    """
    from datetime import datetime, timezone

    # 手动覆盖优先
    if manual_override in ("ADS", "Doris"):
        db = "cx_ads_safe" if manual_override == "ADS" else "doris_db"
        return {
            "storage_engine": manual_override,
            "database": db,
            "reason": f"手动指定: {manual_override}",
            "routed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        }

    # 自动路由规则
    reasons = []

    # 规则1: 维度数>=5 → Doris
    if dimension_count >= DORIS_DIMENSION_THRESHOLD:
        reasons.append(f"维度数={dimension_count}>=5")

    # 规则2: 需要实时下钻 → Doris
    if drill_down:
        reasons.append("需要实时下钻")

    # 规则3: 高并发查询 → Doris
    if concurrency in ("high", "very_high"):
        reasons.append(f"并发级别={concurrency}")

    # 规则4: 实时性要求 → Doris
    if realtime:
        reasons.append("实时性要求")

    # 决策
    if reasons:
        engine = "Doris"
        database = "doris_db"
        reason = "Doris路由: " + ", ".join(reasons)
    else:
        engine = "ADS"
        database = "cx_ads_safe"
        reason = f"ADS路由: 维度数={dimension_count}, 无下钻需求, 并发={concurrency}"

    return {
        "storage_engine": engine,
        "database": database,
        "reason": reason,
        "routed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "routing_factors": {
            "dimension_count": dimension_count,
            "metric_count": metric_count,
            "drill_down": drill_down,
            "concurrency": concurrency,
            "realtime": realtime
        }
    }


def main():
    parser = argparse.ArgumentParser(description="ADS层查询路由")
    parser.add_argument("--dimensions", type=int, required=True, help="维度数")
    parser.add_argument("--metrics", type=int, default=0, help="指标数")
    parser.add_argument("--drill-down", type=str, default="false", help="是否需要下钻(true/false)")
    parser.add_argument("--concurrency", type=str, default="normal", help="并发级别(normal/high/very_high)")
    parser.add_argument("--realtime", type=str, default="false", help="是否需要实时(true/false)")
    parser.add_argument("--override", type=str, default=None, help="手动覆盖(ADS/Doris)")
    args = parser.parse_args()

    result = route_storage(
        dimension_count=args.dimensions,
        metric_count=args.metrics,
        drill_down=args.drill_down.lower() == "true",
        concurrency=args.concurrency,
        realtime=args.realtime.lower() == "true",
        manual_override=args.override
    )

    print(f"存储引擎: {result['storage_engine']}")
    print(f"数据库: {result['database']}")
    print(f"路由原因: {result['reason']}")
    print(f"\n完整路由结果:")
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

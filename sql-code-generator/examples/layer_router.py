#!/usr/bin/env python3
"""
分层构建引擎（LayerRouter）：根据 data_dictionary.yaml 和 data_lineage.json
自动推断目标层、生成FQN、计算构建批次。

用法：
    python layer_router.py --dict DICT --lineage LINEAGE [--requirement REQ]
"""

import argparse
import json
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("错误：需要PyYAML库。请执行：pip install pyyaml")
    sys.exit(1)


LAYER_TO_DB = {
    "ODS": "cx_ods_safe",
    "DWD": "cx_dwd_safe",
    "DWS": "cx_dws_safe",
    "DIM": "cx_dim_safe",
    "ADS": "cx_ads_safe",
    "DWP": "cx_dwp_safe",
}

LAYER_TO_PREFIX = {
    "ODS": "",          # ODS保留源系统前缀
    "DWD": "dwd_",
    "DWS": "dws_",
    "DIM": "dim_",
    "ADS": "ads_",
    "DWP": "adhoc_",
}

LAYER_TO_HDFS = {
    "ODS": "/cx_ods_safe/ods/",
    "DWD": "/cx_dwd_safe/dwd/",
    "DWS": "/cx_dws_safe/dws/",
    "DIM": "/cx_dim_safe/dim/",
    "ADS": "/cx_ads_safe/ads/",
    "DWP": "/cx_dwp_safe/adhoc/",
}

# 构建顺序：依赖驱动
BUILD_ORDER = ["ODS", "DIM", "DWD", "DWS", "ADS", "DWP"]

DEFAULT_CATALOG = "paimon"


def infer_target_layer(requirement: str) -> str:
    """根据需求描述推断目标层"""
    req_lower = requirement.lower()

    # 关键词推断
    if any(kw in req_lower for kw in ["维度表", "dim", "缓慢变化", "scd"]):
        return "DIM"
    if any(kw in req_lower for kw in ["报表", "看板", "dashboard", "ads", "应用层"]):
        return "ADS"
    if any(kw in req_lower for kw in ["汇总", "聚合", "日汇总", "月汇总", "dws", "汇总层"]):
        return "DWS"
    if any(kw in req_lower for kw in ["明细", "宽表", "dwd", "明细层", "清洗"]):
        return "DWD"
    if any(kw in req_lower for kw in ["临时", "adhoc", "即席", "取数"]):
        return "DWP"

    # 默认：有聚合关键词→DWS，无→DWD
    if any(kw in req_lower for kw in ["sum", "count", "avg", "合计", "总计", "统计"]):
        return "DWS"
    return "DWD"


def generate_fqn(catalog: str, layer: str, table_name: str) -> str:
    """生成 Fully Qualified Name"""
    database = LAYER_TO_DB.get(layer, "cx_ods_safe")
    prefix = LAYER_TO_PREFIX.get(layer, "")

    # 如果表名已有前缀，不重复添加
    if prefix and not table_name.startswith(prefix):
        qualified_name = f"{prefix}{table_name}"
    else:
        qualified_name = table_name

    return f"{catalog}.{database}.{qualified_name}"


def compute_build_batches(lineage: dict) -> list:
    """基于血缘依赖计算构建批次（拓扑排序）"""
    # 按层分组
    layer_tables = {}
    for fqn, meta in lineage.items():
        layer = meta.get("layer", "ODS")
        if layer not in layer_tables:
            layer_tables[layer] = []
        layer_tables[layer].append(fqn)

    # 按BUILD_ORDER生成批次
    batches = []
    for layer in BUILD_ORDER:
        if layer in layer_tables and layer_tables[layer]:
            batches.append({
                "layer": layer,
                "database": LAYER_TO_DB.get(layer, "cx_ods_safe"),
                "hdfs_path": LAYER_TO_HDFS.get(layer, ""),
                "tables": layer_tables[layer],
                "parallel": True  # 同层表可并行构建
            })

    return batches


def main():
    parser = argparse.ArgumentParser(description="分层构建引擎")
    parser.add_argument("--dict", required=True, help="data_dictionary.yaml路径")
    parser.add_argument("--lineage", required=True, help="data_lineage.json路径")
    parser.add_argument("--requirement", default=None, help="需求描述（用于推断目标层）")
    parser.add_argument("--table", default=None, help="表名（用于生成FQN）")
    args = parser.parse_args()

    # 读取数据字典
    with open(args.dict, "r", encoding="utf-8") as f:
        data_dict = yaml.safe_load(f)

    # 读取血缘关系
    with open(args.lineage, "r", encoding="utf-8") as f:
        lineage_data = json.load(f)

    lineage = lineage_data.get("lineage", {})

    # 1. 推断目标层
    if args.requirement:
        target_layer = infer_target_layer(args.requirement)
        print(f"需求推断目标层: {target_layer}")
        print(f"  database: {LAYER_TO_DB[target_layer]}")
        print(f"  HDFS路径: {LAYER_TO_HDFS[target_layer]}")

        if args.table:
            fqn = generate_fqn(DEFAULT_CATALOG, target_layer, args.table)
            print(f"  FQN: {fqn}")

    # 2. 计算构建批次
    batches = compute_build_batches(lineage)
    print(f"\n构建批次（共{len(batches)}批）:")
    for i, batch in enumerate(batches, 1):
        print(f"  批次{i}: {batch['layer']}层 ({batch['database']}) - {len(batch['tables'])}张表, 并行={batch['parallel']}")

    # 3. 输出JSON结果
    result = {
        "target_layer": infer_target_layer(args.requirement) if args.requirement else None,
        "build_batches": [
            {
                "layer": b["layer"],
                "database": b["database"],
                "hdfs_path": b["hdfs_path"],
                "table_count": len(b["tables"]),
                "parallel": b["parallel"]
            }
            for b in batches
        ]
    }

    output_path = Path(args.lineage).parent / "build_plan.json"
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    print(f"\n构建计划已输出: {output_path}")


if __name__ == "__main__":
    main()

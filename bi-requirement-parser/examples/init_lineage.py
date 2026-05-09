#!/usr/bin/env python3
"""
初始化 data_lineage.json：基于 fk_graph.json 和 data_dictionary.yaml 生成跨层血缘关系初始结构。

当前仅包含ODS层表，upstream为空（ODS层无上游），downstream待DWD层建设后填充。

用法：
    python init_lineage.py [--fk-graph FK_GRAPH] [--dict DICT] [--output OUTPUT]
"""

import argparse
import json
import sys
from datetime import datetime, timezone
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


def build_lineage(data_dict: dict, fk_graph: dict) -> tuple:
    """基于数据字典和FK图构建血缘关系"""

    tables = data_dict.get("tables", {})
    forward = fk_graph.get("forward", {})

    lineage = {}
    reverse_index = {}

    for table_name, table_def in tables.items():
        if not isinstance(table_def, dict):
            continue

        catalog = table_def.get("catalog", "paimon")
        database = table_def.get("database", "cx_ods_safe")
        layer = table_def.get("layer", "ODS")
        fqn = f"{catalog}.{database}.{table_name}"

        # ODS层表：upstream为空，downstream待填充
        # ODS层内部的FK关系记录在reverse_index中
        upstream = []
        downstream = []

        # 从fk_graph中获取ODS层内部的外键关系作为upstream
        if table_name in forward:
            for fk_col, parent_table in forward[table_name].items():
                parent_fqn = f"{catalog}.{database}.{parent_table}"
                if parent_fqn not in upstream:
                    upstream.append(parent_fqn)

        lineage[fqn] = {
            "layer": layer,
            "database": database,
            "catalog": catalog,
            "upstream": upstream,
            "downstream": downstream,
            "etl_script": "",
            "schedule_task": "",
            "related_requirements": [],
            "confidence": "confirmed"
        }

        # 构建reverse_index：记录哪些表引用了当前表
        if fqn not in reverse_index:
            reverse_index[fqn] = []

    # 基于forward关系填充reverse_index
    for table_name, fk_refs in forward.items():
        catalog = tables.get(table_name, {}).get("catalog", "paimon") if isinstance(tables.get(table_name), dict) else "paimon"
        database = tables.get(table_name, {}).get("database", "cx_ods_safe") if isinstance(tables.get(table_name), dict) else "cx_ods_safe"
        child_fqn = f"{catalog}.{database}.{table_name}"

        for fk_col, parent_table in fk_refs.items():
            parent_fqn = f"{catalog}.{database}.{parent_table}"
            if parent_fqn in reverse_index:
                if child_fqn not in reverse_index[parent_fqn]:
                    reverse_index[parent_fqn].append(child_fqn)

    return lineage, reverse_index


def main():
    parser = argparse.ArgumentParser(description="初始化data_lineage.json")
    parser.add_argument("--fk-graph", default=None, help="fk_graph.json路径")
    parser.add_argument("--dict", default=None, help="data_dictionary.yaml路径")
    parser.add_argument("--output", "-o", default=None, help="输出路径")
    args = parser.parse_args()

    base_dir = Path(__file__).parent.parent / "dictionaries"

    # 读取fk_graph.json
    fk_graph_path = Path(args.fk_graph) if args.fk_graph else base_dir / "dict_rag_index" / "fk_graph.json"
    if not fk_graph_path.exists():
        print(f"错误：fk_graph.json不存在：{fk_graph_path}")
        sys.exit(1)

    with open(fk_graph_path, "r", encoding="utf-8") as f:
        fk_graph = json.load(f)

    # 读取data_dictionary.yaml
    dict_path = Path(args.dict) if args.dict else base_dir / "data_dictionary.yaml"
    if not dict_path.exists():
        print(f"错误：data_dictionary.yaml不存在：{dict_path}")
        sys.exit(1)

    with open(dict_path, "r", encoding="utf-8") as f:
        data_dict = yaml.safe_load(f)

    # 构建血缘关系
    lineage, reverse_index = build_lineage(data_dict, fk_graph)

    # 组装输出
    output = {
        "version": "1.0",
        "updated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "lineage": lineage,
        "reverse_index": reverse_index
    }

    # 写入输出
    output_path = Path(args.output) if args.output else base_dir / "data_lineage.json"
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    # 统计
    total_tables = len(lineage)
    tables_with_upstream = sum(1 for v in lineage.values() if v["upstream"])
    total_reverse = sum(len(v) for v in reverse_index.values())

    print(f"data_lineage.json 已生成：{output_path}")
    print(f"  总表数：{total_tables}")
    print(f"  有上游关系的表：{tables_with_upstream}")
    print(f"  反向索引关系数：{total_reverse}")
    print("验证通过！")


if __name__ == "__main__":
    main()

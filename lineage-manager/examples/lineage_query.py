#!/usr/bin/env python3
"""
血缘元数据管理引擎 CLI：查询上游依赖、下游影响、三级影响传播、反向追踪、血缘图可视化。

用法：
    python lineage_query.py --lineage LINEAGE --action upstream|downstream|impact|trace|graph --table FQN [--depth N] [--format mermaid|json]
"""

import argparse
import json


def load_lineage(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def query_upstream(lineage: dict, table_fqn: str) -> list:
    """查询上游依赖"""
    meta = lineage.get("lineage", {}).get(table_fqn)
    if not meta:
        return []
    return meta.get("upstream", [])


def query_downstream(lineage: dict, table_fqn: str) -> list:
    """查询下游影响（从reverse_index）"""
    return lineage.get("reverse_index", {}).get(table_fqn, [])


def impact_analysis(lineage: dict, table_fqn: str, depth: int = 3) -> dict:
    """三级影响传播分析"""
    result = {}
    current_tables = [table_fqn]

    for level in range(1, depth + 1):
        next_tables = []
        level_impacts = []
        for t in current_tables:
            downstream = query_downstream(lineage, t)
            for d in downstream:
                if d not in next_tables:
                    next_tables.append(d)
                    level_impacts.append({
                        "source": t,
                        "impacted": d,
                        "layer": lineage.get("lineage", {}).get(d, {}).get("layer", "unknown")
                    })
        result[f"level_{level}"] = level_impacts
        current_tables = next_tables

    return result


def reverse_trace(lineage: dict, table_fqn: str) -> list:
    """反向追踪到ODS源表"""
    visited = set()
    result = []

    def _trace(fqn: str):
        if fqn in visited:
            return
        visited.add(fqn)
        upstream = query_upstream(lineage, fqn)
        for u in upstream:
            meta = lineage.get("lineage", {}).get(u, {})
            layer = meta.get("layer", "unknown")
            result.append({"fqn": u, "layer": layer})
            if layer != "ODS":
                _trace(u)

    _trace(table_fqn)
    return result


def generate_mermaid(lineage: dict, table_fqn: str, depth: int = 3) -> str:
    """生成Mermaid血缘图"""
    lines = ["graph TD"]
    visited = set()

    def _add_node(fqn: str, current_depth: int):
        if fqn in visited or current_depth > depth:
            return
        visited.add(fqn)

        meta = lineage.get("lineage", {}).get(fqn, {})
        layer = meta.get("layer", "unknown")
        short_name = fqn.split(".")[-1]

        # 上游
        for u in meta.get("upstream", []):
            u_short = u.split(".")[-1]
            lines.append(f"    {u_short} --> {short_name}")
            _add_node(u, current_depth + 1)

        # 下游
        for d in query_downstream(lineage, fqn):
            d_short = d.split(".")[-1]
            lines.append(f"    {short_name} --> {d_short}")
            _add_node(d, current_depth + 1)

    _add_node(table_fqn, 0)
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="血缘元数据管理引擎")
    parser.add_argument("--lineage", required=True, help="data_lineage.json路径")
    parser.add_argument("--action", required=True, choices=["upstream", "downstream", "impact", "trace", "graph"])
    parser.add_argument("--table", required=True, help="表FQN")
    parser.add_argument("--depth", type=int, default=3, help="影响传播深度")
    parser.add_argument("--format", default="text", choices=["text", "mermaid", "json"])
    args = parser.parse_args()

    data = load_lineage(args.lineage)

    if args.action == "upstream":
        result = query_upstream(data, args.table)
        print(f"上游依赖（{args.table}）：")
        for r in result:
            print(f"  ← {r}")

    elif args.action == "downstream":
        result = query_downstream(data, args.table)
        print(f"下游影响（{args.table}）：")
        for r in result:
            print(f"  → {r}")

    elif args.action == "impact":
        result = impact_analysis(data, args.table, args.depth)
        print(f"三级影响传播（{args.table}，深度={args.depth}）：")
        for level, impacts in result.items():
            print(f"\n  {level}：")
            for imp in impacts:
                print(f"    {imp['source']} → {imp['impacted']} (层={imp['layer']})")

    elif args.action == "trace":
        result = reverse_trace(data, args.table)
        print(f"反向追踪到ODS源表（{args.table}）：")
        for r in result:
            print(f"  ← {r['fqn']} (层={r['layer']})")

    elif args.action == "graph":
        mermaid = generate_mermaid(data, args.table, args.depth)
        print(mermaid)


if __name__ == "__main__":
    main()

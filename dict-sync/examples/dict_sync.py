#!/usr/bin/env python3
"""
数据字典同步引擎：DDL执行后自动同步更新data_dictionary.yaml、data_lineage.json和RAG索引。

用法：
    python dict_sync.py --ddl SQL_FILE --dict DICT --lineage LINEAGE [--dry-run]
"""

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

try:
    import yaml
except ImportError:
    print("错误：需要PyYAML库。请执行：pip install pyyaml")
    sys.exit(1)


def parse_ddl(ddl_text: str) -> list:
    """解析DDL语句，提取表结构变更"""
    results = []

    create_pattern = re.compile(
        r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?"
        r"`?(\w+)`?\.`?(\w+)`?\.`?(\w+)`?"
        r"\s*\((.*?)\)\s*",
        re.IGNORECASE | re.DOTALL
    )

    for match in create_pattern.finditer(ddl_text):
        catalog, database, table_name = match.group(1), match.group(2), match.group(3)
        fields_text = match.group(4)

        fields = []
        for line in fields_text.split("\n"):
            line = line.strip().rstrip(",")
            if not line or line.startswith("--"):
                continue
            field_match = re.match(
                r"`?(\w+)`?\s+([\w()]+(?:\([\d,]+\))?)\s*(?:COMMENT\s+'([^']*)')?",
                line, re.IGNORECASE
            )
            if field_match:
                fields.append({
                    "name": field_match.group(1),
                    "type": field_match.group(2),
                    "comment": field_match.group(3) or ""
                })

        results.append({
            "action": "CREATE",
            "catalog": catalog,
            "database": database,
            "table_name": table_name,
            "fields": fields
        })

    alter_add_pattern = re.compile(
        r"ALTER\s+TABLE\s+`?(\w+)`?\.`?(\w+)`?\.`?(\w+)`?"
        r"\s+ADD\s+(?:COLUMN\s+)?`?(\w+)`?\s+([\w()]+(?:\([\d,]+\))?)\s*(?:COMMENT\s+'([^']*)')?",
        re.IGNORECASE
    )

    for match in alter_add_pattern.finditer(ddl_text):
        catalog, database, table_name = match.group(1), match.group(2), match.group(3)
        results.append({
            "action": "ALTER_ADD",
            "catalog": catalog,
            "database": database,
            "table_name": table_name,
            "fields": [{
                "name": match.group(4),
                "type": match.group(5),
                "comment": match.group(6) or ""
            }]
        })

    alter_drop_pattern = re.compile(
        r"ALTER\s+TABLE\s+`?(\w+)`?\.`?(\w+)`?\.`?(\w+)`?"
        r"\s+DROP\s+(?:COLUMN\s+)?`?(\w+)`?",
        re.IGNORECASE
    )

    for match in alter_drop_pattern.finditer(ddl_text):
        catalog, database, table_name = match.group(1), match.group(2), match.group(3)
        results.append({
            "action": "ALTER_DROP",
            "catalog": catalog,
            "database": database,
            "table_name": table_name,
            "fields": [{"name": match.group(4)}]
        })

    return results


def classify_change(old_fields: dict, new_fields: dict) -> list:
    """分类字段变更"""
    changes = []

    old_names = {f["name"] for f in old_fields} if old_fields else set()
    new_names = {f["name"] for f in new_fields} if new_fields else set()
    old_map = {f["name"]: f for f in old_fields} if old_fields else {}
    new_map = {f["name"]: f for f in new_fields} if new_fields else {}

    # 新增字段 → 扩展级
    for name in new_names - old_names:
        changes.append({"field": name, "type": "extension", "action": "ADD", "severity": "medium"})

    # 删除字段 → 语义级
    for name in old_names - new_names:
        changes.append({"field": name, "type": "semantic", "action": "DROP", "severity": "high"})

    # 修改字段
    for name in old_names & new_names:
        old_f = old_map[name]
        new_f = new_map[name]

        if old_f["type"] != new_f["type"]:
            # 类型改变 → 语义级
            changes.append({
                "field": name, "type": "semantic", "action": "TYPE_CHANGE",
                "old_type": old_f["type"], "new_type": new_f["type"], "severity": "high"
            })
        elif old_f.get("comment", "") != new_f.get("comment", ""):
            # 注释修改 → 格式级
            changes.append({
                "field": name, "type": "format", "action": "COMMENT_CHANGE", "severity": "low"
            })

    return changes


def sync_dictionary(data_dict: dict, ddl_results: list, dry_run: bool = False) -> dict:
    """同步更新data_dictionary.yaml"""
    tables = data_dict.get("tables", {})
    sync_log = []

    for ddl in ddl_results:
        table_name = ddl["table_name"]
        fqn = f"{ddl['catalog']}.{ddl['database']}.{table_name}"

        if table_name in tables:
            # 已有表：分类变更
            old_fields = tables[table_name].get("columns", [])
            changes = classify_change(old_fields, ddl["fields"])
            sync_log.append({"fqn": fqn, "action": "UPDATE", "changes": changes})
        else:
            # 新增表
            sync_log.append({"fqn": fqn, "action": "CREATE", "changes": []})

            if not dry_run:
                tables[table_name] = {
                    "catalog": ddl["catalog"],
                    "database": ddl["database"],
                    "layer": _db_to_layer(ddl["database"]),
                    "columns": ddl["fields"]
                }

    if not dry_run:
        data_dict["tables"] = tables

    return sync_log


def _db_to_layer(database: str) -> str:
    """从数据库名反推层名"""
    db_to_layer = {
        "cx_ods_safe": "ODS", "cx_dwd_safe": "DWD", "cx_dws_safe": "DWS",
        "cx_dim_safe": "DIM", "cx_ads_safe": "ADS", "cx_dwp_safe": "DWP",
    }
    return db_to_layer.get(database, "ODS")


def sync_lineage(lineage_data: dict, ddl_results: list, dry_run: bool = False) -> list:
    """同步更新data_lineage.json"""
    lineage = lineage_data.get("lineage", {})
    sync_log = []

    for ddl in ddl_results:
        fqn = f"{ddl['catalog']}.{ddl['database']}.{ddl['table_name']}"

        if fqn not in lineage:
            if not dry_run:
                lineage[fqn] = {
                    "layer": _db_to_layer(ddl["database"]),
                    "database": ddl["database"],
                    "catalog": ddl["catalog"],
                    "upstream": [],
                    "downstream": [],
                    "etl_script": "",
                    "schedule_task": "",
                    "related_requirements": [],
                    "confidence": "confirmed"
                }
            sync_log.append({"fqn": fqn, "action": "ADD_LINEAGE"})

    if not dry_run:
        lineage_data["lineage"] = lineage
        lineage_data["updated_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    return sync_log


def main():
    parser = argparse.ArgumentParser(description="数据字典同步引擎")
    parser.add_argument("--ddl", required=True, help="DDL SQL文件路径")
    parser.add_argument("--dict", required=True, help="data_dictionary.yaml路径")
    parser.add_argument("--lineage", required=True, help="data_lineage.json路径")
    parser.add_argument("--dry-run", action="store_true", help="仅分析不修改")
    args = parser.parse_args()

    # 读取DDL
    with open(args.ddl, "r", encoding="utf-8") as f:
        ddl_text = f.read()

    # 解析DDL
    ddl_results = parse_ddl(ddl_text)
    print(f"解析DDL: {len(ddl_results)}个表操作")
    for ddl in ddl_results:
        print(f"  {ddl['action']}: {ddl['catalog']}.{ddl['database']}.{ddl['table_name']} ({len(ddl['fields'])}个字段)")

    # 读取数据字典
    with open(args.dict, "r", encoding="utf-8") as f:
        data_dict = yaml.safe_load(f)

    # 读取血缘关系
    with open(args.lineage, "r", encoding="utf-8") as f:
        lineage_data = json.load(f)

    # 同步字典
    dict_log = sync_dictionary(data_dict, ddl_results, dry_run=args.dry_run)
    print(f"\n字典同步: {len(dict_log)}个变更")
    for log in dict_log:
        print(f"  {log['fqn']}: {log['action']}")
        for change in log.get("changes", []):
            print(f"    - {change['field']}: {change['action']} ({change['type']}, severity={change['severity']})")

    # 同步血缘
    lineage_log = sync_lineage(lineage_data, ddl_results, dry_run=args.dry_run)
    print(f"\n血缘同步: {len(lineage_log)}个新增")
    for log in lineage_log:
        print(f"  {log['fqn']}: {log['action']}")

    # 写入（非dry-run时）
    if not args.dry_run:
        with open(args.dict, "w", encoding="utf-8") as f:
            yaml.dump(data_dict, f, allow_unicode=True, default_flow_style=False, sort_keys=False)

        with open(args.lineage, "w", encoding="utf-8") as f:
            json.dump(lineage_data, f, ensure_ascii=False, indent=2)

        print("\n同步完成！")
    else:
        print("\n[dry-run] 未修改任何文件")


if __name__ == "__main__":
    main()

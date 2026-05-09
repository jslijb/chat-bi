#!/usr/bin/env python3
"""
数据字典增强脚本：为所有ODS层表补充 catalog、database、layer 字段。

用法：
    python enhance_data_dictionary.py [--input INPUT] [--output OUTPUT]

示例：
    python enhance_data_dictionary.py
    python enhance_data_dictionary.py --input data_dictionary.yaml --output data_dictionary_enhanced.yaml
"""

import argparse
import sys
from pathlib import Path

# 尝试导入yaml，失败则提示安装
try:
    import yaml
except ImportError:
    print("错误：需要PyYAML库。请执行：pip install pyyaml")
    sys.exit(1)


# 分层到库名的映射
LAYER_TO_DB = {
    "ODS": "cx_ods_safe",
    "DWD": "cx_dwd_safe",
    "DWS": "cx_dws_safe",
    "DIM": "cx_dim_safe",
    "ADS": "cx_ads_safe",
    "DWP": "cx_dwp_safe",
}

DEFAULT_CATALOG = "paimon"
DEFAULT_LAYER = "ODS"  # 当前所有表都是ODS层


def enhance_dictionary(data: dict, catalog: str = DEFAULT_CATALOG, layer: str = DEFAULT_LAYER) -> dict:
    """为数据字典中的每张表补充 catalog、database、layer 字段"""

    if "tables" not in data:
        print("错误：数据字典中未找到 'tables' 键")
        return data

    database = LAYER_TO_DB.get(layer, "cx_ods_safe")
    tables = data["tables"]
    enhanced_count = 0
    skipped_count = 0

    for table_name, table_def in tables.items():
        if not isinstance(table_def, dict):
            skipped_count += 1
            continue

        # 如果已有这些字段则跳过
        if "catalog" in table_def and "database" in table_def and "layer" in table_def:
            skipped_count += 1
            continue

        # 在comment之前插入catalog、database、layer字段
        # YAML中dict的顺序：构建新的有序dict
        enhanced = {}
        enhanced["catalog"] = catalog
        enhanced["database"] = database
        enhanced["layer"] = layer

        # 保留原有字段
        for key, value in table_def.items():
            enhanced[key] = value

        tables[table_name] = enhanced
        enhanced_count += 1

    print(f"增强完成：{enhanced_count} 张表已补充字段，{skipped_count} 张表跳过（已有字段或非dict类型）")
    return data


def main():
    parser = argparse.ArgumentParser(description="数据字典增强：补充catalog/database/layer字段")
    parser.add_argument("--input", "-i", default=None, help="输入数据字典YAML文件路径")
    parser.add_argument("--output", "-o", default=None, help="输出YAML文件路径（默认覆盖输入文件）")
    parser.add_argument("--catalog", "-c", default=DEFAULT_CATALOG, help=f"catalog名称（默认：{DEFAULT_CATALOG}）")
    parser.add_argument("--layer", "-l", default=DEFAULT_LAYER, help=f"分层名称（默认：{DEFAULT_LAYER}）")
    args = parser.parse_args()

    # 确定输入文件路径
    if args.input:
        input_path = Path(args.input)
    else:
        # 默认路径：脚本同目录下的data_dictionary.yaml
        input_path = Path(__file__).parent.parent / "dictionaries" / "data_dictionary.yaml"

    if not input_path.exists():
        print(f"错误：输入文件不存在：{input_path}")
        sys.exit(1)

    # 确定输出文件路径
    output_path = Path(args.output) if args.output else input_path

    print(f"读取数据字典：{input_path}")
    with open(input_path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f)

    # 检查表数量
    table_count = len(data.get("tables", {}))
    print(f"当前表数量：{table_count}")

    # 执行增强
    data = enhance_dictionary(data, catalog=args.catalog, layer=args.layer)

    # 写入输出文件
    print(f"写入增强后的数据字典：{output_path}")
    with open(output_path, "w", encoding="utf-8") as f:
        yaml.dump(data, f, allow_unicode=True, default_flow_style=False, sort_keys=False)

    # 验证
    with open(output_path, "r", encoding="utf-8") as f:
        verify_data = yaml.safe_load(f)

    verified_count = 0
    for table_name, table_def in verify_data.get("tables", {}).items():
        if isinstance(table_def, dict) and "catalog" in table_def and "database" in table_def and "layer" in table_def:
            verified_count += 1

    print(f"验证：{verified_count}/{table_count} 张表包含 catalog/database/layer 字段")

    if verified_count == table_count:
        print("验证通过！所有表均已增强。")
    else:
        print(f"警告：{table_count - verified_count} 张表未包含增强字段，请检查。")
        sys.exit(1)


if __name__ == "__main__":
    main()

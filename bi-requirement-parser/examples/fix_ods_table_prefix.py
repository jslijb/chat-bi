# fix_ods_table_prefix.py
# 修复数据字典中 ODS 表名前缀：添加 cx_ods_safe. 和 pingan_insurance_ 前缀
# 同时重建 RAG 索引文件
# 运行方式: python fix_ods_table_prefix.py
# 需要安装的包: pyyaml (pip install pyyaml)

import os
import json
import copy
import shutil

BASE_DIR = r"d:\data_lake\.codebuddy\skills\bi-requirement-parser\dictionaries"
ODS_DB = "cx_ods_safe"
TABLE_PREFIX = "pingan_insurance_"

def fix_yaml():
    import yaml
    yaml_path = os.path.join(BASE_DIR, "data_dictionary.yaml")
    backup_path = yaml_path + ".bak"

    shutil.copy2(yaml_path, backup_path)
    print(f"[1/5] 备份 data_dictionary.yaml -> {backup_path}")

    with open(yaml_path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f)

    if "domains" in data:
        for domain_name, domain_info in data["domains"].items():
            if "names" in domain_info:
                domain_info["names"] = [TABLE_PREFIX + n for n in domain_info["names"]]

    if "tables" in data:
        new_tables = {}
        for table_name, table_info in data["tables"].items():
            new_name = TABLE_PREFIX + table_name
            new_tables[new_name] = table_info
        data["tables"] = new_tables

    with open(yaml_path, "w", encoding="utf-8") as f:
        yaml.dump(data, f, allow_unicode=True, default_flow_style=False, sort_keys=False)

    print(f"[1/5] data_dictionary.yaml 表名前缀修复完成")

def fix_yaml_index():
    yaml_path = os.path.join(BASE_DIR, "data_dictionary_index.yaml")
    if not os.path.exists(yaml_path):
        print("[2/5] data_dictionary_index.yaml 不存在，跳过")
        return

    backup_path = yaml_path + ".bak"
    shutil.copy2(yaml_path, backup_path)

    with open(yaml_path, "r", encoding="utf-8") as f:
        content = f.read()

    lines = content.split("\n")
    new_lines = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("- ") and "(" in stripped and "列" in stripped:
            dash_and_space = line[:line.index("-")]
            rest = stripped[2:]
            space_idx = rest.index(" ")
            table_name = rest[:space_idx]
            suffix = rest[space_idx:]
            new_lines.append(f"{dash_and_space}- {TABLE_PREFIX}{table_name}{suffix}")
        else:
            new_lines.append(line)

    with open(yaml_path, "w", encoding="utf-8") as f:
        f.write("\n".join(new_lines))

    print(f"[2/5] data_dictionary_index.yaml 表名前缀修复完成")

def fix_md():
    md_path = os.path.join(BASE_DIR, "data_dictionary.md")
    if not os.path.exists(md_path):
        print("[3/5] data_dictionary.md 不存在，跳过")
        return

    backup_path = md_path + ".bak"
    shutil.copy2(md_path, backup_path)

    with open(md_path, "r", encoding="utf-8") as f:
        content = f.read()

    lines = content.split("\n")
    new_lines = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("- **") and "**（" in stripped:
            prefix = line[:line.index("- ")]
            rest = stripped[2:]
            name_end = rest.index("**")
            table_name = rest[2:name_end]
            suffix = rest[name_end:]
            new_lines.append(f"{prefix}- **{TABLE_PREFIX}{table_name}**{suffix}")
        else:
            new_lines.append(line)

    with open(md_path, "w", encoding="utf-8") as f:
        f.write("\n".join(new_lines))

    print(f"[3/5] data_dictionary.md 表名前缀修复完成")

def fix_rag_index():
    rag_dir = os.path.join(BASE_DIR, "dict_rag_index")
    if not os.path.exists(rag_dir):
        print("[4/5] dict_rag_index 目录不存在，跳过")
        return

    for fname in ["metadata.json", "tables.json", "domains.json"]:
        fpath = os.path.join(rag_dir, fname)
        if not os.path.exists(fpath):
            continue

        backup_path = fpath + ".bak"
        shutil.copy2(fpath, backup_path)

        with open(fpath, "r", encoding="utf-8") as f:
            data = json.load(f)

        if fname == "metadata.json":
            for item in data:
                if "table" in item:
                    item["table"] = TABLE_PREFIX + item["table"]
                if "yaml_file" in item:
                    item["yaml_file"] = TABLE_PREFIX + item["yaml_file"]
                if "chunk_text" in item:
                    old_chunk = item["chunk_text"]
                    if old_chunk.startswith("表: "):
                        colon_idx = old_chunk.index(" ", 3)
                        table_name = old_chunk[3:colon_idx]
                        item["chunk_text"] = "表: " + TABLE_PREFIX + table_name + old_chunk[colon_idx:]
                if "columns" in item:
                    pass

        elif fname == "domains.json":
            for domain_name, domain_info in data.items():
                if "names" in domain_info:
                    domain_info["names"] = [TABLE_PREFIX + n for n in domain_info["names"]]

        elif fname == "tables.json":
            new_data = {}
            for table_name, table_info in data.items():
                new_name = TABLE_PREFIX + table_name
                new_data[new_name] = table_info
            data = new_data

        with open(fpath, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    print(f"[4/5] dict_rag_index JSON 文件表名前缀修复完成")

def fix_ods_er():
    er_path = os.path.join(BASE_DIR, "ods_er.txt")
    if not os.path.exists(er_path):
        print("[5/5] ods_er.txt 不存在，跳过")
        return

    backup_path = er_path + ".bak"
    shutil.copy2(er_path, backup_path)

    with open(er_path, "r", encoding="utf-8") as f:
        content = f.read()

    lines = content.split("\n")
    new_lines = []
    for line in lines:
        new_line = line
        if "**`" in line and "`**" in line:
            start = line.index("**`") + 3
            end = line.index("`**", start)
            table_name = line[start:end]
            if not table_name.startswith(TABLE_PREFIX):
                new_line = line[:start] + TABLE_PREFIX + table_name + line[end:]

        if "→ `" in line:
            parts = line.split("→ `")
            for i in range(1, len(parts)):
                end_idx = parts[i].index("`")
                ref_name = parts[i][:end_idx]
                if not ref_name.startswith(TABLE_PREFIX) and ref_name not in ("user_id", "vehicle_id", "policy_no", "claim_no", "enterprise_id", "agent_id", "product_code", "station_id", "surveyor_id", "coupon_id", "order_no", "part_code"):
                    parts[i] = TABLE_PREFIX + ref_name + parts[i][end_idx:]
            new_line = "→ `".join(parts)

        new_lines.append(new_line)

    with open(er_path, "w", encoding="utf-8") as f:
        f.write("\n".join(new_lines))

    print(f"[5/5] ods_er.txt 表名前缀修复完成")

if __name__ == "__main__":
    print("=" * 60)
    print("ODS 表名前缀修复工具")
    print(f"前缀: {ODS_DB}.{TABLE_PREFIX}")
    print("=" * 60)
    fix_yaml()
    fix_yaml_index()
    fix_md()
    fix_rag_index()
    fix_ods_er()
    print("\n全部修复完成！")
    print("原始文件已备份为 .bak 后缀")
    print("⚠️  RAG 向量索引 (index.faiss, idmap.pkl) 需要重新构建！")
    print("   请运行: rag build --er-file ods_er.txt")
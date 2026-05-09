"""
数据字典生成脚本
从 create_table.sql + pingan_insurance_data.sql 自动提取:
- 表结构（字段名、类型、注释）
- 枚举值（仅 COMMENT 中描述的，DML 仅补充 COMMENT 未覆盖的）
- 表间关系（外键）
- 输出为 YAML 格式，供大模型写 SQL 时参考

枚举值策略:
- COMMENT 中已用 "数字-中文" 或 "/分隔" 描述了枚举 => 仅保留 COMMENT 中的，不从 DML 补充
- COMMENT 中无枚举描述，但字段名匹配枚举模式 => 从 DML 提取实际值
- 字段属于排除类别（ID/时间/姓名/密码/URL/公式等）=> 不收集枚举值
"""

import argparse
import os
import re
import sys
from collections import defaultdict
from pathlib import Path


# ============ SQL 解析器 ============

def extract_create_tables(sql_content: str) -> list:
    """
    从 SQL 文件中提取 CREATE TABLE 语句
    返回: [{"table_name": str, "database": str, "comment": str, "columns": [...], "fks": [...]}]
    """
    tables = []
    current_db = None

    # 匹配 USE 语句
    use_pattern = re.compile(r'USE\s+`?(\w+)`?\s*;', re.IGNORECASE)
    for m in use_pattern.finditer(sql_content):
        current_db = m.group(1)

    # 匹配 CREATE TABLE
    create_pattern = re.compile(
        r'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?`?(\w+)`?\s*\((.*?)\)\s*'
        r'ENGINE\s*=\s*\w+.*?COMMENT\s*=\s*\'([^\']*)\'',
        re.IGNORECASE | re.DOTALL
    )

    for m in create_pattern.finditer(sql_content):
        table_name = m.group(1)
        body = m.group(2)
        table_comment = m.group(3)

        columns = []
        fks = []
        primary_key = []

        # 按行分割
        lines = [line.strip().rstrip(',') for line in body.split('\n') if line.strip()]

        for line in lines:
            # 跳过约束定义行
            if re.match(r'^\s*(PRIMARY\s+KEY|UNIQUE\s+KEY|KEY\s+|INDEX\s+|CONSTRAINT\s+)', line, re.IGNORECASE):
                # 提取 PRIMARY KEY
                pk_match = re.match(r'^\s*PRIMARY\s+KEY\s*\(`?(\w+)`?\)', line, re.IGNORECASE)
                if pk_match:
                    primary_key.append(pk_match.group(1))
                continue

            # 解析外键
            fk_match = re.match(
                r'^\s*CONSTRAINT\s+`?\w+`?\s*FOREIGN\s+KEY\s*\(`?(\w+)`?\)\s*'
                r'REFERENCES\s+`?(\w+)`?\s*\(`?(\w+)`?\)',
                line, re.IGNORECASE
            )
            if fk_match:
                fks.append({
                    "column": fk_match.group(1),
                    "ref_table": fk_match.group(2),
                    "ref_column": fk_match.group(3)
                })
                continue

            # 解析列定义
            col_match = re.match(
                r'^\s*`?(\w+)`?\s+([A-Za-z]+(?:\([^)]*\))?)\s*'
                r'(.*?)(?:COMMENT\s+\'([^\']*)\')?$',
                line, re.IGNORECASE
            )
            if col_match:
                col_name = col_match.group(1)
                col_type = col_match.group(2)
                constraints = col_match.group(3).strip()
                col_comment = col_match.group(4) or ""

                # 提取默认值
                default_val = None
                default_match = re.search(r"DEFAULT\s+('(?:[^']*)'|\S+)", constraints, re.IGNORECASE)
                if default_match:
                    default_val = default_match.group(1)

                # 提取枚举值（仅从 COMMENT 中，排除类字段不提取）
                enum_values = extract_enum_from_comment(col_comment, col_name, col_type)

                # 判断 COMMENT 中是否已描述枚举
                comment_has_enum = len(enum_values) > 0

                # 判断是否可为空
                nullable = "NOT NULL" not in constraints.upper()

                # 判断是否自增
                auto_increment = "AUTO_INCREMENT" in constraints.upper()

                columns.append({
                    "name": col_name,
                    "type": col_type,
                    "comment": col_comment,
                    "nullable": nullable,
                    "default": default_val,
                    "auto_increment": auto_increment,
                    "is_primary": col_name in primary_key,
                    "enum_values": enum_values,
                    "comment_has_enum": comment_has_enum,
                })

        tables.append({
            "table_name": table_name,
            "comment": table_comment,
            "columns": columns,
            "foreign_keys": fks,
            "primary_key": primary_key
        })

    return tables


def extract_enum_from_comment(comment: str, col_name: str = "", col_type: str = "") -> list:
    """
    从 COMMENT 中提取枚举值描述
    格式: "状态：0-冻结，1-正常" 或 "来源类型（活动/签到/购买）" 或 "0=xxx, 1=yyy"
    排除类字段（时间/ID/金额/名称等）直接跳过
    """
    if not comment:
        return []

    # 排除类字段不提取 COMMENT 枚举
    if should_exclude_column(col_name, col_type):
        return []

    enum_values = []

    # 格式1: "数字-中文" 或 "数字=中文" 或 "数字：中文"
    # 如: "状态：0-冻结，1-正常，2-注销"
    enum_pattern = re.compile(r'(\d+)\s*[-=：:]\s*([^，,；;\s\d]+(?:，[^，,；;\s\d]+)*)')
    matches = enum_pattern.findall(comment)
    for val, label in matches:
        label = re.split(r'[，,；;\s]\d+\s*[-=：:]', label)[0].strip()
        if label:
            enum_values.append({"value": val, "label": label})

    # 格式2: 斜杠分隔的枚举值
    # 支持: "来源类型（活动/签到/购买）" / "操作系统：iOS/Android" / "油品类型（92#/95#/98#）"
    if not enum_values:
        slash_pattern = re.compile(r'[（(：:]\s*([^\）)]+)\s*[）)]?$')
        m = slash_pattern.search(comment)
        if m:
            items = [item.strip() for item in m.group(1).split('/')]
            items = [item for item in items if item and len(item) <= 20]
            if len(items) >= 2:
                # 校验每项: 不含空格/标点句子符号
                valid = True
                for item in items:
                    if re.search(r'\s|[。.，,！!？?、]', item):
                        valid = False
                        break
                    # 中文项需>=2字符（过滤 省/市 等单字）
                    if re.search(r'[\u4e00-\u9fff]', item) and len(item) < 2:
                        valid = False
                        break
                if valid:
                    # 过滤尾部描述词（如 "精洗价格" → "价格"）
                    desc_suffixes = ('价格', '费用', '金额', '标准', '级别', '类型')
                    filtered = [item for item in items
                                if not any(item.endswith(s) for s in desc_suffixes)]
                    if len(filtered) >= 2:
                        for item in filtered:
                            enum_values.append({"value": item, "label": item})

    return enum_values


# ============ 枚举值过滤规则 ============

# 需要从数据字典中排除的列名模式（不需要记录枚举值）
EXCLUDE_COL_PATTERNS = [
    # === ID / 编号类 ===
    re.compile(r'.*_id$', re.IGNORECASE),
    re.compile(r'.*_no$', re.IGNORECASE),
    re.compile(r'.*_code$', re.IGNORECASE),
    # === 时间日期类 ===
    re.compile(r'.*时间$'),
    re.compile(r'.*日期$'),
    re.compile(r'.*_time$', re.IGNORECASE),
    re.compile(r'.*_date$', re.IGNORECASE),
    re.compile(r'.*_at$', re.IGNORECASE),
    # === 安全/凭证类 ===
    re.compile(r'.*password.*', re.IGNORECASE),
    re.compile(r'.*_hash$', re.IGNORECASE),
    re.compile(r'.*_salt$', re.IGNORECASE),
    re.compile(r'.*_key$', re.IGNORECASE),
    re.compile(r'.*_token$', re.IGNORECASE),
    re.compile(r'.*_secret$', re.IGNORECASE),
    re.compile(r'.*_signature$', re.IGNORECASE),
    re.compile(r'.*_sign$', re.IGNORECASE),
    re.compile(r'.*_encrypt.*', re.IGNORECASE),
    re.compile(r'.*_md5$', re.IGNORECASE),
    re.compile(r'.*_sha.*$', re.IGNORECASE),
    re.compile(r'.*openid$', re.IGNORECASE),
    re.compile(r'.*unionid$', re.IGNORECASE),
    re.compile(r'.*apple_id$', re.IGNORECASE),
    re.compile(r'.*userid$', re.IGNORECASE),
    # === 车辆标识类 ===
    re.compile(r'.*plate.*', re.IGNORECASE),
    re.compile(r'^vin$', re.IGNORECASE),
    re.compile(r'.*engine_no$', re.IGNORECASE),
    re.compile(r'.*frame_no$', re.IGNORECASE),
    re.compile(r'.*register_no$', re.IGNORECASE),
    re.compile(r'.*cert_no$', re.IGNORECASE),
    re.compile(r'.*license.*', re.IGNORECASE),
    # === 公式/表达式/JSON/文件类 ===
    re.compile(r'.*formula$', re.IGNORECASE),
    re.compile(r'.*expression$', re.IGNORECASE),
    re.compile(r'.*_json$', re.IGNORECASE),
    re.compile(r'.*_properties$', re.IGNORECASE),
    re.compile(r'.*_file$', re.IGNORECASE),
    re.compile(r'.*_path$', re.IGNORECASE),
    re.compile(r'.*_url$', re.IGNORECASE),
    re.compile(r'.*_uri$', re.IGNORECASE),
    re.compile(r'.*_link$', re.IGNORECASE),
    re.compile(r'.*_image$', re.IGNORECASE),
    re.compile(r'.*_photo$', re.IGNORECASE),
    re.compile(r'.*_avatar$', re.IGNORECASE),
    re.compile(r'.*_logo$', re.IGNORECASE),
    re.compile(r'.*_qr_code$', re.IGNORECASE),
    re.compile(r'.*_qr$', re.IGNORECASE),
    # === 名称类（不是枚举） ===
    re.compile(r'.*_name$', re.IGNORECASE),
    re.compile(r'^name$', re.IGNORECASE),
    re.compile(r'^anchor$', re.IGNORECASE),
    re.compile(r'^model$', re.IGNORECASE),
    re.compile(r'.*breed$', re.IGNORECASE),
    re.compile(r'.*species$', re.IGNORECASE),
    re.compile(r'.*variety$', re.IGNORECASE),
    re.compile(r'.*color$', re.IGNORECASE),
    # === 字典/通用值字段 ===
    re.compile(r'^dict_', re.IGNORECASE),
    re.compile(r'.*_info$', re.IGNORECASE),
    re.compile(r'.*_value$', re.IGNORECASE),
    # === 自由文本/个人信息类 ===
    re.compile(r'^(mobile|phone|email|session|ip|address|url|link|avatar|photo|image|file|remark|memo|description|note|content|text|reason|opinion|feedback|comment|message|title|nickname|first_name|last_name|fullname|occupation|insured_name|beneficiary_name|holder_name|driver_name)$', re.IGNORECASE),
    # === 金额/数值类（虽然不是枚举，防止误入） ===
    re.compile(r'.*amount$', re.IGNORECASE),
    re.compile(r'.*_amt$', re.IGNORECASE),
    re.compile(r'.*_price$', re.IGNORECASE),
    re.compile(r'.*_fee$', re.IGNORECASE),
    re.compile(r'.*_rate$', re.IGNORECASE),
    re.compile(r'.*_ratio$', re.IGNORECASE),
    re.compile(r'.*_count$', re.IGNORECASE),
    re.compile(r'.*_num$', re.IGNORECASE),
    re.compile(r'.*_quantity$', re.IGNORECASE),
    re.compile(r'.*_score$', re.IGNORECASE),
    re.compile(r'.*_total$', re.IGNORECASE),
    re.compile(r'.*_sum$', re.IGNORECASE),
    re.compile(r'.*_balance$', re.IGNORECASE),
    re.compile(r'.*_limit$', re.IGNORECASE),
    re.compile(r'.*_percent$', re.IGNORECASE),
    re.compile(r'.*_longitude$', re.IGNORECASE),
    re.compile(r'.*_latitude$', re.IGNORECASE),
    re.compile(r'.*_distance$', re.IGNORECASE),
    re.compile(r'.*_duration$', re.IGNORECASE),
    re.compile(r'.*_weight$', re.IGNORECASE),
    re.compile(r'.*_area$', re.IGNORECASE),
]

# 只记录枚举值的列名模式（白名单）
ENUM_COL_PATTERNS = [
    re.compile(r'.*status$', re.IGNORECASE),
    re.compile(r'.*type$', re.IGNORECASE),
    re.compile(r'.*level$', re.IGNORECASE),
    re.compile(r'.*category$', re.IGNORECASE),
    re.compile(r'.*channel$', re.IGNORECASE),
    re.compile(r'.*method$', re.IGNORECASE),
    re.compile(r'.*result$', re.IGNORECASE),
    re.compile(r'.*flag$', re.IGNORECASE),
    re.compile(r'.*tag$', re.IGNORECASE),
    re.compile(r'gender$', re.IGNORECASE),
    re.compile(r'is_\w+', re.IGNORECASE),
    re.compile(r'has_\w+', re.IGNORECASE),
    re.compile(r'cancel_\w+', re.IGNORECASE),
]


def should_exclude_column(col_name: str, col_type: str) -> bool:
    """判断该列是否应该从枚举值收集中排除"""
    # 1. 时间类型字段一律排除
    if col_type.upper().startswith(('DATE', 'DATETIME', 'TIMESTAMP', 'TIME')):
        return True
    # 2. 黑名单优先
    for pattern in EXCLUDE_COL_PATTERNS:
        if pattern.match(col_name):
            return True
    # 3. 白名单：不在黑名单中且匹配白名单才保留
    for pattern in ENUM_COL_PATTERNS:
        if pattern.match(col_name):
            return False
    # 4. 默认排除（既不在黑名单也不在白名单的字段不收集枚举值）
    return True


def is_variable_placeholder(val: str) -> bool:
    """判断值是否是变量占位符"""
    if not val:
        return True
    if val.startswith('@') or '@' in val:
        return True
    if val.startswith('{') or val.startswith('['):
        return True
    return False


def extract_insert_enums(sql_content: str, tables: list) -> dict:
    """
    从 INSERT 语句中提取字段的实际枚举值
    仅对 COMMENT 中无枚举描述且匹配白名单的字段生效
    返回: {"table_name.column_name": ["值1", "值2"]}
    """
    table_columns = defaultdict(set)

    # 构建映射
    table_col_types = {}
    table_col_has_enum = {}
    table_valid_cols = {}
    for table in tables:
        table_valid_cols[table["table_name"]] = {c["name"] for c in table["columns"]}
        for col in table["columns"]:
            key = f"{table['table_name']}.{col['name']}"
            table_col_types[key] = col["type"]
            table_col_has_enum[key] = col.get("comment_has_enum", False)

    # 匹配完整 INSERT 语句
    insert_pattern = re.compile(
        r"INSERT\s+INTO\s+`?(\w+)`?\s*\(([^)]+)\)\s*VALUES\s*(.*?);",
        re.IGNORECASE | re.DOTALL
    )

    # 构建所有列名集合（用于检测错位）
    all_col_names = set()
    for table in tables:
        for col in table["columns"]:
            all_col_names.add(col["name"])

    for m in insert_pattern.finditer(sql_content):
        table_name = m.group(1)
        cols_str = m.group(2)
        values_section = m.group(3)
        columns = [c.strip().strip('`') for c in cols_str.split(',')]

        valid_cols = table_valid_cols.get(table_name, set())
        if not valid_cols:
            continue

        value_pattern = re.compile(r"\(([^)]+)\)", re.DOTALL)
        for v_match in value_pattern.finditer(values_section):
            values_str = v_match.group(1)
            values = [v.strip().strip("'\"") for v in values_str.split(',')]

            # 列数必须匹配
            if len(values) != len(columns):
                continue

            for i, val in enumerate(values):
                if i >= len(columns):
                    continue
                col_name = columns[i]
                if col_name not in valid_cols:
                    continue

                key = f"{table_name}.{col_name}"
                col_type = table_col_types.get(key, "")

                # COMMENT 已有枚举描述 => 不从 DML 补充
                if table_col_has_enum.get(key, False):
                    continue

                # 排除类字段 => 不收集
                if should_exclude_column(col_name, col_type):
                    continue

                # 值过滤
                if is_variable_placeholder(val):
                    continue
                if not val or val == "NULL":
                    continue
                if val.replace('.', '').replace('-', '').isdigit():
                    continue
                if re.match(r'^[0-9a-f]{8}-[0-9a-f]{4}', val, re.IGNORECASE):
                    continue
                if len(val) > 50:
                    continue
                if re.match(r'^1[3-9]\d{9}$', val):
                    continue
                if re.match(r'^\d{17}[\dXx]$', val):
                    continue
                if re.match(r'^https?://', val):
                    continue
                # 包含运算符的不是枚举（公式/表达式残留）
                if re.search(r'[=<>+\-*/]', val):
                    continue
                # 句子片段不是枚举（含句号、常见虚词等）
                if re.search(r'[。.！!？?]', val):
                    continue
                if val.endswith('也是') or val.endswith('同时'):
                    continue
                # 值过长（超过20字的中文通常是句子）
                if len(val) > 20 and re.search(r'[\u4e00-\u9fff]', val):
                    continue
                # 看起来像 SQL 列名
                if '_' in val and not re.search(r'[\u4e00-\u9fff]', val):
                    if val in all_col_names:
                        continue

                table_columns[key].add(val)

    return table_columns


def merge_enums(tables: list, insert_enums: dict) -> list:
    """将 INSERT 中的枚举值合并到表结构中（仅 COMMENT 无枚举的字段）"""
    for table in tables:
        for col in table["columns"]:
            key = f"{table['table_name']}.{col['name']}"
            # COMMENT 已有枚举 => 不合并 DML
            if col.get("comment_has_enum", False):
                continue
            if key in insert_enums:
                insert_vals = sorted(insert_enums[key])
                existing_values = {e["value"] for e in col["enum_values"]}
                for val in insert_vals:
                    if val not in existing_values:
                        col["enum_values"].append({"value": val, "label": val})
    return tables


# ============ YAML 输出 ============

def tables_to_yaml(tables: list) -> str:
    """将表结构转为 YAML 格式"""
    lines = []
    lines.append(f"# 数据字典 - 自动生成")
    lines.append(f"# 生成时间: {__import__('datetime').datetime.now().strftime('%Y-%m-%d %H:%M')}")
    lines.append(f"# 表数量: {len(tables)}")
    lines.append(f"# 说明: 供大模型写 SQL 时参考表结构、字段类型、枚举值")
    lines.append(f"# 枚举策略: COMMENT 中已描述枚举的不重复列出; 超过10个枚举值的字段仅列出值列表")
    lines.append("")
    lines.append(f"table_count: {len(tables)}")
    lines.append("")

    # 按业务域分组
    domains = defaultdict(list)
    for table in tables:
        domain = guess_domain(table["table_name"])
        domains[domain].append(table)

    lines.append("domains:")
    for domain, domain_tables in sorted(domains.items()):
        lines.append(f"  {domain}:")
        lines.append(f"    tables: {len(domain_tables)}")
        lines.append(f"    names: [{', '.join(t['table_name'] for t in domain_tables)}]")
    lines.append("")

    # 每张表的详情
    lines.append("tables:")
    for table in tables:
        lines.append(f"  {table['table_name']}:")
        lines.append(f"    comment: \"{table['comment']}\"")
        if table["primary_key"]:
            lines.append(f"    primary_key: [{', '.join(table['primary_key'])}]")
        if table["foreign_keys"]:
            lines.append(f"    foreign_keys:")
            for fk in table["foreign_keys"]:
                lines.append(f"      - column: {fk['column']}")
                lines.append(f"        ref_table: {fk['ref_table']}")
                lines.append(f"        ref_column: {fk['ref_column']}")
        lines.append(f"    columns:")
        for col in table["columns"]:
            lines.append(f"      {col['name']}:")
            lines.append(f"        type: {col['type']}")
            if col["comment"]:
                lines.append(f"        comment: \"{col['comment']}\"")
            lines.append(f"        nullable: {str(col['nullable']).lower()}")
            if col["default"]:
                lines.append(f"        default: {col['default']}")
            if col["is_primary"]:
                lines.append(f"        primary_key: true")
            if col["auto_increment"]:
                lines.append(f"        auto_increment: true")
            # COMMENT 已描述枚举 => 不重复输出 enum_values（避免重复建设）
            if col["enum_values"] and not col.get("comment_has_enum", False):
                lines.append(f"        enum_values:")
                for ev in col["enum_values"]:
                    lines.append(f"          - value: \"{ev['value']}\"")
                    lines.append(f"            label: \"{ev['label']}\"")
        lines.append("")

    return "\n".join(lines)


def guess_domain(table_name: str) -> str:
    """根据表名推断业务域"""
    domain_map = {
        "user": "用户域", "enterprise": "企业域", "agent": "代理人域",
        "policy": "保单域", "claim": "理赔域", "premium": "保费域",
        "underwriting": "核保域", "price": "定价域", "product": "产品域",
        "campaign": "营销域", "coupon": "优惠券域", "points": "积分域",
        "service": "车服务域", "car_wash": "车服务域", "fuel": "车服务域",
        "charge": "车服务域", "maintenance": "车服务域", "rescue": "车服务域",
        "designated_driver": "车服务域", "move_car": "车服务域",
        "live": "直播域", "push": "触达域", "call": "触达域",
        "wechat": "触达域", "signin": "运营域",
        "merchant": "商家域", "mall": "商城域",
        "survey": "查勘域", "damage": "理赔域",
        "complaint": "客服域", "blacklist": "风控域",
        "compliance": "合规域", "audit": "审计域",
        "anti_fraud": "反欺诈域", "risk": "风控域",
        "agricultural": "农险域", "disaster": "灾害域",
        "blackspot": "道路安全域", "enterprise_health": "企业健康域",
        "session": "会话域", "data_": "系统域",
        "inbox": "消息域", "share": "社交域",
    }
    for prefix, domain in domain_map.items():
        if table_name.startswith(prefix):
            return domain
    return "其他"


# ============ Markdown 输出 ============

def tables_to_markdown(tables: list) -> str:
    """将表结构转为 Markdown 格式（人类可读）"""
    lines = []
    lines.append("# 数据字典 - 平安产险业务数据库")
    lines.append("")
    lines.append(f"生成时间：{__import__('datetime').datetime.now().strftime('%Y-%m-%d %H:%M')}")
    lines.append(f"表数量：{len(tables)}")
    lines.append("")

    # 统计
    total_cols = sum(len(t["columns"]) for t in tables)
    tables_with_enums = sum(1 for t in tables for c in t["columns"] if c["enum_values"])
    lines.append(f"| 指标 | 数量 |")
    lines.append(f"|------|------|")
    lines.append(f"| 总表数 | {len(tables)} |")
    lines.append(f"| 总字段数 | {total_cols} |")
    lines.append(f"| 含枚举的字段数 | {tables_with_enums} |")
    lines.append("")

    # 按域分组
    domains = defaultdict(list)
    for table in tables:
        domain = guess_domain(table["table_name"])
        domains[domain].append(table)

    lines.append("## 目录")
    lines.append("")
    for domain, domain_tables in sorted(domains.items()):
        lines.append(f"### {domain}（{len(domain_tables)} 张表）")
        for t in domain_tables:
            col_count = len(t["columns"])
            enum_count = sum(1 for c in t["columns"] if c["enum_values"])
            suffix = f" [enum:{enum_count}]" if enum_count else ""
            lines.append(f"- **{t['table_name']}**（{col_count} 字段{suffix}）: {t['comment']}")
        lines.append("")

    # 每张表详情
    lines.append("---")
    lines.append("## 表详情")
    lines.append("")

    for table in tables:
        lines.append(f"### {table['table_name']}")
        lines.append(f"**{table['comment']}**")
        lines.append("")

        lines.append("| 字段名 | 类型 | 可空 | 默认值 | 枚举值 | 说明 |")
        lines.append("|--------|------|------|--------|--------|------|")

        for col in table["columns"]:
            enum_str = ""
            if col["enum_values"]:
                enum_str = "<br>".join(f"`{e['value']}`={e['label']}" for e in col["enum_values"][:5])
                if len(col["enum_values"]) > 5:
                    enum_str += f"<br>...共{len(col['enum_values'])}个"

            nullable = "Y" if col["nullable"] else "N"
            default = col["default"] or ""
            lines.append(f"| {col['name']} | {col['type']} | {nullable} | {default} | {enum_str} | {col['comment']} |")

        if table["foreign_keys"]:
            lines.append("")
            lines.append("**外键关系**：")
            for fk in table["foreign_keys"]:
                lines.append(f"- `{fk['column']}` -> `{fk['ref_table']}.{fk['ref_column']}`")

        lines.append("")

    return "\n".join(lines)


# ============ 主函数 ============

def main():
    parser = argparse.ArgumentParser(description="从 SQL 文件生成数据字典")
    parser.add_argument("--ddl", default="create_table.sql", help="DDL 文件路径")
    parser.add_argument("--dml", default="pingan_insurance_data.sql", help="DML 文件路径")
    parser.add_argument("--output", "-o", default="data_dictionary.yaml", help="输出文件路径（.yaml 或 .md）")
    parser.add_argument("--format", "-f", choices=["yaml", "markdown", "both"], default="both")

    args = parser.parse_args()

    print(f"[1/4] 读取 DDL: {args.ddl}")
    if not os.path.exists(args.ddl):
        print(f"[ERROR] 文件不存在: {args.ddl}")
        sys.exit(1)
    with open(args.ddl, "r", encoding="utf-8") as f:
        ddl_content = f.read()

    print(f"[2/4] 解析 CREATE TABLE...")
    tables = extract_create_tables(ddl_content)
    print(f"  -> 找到 {len(tables)} 张表")

    # 提取 DML 中的枚举值（仅补充 COMMENT 未覆盖的字段）
    insert_enums = {}
    if args.dml and os.path.exists(args.dml):
        print(f"[3/4] 读取 DML: {args.dml}（提取枚举值）")
        with open(args.dml, "r", encoding="utf-8") as f:
            dml_content = f.read()
        insert_enums = extract_insert_enums(dml_content, tables)
        print(f"  -> 找到 {len(insert_enums)} 个字段需从 DML 补充枚举")
        tables = merge_enums(tables, insert_enums)
    else:
        print(f"[3/4] 跳过 DML（文件不存在: {args.dml}）")

    print(f"[4/4] 生成数据字典...")

    if args.format in ("yaml", "both"):
        yaml_path = args.output if args.output.endswith(".yaml") else "data_dictionary.yaml"
        yaml_content = tables_to_yaml(tables)
        with open(yaml_path, "w", encoding="utf-8") as f:
            f.write(yaml_content)
        print(f"  [OK] YAML: {yaml_path}")

    if args.format in ("markdown", "both"):
        md_path = args.output if args.output.endswith(".md") else "data_dictionary.md"
        md_content = tables_to_markdown(tables)
        with open(md_path, "w", encoding="utf-8") as f:
            f.write(md_content)
        print(f"  [OK] Markdown: {md_path}")

    # 打印统计
    total_cols = sum(len(t["columns"]) for t in tables)
    enum_cols = sum(1 for t in tables for c in t["columns"] if c["enum_values"])
    comment_enum_cols = sum(1 for t in tables for c in t["columns"] if c.get("comment_has_enum"))
    dml_enum_cols = enum_cols - comment_enum_cols
    print(f"\n[STATS] {len(tables)} tables, {total_cols} columns")
    print(f"  COMMENT 枚举: {comment_enum_cols} fields")
    print(f"  DML 补充枚举: {dml_enum_cols} fields")
    print(f"  Total enum fields: {enum_cols}")


if __name__ == "__main__":
    main()

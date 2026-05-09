#!/usr/bin/env python3
"""
SQL指纹计算器：将SQL文本中的字面值替换为占位符，然后计算MD5哈希。

用法：
    python sql_fingerprint.py --sql "SELECT * FROM t WHERE dt = '2026-04-26'"
"""

import argparse
import hashlib
import re


FINGERPRINT_TABLE_SUFFIX_LEN = 12


def parameterize_sql(sql: str) -> str:
    """将SQL中的字面值替换为占位符?"""
    # 标准化：去除多余空白
    sql = re.sub(r'\s+', ' ', sql.strip())

    # 替换字符串字面值 'xxx'
    sql = re.sub(r"'[^']*'", "?", sql)

    # 替换数字字面值（整数和浮点数）
    sql = re.sub(r'\b\d+\.?\d*\b', "?", sql)

    # 替换日期字面值 DATE 'xxx'
    sql = re.sub(r'\bDATE\s+\?', "DATE ?", sql, flags=re.IGNORECASE)

    # 替换TIMESTAMP字面值
    sql = re.sub(r'\bTIMESTAMP\s+\?', "TIMESTAMP ?", sql, flags=re.IGNORECASE)

    return sql


def compute_fingerprint(sql: str) -> str:
    """计算SQL指纹（MD5哈希）"""
    param_sql = parameterize_sql(sql)
    md5 = hashlib.md5(param_sql.encode('utf-8')).hexdigest()
    return md5


def main():
    parser = argparse.ArgumentParser(description="SQL指纹计算器")
    parser.add_argument("--sql", required=True, help="SQL语句")
    parser.add_argument("--verbose", "-v", action="store_true", help="显示参数化后的SQL")
    args = parser.parse_args()

    param_sql = parameterize_sql(args.sql)
    fingerprint = compute_fingerprint(args.sql)

    print(f"SQL指纹: {fingerprint}")
    if args.verbose:
        print(f"参数化SQL: {param_sql}")

    # 生成DWP临时表名
    table_name = f"adhoc_{fingerprint[:FINGERPRINT_TABLE_SUFFIX_LEN]}"
    print(f"DWP临时表: paimon.cx_dwp_safe.{table_name}")


if __name__ == "__main__":
    main()

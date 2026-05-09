"""
OpenClaw 配置加载器（支持环境变量替换）

用法:
    from config_loader import load_config
    cfg = load_config("config.yaml")   # 自动替换 ${VAR} 为环境变量值

config.yaml 中的写法:
    token: "${GITEE_TOKEN}"            # 从环境变量读取，避免明文存储

替换规则:
    ${VAR_NAME}     → os.environ["VAR_NAME"]
    ${VAR:-default} → os.environ.get("VAR_NAME", "default")  (可选默认值)
    未设置且无默认值 → 保留原字符串并打印 WARN
"""

import os
import re
import sys
from pathlib import Path


# 匹配 ${VAR} 或 ${VAR:-default}
_ENV_VAR_PATTERN = re.compile(r'\$\{([^}]+)\}')


def _substitute_env_vars(value: str) -> str:
    """递归替换字符串中的 ${VAR} 和 ${VAR:-default}"""

    def replacer(match):
        expr = match.group(1)
        if ':-' in expr:
            var_name, default = expr.split(':-', 1)
            val = os.environ.get(var_name.strip(), default)
        else:
            var_name = expr.strip()
            val = os.environ.get(var_name)

        if val is None:
            print(f"[WARN] 环境变量 ${var_name} 未设置 (在 config.yaml 中引用)")
            return match.group(0)  # 保留原始 ${VAR}
        return val

    return _ENV_VAR_PATTERN.sub(replacer, value)


def _deep_substitute(obj):
    """递归遍历所有字符串值，执行环境变量替换"""
    if isinstance(obj, str):
        return _substitute_env_vars(obj)
    elif isinstance(obj, dict):
        return {k: _deep_substitute(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [_deep_substitute(item) for item in obj]
    return obj


def load_config(config_path: str) -> dict:
    """
    加载 YAML 配置文件并替换环境变量。

    Args:
        config_path: 配置文件路径（绝对/相对路径均可）

    Returns:
        解析后的配置字典（${VAR} 已被替换为实际值）
    """
    import yaml

    p = Path(config_path)
    if not p.exists():
        # 尝试相对于本脚本所在目录查找
        here = Path(__file__).parent
        alt = here / config_path
        if alt.exists():
            p = alt
        else:
            print(f"[ERROR] 配置文件不存在: {config_path}")
            sys.exit(1)

    with open(p, "r", encoding="utf-8") as f:
        raw = yaml.safe_load(f) or {}

    result = _deep_substitute(raw)
    print(f"[INFO] 配置已加载: {p}")
    return result


def get_nested(dct: dict, key_path: str, default=None):
    """
    获取嵌套字典的值（用点号分隔路径）。

    示例:
        get_nested(cfg, "hadoop.clusters.prod.hdfs.namenode")
        # 等价于 cfg["hadoop"]["clusters"]["prod"]["hdfs"]["namenode"]
    """
    keys = key_path.split(".")
    current = dct
    for k in keys:
        if isinstance(current, dict) and k in current:
            current = current[k]
        else:
            return default
    return current


if __name__ == "__main__":
    # 测试：加载同目录下的 config.yaml 并打印敏感字段是否已替换
    test_cfg = load_config(os.path.join(os.path.dirname(__file__), "config.yaml"))
    
    # 只显示非敏感信息用于验证
    spark_ver = get_nested(test_cfg, "hadoop.clusters.prod.spark.version", "<未替换>")
    namenode = get_nested(test_cfg, "hadoop.clusters.prod.hdfs.namenode", "<未替换>")
    gitee_token = get_nested(test_cfg, "git.auth.token", "<未替换>")
    repo = get_nested(test_cfg, "git.remote.origin", "<未替换>")
    
    print("=" * 50)
    print("配置验证结果:")
    print(f"  SPARK_VERSION     = {spark_ver}")
    print(f"  HADOOP_NAMENODE   = {namenode}")
    print(f"  GITEE_REPO        = {repo}")
    print(f"  GITEE_TOKEN       = {gitee_token if gitee_token == '${GITEE_TOKEN}' else '*** 已替换 ('+gitee_token[:10]+'...)'}")
    print()
    print("提示:")
    print("  - 如果显示 '${...}' 原文，说明该环境变量未设置")
    print("  - 设置方法: PowerShell: $env:VAR='value'  |  Bash: export VAR=value")

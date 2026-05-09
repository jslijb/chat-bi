# 代码变更报告模板

version: 1.0.0
description: code-updater 输出的标准代码变更报告模板

---

## 报告基本信息

| 字段 | 说明 |
|------|------|
| 报告编号 | {类型}-{年份}-{序号}，如 CODE-CHG-2026-001 |
| 关联需求编号 | 变更对应的需求编号 |
| 报告状态 | 待测试 / 测试中 / 测试通过 / 已合并 / 已回滚 |
| 生成时间 | YYYY-MM-DD HH:mm |
| Git分支 | upgrade/{需求编号} |
| 负责人 | AI / 用户名 |

---

## 变更文件清单模板

### SQL文件变更

```markdown
## {表类型} 表变更

### {表名}

**文件路径**：`{路径}/{表名}.sql`

**变更前**：
```sql
-- 原有SQL内容
```

**变更后**：
```sql
-- 修改后的SQL内容
```

**影响范围**：
- 上游依赖：{表名列表}
- 下游依赖：{表名列表}
```

---

### Python ETL变更

```markdown
## ETL脚本变更

### {脚本名称}

**文件路径**：`{路径}/{脚本名称}.py`

**变更行号**：{start_line} - {end_line}

**变更前**：
```python
# 原有代码
```

**变更后**：
```python
# 修改后的代码
```

**影响范围**：
- 输出表：{表名}
- 调度任务：{任务名}
```

---

## 测试脚本模板

### Shell测试脚本

```bash
#!/bin/bash
# 测试脚本：test_upgrade_{需求编号}.sh
# 用途：验证 {需求编号} 变更的正确性

set -e

echo "========================================"
echo "开始执行代码变更测试"
echo "需求编号：{需求编号}"
echo "测试时间：$(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"

# 1. 检查环境
echo "[1/5] 检查测试环境..."
# 检查命令

# 2. 执行DDL变更（测试环境）
echo "[2/5] 执行DDL变更..."
# DDL执行命令

# 3. 运行ETL脚本
echo "[3/5] 运行ETL脚本..."
# ETL执行命令

# 4. 验证数据正确性
echo "[4/5] 验证数据正确性..."
# 验证SQL

# 5. 清理测试数据
echo "[5/5] 清理测试数据..."
# 清理命令

echo "========================================"
echo "测试完成！"
echo "========================================"
exit 0
```

### Python测试脚本

```python
#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
测试脚本：test_upgrade_{需求编号}.py
用途：验证 {需求编号} 变更的正确性
"""

import sys
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def test_ddl_changes():
    """测试DDL变更"""
    logger.info("测试DDL变更...")
    # 测试代码
    pass

def test_etl_execution():
    """测试ETL执行"""
    logger.info("测试ETL执行...")
    # 测试代码
    pass

def test_data_validation():
    """测试数据验证"""
    logger.info("测试数据验证...")
    # 测试代码
    pass

def main():
    try:
        test_ddl_changes()
        test_etl_execution()
        test_data_validation()
        logger.info("所有测试通过！")
        return 0
    except Exception as e:
        logger.error(f"测试失败: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())
```

---

## Git提交信息模板

```markdown
chore: upgrade requirement {需求编号} to {版本号}

## 变更内容
- 新增字段：{字段名列表}
- 修改口径：{口径变更说明}
- 删除字段：{字段名列表}
- 更新ETL脚本：{脚本数量} 份
- 新增测试脚本：{脚本数量} 份

## 影响范围
- 影响表：{表名列表}
- 影响ETL：{脚本名列表}
- 影响调度任务：{任务名列表}

## 测试验证
- 测试脚本：test_upgrade_{需求编号}.sh
- 测试覆盖：{覆盖的测试场景}

## 相关链接
- 需求文档：{链接}
- 变更分析报告：{链接}
```

---

## 回滚脚本模板

```bash
#!/bin/bash
# 回滚脚本：rollback_{需求编号}.sh
# 用途：回滚 {需求编号} 的所有代码变更

set -e

echo "========================================"
echo "开始回滚代码变更"
echo "需求编号：{需求编号}"
echo "回滚时间：$(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"

# 1. 切换到主分支
git checkout main

# 2. 回滚提交
git revert {commit_id}

# 3. 推送变更
git push origin main

echo "========================================"
echo "回滚完成！"
echo "========================================"
```

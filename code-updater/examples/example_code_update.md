# 代码变更示例集

version: 1.0.0
description: code-updater 变更示例，供学习和测试使用

---

## 示例一：新增字段变更

### 输入（变更影响报告摘要）

```markdown
# 需求变更分析报告：REQ-001 v1.0 → REQ-001 v2.0

## 变更摘要
- 新增字段：user_active_score (用户活跃度得分)
- 新增字段：first_policy_date (首保日期)

## 下游影响
- dwd_user_behavior 表需新增字段
- etl_user_features.sql 需新增计算逻辑
```

### 输出（代码变更报告）

```markdown
# 代码变更报告：REQ-001

## 1. 变更概述

| 变更类型 | 文件数 |
|----------|--------|
| DDL修改 | 1 |
| ETL修改 | 1 |
| 配置更新 | 1 |
| 新增文件 | 1 |

---

## 2. 详细变更清单

### 2.1 DDL修改

| 序号 | 表名 | 操作类型 | SQL摘要 |
|------|------|----------|---------|
| 1 | dwd_user_behavior | ALTER TABLE ADD | 新增 user_active_score, first_policy_date |

### 2.2 ETL修改

| 序号 | 脚本路径 | 变更类型 | 修改内容 |
|------|----------|----------|----------|
| 1 | etl/user_features.sql | 修改 | 新增活跃度得分计算，新增首保日期提取 |

### 2.3 新增文件

| 序号 | 文件路径 | 文件说明 |
|------|----------|----------|
| 1 | test/test_upgrade_REQ-001.sh | DDL和ETL验证脚本 |

---

## 3. 测试脚本

| 序号 | 脚本名称 | 测试内容 |
|------|----------|----------|
| 1 | test/test_upgrade_REQ-001.sh | DDL执行 + ETL验证 + 数据对比 |

---

## 4. Git提交信息

```
chore: upgrade requirement REQ-001 to v2

变更内容：
- 新增字段 user_active_score
- 新增字段 first_policy_date
- 更新 etl/user_features.sql

影响范围：
- dwd_user_behavior 表
```

---

## 生成的DDL

```sql
-- 文件：sql/dwd/dwd_user_behavior.sql
-- 变更：新增用户活跃度相关字段

ALTER TABLE dwd_user_behavior 
ADD COLUMN user_active_score INT COMMENT '用户活跃度得分，范围0-100'
ADD COLUMN first_policy_date STRING COMMENT '用户首保日期，格式YYYY-MM-DD';
```

---

## 生成的ETL变更

```sql
-- 文件：etl/user_features.sql
-- 变更位置：SELECT子句新增字段

SELECT
    user_id,
    -- 新增：用户活跃度得分
    CASE 
        WHEN active_days >= 30 THEN 100
        WHEN active_days >= 20 THEN 80
        WHEN active_days >= 10 THEN 60
        WHEN active_days >= 5 THEN 40
        ELSE 20
    END AS user_active_score,
    -- 新增：首保日期
    MIN(policy_date) OVER (PARTITION BY user_id) AS first_policy_date,
    -- 原有字段...
FROM dwd_user_behavior_base
```

---

## 生成的测试脚本

```bash
#!/bin/bash
# test_upgrade_REQ-001.sh

set -e

echo "开始测试 REQ-001 变更..."

# 1. 执行DDL
echo "[1/3] 执行DDL变更..."
# psql -f sql/dwd/dwd_user_behavior.sql

# 2. 运行ETL
echo "[2/3] 运行ETL脚本..."
# spark-sql -f etl/user_features.sql

# 3. 验证数据
echo "[3/3] 验证数据..."
# SELECT COUNT(*) FROM dwd_user_behavior WHERE user_active_score IS NOT NULL;

echo "测试完成！"
exit 0
```

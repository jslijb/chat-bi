# 调度更新示例集

version: 1.0.0
description: scheduler-updater 变更示例，供学习和测试使用

---

## 示例一：新增日级ETL调度

### 输入（代码变更摘要）

```markdown
# 代码变更报告：REQ-001

## 新增文件
- etl/user_features.py (用户特征计算)
- sql/dwd/dwd_user_features.sql (目标表)

## 变更说明
新增用户活跃度特征计算ETL，需要每日凌晨2点执行
```

### 输出（调度更新报告）

```markdown
# 调度更新报告：REQ-001

**调度系统**：OpenClaw

## 1. 调度变更概述

| 变更类型 | 任务数 |
|----------|--------|
| 新增任务 | 1 |

## 2. 详细变更清单

### 2.1 新增任务

| 序号 | 任务名称 | 执行周期 | 执行脚本 | 依赖任务 |
|------|----------|----------|----------|----------|
| 1 | bi_user_features_daily | 0 2 * * * | python /data/etl/user_features.py | ods_user_data_daily |

---

## 4. 执行命令

### OpenClaw

```bash
# 新增调度任务
openclaw cron add \
    --name "bi_user_features_daily" \
    --cron "0 2 * * *" \
    --message "python /data/etl/user_features.py" \
    --timeout 3600 \
    --retry 3
```

### 验证命令

```bash
# 查看任务列表
openclaw cron list | grep user_features

# 查看执行记录
openclaw cron runs --name bi_user_features_daily
```
```

---

## 示例二：更新任务周期并添加依赖

### 输入

```markdown
# 代码变更报告：REQ-002

## 修改内容
- etl/policy_daily.py 已优化，可提前到凌晨1点执行
- 新增 policy_base_daily 任务，需在 policy_daily 前执行
```

### 输出

```markdown
# 调度更新报告：REQ-002

## 2. 详细变更清单

### 2.2 更新任务

| 序号 | 任务名称 | 原配置 | 新配置 | 变更说明 |
|------|----------|--------|--------|----------|
| 1 | bi_policy_daily | 0 2 * * * | 0 1 * * * | 执行时间提前1小时 |

### 2.3 依赖关系更新

| 序号 | 上游任务 | 下游任务 | 变更类型 |
|------|----------|----------|----------|
| 1 | bi_policy_base_daily | bi_policy_daily | 新增依赖 |

---

## 3. 任务时间轴

```
[T+1 01:00] ─ [policy_base_daily] ─→ [policy_daily] ─→ [报表刷新]
                  ↑新增                    ↑
                                     (时间提前)
```

---

## 4. 执行命令

```bash
# 1. 新增基础任务
openclaw cron add \
    --name "bi_policy_base_daily" \
    --cron "0 1 * * *" \
    --message "python /data/etl/policy_base.py"

# 2. 更新主任务时间
openclaw cron update \
    --name "bi_policy_daily" \
    --cron "0 1 * * *"
```

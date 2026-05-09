---
name: scheduler-updater
description: 调度系统适配层，自动检测并适配OpenClaw cron/Airflow/DolphinScheduler，根据代码变更自动更新调度任务
version: 2.0.0
author: BI Team
trigger_keywords:
  - 更新调度
  - 配置调度任务
  - 修改cron
  - 新增调度
  - 删除调度
  - 调度变更
  - 任务依赖
  - 调度适配
upstream_skill: git-merger
downstream_skill: null
---

# 技能名称：scheduler-updater

## 技能描述
调度配置专家。当代码文件发生变更（新增ETL脚本、修改任务依赖等）时，自动更新对应的调度任务定义，确保新逻辑能够按时执行。

### 调度系统适配器（SchedulerAdapter）

采用适配器模式，自动检测当前环境可用的调度系统：

**检测优先级**：Airflow > DolphinScheduler > OpenClaw cron

| 调度系统 | 检测方式 | 配置目录 | 任务格式 | 部署阶段 |
|----------|---------|---------|---------|---------|
| Airflow | `which airflow` 或 `pip show airflow` | `$AIRFLOW_HOME/dags/` | Python DAG | Phase 3+ |
| DolphinScheduler | API探测 `http://{host}:12345/dolphinscheduler` | Web UI配置 | JSON工作流 | Phase 4+ |
| OpenClaw cron | `ls ~/.openclaw/cron/` | `~/.openclaw/cron/` | Shell cron | Phase 1-2（当前） |

**当前默认**：OpenClaw cron（服务器未部署调度软件）

**任务命名规范**：`{layer}_{table_name}_{type}`
- DWD层ETL：`dwd_policy_premium_daily_etl`
- DWS层ETL：`dws_policy_premium_daily_etl`
- ADS层ETL：`ads_channel_premium_report_etl`
- DIM层ETL：`dim_channel_etl`

**时间窗口设计**（按优先级）：

| 优先级 | 执行窗口 | 说明 |
|--------|---------|------|
| P0（核心领导） | 06:00-07:00 | 最早产出，领导晨会前可用 |
| P1（高频） | 07:00-09:00 | 上午工作开始前产出 |
| P2（常规） | 09:00-12:00 | 上午空闲时段 |
| P3（低频） | 12:00-14:00 | 午间低峰时段 |

## 触发条件
- 用户指令包含"更新调度"、"配置调度任务"、"修改cron"、"新增调度"、"删除调度"、"调度变更"、"任务依赖"等关键词
- 代码变更影响报告中包含调度任务相关条目
- 由 `code-updater` 输出确认后

> **跳过条件**：如果代码变更不涉及ETL脚本或调度配置，输出"无需调度更新"。

## 输入格式
- 代码变更摘要（可由 `code-updater` 输出）
- 调度配置目录（默认为 `~/.openclaw/cron/` 或用户指定的 airflow/dag 文件夹）
- 调度系统类型（自动识别或用户指定）

## 输出格式
严格按照以下模板输出：

```markdown
# 调度更新报告：{需求编号}

**报告状态**：待执行 → 执行中 → 已生效
**生成时间**：{YYYY-MM-DD HH:mm}
**调度系统**：{OpenClaw / Airflow / DolphinScheduler / 其他}

---

## 1. 调度变更概述

| 变更类型 | 任务数 | 说明 |
|----------|--------|------|
| 新增任务 | N | 新增ETL调度任务 |
| 更新任务 | N | 修改执行周期或脚本 |
| 删除任务 | N | 移除废弃任务 |
| 依赖更新 | N | 修改任务依赖关系 |

---

## 2. 详细变更清单

### 2.1 新增任务

| 序号 | 任务名称 | 执行周期 | 执行脚本 | 依赖任务 |
|------|----------|----------|----------|----------|
| 1 | | | | |

### 2.2 更新任务

| 序号 | 任务名称 | 原配置 | 新配置 | 变更说明 |
|------|----------|--------|--------|----------|
| 1 | | | | |

### 2.3 删除任务

| 序号 | 任务名称 | 删除原因 | 替代任务 |
|------|----------|----------|----------|
| 1 | | | |

### 2.4 依赖关系更新

| 序号 | 上游任务 | 下游任务 | 变更类型 |
|------|----------|----------|----------|
| 1 | | | |

---

## 3. 任务时间轴

```
{T+1 00:00} ─ [数据接入任务] ─→ [ETL任务A] ─→ [ETL任务B] ─→ [报表任务]
                        ↑                                    ↑
                    [新增]                               [新增]
```

---

## 4. 执行命令

### 4.1 OpenClaw 命令

```bash
# 新增任务
openclaw cron add --name {任务名} --cron "{cron表达式}" --message "{执行命令}"

# 更新任务
openclaw cron update --id {任务ID} --cron "{cron表达式}"

# 删除任务
openclaw cron remove --id {任务ID}
```

### 4.2 Airflow 命令

```bash
# 上传DAG文件
cp {dag文件} $AIRFLOW_HOME/dags/

# 重启scheduler
airflow scheduler -d
```

### 4.3 验证命令

```bash
# 查看任务执行记录
openclaw cron runs --id {任务ID}

# Airflow Web UI
http://{airflow_host}:8080
```

---

## 5. 异常监控

| 任务名称 | 监控指标 | 告警阈值 | 通知方式 |
|----------|----------|----------|----------|
| | 执行时长 > X分钟 | | |
| | 执行失败 | 连续X次 | 邮件/钉钉 |

---

## 业务确认

[ ] 已审核调度变更配置
[ ] 确认执行时间窗口
[ ] 确认告警通知配置

**确认签名**：__________________
**确认日期**：__________________
```

## 执行流程

### 第一步：识别需要更新的调度任务
- 解析代码变更摘要，找出受影响的任务名称（如 `daily_policy_etl`）
- 若新增了ETL脚本，推断建议的调度任务名（脚本名转换 + `_schedule`）

### 第二步：根据调度系统类型执行操作

**场景A：使用 OpenClaw 内置 cron**
- 读取现有 cron 任务列表：`openclaw cron list`
- 对于需更新的任务：`openclaw cron update --id <id> --message "新的执行指令" --cron "0 2 * * *"`
- 对于新增任务：`openclaw cron add --name <name> --cron "0 2 * * *" --message "python /path/to/etl_script.py"`
- 对于删除任务：`openclaw cron remove --id <id>`

**场景B：使用 Airflow**
- 定位到 DAG 定义文件（如 `dags/policy_etl_dag.py`）
- 修改 DAG 的 `schedule_interval` 或 `start_date`
- 若新增脚本，在 DAG 文件中添加新的 PythonOperator 或 BashOperator
- 保存文件，并提示用户重启 scheduler

**场景C：使用 DolphinScheduler / 其他**
- 生成对应的 API 调用脚本（curl 或 Python），由用户手动执行（因为需要认证权限）

### 第三步：更新依赖关系元数据
- 如果调度任务之间存在依赖（如任务B依赖任务A完成），自动修改依赖配置
- 在 `data_lineage.json` 中记录调度任务与表/脚本的关联关系

### 第四步：输出调度更新报告
- 列出所有修改/新增/删除的调度任务
- 提供验证命令（如 `openclaw cron runs --id <id>` 或 Airflow UI 地址）

## 与上下游 Skill 的衔接

| 角色 | Skill名称 | 触发条件 | 传递内容 |
|------|-----------|----------|----------|
| 上游 | `git-merger` | 代码合并完成后 | 合并报告 + 变更文件列表 |

**完整需求生命周期状态机**：
```
bi-requirement-parser (需求解析)
        ↓
requirement-diff-analyzer (变更分析)
        ↓
code-updater (代码生成 + 提交分支)
        ↓
sql-validator (Hadoop EXPLAIN 验证)
        ↓
git-merger (人工确认 → 合并到开发分支)
        ↓
scheduler-updater (调度更新)
        ↓
需求上线
```

## 异常处理
- 若调度系统类型无法自动识别，提示用户选择或手动配置
- 若需要权限的API调用，生成命令脚本但不自动执行，交由用户运行
- 若任务依赖存在循环引用，报错并拒绝执行
- **对话退出条件**：最多追问 **3 轮**，每轮最多 **5 个问题**

## 注意事项
- 调度时间窗口需避开业务高峰期
- 新任务上线需设置观察期（建议3天）
- 重要任务必须配置告警机制
- 任务命名规范：`{业务域}_{表名/功能}_{频率}`，如 `bi_policy_daily_etl`
- 禁止在生产环境直接修改调度配置，必须经过审核

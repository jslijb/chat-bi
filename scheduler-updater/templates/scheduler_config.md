# 调度配置模板

version: 1.0.0
description: scheduler-updater 输出的标准调度配置模板

---

## 报告基本信息

| 字段 | 说明 |
|------|------|
| 报告编号 | {类型}-{年份}-{序号}，如 SCH-2026-001 |
| 关联需求编号 | 变更对应的需求编号 |
| 报告状态 | 待执行 / 执行中 / 已生效 / 已回滚 |
| 生成时间 | YYYY-MM-DD HH:mm |
| 调度系统 | OpenClaw / Airflow / DolphinScheduler / 自研 |
| 负责人 | AI / 用户名 |

---

## OpenClaw 配置模板

### 新增任务

```bash
# 新增调度任务
openclaw cron add \
    --name "{任务名称}" \
    --cron "{cron表达式}" \
    --message "{执行命令}" \
    --timeout {超时时间(秒)} \
    --retry {重试次数}

# 示例
openclaw cron add \
    --name "bi_policy_daily_etl" \
    --cron "0 2 * * *" \
    --message "python /data/etl/policy_daily.py" \
    --timeout 3600 \
    --retry 3
```

### 更新任务

```bash
# 更新任务配置
openclaw cron update \
    --id {任务ID} \
    --name "{新任务名称}" \
    --cron "{新cron表达式}" \
    --message "{新执行命令}"

# 仅更新执行时间
openclaw cron update --id {任务ID} --cron "30 2 * * *"
```

### 删除任务

```bash
# 删除任务（软删除，保留记录）
openclaw cron remove --id {任务ID}

# 强制删除
openclaw cron remove --id {任务ID} --force
```

---

## Airflow DAG 配置模板

### DAG 文件模板

```python
# -*- coding: utf-8 -*-
"""
DAG: {DAG名称}
用途：{DAG用途描述}
调度周期：{频率}
"""

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator
from datetime import datetime, timedelta

default_args = {
    'owner': '{所有者}',
    'depends_on_past': {True/False},
    'start_date': datetime({年}, {月}, {日}),
    'email_on_failure': {True/False},
    'email_on_retry': {True/False},
    'retries': {重试次数},
    'retry_delay': timedelta(minutes={重试间隔}),
}

dag = DAG(
    dag_id='{DAG_ID}',
    default_args=default_args,
    schedule_interval='{cron表达式}',
    catchup={True/False},
    tags=['{标签1}', '{标签2}'],
)

# 任务定义
start_task = BashOperator(
    task_id='start',
    bash_command='echo "DAG started"',
    dag=dag,
)

# ETL任务
etl_task = PythonOperator(
    task_id='etl_{任务名}',
    python_callable={Python函数},
    dag=dag,
)

# 结束任务
end_task = BashOperator(
    task_id='end',
    bash_command='echo "DAG completed"',
    dag=dag,
)

# 任务依赖
start_task >> etl_task >> end_task
```

### 新增任务到现有DAG

```python
# 在现有DAG文件中添加

new_task = PythonOperator(
    task_id='{新任务ID}',
    python_callable={函数名},
    dag=dag,
)

# 设置依赖
existing_task >> new_task >> next_task
```

---

## DolphinScheduler API 配置模板

### 创建工作流

```bash
# 登录获取token
TOKEN=$(curl -X POST "http://{host}:12345/dolphinscheduler/login" \
    -H "Content-Type: application/json" \
    -d '{"userName":"{用户名}","userPassword":"{密码}"}' | jq -r '.data.token')

# 创建项目
curl -X POST "http://{host}:12345/dolphinscheduler/projects" \
    -H "token: $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"projectName":"{项目名}"}'
```

---

## Cron 表达式参考

| 频率 | 表达式 | 说明 |
|------|--------|------|
| 每日凌晨2点 | `0 2 * * *` | T+1数据处理 |
| 每小时 | `0 * * * *` | 实时数据处理 |
| 每日8点 | `0 8 * * *` | 早报数据 |
| 每周一9点 | `0 9 * * 1` | 周报数据 |
| 每月1号2点 | `0 2 1 * *` | 月报数据 |
| 每15分钟 | `*/15 * * * *` | 高频任务 |
| 每5分钟 | `*/5 * * * *` | 准实时任务 |

---

## 任务命名规范

```
{业务域}_{功能模块}_{频率}_{类型}

示例：
bi_policy_daily_etl          # BI-保单-日-ETL
bi_policy_hourly_etl         # BI-保单-小时-ETL
bi_user_weekly_report        # BI-用户-周-报表
bi_finance_monthly_agg       # BI-财务-月-聚合
```

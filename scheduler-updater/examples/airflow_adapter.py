#!/usr/bin/env python3
"""
Airflow调度系统适配器：生成Airflow DAG Python文件，定义SparkSubmitOperator和显式依赖链。

用法：
    python airflow_adapter.py --action generate-dag --tasks tasks.json --output-dir ./dags
"""

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


DAG_TEMPLATE = '''"""
Airflow DAG: {dag_id}
自动生成于: {generated_at}
需求来源: {requirement_id}
"""

from airflow import DAG
from airflow.providers.apache.spark.operators.spark_submit import SparkSubmitOperator
from airflow.operators.bash import BashOperator
from datetime import datetime, timedelta

default_args = {{
    'owner': 'bi-team',
    'depends_on_past': False,
    'email_on_failure': True,
    'email': ['bi-team@company.com'],
    'retries': {retries},
    'retry_delay': timedelta(minutes={retry_delay_min}),
}}

with DAG(
    dag_id='{dag_id}',
    default_args=default_args,
    description='{description}',
    schedule_interval='{schedule}',
    start_date=datetime(2026, 4, 1),
    catchup=False,
    tags=['bi', '{layer}'],
) as dag:

{task_definitions}

    # 显式依赖链
{dependency_chain}
'''


SPARK_SUBMIT_TEMPLATE = '''    {task_id} = SparkSubmitOperator(
        task_id='{task_id}',
        application='{sql_file}',
        conn_id='spark_default',
        conf={{
            'spark.sql.catalog.paimon': 'org.apache.paimon.spark.SparkCatalog',
            'spark.sql.catalog.paimon.warehouse': 'hdfs:///paimon_warehouse',
            'spark.sql.adaptive.enabled': 'true',
            'spark.sql.shuffle.partitions': '{shuffle_partitions}',
        }},
        executor_memory='{executor_memory}',
        executor_cores={executor_cores},
        num_executors={num_executors},
        queue='{queue}',
    )'''


LAYER_TO_CONFIG = {
    "DIM": {"executor_memory": "2g", "executor_cores": 1, "num_executors": 2, "shuffle_partitions": "20", "queue": "default"},
    "DWD": {"executor_memory": "4g", "executor_cores": 2, "num_executors": 4, "shuffle_partitions": "50", "queue": "default"},
    "DWS": {"executor_memory": "4g", "executor_cores": 2, "num_executors": 4, "shuffle_partitions": "50", "queue": "default"},
    "ADS": {"executor_memory": "2g", "executor_cores": 1, "num_executors": 2, "shuffle_partitions": "20", "queue": "default"},
}

PRIORITY_TO_RETRIES = {
    "P0": {"retries": 3, "retry_delay_min": 5},
    "P1": {"retries": 2, "retry_delay_min": 10},
    "P2": {"retries": 1, "retry_delay_min": 30},
    "P3": {"retries": 1, "retry_delay_min": 60},
}


def generate_dag(tasks: list, dag_id: str, description: str, schedule: str,
                 layer: str, priority: str = "P2", requirement_id: str = "") -> str:
    """生成Airflow DAG Python文件"""

    # 获取配置
    layer_config = LAYER_TO_CONFIG.get(layer, LAYER_TO_CONFIG["DWS"])
    retry_config = PRIORITY_TO_RETRIES.get(priority, PRIORITY_TO_RETRIES["P2"])

    # 生成任务定义
    task_defs = []
    task_ids = []

    for task in tasks:
        task_id = task["task_id"]
        task_ids.append(task_id)

        task_def = SPARK_SUBMIT_TEMPLATE.format(
            task_id=task_id,
            sql_file=task.get("sql_file", ""),
            **layer_config
        )
        task_defs.append(task_def)

    # 生成依赖链
    if len(task_ids) > 1:
        dep_chain = "    " + " >> ".join(task_ids)
    else:
        dep_chain = f"    # 单任务: {task_ids[0] if task_ids else 'none'}"

    return DAG_TEMPLATE.format(
        dag_id=dag_id,
        generated_at=datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        requirement_id=requirement_id,
        description=description,
        schedule=schedule,
        layer=layer,
        retries=retry_config["retries"],
        retry_delay_min=retry_config["retry_delay_min"],
        task_definitions="\n\n".join(task_defs),
        dependency_chain=dep_chain
    )


def main():
    parser = argparse.ArgumentParser(description="Airflow调度系统适配器")
    parser.add_argument("--action", required=True, choices=["generate-dag"])
    parser.add_argument("--tasks", required=True, help="任务定义JSON文件")
    parser.add_argument("--dag-id", required=True, help="DAG ID")
    parser.add_argument("--description", default="", help="DAG描述")
    parser.add_argument("--schedule", default="0 2 * * *", help="cron表达式")
    parser.add_argument("--layer", default="DWS", help="数仓分层")
    parser.add_argument("--priority", default="P2", help="优先级")
    parser.add_argument("--requirement-id", default="", help="需求编号")
    parser.add_argument("--output-dir", default="./dags", help="输出目录")
    args = parser.parse_args()

    # 读取任务定义
    with open(args.tasks, "r", encoding="utf-8") as f:
        tasks = json.load(f)

    # 生成DAG
    dag_content = generate_dag(
        tasks=tasks,
        dag_id=args.dag_id,
        description=args.description,
        schedule=args.schedule,
        layer=args.layer,
        priority=args.priority,
        requirement_id=args.requirement_id
    )

    # 输出
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    output_file = output_dir / f"{args.dag_id}.py"

    with open(output_file, "w", encoding="utf-8") as f:
        f.write(dag_content)

    print(f"DAG已生成: {output_file}")
    print(f"  DAG ID: {args.dag_id}")
    print(f"  任务数: {len(tasks)}")
    print(f"  分层: {args.layer}")
    print(f"  优先级: {args.priority}")
    print(f"  调度: {args.schedule}")


if __name__ == "__main__":
    main()

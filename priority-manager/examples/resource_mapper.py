#!/usr/bin/env python3
"""
报表优先级与集群资源映射：P0-P3 → YARN队列/Spark资源/重试策略。

用法：
    python resource_mapper.py --priority P0 [--format spark-submit|yarn|json]
"""

import argparse
import json


# 优先级→YARN队列映射
PRIORITY_TO_YARN_QUEUE = {
    "P0": "production_high",
    "P1": "production",
    "P2": "default",
    "P3": "low_priority",
}

# 优先级→Spark资源映射
PRIORITY_TO_SPARK_RESOURCE = {
    "P0": {
        "executor_memory": "8g",
        "executor_cores": 4,
        "num_executors": 8,
        "shuffle_partitions": 200,
        "driver_memory": "4g",
        "dynamic_allocation": False,
    },
    "P1": {
        "executor_memory": "6g",
        "executor_cores": 3,
        "num_executors": 6,
        "shuffle_partitions": 100,
        "driver_memory": "3g",
        "dynamic_allocation": False,
    },
    "P2": {
        "executor_memory": "4g",
        "executor_cores": 2,
        "num_executors": 4,
        "shuffle_partitions": 50,
        "driver_memory": "2g",
        "dynamic_allocation": True,
    },
    "P3": {
        "executor_memory": "2g",
        "executor_cores": 1,
        "num_executors": 2,
        "shuffle_partitions": 20,
        "driver_memory": "1g",
        "dynamic_allocation": True,
    },
}

# 优先级→重试策略映射
PRIORITY_TO_RETRY = {
    "P0": {"max_retries": 3, "retry_delay_minutes": 5, "alert_on_failure": True},
    "P1": {"max_retries": 2, "retry_delay_minutes": 10, "alert_on_failure": True},
    "P2": {"max_retries": 1, "retry_delay_minutes": 30, "alert_on_failure": False},
    "P3": {"max_retries": 1, "retry_delay_minutes": 60, "alert_on_failure": False},
}


DYNAMIC_ALLOCATION_MAX_MULTIPLIER = 2


def get_resource_mapping(priority: str) -> dict:
    """获取优先级对应的完整资源映射"""
    if priority not in PRIORITY_TO_YARN_QUEUE:
        raise ValueError(f"无效优先级: {priority}，必须是P0/P1/P2/P3")

    return {
        "priority": priority,
        "yarn_queue": PRIORITY_TO_YARN_QUEUE[priority],
        "spark": PRIORITY_TO_SPARK_RESOURCE[priority],
        "retry": PRIORITY_TO_RETRY[priority],
    }


def format_spark_submit(mapping: dict) -> str:
    """生成spark-submit参数"""
    spark = mapping["spark"]
    args = [
        f"--queue {mapping['yarn_queue']}",
        f"--executor-memory {spark['executor_memory']}",
        f"--executor-cores {spark['executor_cores']}",
        f"--num-executors {spark['num_executors']}",
        f"--driver-memory {spark['driver_memory']}",
        f"--conf spark.sql.shuffle.partitions={spark['shuffle_partitions']}",
    ]
    if spark["dynamic_allocation"]:
        args.append("--conf spark.dynamicAllocation.enabled=true")
        args.append("--conf spark.dynamicAllocation.minExecutors=1")
        args.append(f"--conf spark.dynamicAllocation.maxExecutors={spark['num_executors'] * DYNAMIC_ALLOCATION_MAX_MULTIPLIER}")
    return " ".join(args)


def main():
    parser = argparse.ArgumentParser(description="报表优先级与集群资源映射")
    parser.add_argument("--priority", required=True, choices=["P0", "P1", "P2", "P3"])
    parser.add_argument("--format", default="json", choices=["spark-submit", "yarn", "json"])
    args = parser.parse_args()

    mapping = get_resource_mapping(args.priority)

    if args.format == "json":
        print(json.dumps(mapping, ensure_ascii=False, indent=2))
    elif args.format == "spark-submit":
        print(format_spark_submit(mapping))
    elif args.format == "yarn":
        print(f"YARN队列: {mapping['yarn_queue']}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
DolphinScheduler适配器：通过API创建/更新任务，生成API调用脚本。

DolphinScheduler API文档：https://dolphinscheduler.apache.org/en-us/docs/3.2.2/api

用法：
    python dolphinscheduler_adapter.py --action create-workflow|update-workflow|detect [options]
"""

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


# DolphinScheduler API端点
DS_API_ENDPOINTS = {
    "login": "/dolphinscheduler/login",
    "create_process_definition": "/dolphinscheduler/projects/{projectCode}/process/save",
    "update_process_definition": "/dolphinscheduler/projects/{projectCode}/process/update",
    "schedule_process_definition": "/dolphinscheduler/projects/{projectCode}/schedule/create",
    "online_process_definition": "/dolphinscheduler/projects/{projectCode}/process/release",
}


class DolphinSchedulerAdapter:
    """DolphinScheduler适配器"""

    def __init__(self, host: str, port: int = 12345, token: str = ""):
        self.host = host
        self.port = port
        self.token = token
        self.base_url = f"http://{host}:{port}"

    def detect(self) -> dict:
        """检测DolphinScheduler是否可用"""
        import urllib.request
        import urllib.error

        try:
            url = f"{self.base_url}/dolphinscheduler"
            req = urllib.request.Request(url, method="GET")
            with urllib.request.urlopen(req, timeout=5) as resp:
                return {"available": True, "host": self.host, "port": self.port}
        except (urllib.error.URLError, ConnectionError, TimeoutError):
            return {"available": False, "host": self.host, "port": self.port}

    def generate_api_script(self, workflow_name: str, tasks: list,
                            project_code: str = "bi_project") -> str:
        """生成DolphinScheduler API调用脚本（curl命令）"""
        lines = [
            "#!/bin/bash",
            f"# DolphinScheduler API调用脚本",
            f"# 工作流: {workflow_name}",
            f"# 生成时间: {datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}",
            "",
            f"DS_HOST=\"{self.host}\"",
            f"DS_PORT=\"{self.port}\"",
            f"DS_TOKEN=\"${{DS_TOKEN:-{self.token}}}\"",
            f"PROJECT_CODE=\"{project_code}\"",
            "",
            "# 1. 登录获取Token",
            "LOGIN_RESP=$(curl -s -X POST \"http://${DS_HOST}:${DS_PORT}/dolphinscheduler/login\" \\",
            "  -H 'Content-Type: application/x-www-form-urlencoded' \\",
            "  -d \"userName=${DS_USER:-admin}&userPassword=${DS_PASSWORD:-}\")",
            "TOKEN=$(echo $LOGIN_RESP | python3 -c \"import sys,json; print(json.load(sys.stdin)['data']['token'])\")",
            "",
            f"# 2. 创建工作流: {workflow_name}",
        ]

        # 生成任务定义JSON
        task_defs = []
        for i, task in enumerate(tasks):
            task_defs.append({
                "taskCode": f"task_{i+1}",
                "name": task["task_id"],
                "taskType": "SHELL",
                "taskParams": {
                    "rawScript": f"spark-sql -f {task.get('sql_file', '')}"
                },
                "flag": "YES",
                "taskPriority": "MEDIUM",
                "workerGroup": "default",
                "preTasks": [tasks[i-1]["task_id"]] if i > 0 else []
            })

        task_json = json.dumps(task_defs, ensure_ascii=False)

        lines.extend([
            "TASK_JSON=$(cat <<'TASKJSONEOF'",
            task_json,
            "TASKJSONEOF",
            ")",
            "",
            "curl -s -X POST \"http://${DS_HOST}:${DS_PORT}/dolphinscheduler/projects/${PROJECT_CODE}/process/save\" \\",
            "  -H 'Content-Type: application/json' \\",
            "  -H \"token: ${TOKEN}\" \\",
            f"  -d \"{{\\\"name\\\": \\\"{workflow_name}\\\", \\\"taskDefinitionJson\\\": $TASK_JSON}}\"",
            "",
            "echo '工作流创建完成'",
        ])

        return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="DolphinScheduler适配器")
    parser.add_argument("--host", default="localhost", help="DolphinScheduler主机")
    parser.add_argument("--port", type=int, default=12345, help="DolphinScheduler端口")
    parser.add_argument("--token", default="", help="API Token")
    parser.add_argument("--action", required=True, choices=["detect", "generate-script"])
    parser.add_argument("--workflow-name", default="bi_workflow", help="工作流名称")
    parser.add_argument("--tasks", help="任务定义JSON文件")
    parser.add_argument("--output", help="输出脚本文件路径")
    args = parser.parse_args()

    adapter = DolphinSchedulerAdapter(args.host, args.port, args.token)

    if args.action == "detect":
        result = adapter.detect()
        print(f"DolphinScheduler: {'可用' if result['available'] else '不可用'}")
        print(f"  地址: {result['host']}:{result['port']}")

    elif args.action == "generate-script":
        if not args.tasks:
            print("错误: 需要指定--tasks")
            sys.exit(1)

        with open(args.tasks, "r", encoding="utf-8") as f:
            tasks = json.load(f)

        script = adapter.generate_api_script(args.workflow_name, tasks)

        if args.output:
            with open(args.output, "w", encoding="utf-8") as f:
                f.write(script)
            print(f"API脚本已生成: {args.output}")
        else:
            print(script)


if __name__ == "__main__":
    main()

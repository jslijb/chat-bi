#!/usr/bin/env python3
"""
临时取数高频提升评分引擎：8条评分规则(R-SQL-01~04, R-TBL-01~02, R-ACT-01~02)，
阈值动作(0-14:monitor, 15-29:hint, 30-49:recommend, >=50:auto_generate)。

用法：
    python adhoc_scorer.py --action score|snapshot|threshold [options]
"""

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


# 8条评分规则定义
SCORING_RULES = [
    {
        "rule_id": "R-SQL-01", "name": "月查询频次", "score": 10,
        "condition": "同一SQL指纹月查询>=10次",
        "exclude_when": None  # 无排除
    },
    {
        "rule_id": "R-SQL-02", "name": "多用户查询", "score": 8,
        "condition": "同一SQL指纹被>=3个用户查询",
        "exclude_when": None
    },
    {
        "rule_id": "R-SQL-03", "name": "关键用户查询", "score": 12,
        "condition": "P0/P1用户查询",
        "exclude_when": None
    },
    {
        "rule_id": "R-SQL-04", "name": "季度查询频次", "score": 5,
        "condition": "同一SQL指纹季度查询>=3次/月",
        "exclude_when": "R-SQL-01"  # R-SQL-01已匹配时排除
    },
    {
        "rule_id": "R-TBL-01", "name": "核心表访问", "score": 10,
        "condition": "涉及P0/P1优先级表",
        "exclude_when": None
    },
    {
        "rule_id": "R-TBL-02", "name": "多表关联", "score": 5,
        "condition": "涉及>=3张表JOIN",
        "exclude_when": None
    },
    {
        "rule_id": "R-ACT-01", "name": "结果导出", "score": 8,
        "condition": "查询结果被导出>=5次/月",
        "exclude_when": None
    },
    {
        "rule_id": "R-ACT-02", "name": "结果分享", "score": 6,
        "condition": "查询结果被分享>=3次/月",
        "exclude_when": None
    },
]

# 阈值动作
THRESHOLD_ACTIONS = [
    {"min_score": 0, "max_score": 14, "action": "monitor", "description": "仅监控，不干预"},
    {"min_score": 15, "max_score": 29, "action": "hint", "description": "提示用户可转为正式报表"},
    {"min_score": 30, "max_score": 49, "action": "recommend", "description": "推荐转为正式报表，生成需求建议"},
    {"min_score": 50, "max_score": 999, "action": "auto_generate", "description": "自动生成需求，进入bi-requirement-parser流水线"},
]


class AdhocScorer:
    """临时取数高频提升评分器"""

    def __init__(self, log_file: str):
        self.log_file = Path(log_file)
        self.query_log = self._load_log()

    def _load_log(self) -> dict:
        if self.log_file.exists():
            with open(self.log_file, "r", encoding="utf-8") as f:
                return json.load(f)
        return {"queries": {}, "scores": {}}

    def _save_log(self):
        with open(self.log_file, "w", encoding="utf-8") as f:
            json.dump(self.query_log, f, ensure_ascii=False, indent=2)

    def score(self, fingerprint: str) -> dict:
        """计算SQL指纹的累计评分"""
        query = self.query_log["queries"].get(fingerprint, {})
        matched_rules = []
        total_score = 0
        excluded_rules = set()

        # 按顺序评估规则
        for rule in SCORING_RULES:
            # 检查排除条件
            if rule["exclude_when"] and rule["exclude_when"] in [r["rule_id"] for r in matched_rules]:
                excluded_rules.add(rule["rule_id"])
                continue

            # 评估条件（简化：基于查询日志中的统计）
            is_matched = self._evaluate_rule(rule, fingerprint, query)

            if is_matched:
                matched_rules.append({
                    "rule_id": rule["rule_id"],
                    "name": rule["name"],
                    "score": rule["score"],
                    "condition": rule["condition"]
                })
                total_score += rule["score"]

        # 确定阈值动作
        action = "monitor"
        action_desc = "仅监控，不干预"
        for threshold in THRESHOLD_ACTIONS:
            if threshold["min_score"] <= total_score <= threshold["max_score"]:
                action = threshold["action"]
                action_desc = threshold["description"]
                break

        result = {
            "fingerprint": fingerprint,
            "total_score": total_score,
            "matched_rules": matched_rules,
            "excluded_rules": list(excluded_rules),
            "action": action,
            "action_description": action_desc,
            "scored_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        }

        # 保存评分快照
        self.query_log["scores"][fingerprint] = result
        self._save_log()

        return result

    def _evaluate_rule(self, rule: dict, fingerprint: str, query: dict) -> bool:
        """评估单条规则是否匹配（简化实现）"""
        rule_id = rule["rule_id"]

        if rule_id == "R-SQL-01":
            return query.get("monthly_count", 0) >= 10
        elif rule_id == "R-SQL-02":
            return query.get("user_count", 0) >= 3
        elif rule_id == "R-SQL-03":
            return query.get("key_user_access", False)
        elif rule_id == "R-SQL-04":
            return query.get("quarterly_monthly_avg", 0) >= 3
        elif rule_id == "R-TBL-01":
            return query.get("involves_core_table", False)
        elif rule_id == "R-TBL-02":
            return query.get("join_table_count", 0) >= 3
        elif rule_id == "R-ACT-01":
            return query.get("export_count_monthly", 0) >= 5
        elif rule_id == "R-ACT-02":
            return query.get("share_count_monthly", 0) >= 3

        return False

    def get_threshold_action(self, score: int) -> dict:
        """根据评分获取阈值动作"""
        for threshold in THRESHOLD_ACTIONS:
            if threshold["min_score"] <= score <= threshold["max_score"]:
                return threshold
        return THRESHOLD_ACTIONS[-1]


def main():
    parser = argparse.ArgumentParser(description="临时取数高频提升评分引擎")
    parser.add_argument("--log", default="adhoc_query_log.json", help="查询日志文件路径")
    parser.add_argument("--action", required=True, choices=["score", "threshold"])
    parser.add_argument("--fingerprint", help="SQL指纹")
    parser.add_argument("--score-value", type=int, help="评分值（用于threshold动作）")
    args = parser.parse_args()

    scorer = AdhocScorer(args.log)

    if args.action == "score":
        if not args.fingerprint:
            print("错误: 需要指定--fingerprint")
            sys.exit(1)
        result = scorer.score(args.fingerprint)
        print(f"SQL指纹: {result['fingerprint']}")
        print(f"累计评分: {result['total_score']}")
        print(f"匹配规则: {len(result['matched_rules'])}条")
        for r in result["matched_rules"]:
            print(f"  {r['rule_id']} {r['name']}: +{r['score']} ({r['condition']})")
        if result["excluded_rules"]:
            print(f"排除规则: {result['excluded_rules']}")
        print(f"阈值动作: {result['action']} - {result['action_description']}")

    elif args.action == "threshold":
        score_val = args.score_value if args.score_value is not None else 0
        threshold = scorer.get_threshold_action(score_val)
        print(f"评分={score_val} → 动作: {threshold['action']} ({threshold['description']})")


if __name__ == "__main__":
    main()

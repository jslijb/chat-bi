---
name: async-task-scheduler
description: 异步任务调度器，管理集群空闲时执行的辅助任务（索引重建、血缘推断、评分计算、优先级调整、DWP清理、一致性校验），支持手动维护
version: 1.0.0
author: BI Team
trigger_keywords:
  - 异步任务
  - 集群空闲
  - 手动触发
  - 任务队列
  - bi-task
upstream_skill: null
downstream_skill: null
---

# 异步任务调度器

## 技能描述
管理集群空闲时执行的辅助任务队列，核心链路（SQL生成→验证→执行→报表）同步执行，辅助工作异步执行。

## 设计原则
**"先保存状态（同步），后处理逻辑（异步）"**

- 核心链路：同步执行，不等待集群空闲
- 辅助工作：异步执行，仅在集群空闲时触发
- 状态暂存：所有异步任务先写入状态表（同步），再由消费者异步处理

## 6级异步任务队列

| 优先级 | 任务类型 | 说明 | 触发时机 |
|--------|---------|------|---------|
| 1 | index_rebuild | RAG索引重建 | 字典变更后 |
| 2 | lineage_infer | 血缘关系推断 | 新ETL上线后 |
| 3 | score_calc | 高频提升评分计算 | 每日凌晨 |
| 4 | priority_adjust | 报表优先级升降级 | 每日凌晨 |
| 5 | dwp_cleanup | DWP临时表TTL清理 | 集群空闲时 |
| 6 | consistency_check | 数据一致性校验 | 每日凌晨 |

## 集群空闲判定

满足以下任一条件即视为空闲：
- YARN可用资源 > 60%
- 无P0/P1任务在执行
- 凌晨2:00-6:00（低峰时段）

## 手动维护功能

初期上线时自动触发可能不稳定，提供手动维护能力：

| 命令 | 说明 |
|------|------|
| `bi-task trigger <type>` | 手动触发任务（不等待集群空闲） |
| `bi-task pause <type>` | 暂停某类任务自动触发 |
| `bi-task resume <type>` | 恢复某类任务自动触发 |
| `bi-task mode auto/manual` | 全局切换自动/手动模式 |
| `bi-task status` | 查看所有任务状态 |
| `bi-task retry <task_id>` | 重试失败任务 |
| `bi-task cancel <task_id>` | 取消待执行任务 |

## 状态暂存表

```sql
-- 异步任务状态表
CREATE TABLE IF NOT EXISTS async_task_state (
    task_id       STRING  COMMENT '任务ID',
    task_type     STRING  COMMENT '任务类型(index_rebuild/lineage_infer/...)',
    status        STRING  COMMENT '状态(pending/running/completed/failed/cancelled)',
    priority      INT     COMMENT '优先级(1-6)',
    payload       STRING  COMMENT '任务参数(JSON)',
    created_at    TIMESTAMP COMMENT '创建时间',
    started_at    TIMESTAMP COMMENT '开始时间',
    completed_at  TIMESTAMP COMMENT '完成时间',
    error_msg     STRING  COMMENT '错误信息',
    retry_count   INT     COMMENT '重试次数',
    trigger_mode  STRING  COMMENT '触发方式(auto/manual)',
    PRIMARY KEY (task_id) NOT ENFORCED
);
```

## 目录结构
```
async-task-scheduler/
├── SKILL.md
└── examples/
    └── async_task_manager.py
```

---
name: dict-sync
description: 数据字典同步引擎，DDL执行成功后自动同步更新data_dictionary.yaml、data_lineage.json和RAG索引
version: 1.0.0
author: BI Team
trigger_keywords:
  - 同步字典
  - 更新字典
  - 字段变更
  - 字典同步
  - 重建索引
upstream_skill: cluster-tester
downstream_skill: null
---

# 数据字典同步引擎

## 技能描述
DDL执行成功后，自动同步更新数据字典、血缘关系和RAG索引，确保元数据与实际表结构一致。

## 同步流程

```
DDL执行成功
    │
    ├── 1. 解析DDL语句，提取表结构变更
    │
    ├── 2. 字段变更分类
    │   ├── 语义级变更（类型改变、字段删除）→ 标记ETL需检查 + 写入index_rebuild_queue
    │   ├── 格式级变更（注释修改、精度调整）→ 仅更新字典
    │   └── 扩展级变更（新增字段、新增分区）→ 标记CASE WHEN可能需更新 + 写入index_rebuild_queue
    │
    ├── 3. 更新 data_dictionary.yaml
    │   └── 新增/修改/删除表定义
    │
    ├── 4. 更新 data_lineage.json
    │   └── 新增/修改血缘记录（upstream/downstream）
    │
    └── 5. 写入 index_rebuild_queue
        └── 异步触发RAG索引重建（集群空闲时）
```

## 字段变更分类算法

| 变更类型 | 判定条件 | 动作 | 影响范围 |
|---------|---------|------|---------|
| 语义级 | 字段类型改变、字段删除、字段重命名 | 标记ETL需检查 + 写入index_rebuild_queue | 高：下游ETL可能报错 |
| 格式级 | COMMENT修改、DECIMAL精度调整、字段顺序调整 | 仅更新字典 | 低：不影响ETL逻辑 |
| 扩展级 | 新增字段、新增分区字段、新增TBLPROPERTIES | 标记CASE WHEN可能需更新 + 写入index_rebuild_queue | 中：下游SELECT *会受影响 |

## 触发条件
- cluster-tester报告DDL执行成功
- 用户手动触发"同步字典"
- 定时巡检发现字典与实际表结构不一致

## 目录结构
```
dict-sync/
├── SKILL.md
└── examples/
    └── dict_sync.py
```

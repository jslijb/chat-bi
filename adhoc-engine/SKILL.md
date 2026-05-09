---
name: adhoc-engine
description: 临时取数引擎，支持SQL指纹去重、结果缓存、DWP临时表TTL管理、高频提升评分
version: 1.0.0
author: BI Team
trigger_keywords:
  - 临时取数
  - 即席查询
  - adhoc
  - 取数
  - 临时表
upstream_skill: sql-code-generator
downstream_skill: cluster-tester
---

# 临时取数引擎

## 技能描述
处理临时取数/即席查询请求，核心能力：
1. **SQL指纹去重**：相同查询模式（参数化后MD5）复用缓存结果
2. **结果缓存**：DWP层临时表缓存查询结果，支持TTL过期
3. **DWP临时表TTL管理**：cache=0(不持久化), pattern=7d, saved=30d, transition=90d
4. **高频提升评分**：8条规则(R-SQL-01~04, R-TBL-01~02, R-ACT-01~02)自动评分

## SQL指纹（Fingerprint）

将SQL文本中的字面值替换为占位符，然后计算MD5哈希，用于识别相同查询模式：

```
原始SQL: SELECT * FROM t WHERE dt = '2026-04-26' AND channel = 'online'
指纹SQL: SELECT * FROM t WHERE dt = ? AND channel = ?
MD5指纹: a3f8c2b1e4d7...
```

**去重逻辑**：
- 相同指纹的查询，若缓存未过期，直接返回缓存结果
- 不同参数值的查询，共享执行计划但重新执行

## DWP临时表TTL策略

| 临时表类型 | TTL | 说明 | 清理时机 |
|-----------|-----|------|---------|
| cache | 0 | 不持久化，查询完即删 | 查询结束 |
| pattern | 7天 | 常用查询模式缓存 | 集群空闲时 |
| saved | 30天 | 用户主动保存的临时表 | 集群空闲时 |
| transition | 90天 | 过渡期临时表（待转正式） | 集群空闲时 |

## 高频提升评分规则

8条非重叠规则，累计评分决定动作：

| 规则ID | 规则名称 | 条件 | 分值 | 排除逻辑 |
|--------|---------|------|------|---------|
| R-SQL-01 | 月查询频次 | 同一SQL指纹月查询>=10次 | +10 | - |
| R-SQL-02 | 多用户查询 | 同一SQL指纹被>=3个用户查询 | +8 | - |
| R-SQL-03 | 关键用户查询 | P0/P1用户查询 | +12 | - |
| R-SQL-04 | 季度查询频次 | 同一SQL指纹季度查询>=3次/月 | +5 | R-SQL-01已匹配时排除 |
| R-TBL-01 | 核心表访问 | 涉及P0/P1优先级表 | +10 | - |
| R-TBL-02 | 多表关联 | 涉及>=3张表JOIN | +5 | - |
| R-ACT-01 | 结果导出 | 查询结果被导出>=5次/月 | +8 | - |
| R-ACT-02 | 结果分享 | 查询结果被分享>=3次/月 | +6 | - |

**评分阈值动作**：

| 累计分值 | 动作 | 说明 |
|---------|------|------|
| 0-14 | monitor | 仅监控，不干预 |
| 15-29 | hint | 提示用户可转为正式报表 |
| 30-49 | recommend | 推荐转为正式报表，生成需求建议 |
| >=50 | auto_generate | 自动生成需求，进入bi-requirement-parser流水线 |

## 工作流程

### Step 1: SQL指纹计算
- 参数化SQL文本（替换字面值为?）
- 计算MD5哈希
- 查询缓存：若指纹命中且未过期，返回缓存结果

### Step 2: 执行查询
- 在DWP层创建临时表（`paimon.cx_dwp_safe.adhoc_{fingerprint_prefix}`）
- 提交到cluster-tester执行
- 结果写入临时表

### Step 3: 结果缓存
- 根据TTL策略设置临时表过期时间
- 记录查询日志（用户、时间、指纹、耗时）

### Step 4: 高频评分
- 异步执行8条评分规则
- 累计分值达到阈值时触发对应动作

### Step 5: TTL清理（集群空闲时异步执行）
- 扫描DWP层临时表
- 按TTL策略清理过期表
- 释放存储空间

## 目录结构
```
adhoc-engine/
├── SKILL.md
└── examples/
    ├── sql_fingerprint.py
    ├── adhoc_scorer.py
    ├── dwp_cleanup.py
    └── report_storage_router.py
```

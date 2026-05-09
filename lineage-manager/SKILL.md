---
name: lineage-manager
description: 血缘元数据管理引擎，提供血缘查询、三级影响传播分析、反向追踪、血缘图可视化
version: 1.0.0
author: BI Team
trigger_keywords:
  - 血缘查询
  - 影响分析
  - 下游影响
  - 上游依赖
  - 血缘图
  - 依赖追踪
upstream_skill: requirement-diff-analyzer
downstream_skill: sql-code-generator
---

# 血缘元数据管理引擎

## 技能描述
管理 data_lineage.json 中的血缘关系，提供：
- **血缘查询**：给定表名，查询其上游依赖和下游影响
- **三级影响传播**：从变更表出发，逐层传播影响到下游报表
- **反向追踪**：从报表出发，反向追踪到上游ODS源表
- **血缘图可视化**：输出Mermaid格式的血缘关系图

## 数据源
- `bi-requirement-parser/dictionaries/data_lineage.json`：血缘关系主文件
- `bi-requirement-parser/dictionaries/data_dictionary.yaml`：表元数据

## 核心接口

### 1. 查询上游依赖
```
lineage-manager --action upstream --table paimon.cx_dws_safe.dws_policy_premium_daily
```
输出：该表的所有上游表（ODS源表+DIM维度表）

### 2. 查询下游影响
```
lineage-manager --action downstream --table paimon.cx_ods_safe.pingan_insurance_policy_master
```
输出：该表的所有下游表（DWD→DWS→ADS）

### 3. 三级影响传播
```
lineage-manager --action impact --table paimon.cx_ods_safe.pingan_insurance_policy_master --depth 3
```
输出：
- 一级影响：直接依赖该表的DWD表
- 二级影响：依赖DWD表的DWS表
- 三级影响：依赖DWS表的ADS报表

### 4. 反向追踪
```
lineage-manager --action trace --table paimon.cx_ads_safe.ads_channel_premium_report
```
输出：从ADS报表反向追踪到所有ODS源表

### 5. 血缘图可视化
```
lineage-manager --action graph --table paimon.cx_dws_safe.dws_policy_premium_daily --format mermaid
```
输出：Mermaid格式的血缘关系图

## 影响分析报告模板

```markdown
## ⚠️ 影响分析报告

**变更对象**：{table_fqn}
**变更类型**：{字段新增/字段修改/字段删除/表结构变更}

### 一、直接影响范围（一级传播）

| 影响对象 | 对象名称 | 影响类型 | 影响说明 |
|----------|----------|----------|----------|
| DWD表 | dwd_xxx | 需同步修改 | 下游ETL需增加字段映射 |

### 二、间接影响范围（二级传播）

| 影响对象 | 对象名称 | 影响类型 | 影响说明 |
|----------|----------|----------|----------|
| DWS表 | dws_xxx | 需同步修改 | 聚合逻辑可能受影响 |

### 三、末端影响范围（三级传播）

| 影响对象 | 对象名称 | 影响类型 | 影响说明 |
|----------|----------|----------|----------|
| ADS报表 | ads_xxx | 需同步修改 | 报表展示可能受影响 |

### 四、受影响的关联需求

| 需求编号 | 需求名称 | 影响程度 | 说明 |
|----------|----------|----------|------|
| REQ-xxx | xxx报表 | 高 | 核心指标受影响 |

### 五、风险等级

| 风险项 | 等级 | 说明 |
|--------|------|------|
| 数据一致性 | 高 | 需同步修改3层ETL |
| 历史数据 | 中 | 需确认是否回刷 |
```

## 目录结构
```
lineage-manager/
├── SKILL.md
└── examples/
    └── lineage_query.py
```

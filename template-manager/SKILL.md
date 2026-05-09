---
name: template-manager
description: 报表模板管理引擎，提供7个BI报表模板+4个数据分析模板，支持用户上传自定义模板，区分template_type=report(BI报表)和template_type=analysis(数据分析)
version: 1.0.0
author: BI Team
trigger_keywords:
  - 生成报表
  - 报表模板
  - 数据分析
  - 上传模板
  - 自定义模板
  - 模板列表
upstream_skill: sql-code-generator
downstream_skill: cluster-tester
---

# 报表模板管理引擎

## 技能描述
管理BI报表模板和数据分析模板。内置11个标准模板（7个BI报表+4个数据分析），支持用户上传自定义模板。

## 模板分类

| template_type | 说明 | 内置数量 | 存储路径 |
|---------------|------|---------|---------|
| report | BI报表（固定格式，定期产出） | 7 | templates/report/ |
| analysis | 数据分析（灵活探索，即席分析） | 4 | templates/analysis/ |

## 内置BI报表模板（template_type=report）

| 编号 | 模板ID | 模板名称 | 适用场景 | 维度数 | 指标数 |
|------|--------|---------|---------|--------|--------|
| R01 | trend_monthly | 月度趋势报表 | 按月查看指标变化趋势 | 2-3 | 3-5 |
| R02 | rank_top_n | 排名TopN报表 | 按维度排名取Top N | 1-2 | 1-3 |
| R03 | comparison_yoy | 同比环比报表 | 当期vs同期对比 | 2-3 | 2-4 |
| R04 | distribution_pie | 分布占比报表 | 各维度占比分布 | 1 | 1-2 |
| R05 | detail_drill | 明细下钻报表 | 从汇总下钻到明细 | 3-5 | 5-10 |
| R06 | multi_dim_cross | 多维交叉报表 | 多维度交叉分析 | 3-6 | 3-8 |
| R07 | kpi_dashboard | KPI看板报表 | 核心KPI指标汇总 | 0-1 | 5-15 |

## 内置数据分析模板（template_type=analysis）

| 编号 | 模板ID | 模板名称 | 适用场景 | 维度数 | 指标数 |
|------|--------|---------|---------|--------|--------|
| A01 | adhoc_query | 即席查询 | 自由SQL查询+结果导出 | 不限 | 不限 |
| A02 | cohort_retention | 队列留存分析 | 用户/保单留存率分析 | 2-3 | 2-4 |
| A03 | funnel_conversion | 漏斗转化分析 | 多步骤转化率分析 | 1-2 | 1-2 |
| A04 | anomaly_detection | 异常检测分析 | 指标异常波动检测 | 1-2 | 1-3 |

## 存储引擎路由

根据报表复杂度自动选择存储引擎：

| 条件 | 存储引擎 | 说明 |
|------|---------|------|
| 维度数>=5 或 需要实时下钻 或 高并发查询 | Doris | 复杂报表走Doris |
| 其他 | ADS(Paimon) | 简单报表走Paimon ADS层 |

## 触发条件
- 用户说"生成报表"、"报表模板"、"数据分析"等关键词
- sql-code-generator 生成SQL后需要选择报表模板
- 用户上传自定义模板文件

## 工作流程

### Step 1: 确定模板类型
- 根据需求描述判断 template_type（report/analysis）
- 根据维度数、指标数、交互需求匹配具体模板

### Step 2: 加载模板
- 内置模板：从 templates/{type}/ 目录读取
- 自定义模板：从用户上传路径读取

### Step 3: 填充模板参数
- 将SQL查询结果映射到模板的维度/指标槽位
- 生成最终报表配置（JSON格式）

### Step 4: 存储引擎路由
- 评估报表复杂度，选择ADS或Doris
- 输出 storage_engine 字段

## 目录结构
```
template-manager/
├── SKILL.md
├── templates/
│   ├── report/           ← BI报表模板（7个）
│   │   ├── trend_monthly.json
│   │   ├── rank_top_n.json
│   │   ├── comparison_yoy.json
│   │   ├── distribution_pie.json
│   │   ├── detail_drill.json
│   │   ├── multi_dim_cross.json
│   │   └── kpi_dashboard.json
│   └── analysis/         ← 数据分析模板（4个）
│       ├── adhoc_query.json
│       ├── cohort_retention.json
│       ├── funnel_conversion.json
│       └── anomaly_detection.json
└── examples/
    └── example_report_config.json
```

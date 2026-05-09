---
name: sql-code-generator
description: 根据结构化BI需求文档，自动生成标准Spark SQL代码（DDL建表/ETL取数/聚合查询），遵循Spark SQL编码规范，支持Paimon表格式
version: 1.1.0
author: BI Team
trigger_keywords:
  - 生成SQL
  - 写SQL
  - 代码生成
  - 建表
  - ETL
  - 取数逻辑
  - 落地实现
---

# SQL 代码生成 Skill

## Skill 名称

`sql-code-generator`

## Skill 目标

**从结构化 BI 需求文档 → 可直接执行的 Spark SQL 代码（DDL / ETL / 查询）**。

本 Skill 是 `code-updater` 的**专职 SQL 编写引擎**。它不负责 Git 提交和分支管理（那是 code-updater 的职责），只专注于产出高质量、规范化的 SQL 代码。

## 触发条件

当以下任一场景触发时激活：

| 场景 | 触发方式 |
|------|---------|
| **需求落地** | `bi-requirement-parser` 输出需求文档后，进入"写代码"阶段 |
| **显式要求** | 用户说"生成 SQL"、"写 ETL"、"建表"、"实现这个需求" |
| **code-updater 下游** | `code-updater` 收到变更影响报告后调用 |

## 核心能力

### 1. 三层代码输出

根据需求类型自动判断输出哪类 SQL：

```
需求分析结果
    │
    ├── 需要新表 → 输出 DDL（CREATE TABLE Paimon 格式）
    │
    ├── 数据加工 → 输出 ETL（INSERT OVERWRITE / MERGE INTO）
    │
    └── 即时查询 → 输出 SELECT（临时取数 / 报表查询）
```

### 2. 规范强制执行

所有生成的代码**必须符合** `dictionaries/spark-sql-standards.md` 中的编码规范：
- 关键字全大写、字段名 snake_case
- 禁止 `SELECT *`
- CASE WHEN 必须有 ELSE
- 每条语句必须有注释
- CTE 优先于嵌套子查询

### 3. 数据字典联动

- 表名、字段名优先从 **RAG 检索结果 (tables.json)** 获取，RAG 不可用时降级为 `data_dictionary.yaml` 全文读取
- 不允许臆造不存在的表或字段
- 字段类型参考数据字典定义
- 外键关系参考 `dict_rag_index/fk_graph.json` 自动补 JOIN

### 4. 幂等性保证

- ETL 使用 `INSERT OVERWRITE TABLE ... PARTITION(dt=)` 实现幂等写入
- 支持增量合并场景使用 `MERGE INTO`
- DDL 使用 `IF NOT EXISTS` 避免重复建表错误。

### 5. 分层构建引擎

根据 data_dictionary.yaml 中的 layer/database/catalog 字段自动路由到正确的数仓分层：

**分层路由规则**（LayerRouter）：

| 需求类型 | 目标层 | catalog | database | 表名前缀 | HDFS路径 |
|----------|--------|---------|----------|---------|----------|
| 明细宽表 | DWD | paimon | cx_dwd_safe | dwd_ | /cx_dwd_safe/dwd/ |
| 汇总宽表 | DWS | paimon | cx_dws_safe | dws_ | /cx_dws_safe/dws/ |
| 维度表 | DIM | paimon | cx_dim_safe | dim_ | /cx_dim_safe/dim/ |
| 应用报表 | ADS | paimon | cx_ads_safe | ads_ | /cx_ads_safe/ads/ |
| 临时取数 | DWP | paimon | cx_dwp_safe | adhoc_ | /cx_dwp_safe/adhoc/ |

**构建顺序**（依赖驱动）：
```
ODS(已存在) → DIM(维度表,无上游依赖) → DWD(明细宽表,依赖ODS+DIM) → DWS(汇总宽表,依赖DWD+DIM) → ADS(应用报表,依赖DWS+DIM)
```

**自动推断逻辑**：
1. 读取 data_dictionary.yaml 获取源表的 layer 字段
2. 根据需求中的聚合粒度推断目标层：无聚合→DWD，有聚合→DWS，面向报表→ADS
3. 自动生成 FQN（Fully Qualified Name）：`{catalog}.{database}.{table_name}`
4. 自动补全上游依赖：基于 data_lineage.json 的 reverse_index 获取下游影响
5. 生成构建批次：按依赖拓扑排序，同层无依赖的表可并行构建

## 工作流程

### Step 1: 读取输入

**数据获取优先级（RAG 优先，YAML 兜底）**：

| 优先级 | 方式 | 数据来源 | Token 消耗 | 说明 |
|:---:|------|---------|:---:|------|
| **① 主力** | **RAG 语义检索** | `dict_rag_index/index.faiss` + `tables.json` | ~5-8K | 用户说"渠道保费"→ 向量检索 Top-K 相关表 → 读 tables.json 获取字段详情 |
| **② 补充** | FK 关联扩展 | `dict_rag_index/fk_graph.json` | ~1-2K | 根据命中表的外键关系，自动扩展 JOIN 关联表 |
| **③ 兜底** | 全文读 YAML | `data_dictionary.yaml` | ~35K | 仅当 RAG 索引不存在或构建失败时降级使用 |

> **重要**: 正常情况下只走 ①+②。走 ③ 时应输出警告 `[WARN] RAG 索引不可用, 退化为全文模式 (高 token 消耗)` 并建议用户运行 `rag build --er-file ods_er.txt`。

**必须确认的信息**（缺则追问）：
- [ ] 目标表名（新建还是已有？）
- [ ] 数仓分层（ODS/DWD/DWS/ADS）
- [ ] 数据粒度（分区字段？如 dt）
- [ ] 数据范围（全量？增量？特定时间？）
- [ ] 输出类型（DDL / ETL / SELECT）

### Step 2: 设计 SQL 方案

在写代码前，先输出**设计方案**让用户确认（简单需求可跳过）：

```markdown
## SQL 设计方案

**目标表**: `dws_policy_premium_daily`
**分层**: DWS 汇总层
**分区**: `dt` (日分区)
**写入方式**: INSERT OVERWRITE（全量覆盖当日分区）

### 数据来源
| 别名 | 表名 | 关联方式 | 说明 |
|------|------|---------|------|
| ods | `paimon.cx_ods_safe.pingan_insurance_policy_master` | 主表 | 保单基本信息（ODS层，带pingan_insurance_前缀） |
| prem | `paimon.cx_ods_safe.pingan_insurance_premium_payment` | LEFT JOIN | 保费记录 |
| chnl | `paimon.cx_dim_safe.dim_channel` | LEFT JOIN | 渠道维度表（DWD/DWS层无前缀） |

**⚠️ 数据库和表名规范（必须遵守！）**：

| 层级 | Database | 表名前缀 | 示例 |
|:---:|----------|---------|------|
| **ODS** (源数据层) | `paimon.cx_ods_safe`  | `pingan_insurance_` | `paimon.cx_ods_safe.pingan_insurance_policy_master` |
| **DWD** (明细层) | `paimon.cx_dwd_safe` | 无前缀 | `paimon.cx_dwd_safe.dwd_car_insurance_quote` |
| **DWD** (明细层) | `paimon.cx_dwd_safe` | 无前缀 | `paimon.cx_dwd_safe.dwd_policy_premium_daily` |
| **DWS** (汇总层) | `paimon.cx_dws_safe` | 无前缀 | `paimon.cx_dws_safe.dws_policy_premium_daily` |
| **DIM** (维度层) | `paimon.cx_dim_safe` | 无前缀 | `paimon.cx_dim_safe.dim_channel` |
| **ADS** (应用层) | `paimon.cx_ads_safe` | 无前缀 | `paimon.cx_ads_safe.ads_xxx_report` |

### 计算逻辑
1. 按 保单号 + 渠道 + 日分区 聚合
2. SUM(保费金额) → total_premium
3. COUNT(DISTINCT 保单号) → policy_cnt
4. WHERE dt = '${biz_date}' （宏变量）

### 预计输出文件 + HDFS 路径
```
HDFS 目录结构（部署到 YARN 集群时使用）:
  /cx_dwd_safe/ddl/     → 所有 DDL 建表语句（DWD/DWS/ADS 统一存放）,文件名：表名_ddl.sql。 例如：dwd_policy_premium_daily_ddl.sql
  /cx_dwd_safe/dwd/     → DWD 层的 ETL 取数脚本,文件名和表名一致。例如：dwd_policy_premium_daily.sql
  /cx_dws_safe/dws/     → DWS 层的 ETL 取数脚本,文件名和表名一致。例如：dws_policy_premium_daily.sql
  /cx_dim_safe/dim/     → DIM 层的 ETL 取数脚本,文件名和表名一致。例如：dim_channel.sql
  /cx_ads_safe/ads/     → ADS 层的 ETL 取数脚本,文件名和表名一致。例如：ads_xxx_report.sql

本地开发目录:
  ddl/{layer}_{table_name}_ddl.sql   — DDL 文件（本地编辑后 hdfs dfs -put 到 /ddl/）
  etl/etl_{layer}_{table_name}.sql   — ETL 文件

示例:
  ddl/dwd_policy_premium_daily_ddl.sql    → 上传到 hdfs:///cx_dwd_safe/ddl/
  dwd/dwd_policy_premium_daily.sql    → 上传到 hdfs:///cx_dwd_safe/dwd/
  dws/dws_policy_premium_daily.sql    → 上传到 hdfs:///cx_dws_safe/dws/
  dim/dim_policy_premium_daily.sql    → 上传到 hdfs:///cx_dim_safe/dim/
  ads/ads_policy_premium_daily.sql    → 上传到 hdfs:///cx_ads_safe/ads/
```
```

### Step 3: 生成代码

> **⚠️ 重要**: 生成代码前**必须先读取对应模板文件**获取完整语法结构！不要凭记忆编写。

#### 3.1 DDL 模板（Paimon 建表）

**模板文件**: `templates/ddl_template.sql` （主键表 + 非主键表两种形式）

**DDL 规范要点**：
- 必须有完整头部注释（功能描述 + 作者 + 日期 + 修改日志）
- 字段分组：主键 → 维度 → 指标 → 元数据
- 每个字段必须有 COMMENT
- 分区字段放在 PARTITIONED BY 中（不在字段列表内），需要给字段类型和注释
- 使用 `IF NOT EXISTS`
- TBLPROPERTIES 中配置 Paimon 特有参数（压缩、过期清理、主键、是否产生日志变更等）

#### 3.2 ETL 模板（取数逻辑）

**模板文件**: `templates/etl_template.sql`

**ETL 规范要点**：
- 头部注释包含执行频率/耗时预估/依赖任务
- SET 参数放在最前面（shuffle.partitions 等）
- 使用 CTE（WITH 子句）组织逻辑，每个 CTE 有明确语义命名
- 每个 CTE 内部字段必须有行内注释
- JOIN 必须用别名，ON 条件与 JOIN 同级缩进
- NULL 安全：聚合指标用 COALESCE(xx, 0)
- 写入用 INSERT OVERWRITE ... PARTITION(dt) 保证幂等
- 最后 INSERT 加 `/*+ REPARTITION(N) */` 控制输出分区数,需要和建表语句的 bucket 数量一致（如果设置了）

#### 3.3 查询模板（报表/临时取数）

**模板文件**: `templates/query_template.sql`

### Step 4: 自检清单

生成代码后，逐项检查：

```markdown
## SQL 自检报告

**规范类**：
- [ ] 所有 SQL 关键字全大写 (SELECT/FROM/WHERE/JOIN/GROUP BY...)
- [ ] 无 SELECT * 出现
- [ ] 表名/字段名 snake_case
- [ ] 每个字段都有 COMMENT（DDL）/ 行内注释（ETL）
- [ ] CASE WHEN 有 ELSE 分支
- [ ] JOIN 用表别名，ON 条件清晰
- [ ] 聚合函数处理了 NULL（COALESCE/NVL）
- [ ] 除法有除零保护（CASE WHEN divisor != 0）
- [ ] INSERT OVERWRITE 有分区限定（非全表删除）
- [ ] 头部注释完整（功能/作者/日期/修改日志）
- [ ] CTE 命名有业务含义（非 a/b/c）

**数据字典联动**：
- [ ] 字段类型与 **RAG 检索结果(tables.json)** 一致（或 data_dictionary.yaml 兜底）
- [ ] 引用的外键表已通过 fk_graph.json 验证存在

**⚠️ 数据库/表名规范（必须遵守）**：
- [ ] DDL 必须是 paimon 数据湖格式
- [ ] ODS 层源表: `cx_ods_safe.pingan_insurance_xxx`（带前缀）
- [ ] DWD/DWS/ADS/DIM 目标表: `cx_{layer}_safe.{layer}_xxx`（无前缀）
```

## 目录结构

```
sql-code-generator/
├── SKILL.md                              ← 本文件（Skill 定义）
├── dictionaries/
│   ├── spark-sql-standards.md            ← Spark SQL 编写规范（强约束）
│   └── sql_patterns.yaml                ← 常用 SQL 模式库（函数/表达式模板）
├── templates/
│   ├── ddl_template.sql                  ← Paimon DDL 建表模板（★生成前必读）
│   ├── etl_template.sql                  ← ETL 取数逻辑模板（★生成前必读）
│   └── query_template.sql               ← 报表/临时取数查询模板（★生成前必读）
└── examples/
    ├── example_ddl_output.sql            ← DDL 输出示例（车险保费汇总表）
    ├── example_etl_output.sql            ← ETL 输出示例（日汇总加工）
    └── example_query_output.sql          ← 查询输出示例（渠道保费趋势）
```

## 与其他 Skill 的关系

```
bi-requirement-parser（产出需求文档）
         │
         ▼
   sql-code-generator  ← ★ 本 Skill（需求 → SQL 代码）
         │
         ├─→ DDL  →  sql-validator（EXPLAIN 验证）
         ├─→ ETL  →  sql-validator（EXPLAIN 验证）
         └─→ SELECT → cluster-tester（集群执行返回结果）
                       │
                       ▼
                code-updater（Git 提交 + PR 创建）
```

**注意**：本 Skill 只负责「写出正确的 SQL」，不涉及：
- ❌ Git 操作（提交/分支/PR）→ 归 `code-updater`
- ❌ 集群执行验证 → 归 `sql-validator` + `cluster-tester`
- ❌ 调度配置 → 归 `scheduler-updater`
- ❌ 需求解析和澄清 → 归 `bi-requirement-parser`

## 常见反模式（禁止）

| 反模式 | 正确做法 |
|--------|---------|
| `SELECT *` | 明确列出所有字段 |
| `DROP TABLE + CREATE` | `INSERT OVERWRITE` 或 `CREATE IF NOT EXISTS` |
| 隐式类型转换（JOIN 键不一致） | 显式 CAST 或确保源数据一致 |
| 无注释的大段 SQL | 每段逻辑加块注释 + 字段加行注释 |
| 嵌套 3 层以上的子查询 | 拆分为多个 CTE |
| 不处理 NULL 的聚合 | `COALESCE(SUM(x), 0)` |
| 全表扫描无分区限制 | WHERE 中限定 `dt = ${biz_date}` |
| 一个脚本超过 500 行 | 拆分为多个子脚本或视图 |
| **ODS 表名无前缀** `FROM ods.policy_master` | **`FROM paimon.cx_ods_safe.pingan_insurance_policy_master`** |
| **目标表缺 database** `INSERT INTO dws_xxx` | **`INSERT INTO paimon.cx_dws_safe.dws_xxx`** |

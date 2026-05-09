---
name: sql-validator
description: 在 Hadoop 集群中使用 EXPLAIN 验证 SQL 语法正确性，支持 Spark SQL，通过 SSH 提交到 YARN 执行
version: 2.0.0
author: BI Team
trigger_keywords:
  - 验证 SQL
  - SQL 语法检查
  - EXPLAIN 测试
  - Hadoop 验证
  - 语法验证
upstream_skill: sql-code-generator
downstream_skill: cluster-tester
---

# SQL 语法验证 Skill

## 定位

接收 `sql-code-generator` 生成的 DDL/ETL SQL 文件 → 通过 SSH 提交到 YARN 集群执行 EXPLAIN → 输出通过/失败报告。

> ⚠️ 本地无集群环境。所有 EXPLAIN 必须通过 SSH/Gateway 提交到 YARN（同 cluster-tester）。

## 触发条件

| 触发方式 | 说明 |
|---------|------|
| `sql-code-generator` 输出代码后自动触发 | 上游 Skill 产出 SQL 文件 |
| 用户说"验证SQL""EXPLAIN测试"等 | 显式要求 |

## 输入/输出

```
输入: SQL 文件路径列表 (DDL + ETL)
输出: 验证报告 (Markdown) → 通过则进入 cluster-tester，失败则返回 sql-code-generator 修复
```

## 验证流程

### Step 1: 解析分类

从输入中提取 SQL 文件，按类型和依赖排序：
- DDL（CREATE/ALTER/DROP）优先
- ETL（INSERT OVERWRITE / SELECT）在后
- 按分层顺序：ODS → DWD → DWS → ADS

### Step 2: 构建 EXPLAIN + 提交到 YARN

```bash
# 统一命令模板（Hive 和 Spark 仅 --engine 参数不同）
ssh {gateway_user}@{gateway_host} "
  spark-submit \
  --class BatchSQLRunner \
  --master yarn \
  --deploy-mode cluster \
  --jars /opt/spark/jars/paimon-spark-3.5-1.3.1.jar \
  --conf spark.sql.catalog.paimon=org.apache.paimon.spark.SparkCatalog \
  --conf spark.sql.catalog.paimon.warehouse=hdfs:///paimon/warehouse \
  --conf spark.sql.extensions=org.apache.paimon.spark.extensions.PaimonSparkSessionExtensions \
  hdfs:///spark/jars/batch-sql-runner-1.0.jar \
  -e \"EXPLAIN EXTENDED $(cat /path/to/sql_file.sql)\"
"
```

**EXPLAIN 类型映射**：

| SQL 类型 | EXPLAIN 命令 | 说明 |
|---------|-------------|------|
| DDL (`CREATE TABLE`) | `EXPLAIN EXTENDED CREATE TABLE ...` | 不实际建表，仅检查语法 |
| ETL (`INSERT OVERWRITE`) | `EXPLAIN EXTENDED INSERT OVERWRITE ... SELECT ...` | 检查查询计划 |
| SELECT 查询 | `EXPLAIN EXTENDED SELECT ...` | 检查执行计划 |

### Step 3: 判定结果

| 判定 | 标志 | 处理 |
|------|------|------|
| ✅ 通过 | EXPLAIN 返回执行计划，无异常 | 进入 cluster-tester |
| ❌ 失败 | 返回 `ParseException` / `SemanticException` | 报错+修复建议→返回 sql-code-generator |
| ⚠️ 警告 | EXPLAIN 成功但有全表扫描等优化提示 | 记录建议，不阻断流程 |

### Step 4: 输出报告

输出精简报告（固定格式，无需内嵌完整模板）：

```markdown
# SQL 验证报告：{需求编号}

**状态**: ✅ 通过 / ❌ 失败 | **时间**: {YYYY-MM-DD HH:mm} | **引擎**: Spark SQL (YARN)

## 结果汇总
| 类型 | 文件数 | 通过 | 失败 |
|------|--------|------|------|
| DDL  | N      | N    | 0    |
| ETL  | N      | N    | 0    |

## 失败详情（如有）
**文件**: `{path}` | **错误**: `ParseException line X:Y ...`
**修复建议**: {具体修改}
```

## 与上下游的衔接

```
sql-code-generator (生成 SQL)
        │
        ▼
   sql-validator ← ★ 本 Skill (EXPLAIN 语法验证)
        │
        ├── 通过 → cluster-tester (YARN 集群实际执行)
        └── 失败 → sql-code-generator (修复后重新验证)
```

## 注意事项

- **⚠️ 本地无集群**，通过 SSH 提交到 YARN（同 cluster-tester 的提交方式）
- EXPLAIN **不实际执行**，不影响数据
- ETL 验证建议加 `LIMIT 10` 减少资源消耗
- 单条超时默认 60 秒
- HDFS 路径规范：DDL→`/cx_dwd_safe/ddl/`, DWD ETL→`/cx_dwd_safe/dwd/`, DWS ETL→`/cx_dws_safe/dws/`
- ODS 表名规范：`cx_ods_safe.pingan_insurance_xxx`（见 sql-code-generator SKILL.md Step 2）

## 异常处理

| 异常 | 处理 |
|------|------|
| SSH 连接失败 | 检查 Gateway 配置 / SSH 密钥 |
| SQL 文件不存在 | 报错中止 |
| EXPLAIN 超时(>60s) | 标记超时失败，建议简化 SQL |
| YARN 资源不足 | 提示等待或调整队列 |

---
name: cluster-tester
description: 在 Hadoop 集群上执行 DDL 建表、ETL 跑数据、数据验证。支持两种模式：测试模式（LIMIT 采样）和正式执行模式（全量生产运行）
version: 1.1.0
author: BI Team
trigger_keywords:
  - 集群测试
  - 跑数据
  - 验证数据
  - 测试建表
  - 集群执行
  - 执行SQL
  - 正式提交
  - 生产部署
  - 上线运行
  - 正式跑数
upstream_skill: sql-validator
downstream_skill: git-merger
---

# 技能名称：cluster-tester

## 技能描述
集群测试专家。代码在 OpenClaw 开发服务器上编写，通过 SSH 提交到 YARN 集群执行（本地无集群环境）。

**测试流程**：
1. 将 SQL 文件上传到 HDFS 指定目录
2. 通过 `spark-submit --master yarn` 提交到 YARN 集群执行 DDL 建表
3. 执行 ETL 跑数据（INSERT OVERWRITE ... SELECT ...）
4. 验证数据正确性（行数、抽样、指标值）

> ⚠️ 本地无法直接测试 SQL！所有 SQL 必须通过 SSH/Gateway 提交到 YARN 集群执行。

## 触发条件
- 由 `sql-validator` 输出"验证通过"后自动触发
- 用户指令包含"集群测试""跑数据""验证数据""测试建表"等关键词

> **前置条件**：SQL 必须先通过 `sql-validator` 的 EXPLAIN 语法验证

## 输入格式
- SQL 验证报告（由 sql-validator 输出）
- SQL 文件列表（DDL + ETL）
- OpenClaw 环境配置（集群地址、认证方式、执行引擎）

## 输出格式

```markdown
# 集群测试报告：{需求编号}

**测试状态**：待执行 → 执行中 → 通过 / 失败
**测试时间**：{YYYY-MM-DD HH:mm}
**执行集群**：{集群名}
**执行引擎**：Spark SQL / Hive

---

## 1. 测试概述

| 测试项 | 文件数 | 通过 | 失败 |
|--------|--------|------|------|
| DDL 建表 | N | N | 0 |
| ETL 跑数 | N | N | 0 |
| 数据验证 | N | N | 0 |

---

## 2. DDL 执行结果

| 序号 | 文件 | SQL 类型 | 结果 | 耗时 |
|------|------|----------|------|------|
| 1 | sql/dwd/xxx.sql | CREATE TABLE | ✅ 成功 | 2.1s |
| 2 | sql/dws/yyy.sql | ALTER TABLE | ✅ 成功 | 1.3s |

---

## 3. ETL 执行结果

| 序号 | 文件 | 结果行数 | 耗时 | 状态 |
|------|------|----------|------|------|
| 1 | etl/xxx.sql | 1,234 | 45.2s | ✅ 成功 |
| 2 | etl/yyy.sql | 0 | 12.1s | ⚠️ 零行 |

---

## 4. 数据验证

| 验证项 | 预期 | 实际 | 状态 |
|--------|------|------|------|
| 表是否存在 | dwd_xxx | ✅ 存在 | 通过 |
| 行数 > 0 | > 0 | 1,234 | 通过 |
| 关键指标非空 | sum(amount) > 0 | 567,890 | 通过 |
| 抽样数据 | 合理 | [展示前5行] | 通过 |

---

## 5. 失败详情（如有）

### 错误 #1
**文件**：etl/xxx.sql
**错误**：`AnalysisException: Table or view not found: ods_source_table`
**原因**：源表不存在于测试库
**修复建议**：先在测试环境创建源表或确认表名

---

## 6. 执行日志

```bash
# === 本地操作：上传 SQL 到 HDFS ===
hdfs dfs -put sql/ddl/xxx.sql /cx_dwd_safe/ddl/
hdfs dfs -put etl/dwd/xxx.sql /cx_dwd_safe/dwd/
hdfs dfs -put etl/dws/yyy.sql /cx_dws_safe/dws/
hdfs dfs -put etl/dim/xxx.sql /cx_dim_safe/dim/
hdfs dfs -put etl/ads/yyy.sql /cx_ads_safe/ads/

# === 远程执行（通过 SSH/Gateway 提交到 YARN 集群）===
# DDL
ssh {gateway} "spark-submit \
  --class BatchSQLRunner \
  --master yarn \
  --deploy-mode cluster \
  --jars /opt/spark/jars/paimon-spark-3.5-1.3.1.jar \
  --conf spark.sql.catalog.paimon=org.apache.paimon.spark.SparkCatalog \
  --conf spark.sql.catalog.paimon.warehouse=hdfs:///paimon/warehouse \
  --conf spark.sql.extensions=org.apache.paimon.spark.extensions.PaimonSparkSessionExtensions \
  hdfs:///spark/jars/batch-sql-runner-1.0.jar \
  hdfs:///cx_dwd_safe/ddl/xxx.sql"
# Result: OK (2.1s)

# ETL (DWD 层)
ssh {gateway} "spark-submit \
  --class BatchSQLRunner \
  --master yarn \
  --deploy-mode cluster \
  --jars /opt/spark/jars/paimon-spark-3.5-1.3.1.jar \
  --conf spark.sql.catalog.paimon=org.apache.paimon.spark.SparkCatalog \
  --conf spark.sql.catalog.paimon.warehouse=hdfs:///paimon/warehouse \
  --conf spark.sql.extensions=org.apache.paimon.spark.extensions.PaimonSparkSessionExtensions \
  hdfs:///spark/jars/batch-sql-runner-1.0.jar \ 
  hdfs:///cx_dwd_safe/dwd/xxx.sql"
# Result: OK (45.2s, 1234 rows affected)

# ETL (DWS 层)
ssh {gateway} "spark-submit \
  --class BatchSQLRunner \
  --master yarn \
  --deploy-mode cluster \
  --jars /opt/spark/jars/paimon-spark-3.5-1.3.1.jar \
  --conf spark.sql.catalog.paimon=org.apache.paimon.spark.SparkCatalog \
  --conf spark.sql.catalog.paimon.warehouse=hdfs:///paimon/warehouse \
  --conf spark.sql.extensions=org.apache.paimon.spark.extensions.PaimonSparkSessionExtensions \
  hdfs:///spark/jars/batch-sql-runner-1.0.jar \
  hdfs:///cx_dws_safe/dws/yyy.sql"
# Result: OK


# 数据验证
ssh {gateway} "spark-sql ... \
    --jars /opt/spark/jars/paimon-spark-3.5-1.3.1.jar \
    --conf spark.sql.catalog.paimon=org.apache.paimon.spark.SparkCatalog \
    --conf spark.sql.catalog.paimon.warehouse=hdfs:///paimon/warehouse \
    --conf spark.sql.extensions=org.apache.paimon.spark.extensions.PaimonSparkSessionExtensions \
    --master yarn --deploy-mode client \
    -e 'SELECT COUNT(*) FROM paimon.cx_dwd_safe.dwd_xxx'"
# Result: 1234
```

---

## 7. 测试结论

[ ] 所有测试通过，可以进入合并流程
[ ] 存在测试失败，需修复后重新测试
```

## 执行流程

### 第一步：上传 SQL 到 HDFS + 提交到 YARN 执行

```bash
# 1. 将本地 SQL 文件上传到 HDFS
hdfs dfs -mkdir -p /cx_dwd_safe/ddl /cx_dwd_safe/dwd /cx_dws_safe/dws /cx_dim_safe/dim /cx_ads_safe/ads

# DDL 文件统一放 /ddl 目录
hdfs dfs -put sql/dwd/xxx.sql /cx_dwd_safe/ddl/
hdfs dfs -put sql/dws/yyy.sql /cx_dwd_safe/ddl/

# ETL 文件按分层存放
hdfs dfs -put etl/xxx.sql /cx_dwd_safe/dwd/
hdfs dfs -put etl/yyy.sql /cx_dws_safe/dws/
```

```bash
# 2. 通过 Gateway/SSH 提交到 YARN 集群执行（不是本地！）
# 方式 A: SSH 到 Gateway 节点执行
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
  hdfs:///cx_dwd_safe/ddl/xxx.sql
"

# 方式 B: 通过 OpenClaw hadoop exec 命令
openclaw hadoop exec \
    --cluster prod \
    --engine spark \
    --master yarn \
    --deploy-mode cluster \
    --file hdfs:///cx_dwd_safe/ddl/xxx.sql \
    --database cx_dwd_safe
```

**关键点**：
- 本地 **没有 YARN 集群**，必须通过 SSH 或 OpenClaw 网关提交
- SQL 文件先 `hdfs dfs -put` 上传，再通过 HDFS 路径 `-f` 执行
- `--master yarn` + `--deploy-mode cluster` 是必须参数

### 第二步：执行 ETL（跑数据）

```bash
# 通过 SSH 提交到 YARN 集群执行
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
  hdfs://nameservice/cx_dwd_safe/dwd/xxx.sql
"

# DWD 层的 ETL → 放在 /cx_dwd_safe/dwd/
# DWS 层的 ETL → 放在 /cx_dws_safe/dws/
# DDL 统一放在 /cx_dwd_safe/ddl/
```

**HDFS 目录规范**：
| 文件类型 | HDFS 路径 | 示例 |
|---------|-----------|------|
| DDL 建表语句 | `hdfs:///cx_dwd_safe/ddl/` | `ddl/dwd_policy_premium_daily.sql` |
| DWD 层 ETL | `hdfs:///cx_dwd_safe/dwd/` | `dwd/etl_dwd_xxx.sql` |
| DWS 层 ETL | `hdfs:///cx_dws_safe/dws/` | `dws/etl_dws_yyy.sql` |

**安全措施**：
- ETL 语句自动追加 `LIMIT 10000`（测试环境只跑少量数据）
- 如果用户确认需要全量，去掉 LIMIT
- 设置执行超时：单条 ETL 最多 600 秒

**失败处理**：
- 记录完整错误日志
- 自动回滚 DDL（DROP TABLE IF EXISTS）
- 输出修复建议

### 第三步：数据验证

自动执行以下验证：

```sql
-- 1. 表是否存在
SHOW TABLES LIKE '{表名}';

-- 2. 行数检查
SELECT COUNT(*) FROM {表名};

-- 3. 空值检查（关键字段）
SELECT SUM(CASE WHEN {字段} IS NULL THEN 1 ELSE 0 END) AS null_count FROM {表名};

-- 4. 抽样预览
SELECT * FROM {表名} LIMIT 5;

-- 5. 指标合理性检查
SELECT SUM({指标字段}) FROM {表名};
```

### 第四步：输出测试报告

- 汇总所有执行结果
- 标记通过/失败状态
- 失败时提供详细错误和修复建议

---

## 正式执行模式（生产部署）

> ⚠️ **正式执行 = 生产环境全量运行，无 LIMIT 限制，影响真实数据！**

### 触发条件

| 场景 | 触发方式 | 前置条件 |
|------|---------|---------|
| **正式提交** | 用户说"正式提交""生产部署""上线运行""正式跑数" | git-merger 已合并代码到主分支 |
| **补数/重跑** | 用户说"重跑""补数据""修复后重新执行" | SQL 文件已在 HDFS |

### 与测试模式的区别

| 维度 | 测试模式（默认） | 正式执行模式 |
|------|------------------|-------------|
| **触发时机** | sql-validator 通过后 | git-merger 合并后 / 用户显式要求 |
| **数据量** | `LIMIT 10000`（采样） | **无 LIMIT**（全量） |
| **目标环境** | 测试队列 / 开发库 | **生产队列** (`--queue production`) |
| **超时时间** | 单条 600s | 单条 **3600s** (1小时) |
| **DDL 影响** | 可自动回滚 | **不自动回滚**，需人工确认 |
| **日志级别** | INFO + 结果摘要 | **完整日志** + 审计记录 |
| **失败处理** | 回滚 + 报错 | **暂停 + 告警 + 保留现场** |

### 正式执行流程

#### Step 1: 执行前检查（强制）

```bash
# === 前置条件校验 ===
# 1. 确认 Git 分支已合并
git branch --merged master | grep 'upgrade/{需求编号}'

# 2. 确认 SQL 文件已在 HDFS（由 git-merge 后的部署脚本上传）
hdfs dfs -ls /cx_dwd_safe/ddl/{表名}_ddl.sql
hdfs dfs -ls /cx_dwd_safe/dwd/ 或 dws/ 或 dim/ 或 ads/

# 3. 确认上游表分区就绪
ssh {gateway} "spark-sql ... \
    --jars /opt/spark/jars/paimon-spark-3.5-1.3.1.jar \
    --conf spark.sql.catalog.paimon=org.apache.paimon.spark.SparkCatalog \
    --conf spark.sql.catalog.paimon.warehouse=hdfs:///paimon/warehouse \
    --conf spark.sql.extensions=org.apache.paimon.spark.extensions.PaimonSparkSessionExtensions \
    --master yarn --deploy-mode client \
    -e 'SHOW PARTITIONS cx_ods_safe.pingan_insurance_policy_master WHERE dt = \"${biz_date}\"'"

# 4. 确认 YARN 队列资源可用
yarn queue -status production
```

**任一检查不通过则中止，输出原因**：
```markdown
## 正式执行前置检查 — ❌ 未通过

| 检查项 | 状态 | 说明 |
|--------|:---:|------|
| Git 分支已合并 | ❌ | upgrade/REQ-001 未合并到 master |
| DDL 文件在 HDFS | ✅ | dwd_policy_premium_daily_ddl.sql 存在 |
| ETL 文件在 HDFS | ✅ | dwd_policy_premium_daily.sql 存在 |
| 上游分区就绪 | ❌ | ods 表 dt=2026-04-23 分区不存在 |
| YARN 资源可用 | ✅ | production 队列可用 (剩余 120 vcore)

**结论**: 中止。请先确认上游 ODS 表 T-1 分区是否已产出。
```

#### Step 2: 正式执行 DDL（建表）

```bash
# 正式执行 DDL（生产环境）
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
  hdfs:///cx_dwd_safe/ddl/{表名}_ddl.sql
"
```

> **注意**: 正式模式 DDL 使用 `CREATE TABLE IF NOT EXISTS`，如果表已存在则跳过（不会 DROP）。

#### Step 3: 正式执行 ETL（全量跑数）

```bash
# 正式 ETL（全量数据，无 LIMIT）
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
  hdfs://nameservice/cx_dwd_safe/dwd/{etl文件}.sql
"
```

**关键差异（vs 测试模式）**:
- `--queue **production**` （生产队列，非 default）
- **无** `LIMIT 10000`（全量写入）
- 更大资源：`executor.instances=20`（测试用 5）
- 更长超时：**3600 秒**
- 启用 AQE 自适应查询优化

**按分层顺序执行**：
```
ODS 层（如有）→ DWD 层 → DWS 层 → ADS 层
```

#### Step 4: 数据验证（正式）

```sql
-- 1. 行数验证（对比历史趋势，不应偏差 > 50%）
SELECT
    '{biz_date}' AS data_date,
    COUNT(*) AS current_rows,
    LAG(COUNT(*), 1) OVER (ORDER BY dt) AS yesterday_rows,
    ROUND(COUNT(*) * 100.0 / NULLIF(LAG(COUNT(*), 1) OVER (ORDER BY dt), 0), 2)
        AS row_ratio_pct
FROM `{catalog}.{database}.{table_name}`
WHERE dt = '{biz_date}'
GROUP BY '{biz_date}';

-- 2. 关键指标非空率
SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN `{metric_field}` IS NOT NULL THEN 1 ELSE 0 END) AS not_null_cnt,
    ROUND(SUM(CASE WHEN `{metric_field}` IS NOT NULL THEN 1 ELSE 0 END) * 100.0
          / COUNT(*), 2) AS not_null_pct
FROM `{catalog}.{database}.{table_name}`
WHERE dt = '{biz_date}';

-- 3. 分区完整性（确认目标分区已写入）
SHOW PARTITIONS `{catalog}.{database.{table_name}`
PARTITION(dt = '{biz_date}');

-- 4. 抽样预览（前 10 行）
SELECT * FROM `{catalog}.{database}.{table_name}` WHERE dt = '{biz_date}' LIMIT 10;
```

#### Step 5: 输出正式执行报告

```markdown
# 正式执行报告：{需求编号}

**执行状态**: ✅ 成功 / ❌ 失败 / ⚠️ 部分成功
**执行时间**: {YYYY-MM-DD HH:mm} ~ {YYYY-MM-DD HH:mm}
**执行集群**: {生产集群名}
**执行引擎**: Spark SQL (YARN Production Queue)
**Git 提交**: {commit_hash}

---

## 1. 执行概览

| 类型 | 文件数 | 成功 | 失败 | 总耗时 |
|------|--------|------|------|--------|
| DDL 建表 | N | N | 0 | X min |
| DWD ETL | N | N | 0 | X min |
| DWS ETL | N | N | 0 | X min |

---

## 2. 各层执行详情

### 2.1 DDL 建表

| 序号 | 表名 | SQL 类型 | 结果 | 耗时 |
|------|------|----------|------|------|
| 1 | cx_dwd_safe.dwd_xxx | CREATE TABLE IF NOT EXISTS | ✅ 成功 | 5.2s |
| 2 | cx_dws_safe.dws_yyy | CREATE TABLE IF NOT EXISTS | ✅ 成功 | 3.1s |

### 2.2 ETL 取数

| 序号 | 分层 | 文件 | 影响行数 | 耗时 | 状态 |
|------|------|------|----------|------|------|
| 1 | DWD | etl_dwd_xxx.sql | 12,345,678 | 18m32s | ✅ 成功 |
| 2 | DWS | etl_dws_yyy.sql | 234,567 | 5m12s | ✅ 成功 |

---

## 3. 数据质量验证

| 验证项 | 预期 | 实际 | 状态 |
|--------|------|------|------|
| DWD 行数 vs 昨日偏差 | < ±50% | +12% | ✅ 通过 |
| DWS 行数 vs 昨日偏差 | < ±50% | +8% | ✅ 通过 |
| 关键指标非空率 | ≥ 98% | 99.2% | ✅ 通过 |
| 目标分区存在 | dt={biz_date} | ✅ 存在 | ✅ 通过 |

---

## 4. 异常记录（如有）

### 警告 #1
**类型**: 行数异常偏高
**说明**: DWD 层行数比昨日增长 45%（阈值 50%），需关注上游数据量变化

---

## 5. 下一步

- [ ] ✅ 正式执行成功，触发 scheduler-updater 配置调度任务
- [ ] ⏳ 观察 3 天，监控调度运行情况
- [ ] 如有数据问题，使用回滚方案恢复

**审计日志**: `LOG/prod_deploy_{需求编号}_{日期}.log`
```

### 回滚方案

如正式执行后发现问题需要回滚：

```bash
# 方案一：重新跑指定分区的 ETL（覆盖错误数据）
# 修正 SQL 后重新提交
ssh {gateway} "spark-submit \
  --class BatchSQLRunner \
  --master yarn \
  --deploy-mode cluster \
  --jars /opt/spark/jars/paimon-spark-3.5-1.3.1.jar \
  --conf spark.sql.catalog.paimon=org.apache.paimon.spark.SparkCatalog \
  --conf spark.sql.catalog.paimon.warehouse=hdfs:///paimon/warehouse \
  --conf spark.sql.extensions=org.apache.paimon.spark.extensions.PaimonSparkSessionExtensions \
  hdfs:///spark/jars/batch-sql-runner-1.0.jar \
  hdfs:///cx_dwd_safe/dwd/{修正后的_etl}.sql"

# 方案二：删除错误分区数据（谨慎操作）
ssh {gateway} "
spark-sql ... \
    --jars /opt/spark/jars/paimon-spark-3.5-1.3.1.jar \
    --conf spark.sql.catalog.paimon=org.apache.paimon.spark.SparkCatalog \
    --conf spark.sql.catalog.paimon.warehouse=hdfs:///paimon/warehouse \
    --conf spark.sql.extensions=org.apache.paimon.spark.extensions.PaimonSparkSessionExtensions \
    --master yarn --deploy-mode client \
     -e \
    'ALTER TABLE paimon.cx_dwd_safe.dwd_xxx \
     DROP PARTITION (dt=\"{错误的日期}\")'"

```

> **回滚必须人工确认**，不可自动执行。

## 与上下游 Skill 的衔接

| 模式 | 上游 | 下游 | 触发条件 | 传递内容 |
|------|------|------|---------|---------|
| **测试模式** | `sql-validator` | `git-merger` | EXPLAIN 验证通过后 | 测试报告 + SQL 文件列表 |
| **正式执行** | `git-merger` | `scheduler-updater` | 代码合并后 / 用户显式要求 | 正式执行报告 + 部署日志 |

**完整链路（双模式）**：
```
测试路径（开发阶段）:
  sql-validator → cluster-tester(测试) → git-merger(合并)

生产路径（上线阶段）:
  git-merger(合并完成) → cluster-tester(正式执行) → scheduler-updater(调度)
```

## 异常处理
- SSH 连接失败 → 提示检查 OpenClaw 配置或 SSH 密钥
- 执行超时 → 标记超时，建议优化 SQL 或增加资源
- 权限不足 → 提示检查 HDFS/Kerberos 权限
- 资源不足 → YARN 队列满，提示等待或调整队列
- DDL 冲突（表已存在） → 使用 CREATE TABLE IF NOT EXISTS 或先 DROP
- ETL 零行 → 警告，检查上游数据是否有数据

## 注意事项
- **⚠️ 本地无集群环境**：所有 SQL 通过 SSH/Gateway 提交到 YARN 集群执行，不能在本地跑
- **双模式**：
  - **测试模式**（默认）：`LIMIT 10000`、default 队列、600s 超时、自动回滚
  - **正式执行模式**：全量数据、production 队列、3600s 超时、不自动回滚
- **HDFS 目录规范**：DDL→`/cx_dwd_safe/ddl/`, DWD ETL→`/cx_dwd_safe/dwd/`, DWS ETL→`/cx_dws_safe/dws/`
- **测试库隔离**：所有测试按分层使用对应数据库（cx_dwd_safe/cx_dws_safe等）执行；正式执行使用生产队列
- **超时保护**：每条 SQL 设置超时，防止死锁或无限循环（正式模式更长）
- **回滚机制**：测试模式 DDL 失败时自动回滚；正式模式需人工确认后回滚
- **保留日志**：测试日志保存到 `LOG/cluster_test_{日期}.log`，正式执行日志到 `LOG/prod_deploy_{需求编号}_{日期}.log`
- **ODS 表名规范**：ODS 层表使用 `pingan_insurance_` 前缀，数据库为 `cx_ods_safe`
- **前置检查**：正式执行前必须检查 Git 分支已合并 + 上游分区就绪 + YARN 资源可用

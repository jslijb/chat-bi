-- =====================================================================
-- ETL 取数逻辑模板（INSERT OVERWRITE 幂等写入）
-- 适配: Spark SQL + Paimon 目标表
-- 规范依据: spark-sql-standards.md
--
-- ⚠️ 数据库/表名规范:
--   catalog: paimon （所有的 catalog 都是 paimon）
--   ODS层源表: paimon.cx_ods_safe.pingan_insurance_xxx (带前缀)
--   DWD层目标表: paimon.cx_dwd_safe.dwd_xxx
--   DWS层目标表: paimon.cx_dws_safe.dws_xxx
--   ADS层目标表: paimon.cx_ads_safe.ads_xxx
--   DIM层目标表: paimon.cx_dim_safe.dim_xxx
--   所有表均为 Paimon 格式
-- =====================================================================
-- 脚本名称: {script_name}
-- 目标表:   {target_database}.{target_table}
-- 数据来源: {source_description}
-- 功能描述: {description}
-- 执行频率: {frequency} (daily/weekly/monthly)
-- 耗时预估: {estimated_time}
-- 上游依赖: {upstream_tasks}
-- 下游影响: {downstream_consumers}
-- 作者:     AI Code Generator / {author}
-- 创建日期: {date}
-- 修改日志:
--   {date} - 初始版本, 需求来源: {requirement_id}
-- =====================================================================

-- ------------------- Spark 运行参数 -------------------
SET spark.sql.shuffle.partitions = 200;
SET spark.sql.autoBroadcastJoinThreshold = 10485760;  -- 10MB 以下小表自动广播
-- SET spark.sql.adaptive.enabled = true;             -- AQE 自适应查询（按需启用）
-- SET spark.sql.adaptive.coalescePartitions.enabled = true;

-- ------------------- 宏变量 -------------------
-- 运行日期（通过 spark-sql -d 传入, 或默认昨天）
SET biz_date = cast(
    DATE_FORMAT(DATE_SUB(CURRENT_DATE(), 1), 'yyyy-MM-dd') AS STRING
);

WITH
-- ============================================================
-- CTE 1: {cte1_name} — {cte1_description}
-- 数据源: {cte1_source_table}
-- ============================================================
{cte1_alias} AS (
    SELECT
        field1,
        field2,
        field3,
        "${biz_date}"  AS dt                          -- 统一携带分区字段
    FROM {catalog}.{source_database}.{source_table1}
    WHERE dt = "${biz_date}" 
      -- 过滤条件（保留有效数据）
      AND status IN ('1', '2')
),

-- ============================================================
-- CTE 2: {cte2_name} — {cte2_description}
-- 用途: {cte2_purpose}
-- ============================================================
{cte2_alias} AS (
    SELECT
        dim_key,
        dim_name,
        dim_type
    FROM {catalog}.{dim_database}.{dim_table}
    WHERE dt = "${biz_date}" 
),

-- ============================================================
-- CTE N: 聚合层 — 按粒度汇总指标
-- ============================================================
agg_result AS (
    SELECT
        -- 分组维度
        a.group_key1,
        b.dim_name                              AS dimension_name,

        -- 原子指标（带 NULL 保护）
        SUM(COALESCE(a.metric_value, 0))         AS total_metric,     -- 总量
        COUNT(DISTINCT a.unique_key)             AS distinct_cnt,     -- 去重计数
        AVG(COALESCE(a.metric_value, 0))         AS avg_metric,       -- 平均值
        MAX(a.metric_value)                      AS max_metric,       -- 最大值
        MIN(a.metric_value)                      AS min_metric        -- 最小值

    FROM {cte1_alias} a
    LEFT JOIN {cte2_alias} b
        ON a.foreign_key = b.dim_key            -- 外键关联（来自 fk_graph.json）

    GROUP BY
        a.group_key1,
        b.dim_name

    HAVING total_metric > 0                     -- 过滤空结果（可选）
)

-- ============================================================
-- 最终输出：SELECT → INSERT OVERWRITE 目标表分区
-- ============================================================
SELECT
    -- 业务主键
    group_key1,

    -- 维度字段
    dimension_name,

    -- 指标字段
    total_metric,
    distinct_cnt,
    avg_metric,
    max_metric,
    min_metric,

    -- 元数据字段
    dt                                           AS data_date,
    CURRENT_TIMESTAMP()                           AS etl_time

FROM agg_result
;

-- ------------------- 写入目标表（幂等覆盖） -------------------
INSERT OVERWRITE TABLE `{catalog}`.`{target_database}`.`{target_table}`
PARTITION (dt)
SELECT /*+ REPARTITION({output_partitions}) */
    <上述完整字段列表>
;

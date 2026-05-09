-- =====================================================================
-- DDL 建表模板（Paimon 表格式）
-- 适配: Spark 3.x + Paimon 数据湖
-- 规范依据: spark-sql-standards.md
--
-- ⚠️ 数据库/表名规范:
--   catalog: paimon （所有的 catalog 都是 paimon）
--   DWD层: paimon.cx_dwd_safe.dwd_xxx
--   DWS层: paimon.cx_dws_safe.dws_xxx
--   ADS层: paimon.cx_ads_safe.ads_xxx
--   DIM层: paimon.cx_dim_safe.dim_xxx
--   DWP层: paimon.cx_dwp_safe.adhoc_xxx
--   所有表均为 paimon 数据湖格式
-- =====================================================================
--
-- 使用说明:
--   1. 替换 {变量} 为实际值
--   2. ODS层表必须带 pingan_insurance_ 前缀
--   3. DWD/DWS/ADS 层表不带前缀
--   4. 分区字段不要写在字段列表中，放在 PARTITIONED BY， 分区字段需要有数据类型和备注
--   5. 删除不需要的注释块
--   6. TBLPROPERTIES 表属性，根据实际情况增减，这里主要说明主键表和非主键表
-- =====================================================================

-- 主键表
CREATE TABLE IF NOT EXISTS `{catalog}.{database}.{table_name}` (
    -- ==================== 主键 / 业务键 ====================
    `{pk_field1}`        {pk_type1}         COMMENT '{pk_comment1}',
    `{pk_field2}`        {pk_type2}         COMMENT '{pk_comment2}',

    -- ==================== 维度字段 ====================
    `{dim_field1}`       {dim_type1}         COMMENT '{dim_comment1}',
    `{dim_field2}`       {dim_type2}         COMMENT '{dim_comment2}',
    `{dim_field3}`       {dim_type3}         COMMENT '{dim_comment3}',

    -- ==================== 指标字段 ====================
    `{metric_field1}`    {metric_type1}      COMMENT '{metric_comment1}',
    `{metric_field2}`    {metric_type2}      COMMENT '{metric_comment2}',
    `{metric_field3}`    {metric_type3}      COMMENT '{metric_comment3}',

    -- ==================== 元数据字段（所有表必备） ====================
    `etl_time`           TIMESTAMP           COMMENT 'ETL处理时间',
    `data_date`          STRING              COMMENT '业务日期(yyyy-MM-dd)'
)
COMMENT '{table_comment}'
PARTITIONED BY (`{partition_field}` {partition_type} COMMENT '分区字段')
TBLPROPERTIES (
    'file.format' = 'parquet',
    'primary-key' = 'pk_field1' ,               -- 主键
    'bucket' = '2',                             -- 分桶数量
    'sink.parallelism' = '2',                   -- 并发数量，与分桶的数量保持一致
    'bucket-key' = 'pk_field1',                 -- 分桶健与主键相同
    'sink.commit-interval' = '5 min',           -- 对于流式数据每 5  分钟提交一次，对于批处理不起作用
    -- 'partition.expiration-time' = '30 d',     -- 按需启用分区过期清理
    -- 'write.buffer-size' = '256 mb',           -- Paimon 写入缓冲区
    'changelog-producer' = 'input'               -- 是否产生变更日志,主键表需要开启
);

-- 非主键表
CREATE TABLE IF NOT EXISTS `{catalog}.{database}.{table_name}` (
    -- ==================== 主键 / 业务键 ====================
    `{pk_field1}`        {pk_type1}         COMMENT '{pk_comment1}',
    `{pk_field2}`        {pk_type2}         COMMENT '{pk_comment2}',

    -- ==================== 维度字段 ====================
    `{dim_field1}`       {dim_type1}         COMMENT '{dim_comment1}',
    `{dim_field2}`       {dim_type2}         COMMENT '{dim_comment2}',
    `{dim_field3}`       {dim_type3}         COMMENT '{dim_comment3}',

    -- ==================== 指标字段 ====================
    `{metric_field1}`    {metric_type1}      COMMENT '{metric_comment1}',
    `{metric_field2}`    {metric_type2}      COMMENT '{metric_comment2}',
    `{metric_field3}`    {metric_type3}      COMMENT '{metric_comment3}',

    -- ==================== 元数据字段（所有表必备） ====================
    `etl_time`           TIMESTAMP           COMMENT 'ETL处理时间',
    `data_date`          STRING              COMMENT '业务日期(yyyy-MM-dd)'
)
COMMENT '{table_comment}'
PARTITIONED BY (`{partition_field}` {partition_type} COMMENT '分区字段')
TBLPROPERTIES (
    'file.format' = 'parquet',
    'bucket' = '2',                             -- 分桶数量
    'sink.parallelism' = '2',                   -- 并发数量，与分桶的数量保持一致
    'bucket-key' = 'pk_field1',                 -- 分桶健与主键相同
    'sink.commit-interval' = '5 min'            -- 对于流式数据每 5  分钟提交一次，对于批处理不起作用
    -- 'partition.expiration-time' = '30 d',     -- 按需启用分区过期清理
    -- 'write.buffer-size' = '256 mb',           -- Paimon 写入缓冲区
);
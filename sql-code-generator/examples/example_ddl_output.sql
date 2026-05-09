-- =====================================================================
-- 表名: dws_policy_premium_daily
-- 数据库: cx_dws_safe
-- 分层: DWS (数据仓库汇总层 - 按天汇总)
-- 功能描述: 渠道保费日汇总宽表，按渠道+产品维度聚合保单保费数据
-- 表格式: Paimon (数据湖表)
-- 作者: AI Code Generator
-- 创建日期: 2026-04-23
-- 修改日志:
--   2026-04-23 - 初始版本, 需求来源: REQ-2026-Q1-042
-- =====================================================================

CREATE TABLE IF NOT EXISTS `paimon`.`cx_dws_safe`.`dws_policy_premium_daily` (
    -- ==================== 主键 / 业务键 ====================
    `policy_no`          BIGINT              COMMENT '保单唯一标识(来自ODS主键)',

    -- ==================== 维度字段 ====================
    `channel_code`       STRING              COMMENT '渠道编码(关联dim_channel)',
    `product_code`       STRING              COMMENT '产品编码(关联dim_product)',
    `policy_status`      STRING              COMMENT '保单状态: 1-有效 2-已失效 3-已退保',
    `insured_age`        INT                 COMMENT '被保险人年龄(岁)',
    `region_code`        STRING              COMMENT '地区编码(关联dim_region)',

    -- ==================== 指标字段 ====================
    `total_premium`      DECIMAL(18,2)       COMMENT '保费总额(元, SUM聚合)',
    `policy_count`       BIGINT              COMMENT '保单件数(COUNT DISTINCT)',
    `avg_premium`        DECIMAL(18,2)       COMMENT '件均保费(元, 总额/件数)',
    `new_policy_count`   BIGINT              COMMENT '新单件数(当日新生效)',
    `renewal_count`      BIGINT              COMMENT '续保件数',

    -- ==================== 元数据字段 ====================
    `etl_time`           TIMESTAMP           COMMENT 'ETL处理时间'
)
COMMENT '渠道保费日汇总表(DWS层)'
PARTITIONED BY (`part_dt` string COMMENT '分区日期')
TBLPROPERTIES (
    'primary-key' = 'policy_no',
    'bucket' = '2',
    'bucket-key' = 'policy_no',
    'changelog-producer' = 'input',
    'sink.parallelism' = '2',
    'sink.commit-interval' = '5 min',
    'file.format' = 'orc'
);

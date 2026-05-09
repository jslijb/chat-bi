-- =====================================================================
-- 报表查询 / 临时取数模板
-- 适配: Spark SQL / Hive SQL
-- 规范依据: spark-sql-standards.md
-- =====================================================================
-- 查询目的: {purpose}
-- 请求人:   {requester}
-- 请求时间: {request_date}
-- 数据范围: {start_date} ~ {end_date}
-- 缓存指纹: md5(query) 用于临时取数去重
-- =====================================================================

-- 参数说明（如有宏替换）:
--   @start_date: 开始日期 (格式: yyyy-MM-dd)
--   @end_date:   结束日期 (格式: yyyy-MM-dd)
--   @top_n:      返回行数限制 (默认: 1000)

WITH
-- ============================================================
-- 主数据：从 DWS/ADS 层获取聚合数据
-- ============================================================
main_data AS (
    SELECT
        dt                                   AS stat_date,           -- 统计日期
        channel_code                         AS channel_id,          -- 渠道编码
        channel_name                         AS channel_name,        -- 渠道名称

        -- 核心指标
        SUM(total_amount)                    AS total_amount_元,      -- 总金额
        COUNT(DISTINCT order_no)             AS order_count_单数,     -- 订单数
        ROUND(SUM(total_amount) / NULLIF(COUNT(DISTINCT order_no), 0), 2)
                                             AS avg_amount_元,        -- 件均/均值

        -- 同比（YoY）
        LAG(SUM(total_amount), 12) OVER (
            PARTITION BY channel_code
            ORDER BY dt
        )                                    AS same_period_last_year_元,

        -- 环比（MoM）
        LAG(SUM(total_amount), 1) OVER (
            PARTITION BY channel_code
            ORDER BY dt
        )                                    AS last_period_元,

        -- 同比增长率
        CASE
            WHEN LAG(SUM(total_amount), 12) OVER (
                PARTITION BY channel_code ORDER BY dt
            ) != 0 THEN
                ROUND((SUM(total_amount) - LAG(SUM(total_amount), 12) OVER (
                    PARTITION BY channel_code ORDER BY dt
                )) * 100.0 /
                LAG(SUM(total_amount), 12) OVER (
                    PARTITION BY channel_code ORDER BY dt
                ), 2)
            ELSE NULL
        END                                  AS yoy_growth_pct

    FROM paimon.cx_ads_safe.{ads_table_name}

    WHERE dt BETWEEN DATE('{start_date}') AND DATE('{end_date}')

    GROUP BY
        dt,
        channel_code,
        channel_name
)

-- ============================================================
-- 最终输出
-- ============================================================
SELECT
    DATE_FORMAT('yyyy-MM-dd', stat_date)     AS 日期,
    channel_name                             AS 渠道名称,

    -- 当期
    total_amount_元                          AS 当期金额_元,
    order_count_单数                         AS 当期订单数,
    avg_amount_元                            AS 件均金额_元,

    -- 对比
    last_period_元                           AS 上期金额_元,
    same_period_last_year_元                 as 去年同期_元,
    yoy_growth_pct                          AS 同比增长_%,
    ROUND(
        (total_amount_元 - COALESCE(last_period_元, 0))
        / NULLIF(COALESCE(last_period_元, 0), 0) * 100, 2
    )                                       AS 环比增长_%

FROM main_data
WHERE total_amount_元 > 0                   -- 排除零值

ORDER BY stat_date DESC, total_amount_元 DESC

LIMIT {top_n:-1000}
;

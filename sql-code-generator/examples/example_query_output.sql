-- =====================================================================
-- 查询目的: 各渠道月度保费趋势分析（近6个月）
-- 请求人:   业务运营部-张三
-- 请求时间: 2026-04-23
-- 数据范围: 2025-11-01 ~ 2026-04-22
-- 缓存指纹: a3f8c2b1e4d7 (md5 of query intent for adhoc cache)
-- =====================================================================

WITH
-- ============================================================--
-- 月度聚合：按渠道+月份汇总保费
-- ============================================================
monthly_data AS (
    SELECT
        SUBSTR(dt, 1, 7)                     AS month_key,          -- 年月(yyyy-MM)
        dc.channel_name                       AS channel_name,      -- 渠道名称
        dc.channel_type                       AS channel_type,      -- 渠道类型

        -- 核心指标
        SUM(f.total_premium)                  AS total_premium_yuan,   -- 月保费总额（单位元）
        COUNT(DISTINCT f.policy_id)           AS policy_cnt_件,      -- 月保单件数
        ROUND(SUM(f.total_premium) / NULLIF(COUNT(DISTINCT f.policy_id), 0), 2)
                                              AS avg_per_policy_元,  -- 件均保费
        SUM(f.new_policy_count)               AS new_policy_cnt_件,  -- 新单数
        SUM(f.renewal_count)                  AS renewal_cnt_件,     -- 续保数

        -- 同环比参考值
        LAG(SUM(f.total_premium), 1) OVER (
            PARTITION BY f.channel_code
                ORDER BY SUBSTR(dt, 1, 7)
        )                                     AS last_month_元,      -- 上月同期
        LAG(SUM(f.total_premium), 12) OVER (
            PARTITION BY f.channel_code
                ORDER BY SUBSTR(dt, 1, 7)
        )                                     AS last_year_same_元   -- 去年同月

    FROM paimon.cx_dws_safe.dws_policy_premium_daily f
    INNER JOIN paimon.cx_dim_safe.dim_channel dc
        ON f.channel_code = dc.channel_code

    WHERE dt >= '2025-11-01' AND dt < '2026-05-01'

    GROUP BY
        SUBSTR(dt, 1, 7),
        dc.channel_name,
        dc.channel_type,
        f.channel_code                        -- 用于窗口函数分区
)

-- ============================================================
-- 最终输出：含增长率 + 排名
-- ============================================================
SELECT
    month_key                                AS 统计月份,
    channel_name                             AS 渠道名称,
    channel_type                             AS 渠道类型,

    -- 当期核心指标
    total_premium_yuan                       AS 本期保费_元,
    policy_cnt_件                            AS 本期保单数,
    avg_per_policy_元                        AS 本期件均_元,
    new_policy_cnt_件                        AS 新单数,
    renewal_cnt_件                           AS 续保数,

    -- 环比 (vs上月)
    last_month_元                            AS 上月保费_元,
    ROUND((total_premium_yuan - COALESCE(last_month_元, 0))
        * 100.0 / NULLIF(COALESCE(last_month_元, 0), 0), 2)  AS 环比增长_%,

    -- 同比 (vs去年同月)
    last_year_same_元                        AS 去年同月保费_元,
    ROUND((total_premium_yuan - COALESCE(last_year_same_元, 0))
        * 100.0 / NULLIF(COALESCE(last_year_same_元, 0), 0), 2) AS 同比增长_%,

    -- 月度排名(按保费降序)
    RANK() OVER (
        PARTITION BY month_key
        ORDER BY total_premium_yuan DESC
    )                                         AS 月内排名

FROM monthly_data
WHERE total_premium_yuan > 0                   -- 排除零值

ORDER BY month_key DESC, 本期保费_元 DESC;

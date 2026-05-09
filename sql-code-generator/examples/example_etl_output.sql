-- =====================================================================
-- 脚本名称: etl_dws_policy_premium_daily.sql
-- 目标表:   cx_dws_safe.dws_policy_premium_daily
-- 数据来源: ODS层(cx_ods_safe)保单明细 + 维度表(渠道/产品/地区)
-- 功能描述: 每日从ODS层抽取保单基础信息与保费记录，按渠道+产品维度
--            聚合为DWS层日汇总宽表
-- 执行频率: daily (每日 T+1 02:00)
-- 耗时预估: ~15 min (约 5000万行源数据)
-- 上游依赖: cx_ods_safe.pingan_insurance_policy_master / cx_ods_safe.pingan_insurance_premium_payment (T日分区就绪)
-- 下游影响: ads_channel_premium_report / ads_product_rank_analysis
-- 作者:     AI Code Generator
-- 创建日期: 2026-04-23
-- 修改日志:
--   2026-04-23 - 初始版本, 需求来源: REQ-2026-Q1-042
-- =====================================================================

-- ------------------- Spark 运行参数 -------------------
SET spark.sql.shuffle.partitions = 200;
SET spark.sql.autoBroadcastJoinThreshold = 10485760;

-- ------------------- 宏变量 -------------------
SET biz_date = cast(
    DATE_FORMAT(DATE_SUB(CURRENT_DATE(), 1), 'yyyy-MM-dd') AS STRING
);

WITH
-- ============================================================
-- CTE 1: source_policy — 当日有效保单基础信息
-- 数据源: cx_ods_safe.pingan_insurance_policy_master (全量快照)
-- 过滤: 只取状态为 有效(1)/已续保(2) 的保单
-- ============================================================
source_policy AS (
    SELECT
        policy_no,
        channel,
        product_code,
        policy_status,
        effective_date,
        "${biz_date}" AS dt
    FROM paimon.cx_ods_safe.pingan_insurance_policy_master
    WHERE cast(create_time as date) = cast("${biz_date}" as date)
      AND policy_status IN ('1', '2')       -- 仅保留有效和已续保状态
),

-- ============================================================
-- CTE 2: dim_channel — 渠道维度表（最新全量）
-- 用途: 将 channel_code 翻译为可读的渠道名称
-- ============================================================
dim_channel AS (
    SELECT
        channel_code,
        channel_name,
        channel_type,                        -- 直销/代理/经纪/电销/网销
        is_active                            -- 渠道是否营业中
    FROM paimon.cx_dim_safe.dim_channel
    WHERE dt = "${biz_date}"
      AND is_active = '1'
),

-- ============================================================
-- CTE 3: premium_agg — 保单级别保费聚合
-- 来源: cx_ods_safe.pingan_insurance_premium_payment (交费流水)
-- 聚合粒度: policy_no → 每张保单的总保费/交费笔数/最新交费日期
-- ============================================================
premium_agg AS (
    SELECT
        policy_no,
        SUM(COALESCE(amount, 0))     AS total_premium,     -- 累交保费总额
        COUNT(*)                             AS txn_count,         -- 交费笔数
        MAX(payment_time)                    AS last_premium_date,  -- 最近交费日期
        MIN(payment_time)                    AS first_premium_date -- 首次交费日期
    FROM paimon.cx_ods_safe.pingan_insurance_premium_payment
    WHERE cast(create_time as date) = cast("${biz_date}" as date)
      AND status = '1'               -- 已缴费状态
    GROUP BY policy_no
)

-- ============================================================
-- 最终输出：宽表 SELECT → INSERT OVERWRITE
-- ============================================================

-- ------------------- 写入目标表（幂等覆盖当日分区） -------------------
INSERT OVERWRITE TABLE `paimon`.`cx_dws_safe`.`dws_policy_premium_daily`
PARTITION (dt)
SELECT /*+ REPARTITION(2) */
    sp.policy_no,

    -- 维度字段
    sp.channel,
    sp.product_code,
    sp.policy_status,
    -- 指标字段
    COALESCE(pa.total_premium, 0)           AS total_premium,
    1                                        AS policy_count,      -- 每行=1件
    COALESCE(pa.total_premium, 0)           AS avg_premium,         -- 单保单层级即件均
    CASE WHEN DATEDIFF(
            TO_DATE("${biz_date}",'yyyy-MM-dd'),
            TO_DATE(sp.effective_date, 'yyyy-MM-dd')
        ) <= 7 THEN 1 ELSE 0 END             AS new_policy_count,    -- 生效7天内为新单
    CASE WHEN pa.txn_count >= 2 THEN 1 ELSE 0 END  AS renewal_count,  -- 多笔缴费视为续保

    -- 元数据字段
    dt                                       AS data_date,
    CURRENT_TIMESTAMP()                       AS etl_time

FROM source_policy sp
INNER JOIN dim_channel dc                      -- 必须有有效渠道
    ON sp.channel = dc.channel
LEFT JOIN premium_agg pa                       -- 可能有保单但无交费记录
    ON sp.policy_no = pa.policy_no

WHERE pa.total_premium > 0                    -- 排除零保费异常数据

;
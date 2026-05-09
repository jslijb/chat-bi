-- ============================================================
-- 平安产险数据湖 - B端7个需求验证SQL
-- 数据库: pingan_insurance
-- 生成日期: 2026-04-27
-- 说明: 每个需求包含数据完整性检查 + 核心指标验证SQL
-- ============================================================

USE `pingan_insurance`;

-- ============================================================
-- B-REQ-001 企业客户健康度评分及流失风险
-- 验证逻辑: 按企业统计总保费、员工数、活跃天数、风控评分，综合判定健康度等级
-- 健康度等级 = 基于保费+活跃度+风控评分的综合判定(S/A/B/C/D)
-- ============================================================

-- 1.1 数据完整性检查
SELECT 'B-REQ-001 数据完整性' AS check_type,
       'enterprise' AS tbl, COUNT(*) AS cnt FROM enterprise
UNION ALL
SELECT '', 'enterprise_policy', COUNT(*) FROM enterprise_policy
UNION ALL
SELECT '', 'enterprise_user', COUNT(*) FROM enterprise_user
UNION ALL
SELECT '', 'policy_master(企业保单)', COUNT(*) FROM policy_master pm
    INNER JOIN enterprise_policy ep ON pm.policy_no = ep.policy_no
UNION ALL
SELECT '', 'enterprise_risk_assessment', COUNT(*) FROM enterprise_risk_assessment;

-- 1.2 按企业统计健康度评分及流失风险
WITH enterprise_premium AS (
    SELECT ep.enterprise_id,
           SUM(pm.premium_total) AS total_premium_fen,
           COUNT(DISTINCT ep.policy_no) AS policy_count
    FROM enterprise_policy ep
    INNER JOIN policy_master pm ON ep.policy_no = pm.policy_no AND pm.is_deleted = 0
    GROUP BY ep.enterprise_id
),
enterprise_employee AS (
    SELECT enterprise_id,
           COUNT(*) AS employee_count,
           SUM(CASE WHEN is_active = 1 THEN 1 ELSE 0 END) AS active_employee_count
    FROM enterprise_user
    GROUP BY enterprise_id
),
enterprise_active_days AS (
    SELECT eu.enterprise_id,
           COUNT(DISTINCT DATE(ubl.event_time)) AS active_days_90d
    FROM enterprise_user eu
    INNER JOIN user_behavior_log ubl ON eu.user_id = ubl.user_id
    WHERE ubl.event_name = 'login'
      AND ubl.event_time >= DATE_SUB(CURDATE(), INTERVAL 90 DAY)
    GROUP BY eu.enterprise_id
),
enterprise_risk AS (
    SELECT enterprise_id,
           AVG(risk_score) AS avg_risk_score
    FROM enterprise_risk_assessment
    GROUP BY enterprise_id
),
health_score_base AS (
    SELECT e.enterprise_id,
           e.enterprise_name,
           IFNULL(ep.total_premium_fen, 0) AS total_premium_fen,
           IFNULL(ep.policy_count, 0) AS policy_count,
           IFNULL(ee.employee_count, 0) AS employee_count,
           IFNULL(ee.active_employee_count, 0) AS active_employee_count,
           IFNULL(ead.active_days_90d, 0) AS active_days_90d,
           IFNULL(er.avg_risk_score, 0) AS avg_risk_score,
           ROUND(IFNULL(ee.active_employee_count, 0) * 100.0
                 / NULLIF(IFNULL(ee.employee_count, 0), 0), 2) AS employee_active_rate_pct,
           ROUND(IFNULL(ep.total_premium_fen, 0) * 1.0
                 / NULLIF(IFNULL(ee.employee_count, 0), 0), 0) AS per_capita_premium_fen
    FROM enterprise e
    LEFT JOIN enterprise_premium ep ON e.enterprise_id = ep.enterprise_id
    LEFT JOIN enterprise_employee ee ON e.enterprise_id = ee.enterprise_id
    LEFT JOIN enterprise_active_days ead ON e.enterprise_id = ead.enterprise_id
    LEFT JOIN enterprise_risk er ON e.enterprise_id = er.enterprise_id
    WHERE e.is_deleted = 0
),
health_grade AS (
    SELECT enterprise_id,
           enterprise_name,
           total_premium_fen,
           policy_count,
           employee_count,
           active_employee_count,
           active_days_90d,
           avg_risk_score,
           employee_active_rate_pct,
           per_capita_premium_fen,
           CASE
               WHEN total_premium_fen >= 10000000
                    AND employee_active_rate_pct >= 70
                    AND avg_risk_score >= 80 THEN 'S'
               WHEN total_premium_fen >= 5000000
                    AND employee_active_rate_pct >= 50
                    AND avg_risk_score >= 60 THEN 'A'
               WHEN total_premium_fen >= 2000000
                    AND employee_active_rate_pct >= 30
                    AND avg_risk_score >= 40 THEN 'B'
               WHEN total_premium_fen >= 500000
                    AND employee_active_rate_pct >= 15 THEN 'C'
               ELSE 'D'
           END AS health_level,
           CASE
               WHEN employee_active_rate_pct < 15
                    AND active_days_90d < 7 THEN '高流失风险'
               WHEN employee_active_rate_pct < 30
                    AND active_days_90d < 15 THEN '中流失风险'
               ELSE '低流失风险'
           END AS churn_risk
    FROM health_score_base
)
SELECT enterprise_id,
       enterprise_name,
       health_level,
       churn_risk,
       total_premium_fen,
       policy_count,
       employee_count,
       active_employee_count,
       employee_active_rate_pct,
       active_days_90d,
       avg_risk_score,
       per_capita_premium_fen
FROM health_grade
ORDER BY health_level, churn_risk DESC, total_premium_fen DESC;

-- ============================================================
-- B-REQ-002 商家履约准时率实时监控
-- 验证逻辑: 按service_type和merchant_id统计准时率
-- 准时率 = COUNT(准时完成) / COUNT(总订单)
-- 准时规则: 代驾接单≤60秒，救援到达≤30分钟，洗车到店≤2小时
-- 平均响应时长 = AVG(complete_time - create_time)
-- ============================================================

-- 2.1 数据完整性检查
SELECT 'B-REQ-002 数据完整性' AS check_type,
       'merchant' AS tbl, COUNT(*) AS cnt FROM merchant
UNION ALL
SELECT '', 'merchant_score', COUNT(*) FROM merchant_score
UNION ALL
SELECT '', 'service_order', COUNT(*) FROM service_order;

-- 2.2 按服务类型和商家统计准时率
WITH order_response AS (
    SELECT so.order_id,
           so.merchant_id,
           so.service_type,
           so.order_status,
           so.create_time,
           so.complete_time,
           TIMESTAMPDIFF(SECOND, so.create_time, so.complete_time) AS response_seconds,
           CASE so.service_type
               WHEN 4 THEN CASE
                   WHEN TIMESTAMPDIFF(SECOND, so.create_time, so.complete_time) <= 60 THEN 1
                   ELSE 0
               END
               WHEN 1 THEN CASE
                   WHEN TIMESTAMPDIFF(MINUTE, so.create_time, so.complete_time) <= 120 THEN 1
                   ELSE 0
               END
               WHEN 3 THEN CASE
                   WHEN TIMESTAMPDIFF(MINUTE, so.create_time, so.complete_time) <= 120 THEN 1
                   ELSE 0
               END
               ELSE CASE
                   WHEN TIMESTAMPDIFF(MINUTE, so.create_time, so.complete_time) <= 30 THEN 1
                   ELSE 0
               END
           END AS is_on_time,
           CASE so.service_type
               WHEN 1 THEN '加油'
               WHEN 3 THEN '洗车'
               WHEN 4 THEN '代驾'
               WHEN 5 THEN '保养'
               ELSE '其他'
           END AS service_type_name
    FROM service_order so
    WHERE so.order_status IN (3, 4)
),
merchant_base AS (
    SELECT m.merchant_id,
           m.merchant_name,
           m.merchant_type
    FROM merchant m
    WHERE m.is_deleted = 0
)
SELECT mb.merchant_id,
       mb.merchant_name,
       or2.service_type_name,
       COUNT(*) AS total_orders,
       SUM(or2.is_on_time) AS on_time_orders,
       ROUND(SUM(or2.is_on_time) * 100.0 / NULLIF(COUNT(*), 0), 2) AS on_time_rate_pct,
       ROUND(AVG(or2.response_seconds), 0) AS avg_response_seconds,
       ROUND(AVG(or2.response_seconds) / 60.0, 2) AS avg_response_minutes
FROM order_response or2
INNER JOIN merchant_base mb ON or2.merchant_id = mb.merchant_id
GROUP BY mb.merchant_id, mb.merchant_name, or2.service_type_name
ORDER BY or2.service_type_name, on_time_rate_pct DESC;

-- ============================================================
-- B-REQ-003 商家评分与服务质量相关性
-- 验证逻辑: 按score_level分组统计履约率、客诉率、平均用户评分
-- 履约率 = COUNT(order_status=4) / COUNT(总订单)（排除用户取消order_status=5）
-- 客诉率 = COUNT(merchant_complaint) / COUNT(service_order)
-- 平均用户评分 = AVG(merchant_score.avg_rating)
-- ============================================================

-- 3.1 数据完整性检查
SELECT 'B-REQ-003 数据完整性' AS check_type,
       'merchant' AS tbl, COUNT(*) AS cnt FROM merchant
UNION ALL
SELECT '', 'merchant_score', COUNT(*) FROM merchant_score
UNION ALL
SELECT '', 'merchant_complaint', COUNT(*) FROM merchant_complaint
UNION ALL
SELECT '', 'service_order', COUNT(*) FROM service_order;

-- 3.2 按评分等级统计商家服务质量相关性
WITH merchant_quality AS (
    SELECT m.merchant_id,
           m.merchant_name,
           ms.score_level,
           ms.avg_rating
    FROM merchant m
    INNER JOIN merchant_score ms ON m.merchant_id = ms.merchant_id
    WHERE m.is_deleted = 0
),
order_fulfill AS (
    SELECT so.merchant_id,
           COUNT(*) AS total_orders_excl_cancel,
           SUM(CASE WHEN so.order_status = 4 THEN 1 ELSE 0 END) AS fulfilled_orders,
           SUM(CASE WHEN so.order_status = 3 THEN 1 ELSE 0 END) AS in_progress_orders
    FROM service_order so
    WHERE so.order_status != 5
    GROUP BY so.merchant_id
),
complaint_base AS (
    SELECT mc.merchant_id,
           COUNT(*) AS complaint_count
    FROM merchant_complaint mc
    GROUP BY mc.merchant_id
),
order_total_base AS (
    SELECT merchant_id,
           COUNT(*) AS all_order_count
    FROM service_order
    GROUP BY merchant_id
)
SELECT mq.score_level,
       COUNT(DISTINCT mq.merchant_id) AS merchant_count,
       ROUND(AVG(mq.avg_rating), 2) AS avg_user_rating,
       ROUND(SUM(IFNULL(of2.fulfilled_orders, 0)) * 100.0
             / NULLIF(SUM(IFNULL(of2.total_orders_excl_cancel, 0)), 0), 2) AS fulfill_rate_pct,
       ROUND(SUM(IFNULL(cb.complaint_count, 0)) * 100.0
             / NULLIF(SUM(IFNULL(ot.all_order_count, 0)), 0), 2) AS complaint_rate_pct,
       ROUND(SUM(IFNULL(of2.fulfilled_orders, 0)) * 1.0
             / NULLIF(COUNT(DISTINCT mq.merchant_id), 0), 2) AS avg_fulfilled_per_merchant,
       ROUND(SUM(IFNULL(cb.complaint_count, 0)) * 1.0
             / NULLIF(COUNT(DISTINCT mq.merchant_id), 0), 2) AS avg_complaint_per_merchant
FROM merchant_quality mq
LEFT JOIN order_fulfill of2 ON mq.merchant_id = of2.merchant_id
LEFT JOIN complaint_base cb ON mq.merchant_id = cb.merchant_id
LEFT JOIN order_total_base ot ON mq.merchant_id = ot.merchant_id
GROUP BY mq.score_level
ORDER BY mq.score_level;

-- ============================================================
-- B-REQ-004 代理人效能指标
-- 验证逻辑: 按季度和职级统计代理人效能
-- 季度总保费 = SUM(agent_performance.premium_total)
-- 季度总佣金 = SUM(agent_performance.commission_total)
-- 人均客单价 = 总保费 / 客户数
-- 客户续保率、理赔率
-- ============================================================

-- 4.1 数据完整性检查
SELECT 'B-REQ-004 数据完整性' AS check_type,
       'agent' AS tbl, COUNT(*) AS cnt FROM agent
UNION ALL
SELECT '', 'agent_performance', COUNT(*) FROM agent_performance
UNION ALL
SELECT '', 'agent_customer', COUNT(*) FROM agent_customer
UNION ALL
SELECT '', 'policy_master', COUNT(*) FROM policy_master;

-- 4.2 按季度和职级统计代理人效能指标
WITH agent_info AS (
    SELECT a.agent_id,
           a.agent_name,
           a.level AS agent_level,
           CASE a.level
               WHEN 1 THEN '普通'
               WHEN 2 THEN '主管'
               WHEN 3 THEN '经理'
               ELSE '其他'
           END AS level_name
    FROM agent a
    WHERE a.is_deleted = 0
),
perf_quarter AS (
    SELECT ap.agent_id,
           CONCAT(YEAR(ap.stat_date), 'Q', QUARTER(ap.stat_date)) AS stat_quarter,
           ap.premium_total,
           ap.commission_total,
           ap.new_policy_count,
           ap.renewal_count
    FROM agent_performance ap
),
customer_base AS (
    SELECT ac.agent_id,
           COUNT(DISTINCT ac.user_id) AS customer_count,
           SUM(CASE WHEN ac.is_renewed = 1 THEN 1 ELSE 0 END) AS renewed_customer_count,
           SUM(CASE WHEN ac.has_claim = 1 THEN 1 ELSE 0 END) AS claim_customer_count
    FROM agent_customer ac
    GROUP BY ac.agent_id
),
quarter_agg AS (
    SELECT ai.agent_id,
           ai.agent_level,
           ai.level_name,
           pq.stat_quarter,
           SUM(pq.premium_total) AS quarter_premium_fen,
           SUM(pq.commission_total) AS quarter_commission_fen,
           SUM(pq.new_policy_count) AS quarter_new_policies,
           SUM(pq.renewal_count) AS quarter_renewals
    FROM agent_info ai
    INNER JOIN perf_quarter pq ON ai.agent_id = pq.agent_id
    GROUP BY ai.agent_id, ai.agent_level, ai.level_name, pq.stat_quarter
)
SELECT qa.stat_quarter,
       qa.level_name,
       COUNT(DISTINCT qa.agent_id) AS agent_count,
       ROUND(SUM(qa.quarter_premium_fen) / 100.0, 2) AS total_premium_yuan,
       ROUND(SUM(qa.quarter_commission_fen) / 100.0, 2) AS total_commission_yuan,
       ROUND(AVG(qa.quarter_premium_fen), 0) AS avg_premium_per_agent_fen,
       ROUND(AVG(qa.quarter_commission_fen), 0) AS avg_commission_per_agent_fen,
       SUM(qa.quarter_new_policies) AS total_new_policies,
       SUM(qa.quarter_renewals) AS total_renewals,
       ROUND(SUM(qa.quarter_renewals) * 100.0
             / NULLIF(SUM(qa.quarter_new_policies) + SUM(qa.quarter_renewals), 0), 2) AS renewal_rate_pct,
       ROUND(SUM(qa.quarter_premium_fen) * 1.0
             / NULLIF(SUM(IFNULL(cb.customer_count, 0)), 0), 0) AS per_capita_premium_fen,
       ROUND(SUM(IFNULL(cb.renewed_customer_count, 0)) * 100.0
             / NULLIF(SUM(IFNULL(cb.customer_count, 0)), 0), 2) AS customer_renewal_rate_pct,
       ROUND(SUM(IFNULL(cb.claim_customer_count, 0)) * 100.0
             / NULLIF(SUM(IFNULL(cb.customer_count, 0)), 0), 2) AS customer_claim_rate_pct
FROM quarter_agg qa
LEFT JOIN customer_base cb ON qa.agent_id = cb.agent_id
GROUP BY qa.stat_quarter, qa.level_name
ORDER BY qa.stat_quarter, qa.agent_level;

-- ============================================================
-- B-REQ-005 企业客户风控服务ROI
-- 验证逻辑: 对比接受预警vs未接受预警的企业出险率和赔付金额
-- 有预警企业 = 在disaster_warning中有记录的enterprise_id
-- 无预警企业 = 不在disaster_warning中的enterprise_id
-- 出险率 = COUNT(有理赔企业) / COUNT(总企业)
-- 平均赔付金额 = AVG(claim_payment.amount)
-- ============================================================

-- 5.1 数据完整性检查
SELECT 'B-REQ-005 数据完整性' AS check_type,
       'enterprise' AS tbl, COUNT(*) AS cnt FROM enterprise
UNION ALL
SELECT '', 'disaster_warning', COUNT(*) FROM disaster_warning
UNION ALL
SELECT '', 'enterprise_claim', COUNT(*) FROM enterprise_claim
UNION ALL
SELECT '', 'claim_report', COUNT(*) FROM claim_report;

-- 5.2 对比有预警vs无预警企业的风控ROI
WITH warned_enterprise AS (
    SELECT DISTINCT enterprise_id
    FROM disaster_warning
),
enterprise_type_base AS (
    SELECT e.enterprise_id,
           e.enterprise_name,
           CASE WHEN we.enterprise_id IS NOT NULL THEN '有预警' ELSE '无预警' END AS warn_type
    FROM enterprise e
    LEFT JOIN warned_enterprise we ON e.enterprise_id = we.enterprise_id
    WHERE e.is_deleted = 0
),
claim_enterprise AS (
    SELECT etb.warn_type,
           etb.enterprise_id,
           COUNT(DISTINCT ec.claim_no) AS claim_count
    FROM enterprise_type_base etb
    LEFT JOIN enterprise_claim ec ON etb.enterprise_id = ec.enterprise_id
    GROUP BY etb.warn_type, etb.enterprise_id
),
claim_payment_base AS (
    SELECT ec.enterprise_id,
           SUM(cr.claim_amount) AS total_claim_amount_fen,
           AVG(cr.claim_amount) AS avg_claim_amount_fen
    FROM enterprise_claim ec
    INNER JOIN claim_report cr ON ec.claim_no = cr.claim_no AND cr.is_deleted = 0
    GROUP BY ec.enterprise_id
),
warning_cost AS (
    SELECT dw.enterprise_id,
           COUNT(*) AS warning_count
    FROM disaster_warning dw
    GROUP BY dw.enterprise_id
)
SELECT etb.warn_type,
       COUNT(DISTINCT etb.enterprise_id) AS enterprise_count,
       SUM(CASE WHEN ce.claim_count > 0 THEN 1 ELSE 0 END) AS enterprises_with_claim,
       ROUND(SUM(CASE WHEN ce.claim_count > 0 THEN 1 ELSE 0 END) * 100.0
             / NULLIF(COUNT(DISTINCT etb.enterprise_id), 0), 2) AS claim_rate_pct,
       ROUND(AVG(IFNULL(ce.claim_count, 0)), 2) AS avg_claims_per_enterprise,
       ROUND(AVG(IFNULL(cpb.total_claim_amount_fen, 0)), 0) AS avg_total_claim_fen,
       ROUND(AVG(IFNULL(cpb.avg_claim_amount_fen, 0)), 0) AS avg_per_claim_fen,
       ROUND(SUM(IFNULL(wc.warning_count, 0)), 0) AS total_warning_count,
       ROUND(AVG(IFNULL(wc.warning_count, 0)), 2) AS avg_warning_per_enterprise
FROM enterprise_type_base etb
LEFT JOIN claim_enterprise ce ON etb.enterprise_id = ce.enterprise_id AND etb.warn_type = ce.warn_type
LEFT JOIN claim_payment_base cpb ON etb.enterprise_id = cpb.enterprise_id
LEFT JOIN warning_cost wc ON etb.enterprise_id = wc.enterprise_id
GROUP BY etb.warn_type
ORDER BY etb.warn_type;

-- ============================================================
-- B-REQ-006 洗车店重洗率及额外成本
-- 验证逻辑: 按洗车店统计重洗率和额外成本
-- 重洗率 = COUNT(service_guarantee where guarantee_type='洗车重洗') / COUNT(洗车订单)
-- 额外成本 = SUM(service_guarantee.compensation_amount)
-- ============================================================

-- 6.1 数据完整性检查
SELECT 'B-REQ-006 数据完整性' AS check_type,
       'service_order(洗车)' AS tbl, COUNT(*) AS cnt
FROM service_order WHERE service_type = 3
UNION ALL
SELECT '', 'car_wash_order', COUNT(*) FROM car_wash_order
UNION ALL
SELECT '', 'service_guarantee(洗车)', COUNT(*) FROM service_guarantee
    WHERE guarantee_type = '洗车重洗';

-- 6.2 按洗车店统计重洗率及额外成本
WITH wash_orders AS (
    SELECT so.order_id,
           so.merchant_id,
           so.order_status,
           cwo.wash_type,
           cwo.car_model
    FROM service_order so
    INNER JOIN car_wash_order cwo ON so.order_id = cwo.order_id
    WHERE so.service_type = 3
),
rewash_base AS (
    SELECT sg.order_id,
           sg.merchant_id,
           sg.compensation_amount
    FROM service_guarantee sg
    WHERE sg.guarantee_type = '洗车重洗'
),
merchant_info AS (
    SELECT m.merchant_id,
           m.merchant_name
    FROM merchant m
    WHERE m.merchant_type = 2
      AND m.is_deleted = 0
)
SELECT mi.merchant_id,
       mi.merchant_name,
       COUNT(DISTINCT wo.order_id) AS total_wash_orders,
       COUNT(DISTINCT rb.order_id) AS rewash_orders,
       ROUND(COUNT(DISTINCT rb.order_id) * 100.0
             / NULLIF(COUNT(DISTINCT wo.order_id), 0), 2) AS rewash_rate_pct,
       IFNULL(SUM(rb.compensation_amount), 0) AS total_extra_cost_fen,
       ROUND(IFNULL(SUM(rb.compensation_amount), 0) * 1.0
             / NULLIF(COUNT(DISTINCT rb.order_id), 0), 0) AS avg_rewash_cost_fen,
       COUNT(DISTINCT CASE WHEN wo.order_status = 4 THEN wo.order_id END) AS completed_orders,
       COUNT(DISTINCT CASE WHEN wo.order_status = 5 THEN wo.order_id END) AS cancelled_orders
FROM merchant_info mi
LEFT JOIN wash_orders wo ON mi.merchant_id = wo.merchant_id
LEFT JOIN rewash_base rb ON mi.merchant_id = rb.merchant_id
GROUP BY mi.merchant_id, mi.merchant_name
ORDER BY rewash_rate_pct DESC;

-- ============================================================
-- B-REQ-007 企业员工福利使用情况
-- 验证逻辑: 按enterprise_id和benefit_type统计激活率和使用率
-- 激活率 = COUNT(status=1有效) / COUNT(总福利)
-- 使用率 = COUNT(status=0已使用) / COUNT(总福利)
-- ============================================================

-- 7.1 数据完整性检查
SELECT 'B-REQ-007 数据完整性' AS check_type,
       'employee_benefit' AS tbl, COUNT(*) AS cnt FROM employee_benefit
UNION ALL
SELECT '', 'enterprise', COUNT(*) FROM enterprise
UNION ALL
SELECT '', 'enterprise_user', COUNT(*) FROM enterprise_user;

-- 7.2 按企业和福利类型统计激活率和使用率
WITH benefit_stats AS (
    SELECT eb.enterprise_id,
           eb.benefit_type,
           COUNT(*) AS total_benefits,
           SUM(CASE WHEN eb.status = 1 THEN 1 ELSE 0 END) AS active_benefits,
           SUM(CASE WHEN eb.status = 0 THEN 1 ELSE 0 END) AS used_benefits,
           SUM(CASE WHEN eb.status = -1 THEN 1 ELSE 0 END) AS expired_benefits
    FROM employee_benefit eb
    GROUP BY eb.enterprise_id, eb.benefit_type
),
enterprise_info AS (
    SELECT e.enterprise_id,
           e.enterprise_name,
           COUNT(eu.user_id) AS employee_count
    FROM enterprise e
    LEFT JOIN enterprise_user eu ON e.enterprise_id = eu.enterprise_id
    WHERE e.is_deleted = 0
    GROUP BY e.enterprise_id, e.enterprise_name
)
SELECT ei.enterprise_id,
       ei.enterprise_name,
       ei.employee_count,
       bs.benefit_type,
       bs.total_benefits,
       bs.active_benefits,
       bs.used_benefits,
       bs.expired_benefits,
       ROUND(bs.active_benefits * 100.0 / NULLIF(bs.total_benefits, 0), 2) AS activation_rate_pct,
       ROUND(bs.used_benefits * 100.0 / NULLIF(bs.total_benefits, 0), 2) AS usage_rate_pct,
       ROUND(bs.total_benefits * 1.0 / NULLIF(ei.employee_count, 0), 2) AS avg_benefits_per_employee
FROM benefit_stats bs
INNER JOIN enterprise_info ei ON bs.enterprise_id = ei.enterprise_id
ORDER BY ei.enterprise_id, bs.benefit_type;

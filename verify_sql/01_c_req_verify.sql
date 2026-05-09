-- ============================================================
-- 平安产险数据湖 - C端8个需求验证SQL
-- 数据库: pingan_insurance
-- 生成日期: 2026-04-27
-- 说明: 每个需求包含数据完整性检查 + 核心指标验证SQL
-- ============================================================

USE `pingan_insurance`;

-- ============================================================
-- C-REQ-001 三免信用赔用户活跃与续保分析
-- 验证逻辑: 三免用户(safe_driving_score.score>=90且连续3年无理赔) vs 非三免用户
-- 核心指标: 用户数、活跃率、续保率、人均保费
-- ============================================================

-- 1.1 数据完整性检查
SELECT 'C-REQ-001 数据完整性' AS check_type,
       'safe_driving_score' AS tbl, COUNT(*) AS cnt FROM safe_driving_score
UNION ALL
SELECT '', 'claim_fast_payment', COUNT(*) FROM claim_fast_payment
UNION ALL
SELECT '', 'policy_renewal', COUNT(*) FROM policy_renewal
UNION ALL
SELECT '', 'user_behavior_log(login)', COUNT(*) FROM user_behavior_log WHERE event_name = 'login'
UNION ALL
SELECT '', 'claim_report', COUNT(*) FROM claim_report
UNION ALL
SELECT '', 'policy_master', COUNT(*) FROM policy_master;

-- 1.2 三免用户 vs 非三免用户 续保率对比
-- 三免用户定义: safe_driving_score中最新score>=90 且 近3年无理赔
WITH sanmian_users AS (
    SELECT DISTINCT u.user_id
    FROM `user` u
    INNER JOIN safe_driving_score sds ON u.user_id = sds.user_id
    WHERE sds.score >= 90
      AND sds.score_date = (
          SELECT MAX(s2.score_date) FROM safe_driving_score s2 WHERE s2.user_id = u.user_id
      )
      AND NOT EXISTS (
          SELECT 1 FROM claim_report cr
          WHERE cr.user_id = u.user_id
            AND cr.accident_date >= DATE_SUB(CURDATE(), INTERVAL 3 YEAR)
            AND cr.is_deleted = 0
      )
),
non_sanmian_users AS (
    SELECT u.user_id
    FROM `user` u
    WHERE u.user_id BETWEEN 1 AND 50
      AND u.is_deleted = 0
      AND u.user_id NOT IN (SELECT user_id FROM sanmian_users)
),
user_type_base AS (
    SELECT user_id, '三免' AS user_type FROM sanmian_users
    UNION ALL
    SELECT user_id, '非三免' AS user_type FROM non_sanmian_users
),
active_base AS (
    SELECT ub.user_id, ut.user_type,
           COUNT(DISTINCT DATE(ub.event_time)) AS active_days_30d
    FROM user_behavior_log ub
    INNER JOIN user_type_base ut ON ub.user_id = ut.user_id
    WHERE ub.event_name = 'login'
      AND ub.event_time >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
    GROUP BY ub.user_id, ut.user_type
),
renewal_base AS (
    SELECT ut.user_id, ut.user_type,
           pm.policy_no,
           pm.expiry_date,
           CASE WHEN pr.renewal_id IS NOT NULL THEN 1 ELSE 0 END AS is_renewed
    FROM user_type_base ut
    INNER JOIN policy_master pm ON ut.user_id = pm.user_id AND pm.is_deleted = 0
    LEFT JOIN policy_renewal pr ON pr.original_policy_no = pm.policy_no
                                AND pr.renewal_date <= DATE_ADD(pm.expiry_date, INTERVAL 30 DAY)
    WHERE pm.expiry_date <= CURDATE()
)
SELECT rb.user_type,
       COUNT(DISTINCT rb.user_id) AS total_users,
       COUNT(DISTINCT CASE WHEN ab.active_days_30d > 0 THEN ab.user_id END) AS active_users,
       ROUND(COUNT(DISTINCT CASE WHEN ab.active_days_30d > 0 THEN ab.user_id END) * 100.0
             / NULLIF(COUNT(DISTINCT rb.user_id), 0), 2) AS active_rate_pct,
       ROUND(AVG(ab.active_days_30d), 2) AS avg_login_days_30d,
       COUNT(DISTINCT rb.policy_no) AS expired_policies,
       SUM(rb.is_renewed) AS renewed_policies,
       ROUND(SUM(rb.is_renewed) * 100.0
             / NULLIF(COUNT(DISTINCT rb.policy_no), 0), 2) AS renewal_rate_pct,
       ROUND(AVG(pm2.premium_total), 0) AS avg_premium_fen
FROM renewal_base rb
LEFT JOIN active_base ab ON rb.user_id = ab.user_id
LEFT JOIN policy_master pm2 ON rb.user_id = pm2.user_id AND pm2.is_deleted = 0
GROUP BY rb.user_type;

-- ============================================================
-- C-REQ-002 人伤案件医疗垫付时效监控
-- 验证逻辑: 按月份+金额区间统计垫付审批时长
-- 核心指标: 案件数、平均/中位数/P90审批时长(小时)、超时案件数(>24h)
-- ============================================================

-- 2.1 数据完整性检查
SELECT 'C-REQ-002 数据完整性' AS check_type,
       'claim_injury' AS tbl, COUNT(*) AS cnt FROM claim_injury
UNION ALL
SELECT '', 'medical_advance', COUNT(*) FROM medical_advance
UNION ALL
SELECT '', 'claim_report(injury)', COUNT(*) FROM claim_report cr
    INNER JOIN claim_injury ci ON cr.claim_no = ci.claim_no
UNION ALL
SELECT '', 'claim_report', COUNT(*) FROM claim_report;

-- 2.2 按月份+垫付金额区间统计垫付审批时长
WITH injury_advance AS (
    SELECT ci.claim_no,
           cr.accident_date,
           cr.create_time AS report_create_time,
           ma.advance_time,
           ma.amount AS advance_amount_fen,
           TIMESTAMPDIFF(HOUR, cr.create_time, ma.advance_time) AS approval_hours,
           DATE_FORMAT(ma.advance_time, '%Y-%m') AS stat_month
    FROM claim_injury ci
    INNER JOIN claim_report cr ON ci.claim_no = cr.claim_no
    INNER JOIN medical_advance ma ON ci.claim_no = ma.claim_no
    WHERE cr.is_deleted = 0
      AND ma.advance_time >= DATE_SUB(CURDATE(), INTERVAL 6 MONTH)
),
amount_bucket AS (
    SELECT claim_no, stat_month, approval_hours, advance_amount_fen,
           CASE
               WHEN advance_amount_fen < 500000 THEN '<5000元'
               WHEN advance_amount_fen < 2000000 THEN '5000-20000元'
               ELSE '>20000元'
           END AS amount_range
    FROM injury_advance
),
ranked AS (
    SELECT claim_no, stat_month, amount_range, approval_hours,
           ROW_NUMBER() OVER (PARTITION BY stat_month, amount_range ORDER BY approval_hours) AS rn,
           COUNT(*) OVER (PARTITION BY stat_month, amount_range) AS total_cnt
    FROM amount_bucket
)
SELECT rb.stat_month,
       rb.amount_range,
       COUNT(*) AS case_count,
       ROUND(AVG(rb.approval_hours), 2) AS avg_approval_hours,
       MAX(CASE WHEN rn = FLOOR(total_cnt * 0.5) + 1 THEN approval_hours END) AS median_hours,
       MAX(CASE WHEN rn = FLOOR(total_cnt * 0.9) + 1 THEN approval_hours END) AS p90_hours,
       SUM(CASE WHEN rb.approval_hours > 24 THEN 1 ELSE 0 END) AS overtime_count
FROM amount_bucket rb
JOIN ranked r ON rb.claim_no = r.claim_no AND rb.stat_month = r.stat_month
GROUP BY rb.stat_month, rb.amount_range
ORDER BY rb.stat_month, rb.amount_range;

-- ============================================================
-- C-REQ-003 非车险理赔效率KPI
-- 验证逻辑: 按险种+季度统计结案周期与自动核赔率
-- 核心指标: 结案件数、平均结案周期(天)、自动核赔通过率(%)
-- ============================================================

-- 3.1 数据完整性检查
SELECT 'C-REQ-003 数据完整性' AS check_type,
       'claim_report(nonauto)' AS tbl,
       COUNT(*) AS cnt
FROM claim_report cr
INNER JOIN policy_master pm ON cr.policy_no = pm.policy_no
INNER JOIN nonauto_policy np ON pm.policy_no = np.policy_no
WHERE cr.is_deleted = 0
UNION ALL
SELECT '', 'nonauto_policy', COUNT(*) FROM nonauto_policy
UNION ALL
SELECT '', 'damage_assessment', COUNT(*) FROM damage_assessment
UNION ALL
SELECT '', 'claim_approval', COUNT(*) FROM claim_approval;

-- 3.2 按险种类别+季度统计结案周期与自动核赔率
WITH claim_type_base AS (
    SELECT cr.claim_no,
           cr.create_time AS report_time,
           ca.approval_time,
           DATEDIFF(ca.approval_time, cr.create_time) AS close_cycle_days,
           da.is_auto_settled,
           CASE
               WHEN np.policy_type = 1 THEN '健康险'
               WHEN np.policy_type = 2 THEN '家财险'
               WHEN np.policy_type = 3 THEN '旅行险'
               WHEN np.policy_type = 4 THEN '宠物险'
               WHEN np.policy_type = 5 THEN '意外险'
               ELSE '其他非车险'
           END AS risk_category,
           CONCAT(YEAR(ca.approval_time), 'Q', QUARTER(ca.approval_time)) AS stat_quarter
    FROM claim_report cr
    INNER JOIN policy_master pm ON cr.policy_no = pm.policy_no
    INNER JOIN nonauto_policy np ON pm.policy_no = np.policy_no
    INNER JOIN claim_approval ca ON cr.claim_no = ca.claim_no AND ca.approval_result = 1
    INNER JOIN damage_assessment da ON cr.claim_no = da.claim_no
    WHERE cr.claim_status = 5
      AND cr.is_deleted = 0
),
auto_claim_base AS (
    SELECT claim_no, stat_quarter, risk_category, close_cycle_days,
           MAX(is_auto_settled) AS is_auto_settled_flag
    FROM claim_type_base
    GROUP BY claim_no, stat_quarter, risk_category, close_cycle_days
)
SELECT risk_category,
       stat_quarter,
       COUNT(*) AS closed_cases,
       ROUND(AVG(close_cycle_days), 2) AS avg_close_cycle_days,
       ROUND(SUM(CASE WHEN is_auto_settled_flag = 1 THEN 1 ELSE 0 END) * 100.0
             / NULLIF(COUNT(*), 0), 2) AS auto_settle_rate_pct,
       ROUND(SUM(CASE WHEN is_auto_settled_flag = 1 THEN 1 ELSE 0 END) * 100.0
             / NULLIF(COUNT(*), 0), 2) AS auto_settle_case_pct
FROM auto_claim_base
GROUP BY risk_category, stat_quarter
ORDER BY risk_category, stat_quarter;

-- ============================================================
-- C-REQ-004 一键报案功能使用漏斗
-- 验证逻辑: 按日期+设备平台统计报案各环节UV及转化率
-- 事件链: open_claim_page -> fill_accident_info -> upload_damage_photo -> submit_claim -> claim_submit_success
-- ============================================================

-- 4.1 数据完整性检查
SELECT 'C-REQ-004 数据完整性' AS check_type,
       'open_claim_page' AS event_name, COUNT(DISTINCT user_id) AS uv
FROM user_behavior_log WHERE event_name = 'open_claim_page'
UNION ALL
SELECT '', 'fill_accident_info', COUNT(DISTINCT user_id)
FROM user_behavior_log WHERE event_name = 'fill_accident_info'
UNION ALL
SELECT '', 'upload_damage_photo', COUNT(DISTINCT user_id)
FROM user_behavior_log WHERE event_name = 'upload_damage_photo'
UNION ALL
SELECT '', 'submit_claim', COUNT(DISTINCT user_id)
FROM user_behavior_log WHERE event_name = 'submit_claim'
UNION ALL
SELECT '', 'claim_submit_success', COUNT(DISTINCT user_id)
FROM user_behavior_log WHERE event_name = 'claim_submit_success';

-- 4.2 按日期+设备平台统计漏斗各环节UV及转化率
WITH funnel_base AS (
    SELECT DATE(ubl.event_time) AS stat_date,
           d.os_type AS platform,
           ubl.event_name,
           ubl.user_id
    FROM user_behavior_log ubl
    LEFT JOIN device d ON ubl.device_id = d.device_id
    WHERE ubl.event_name IN (
        'open_claim_page', 'fill_accident_info', 'upload_damage_photo',
        'submit_claim', 'claim_submit_success'
    )
    AND ubl.event_time >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
),
funnel_uv AS (
    SELECT stat_date,
           platform,
           COUNT(DISTINCT CASE WHEN event_name = 'open_claim_page' THEN user_id END) AS uv_open,
           COUNT(DISTINCT CASE WHEN event_name = 'fill_accident_info' THEN user_id END) AS uv_fill,
           COUNT(DISTINCT CASE WHEN event_name = 'upload_damage_photo' THEN user_id END) AS uv_upload,
           COUNT(DISTINCT CASE WHEN event_name = 'submit_claim' THEN user_id END) AS uv_submit,
           COUNT(DISTINCT CASE WHEN event_name = 'claim_submit_success' THEN user_id END) AS uv_success
    FROM funnel_base
    GROUP BY stat_date, platform
)
SELECT stat_date,
       IFNULL(platform, '未知') AS platform,
       uv_open,
       uv_fill,
       uv_upload,
       uv_submit,
       uv_success,
       ROUND(uv_fill * 100.0 / NULLIF(uv_open, 0), 2) AS cvr_open_to_fill_pct,
       ROUND(uv_upload * 100.0 / NULLIF(uv_fill, 0), 2) AS cvr_fill_to_upload_pct,
       ROUND(uv_submit * 100.0 / NULLIF(uv_upload, 0), 2) AS cvr_upload_to_submit_pct,
       ROUND(uv_success * 100.0 / NULLIF(uv_submit, 0), 2) AS cvr_submit_to_success_pct,
       ROUND(uv_success * 100.0 / NULLIF(uv_open, 0), 2) AS cvr_overall_pct
FROM funnel_uv
ORDER BY stat_date, platform;

-- ============================================================
-- C-REQ-005 运营活动ROI及拉新效果
-- 验证逻辑: 按活动类型统计参与人数、新注册用户数、首购率、ROI
-- 新用户=活动期间首次注册(通过invite_relation)
-- ROI=保费总收入/budget
-- ============================================================

-- 5.1 数据完整性检查
SELECT 'C-REQ-005 数据完整性' AS check_type,
       'campaign_master' AS tbl, COUNT(*) AS cnt FROM campaign_master
UNION ALL
SELECT '', 'campaign_participation', COUNT(*) FROM campaign_participation
UNION ALL
SELECT '', 'invite_relation', COUNT(*) FROM invite_relation
UNION ALL
SELECT '', 'policy_master', COUNT(*) FROM policy_master;

-- 5.2 按活动类型统计ROI及拉新效果
WITH campaign_info AS (
    SELECT cm.campaign_id,
           cm.campaign_name,
           CASE cm.campaign_type
               WHEN 1 THEN '节日营销'
               WHEN 2 THEN '裂变活动'
               WHEN 3 THEN '直播活动'
               WHEN 4 THEN '签到活动'
               ELSE '其他'
           END AS campaign_type_name,
           cm.budget,
           cm.start_time,
           cm.end_time
    FROM campaign_master cm
),
participation_base AS (
    SELECT ci.campaign_id,
           ci.campaign_type_name,
           ci.budget,
           ci.start_time,
           ci.end_time,
           COUNT(DISTINCT cp.user_id) AS participant_count
    FROM campaign_info ci
    INNER JOIN campaign_participation cp ON ci.campaign_id = cp.campaign_id
    GROUP BY ci.campaign_id, ci.campaign_type_name, ci.budget, ci.start_time, ci.end_time
),
new_user_base AS (
    SELECT ci.campaign_id,
           COUNT(DISTINCT ir.invitee_user_id) AS new_user_count,
           COUNT(DISTINCT CASE WHEN ir.is_purchased = 1 THEN ir.invitee_user_id END) AS new_user_purchased
    FROM campaign_info ci
    INNER JOIN campaign_participation cp ON ci.campaign_id = cp.campaign_id
    INNER JOIN invite_relation ir ON ir.inviter_user_id = cp.user_id
                                  AND ir.invite_time BETWEEN ci.start_time AND ci.end_time
    WHERE ir.is_registered = 1
    GROUP BY ci.campaign_id
),
premium_base AS (
    SELECT ci.campaign_id,
           SUM(pm.premium_total) AS total_premium_fen
    FROM campaign_info ci
    INNER JOIN campaign_participation cp ON ci.campaign_id = cp.campaign_id
    INNER JOIN policy_master pm ON pm.user_id = cp.user_id
                                AND pm.issue_date BETWEEN ci.start_time AND ci.end_time
                                AND pm.is_deleted = 0
    GROUP BY ci.campaign_id
)
SELECT pb.campaign_type_name,
       pb.campaign_id,
       pb.participant_count,
       IFNULL(nu.new_user_count, 0) AS new_user_count,
       ROUND(IFNULL(nu.new_user_purchased, 0) * 100.0
             / NULLIF(nu.new_user_count, 0), 2) AS new_user_first_purchase_rate_pct,
       ROUND(IFNULL(pr.total_premium_fen, 0) * 1.0
             / NULLIF(pb.participant_count, 0), 0) AS avg_premium_per_user_fen,
       ROUND(IFNULL(pr.total_premium_fen, 0) * 1.0
             / NULLIF(pb.budget, 0), 4) AS roi,
       pb.budget AS budget_fen
FROM participation_base pb
LEFT JOIN new_user_base nu ON pb.campaign_id = nu.campaign_id
LEFT JOIN premium_base pr ON pb.campaign_id = pr.campaign_id
ORDER BY pb.campaign_type_name, pb.campaign_id;

-- ============================================================
-- C-REQ-006 用户触达渠道响应率
-- 验证逻辑: APP推送响应率 + 外呼响应率
-- APP推送响应: push_record.status=1 且有open_time
-- 外呼响应: outbound_call_task.call_status=2(已接通)
-- ============================================================

-- 6.1 数据完整性检查
SELECT 'C-REQ-006 数据完整性' AS check_type,
       'push_task' AS tbl, COUNT(*) AS cnt FROM push_task
UNION ALL
SELECT '', 'push_record', COUNT(*) FROM push_record
UNION ALL
SELECT '', 'outbound_call_task', COUNT(*) FROM outbound_call_task
UNION ALL
SELECT '', 'wechat_interaction', COUNT(*) FROM wechat_interaction;

-- 6.2 APP推送响应率(按月份+任务)
WITH push_stats AS (
    SELECT pt.task_id,
           pt.task_name,
           DATE_FORMAT(pr.send_time, '%Y-%m') AS stat_month,
           COUNT(*) AS push_total,
           SUM(CASE WHEN pr.status = 1 THEN 1 ELSE 0 END) AS push_success,
           SUM(CASE WHEN pr.status = 1
                     AND EXISTS (
                         SELECT 1 FROM user_behavior_log ubl
                         WHERE ubl.user_id = pr.user_id
                           AND ubl.event_name = 'push_open'
                           AND ubl.event_time BETWEEN pr.send_time
                               AND DATE_ADD(pr.send_time, INTERVAL 24 HOUR)
                     ) THEN 1 ELSE 0 END) AS push_opened
    FROM push_task pt
    INNER JOIN push_record pr ON pt.task_id = pr.task_id
    GROUP BY pt.task_id, pt.task_name, DATE_FORMAT(pr.send_time, '%Y-%m')
)
SELECT stat_month,
       task_id,
       task_name,
       push_total,
       push_success,
       push_opened,
       ROUND(push_opened * 100.0 / NULLIF(push_success, 0), 2) AS push_open_rate_pct
FROM push_stats
ORDER BY stat_month, task_id;

-- 6.3 外呼响应率(按月份)
SELECT DATE_FORMAT(ct.scheduled_time, '%Y-%m') AS stat_month,
       COUNT(*) AS call_total,
       SUM(CASE WHEN ct.call_status = 2 THEN 1 ELSE 0 END) AS call_connected,
       ROUND(SUM(CASE WHEN ct.call_status = 2 THEN 1 ELSE 0 END) * 100.0
             / NULLIF(COUNT(*), 0), 2) AS call_connect_rate_pct
FROM outbound_call_task ct
GROUP BY DATE_FORMAT(ct.scheduled_time, '%Y-%m')
ORDER BY stat_month;

-- ============================================================
-- C-REQ-007 积分商城运营健康度
-- 验证逻辑: 按月份统计积分发放/兑换/兑换率
-- 兑换率=兑换量/发放量
-- ============================================================

-- 7.1 数据完整性检查
SELECT 'C-REQ-007 数据完整性' AS check_type,
       'points_account' AS tbl, COUNT(*) AS cnt FROM points_account
UNION ALL
SELECT '', 'points_transaction', COUNT(*) FROM points_transaction
UNION ALL
SELECT '', 'points_exchange_order', COUNT(*) FROM points_exchange_order
UNION ALL
SELECT '', 'mall_product', COUNT(*) FROM mall_product;

-- 7.2 按月份统计积分发放总量、兑换总量、兑换率
WITH monthly_points AS (
    SELECT DATE_FORMAT(pt.create_time, '%Y-%m') AS stat_month,
           SUM(CASE WHEN pt.trans_type = 1 THEN pt.points_amount ELSE 0 END) AS points_issued,
           SUM(CASE WHEN pt.trans_type = 2 THEN ABS(pt.points_amount) ELSE 0 END) AS points_consumed
    FROM points_transaction pt
    GROUP BY DATE_FORMAT(pt.create_time, '%Y-%m')
),
monthly_exchange AS (
    SELECT DATE_FORMAT(peo.exchange_time, '%Y-%m') AS stat_month,
           COUNT(*) AS exchange_count,
           SUM(peo.points_used) AS exchange_points
    FROM points_exchange_order peo
    GROUP BY DATE_FORMAT(peo.exchange_time, '%Y-%m')
),
active_compare AS (
    SELECT DATE_FORMAT(ubl.event_time, '%Y-%m') AS stat_month,
           peo_user.user_id AS user_id,
           COUNT(DISTINCT DATE(ubl.event_time)) AS active_days
    FROM user_behavior_log ubl
    INNER JOIN (
        SELECT DISTINCT user_id, DATE_FORMAT(exchange_time, '%Y-%m') AS stat_month
        FROM points_exchange_order
    ) peo_user ON ubl.user_id = peo_user.user_id
                AND DATE_FORMAT(ubl.event_time, '%Y-%m') = peo_user.stat_month
    WHERE ubl.event_name = 'login'
    GROUP BY DATE_FORMAT(ubl.event_time, '%Y-%m'), peo_user.user_id
)
SELECT mp.stat_month,
       mp.points_issued AS points_issued_fen,
       mp.points_consumed AS points_consumed_fen,
       ROUND(mp.points_consumed * 100.0 / NULLIF(mp.points_issued, 0), 2) AS exchange_rate_pct,
       IFNULL(me.exchange_count, 0) AS exchange_order_count,
       IFNULL(me.exchange_points, 0) AS exchange_points_fen,
       ROUND(AVG(ac.active_days), 2) AS avg_active_days_exchange_user
FROM monthly_points mp
LEFT JOIN monthly_exchange me ON mp.stat_month = me.stat_month
LEFT JOIN active_compare ac ON mp.stat_month = ac.stat_month
GROUP BY mp.stat_month, mp.points_issued, mp.points_consumed,
         me.exchange_count, me.exchange_points
ORDER BY mp.stat_month;

-- ============================================================
-- C-REQ-008 分享裂变K因子
-- 验证逻辑: K = 被邀请注册数 / 邀请总人数
-- 按活动(裂变类型campaign_type=2)统计K因子
-- 按季度识别Top传播者
-- ============================================================

-- 8.1 数据完整性检查
SELECT 'C-REQ-008 数据完整性' AS check_type,
       'invite_relation' AS tbl, COUNT(*) AS cnt FROM invite_relation
UNION ALL
SELECT '', 'share_record', COUNT(*) FROM share_record
UNION ALL
SELECT '', 'campaign_master(裂变)', COUNT(*) FROM campaign_master WHERE campaign_type = 2
UNION ALL
SELECT '', 'user', COUNT(*) FROM `user` WHERE is_deleted = 0;

-- 8.2 按裂变活动+月份统计K因子
WITH fission_campaign AS (
    SELECT cm.campaign_id,
           cm.campaign_name,
           cm.start_time,
           cm.end_time
    FROM campaign_master cm
    WHERE cm.campaign_type = 2
),
invite_in_campaign AS (
    SELECT fc.campaign_id,
           fc.campaign_name,
           ir.inviter_user_id,
           ir.invitee_user_id,
           ir.is_registered,
           ir.is_purchased,
           ir.invite_time,
           DATE_FORMAT(ir.invite_time, '%Y-%m') AS stat_month
    FROM fission_campaign fc
    INNER JOIN invite_relation ir ON ir.invite_time BETWEEN fc.start_time AND fc.end_time
),
k_factor_base AS (
    SELECT campaign_id,
           campaign_name,
           stat_month,
           COUNT(DISTINCT invitee_user_id) AS invite_total,
           COUNT(DISTINCT CASE WHEN is_registered = 1 THEN invitee_user_id END) AS registered_count,
           COUNT(DISTINCT CASE WHEN is_purchased = 1 THEN invitee_user_id END) AS purchased_count
    FROM invite_in_campaign
    GROUP BY campaign_id, campaign_name, stat_month
)
SELECT campaign_id,
       campaign_name,
       stat_month,
       invite_total,
       registered_count,
       ROUND(registered_count * 1.0 / NULLIF(invite_total, 0), 4) AS k_factor,
       purchased_count,
       ROUND(purchased_count * 100.0 / NULLIF(registered_count, 0), 2) AS invitee_first_purchase_rate_pct
FROM k_factor_base
ORDER BY campaign_id, stat_month;

-- 8.3 按季度识别Top传播者及其带来的用户价值
WITH quarterly_inviter AS (
    SELECT ir.inviter_user_id,
           CONCAT(YEAR(ir.invite_time), 'Q', QUARTER(ir.invite_time)) AS stat_quarter,
           ir.invitee_user_id,
           ir.is_registered,
           ir.is_purchased
    FROM invite_relation ir
    INNER JOIN fission_campaign fc ON ir.invite_time BETWEEN fc.start_time AND fc.end_time
),
inviter_stats AS (
    SELECT inviter_user_id,
           stat_quarter,
           COUNT(*) AS invite_count,
           SUM(CASE WHEN is_registered = 1 THEN 1 ELSE 0 END) AS registered_count,
           SUM(CASE WHEN is_purchased = 1 THEN 1 ELSE 0 END) AS purchased_count
    FROM quarterly_inviter
    GROUP BY inviter_user_id, stat_quarter
),
inviter_ltv AS (
    SELECT inv.inviter_user_id,
           inv.stat_quarter,
           SUM(pm.premium_total) AS invitee_ltv_6m_fen
    FROM quarterly_inviter inv
    INNER JOIN policy_master pm ON pm.user_id = inv.invitee_user_id
                                AND pm.is_deleted = 0
                                AND pm.issue_date <= DATE_ADD(inv.invite_time, INTERVAL 6 MONTH)
    WHERE inv.is_registered = 1
    GROUP BY inv.inviter_user_id, inv.stat_quarter
)
SELECT ist.inviter_user_id,
       ist.stat_quarter,
       ist.invite_count,
       ist.registered_count,
       ROUND(ist.purchased_count * 100.0 / NULLIF(ist.registered_count, 0), 2) AS invitee_purchase_rate_pct,
       IFNULL(ltv.invitee_ltv_6m_fen, 0) AS invitee_ltv_6m_fen
FROM inviter_stats ist
LEFT JOIN inviter_ltv ltv ON ist.inviter_user_id = ltv.inviter_user_id
                           AND ist.stat_quarter = ltv.stat_quarter
ORDER BY ist.stat_quarter, ist.registered_count DESC;

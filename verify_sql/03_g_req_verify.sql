-- ============================================================
-- 平安产险数据湖 - G端5个需求验证SQL
-- 数据库: pingan_insurance
-- 生成日期: 2026-04-27
-- 说明: 每个需求包含数据完整性检查 + 核心指标验证SQL
-- ============================================================

USE `pingan_insurance`;

-- ============================================================
-- G-REQ-001 惠民保产品渗透率及续保意愿
-- 验证逻辑: 按产品统计参保人数，计算渗透率(参保人数/常住人口)
-- 对比理赔用户续保率 vs 未理赔用户续保率
-- ============================================================

-- 1.1 数据完整性检查
SELECT 'G-REQ-001 数据完整性' AS check_type,
       'gov_insurance_product' AS tbl, COUNT(*) AS cnt FROM gov_insurance_product
UNION ALL
SELECT '', 'gov_insurance_policy', COUNT(*) FROM gov_insurance_policy
UNION ALL
SELECT '', 'policy_master(惠民保)', COUNT(*) FROM policy_master pm
    INNER JOIN gov_insurance_policy gip ON pm.policy_no = gip.policy_no
UNION ALL
SELECT '', 'policy_renewal(惠民保)', COUNT(*) FROM policy_renewal pr
    INNER JOIN gov_insurance_policy gip ON pr.old_policy_no = gip.policy_no
UNION ALL
SELECT '', 'claim_report(惠民保)', COUNT(*) FROM claim_report cr
    INNER JOIN gov_insurance_policy gip ON cr.policy_no = gip.policy_no;

-- 1.2 按产品统计参保人数（渗透率分母为常住人口，需外部提供，此处仅统计分子）
WITH product_policy_base AS (
    SELECT gip.product_code,
           gip.policy_no,
           gip.insured_name,
           gip.issue_date,
           pm.premium_total,
           pm.policy_status
    FROM gov_insurance_policy gip
    INNER JOIN policy_master pm ON gip.policy_no = pm.policy_no AND pm.is_deleted = 0
),
product_insured_count AS (
    SELECT product_code,
           COUNT(*) AS insured_count,
           SUM(CASE WHEN policy_status = 1 THEN 1 ELSE 0 END) AS active_policy_count,
           ROUND(AVG(premium_total), 2) AS avg_premium_fen
    FROM product_policy_base
    GROUP BY product_code
)
SELECT pic.product_code,
       gip.product_name,
       pic.insured_count,
       pic.active_policy_count,
       pic.avg_premium_fen,
       pic.insured_count AS penetration_numerator,
       '常住人口需外部提供' AS penetration_denominator_note
FROM product_insured_count pic
INNER JOIN gov_insurance_product gip ON pic.product_code = gip.product_code
ORDER BY pic.insured_count DESC;

-- 1.3 理赔用户续保率 vs 未理赔用户续保率
WITH claim_user_policy AS (
    SELECT DISTINCT gip.product_code,
                    gip.policy_no,
                    gip.insured_id
    FROM gov_insurance_policy gip
    INNER JOIN claim_report cr ON gip.policy_no = cr.policy_no
),
renewal_base AS (
    SELECT gip.product_code,
           gip.insured_id,
           gip.policy_no,
           pr.new_policy_no,
           CASE WHEN pr.new_policy_no IS NOT NULL THEN 1 ELSE 0 END AS is_renewed,
           CASE WHEN cup.insured_id IS NOT NULL THEN 1 ELSE 0 END AS has_claim
    FROM gov_insurance_policy gip
    LEFT JOIN policy_renewal pr ON gip.policy_no = pr.old_policy_no
    LEFT JOIN claim_user_policy cup ON gip.insured_id = cup.insured_id AND gip.product_code = cup.product_code
),
renewal_stat AS (
    SELECT product_code,
           has_claim,
           COUNT(*) AS total_user_count,
           SUM(is_renewed) AS renewed_count,
           ROUND(SUM(is_renewed) * 100.0 / COUNT(*), 2) AS renewal_rate_pct
    FROM renewal_base
    GROUP BY product_code, has_claim
)
SELECT rs.product_code,
       CASE WHEN rs.has_claim = 1 THEN '理赔用户' ELSE '未理赔用户' END AS user_type,
       rs.total_user_count,
       rs.renewed_count,
       rs.renewal_rate_pct
FROM renewal_stat rs
ORDER BY rs.product_code, rs.has_claim DESC;

-- ============================================================
-- G-REQ-002 红绿灯公益行动社会影响力
-- 验证逻辑: 改造前后事故数对比，计算事故下降率
-- 公益积分参与率 = 有公益积分且安驾分≥90用户 / 安驾分≥90用户
-- ============================================================

-- 2.1 数据完整性检查
SELECT 'G-REQ-002 数据完整性' AS check_type,
       'blackspot_road' AS tbl, COUNT(*) AS cnt FROM blackspot_road
UNION ALL
SELECT '', 'road_improvement_project', COUNT(*) FROM road_improvement_project
UNION ALL
SELECT '', 'public_welfare_points', COUNT(*) FROM public_welfare_points;

-- 2.2 改造前后事故数对比及事故下降率
WITH road_with_project AS (
    SELECT br.road_id,
           br.road_name,
           br.blackspot_level,
           br.accident_count,
           br.accident_count_after,
           br.improvement_status,
           rip.project_id,
           rip.project_name,
           rip.start_date,
           rip.end_date,
           rip.budget_amount
    FROM blackspot_road br
    LEFT JOIN road_improvement_project rip ON br.road_id = rip.road_id
),
accident_comparison AS (
    SELECT road_id,
           road_name,
           blackspot_level,
           improvement_status,
           accident_count,
           accident_count_after,
           CASE WHEN accident_count > 0
                THEN ROUND((accident_count - accident_count_after) * 100.0 / accident_count, 2)
                ELSE 0 END AS accident_drop_rate_pct
    FROM road_with_project
)
SELECT ac.road_id,
       ac.road_name,
       ac.blackspot_level,
       CASE WHEN ac.improvement_status = 0 THEN '待改造'
            WHEN ac.improvement_status = 1 THEN '改造中'
            WHEN ac.improvement_status = 2 THEN '已完成'
            ELSE '未知' END AS improvement_status_desc,
       ac.accident_count AS accident_before,
       ac.accident_count_after AS accident_after,
       ac.accident_drop_rate_pct
FROM accident_comparison ac
ORDER BY ac.accident_drop_rate_pct DESC;

-- 2.3 改造状态汇总统计
SELECT CASE WHEN improvement_status = 0 THEN '待改造'
            WHEN improvement_status = 1 THEN '改造中'
            WHEN improvement_status = 2 THEN '已完成'
            ELSE '未知' END AS improvement_status_desc,
       COUNT(*) AS road_count,
       SUM(accident_count) AS total_accident_before,
       SUM(accident_count_after) AS total_accident_after,
       ROUND((SUM(accident_count) - SUM(accident_count_after)) * 100.0
             / NULLIF(SUM(accident_count), 0), 2) AS overall_drop_rate_pct
FROM blackspot_road
GROUP BY improvement_status
ORDER BY improvement_status;

-- 2.4 公益积分参与率
WITH welfare_user_base AS (
    SELECT user_id,
           driving_score,
           points_balance
    FROM public_welfare_points
),
score_above_90 AS (
    SELECT COUNT(*) AS total_count
    FROM welfare_user_base
    WHERE driving_score >= 90
),
score_above_90_with_points AS (
    SELECT COUNT(*) AS has_points_count
    FROM welfare_user_base
    WHERE driving_score >= 90 AND points_balance > 0
)
SELECT s90.total_count AS safe_driving_user_count,
       sp.has_points_count AS has_welfare_points_count,
       ROUND(sp.has_points_count * 100.0 / NULLIF(s90.total_count, 0), 2) AS welfare_participation_rate_pct
FROM score_above_90 s90
CROSS JOIN score_above_90_with_points sp;

-- ============================================================
-- G-REQ-003 监管数据报送质量监控
-- 验证逻辑: 按日期和产品类型统计成功率、平均延迟、重试次数分布、失败错误码TOP5
-- ============================================================

-- 3.1 数据完整性检查
SELECT 'G-REQ-003 数据完整性' AS check_type,
       'policy_upload_log' AS tbl, COUNT(*) AS cnt FROM policy_upload_log
UNION ALL
SELECT '', 'policy_master(关联)', COUNT(*) FROM policy_master pm
    INNER JOIN policy_upload_log pul ON pm.policy_no = pul.policy_no;

-- 3.2 按日期和产品类型统计报送成功率及平均延迟
WITH upload_with_policy AS (
    SELECT pul.upload_id,
           pul.policy_no,
           pul.upload_time,
           pul.upload_status,
           pul.retry_count,
           pul.response_msg,
           pm.product_type,
           pm.issue_date
    FROM policy_upload_log pul
    INNER JOIN policy_master pm ON pul.policy_no = pm.policy_no
),
daily_stat AS (
    SELECT DATE(upload_time) AS upload_date,
           product_type,
           COUNT(*) AS total_count,
           SUM(CASE WHEN upload_status = 1 THEN 1 ELSE 0 END) AS success_count,
           SUM(CASE WHEN upload_status = 2 THEN 1 ELSE 0 END) AS fail_count,
           SUM(CASE WHEN upload_status = 3 THEN 1 ELSE 0 END) AS retrying_count,
           ROUND(SUM(CASE WHEN upload_status = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS success_rate_pct,
           ROUND(AVG(TIMESTAMPDIFF(MINUTE, issue_date, upload_time)), 2) AS avg_delay_minutes
    FROM upload_with_policy
    GROUP BY DATE(upload_time), product_type
)
SELECT upload_date,
       product_type,
       total_count,
       success_count,
       fail_count,
       retrying_count,
       success_rate_pct,
       avg_delay_minutes
FROM daily_stat
ORDER BY upload_date DESC, product_type;

-- 3.3 重试次数分布
SELECT retry_count,
       COUNT(*) AS upload_count,
       SUM(CASE WHEN upload_status = 1 THEN 1 ELSE 0 END) AS success_after_retry,
       SUM(CASE WHEN upload_status = 2 THEN 1 ELSE 0 END) AS still_failed,
       ROUND(SUM(CASE WHEN upload_status = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS retry_success_rate_pct
FROM policy_upload_log
GROUP BY retry_count
ORDER BY retry_count;

-- 3.4 失败错误码TOP5（从response_msg解析错误码）
WITH failed_uploads AS (
    SELECT upload_id,
           response_msg,
           REGEXP_SUBSTR(response_msg, '[A-Z]+-[0-9]+') AS error_code
    FROM policy_upload_log
    WHERE upload_status = 2
      AND response_msg IS NOT NULL
),
error_code_stat AS (
    SELECT CASE WHEN error_code IS NOT NULL AND error_code != '' THEN error_code
               ELSE 'UNKNOWN' END AS parsed_error_code,
           COUNT(*) AS error_count
    FROM failed_uploads
    GROUP BY parsed_error_code
)
SELECT parsed_error_code,
       error_count
FROM error_code_stat
ORDER BY error_count DESC
LIMIT 5;

-- ============================================================
-- G-REQ-004 消费者投诉热点分类统计
-- 验证逻辑: 按日期和问题类型统计投诉数，关键词匹配分类
-- 问题类型: 理赔时效慢/客服态度/条款争议/退保纠纷/保费计算
-- ============================================================

-- 4.1 数据完整性检查
SELECT 'G-REQ-004 数据完整性' AS check_type,
       'complaint_record' AS tbl, COUNT(*) AS cnt FROM complaint_record;

-- 4.2 按日期和问题类型统计投诉数
WITH complaint_classified AS (
    SELECT cr.complaint_id,
           cr.complaint_date,
           cr.complaint_content,
           cr.complainant_name,
           cr.handler_name,
           cr.status,
           CASE
               WHEN cr.complaint_content LIKE '%理赔时效%' OR cr.complaint_content LIKE '%理赔慢%' OR cr.complaint_content LIKE '%理赔超时%' THEN '理赔时效慢'
               WHEN cr.complaint_content LIKE '%客服态度%' OR cr.complaint_content LIKE '%服务态度%' OR cr.complaint_content LIKE '%客服差%' THEN '客服态度'
               WHEN cr.complaint_content LIKE '%条款争议%' OR cr.complaint_content LIKE '%条款不符%' OR cr.complaint_content LIKE '%免责条款%' THEN '条款争议'
               WHEN cr.complaint_content LIKE '%退保%' OR cr.complaint_content LIKE '%退费%' OR cr.complaint_content LIKE '%退款纠纷%' THEN '退保纠纷'
               WHEN cr.complaint_content LIKE '%保费计算%' OR cr.complaint_content LIKE '%保费贵%' OR cr.complaint_content LIKE '%费率%' THEN '保费计算'
               ELSE '其他'
           END AS problem_type
    FROM complaint_record cr
),
daily_problem_stat AS (
    SELECT complaint_date,
           problem_type,
           COUNT(*) AS complaint_count
    FROM complaint_classified
    GROUP BY complaint_date, problem_type
)
SELECT complaint_date,
       problem_type,
       complaint_count
FROM daily_problem_stat
ORDER BY complaint_date DESC, complaint_count DESC;

-- 4.3 问题类型汇总及占比
WITH complaint_classified AS (
    SELECT CASE
               WHEN complaint_content LIKE '%理赔时效%' OR complaint_content LIKE '%理赔慢%' OR complaint_content LIKE '%理赔超时%' THEN '理赔时效慢'
               WHEN complaint_content LIKE '%客服态度%' OR complaint_content LIKE '%服务态度%' OR complaint_content LIKE '%客服差%' THEN '客服态度'
               WHEN complaint_content LIKE '%条款争议%' OR complaint_content LIKE '%条款不符%' OR complaint_content LIKE '%免责条款%' THEN '条款争议'
               WHEN complaint_content LIKE '%退保%' OR complaint_content LIKE '%退费%' OR complaint_content LIKE '%退款纠纷%' THEN '退保纠纷'
               WHEN complaint_content LIKE '%保费计算%' OR complaint_content LIKE '%保费贵%' OR complaint_content LIKE '%费率%' THEN '保费计算'
               ELSE '其他'
           END AS problem_type
    FROM complaint_record
),
type_stat AS (
    SELECT problem_type,
           COUNT(*) AS complaint_count
    FROM complaint_classified
    GROUP BY problem_type
),
total_count AS (
    SELECT SUM(complaint_count) AS total FROM type_stat
)
SELECT ts.problem_type,
       ts.complaint_count,
       ROUND(ts.complaint_count * 100.0 / NULLIF(t.total, 0), 2) AS proportion_pct
FROM type_stat ts
CROSS JOIN total_count t
ORDER BY ts.complaint_count DESC;

-- 4.4 投诉内容词频（简化：直接输出投诉内容文本及频次）
SELECT complaint_content,
       COUNT(*) AS occurrence_count
FROM complaint_record
WHERE complaint_content IS NOT NULL
GROUP BY complaint_content
ORDER BY occurrence_count DESC
LIMIT 20;

-- ============================================================
-- G-REQ-005 数据操作审计异常行为标记
-- 验证逻辑: 判定非工作时间操作/批量操作/敏感表操作
-- 非工作时间 = HOUR(operation_time) NOT BETWEEN 9 AND 18（含22-06简化为非9-18）
-- 批量操作 = 同一operator_id在10秒内同表操作>100条（使用窗口函数判定）
-- 敏感表操作 = table_name IN ('user','policy_master','claim_report')
-- 综合异常标记 = 非工作时间 OR 批量操作 OR 敏感表操作
-- ============================================================

-- 5.1 数据完整性检查
SELECT 'G-REQ-005 数据完整性' AS check_type,
       'data_audit_log' AS tbl, COUNT(*) AS cnt FROM data_audit_log;

-- 5.2 异常行为标记（使用窗口函数判定批量操作）
WITH work_time_check AS (
    SELECT dal.log_id,
           dal.operator_id,
           dal.operation_type,
           dal.table_name,
           dal.operation_time,
           dal.record_count,
           CASE WHEN HOUR(dal.operation_time) NOT BETWEEN 9 AND 18 THEN 1 ELSE 0 END AS is_off_hours
    FROM data_audit_log dal
),
batch_operation_check AS (
    SELECT log_id,
           operator_id,
           table_name,
           operation_time,
           CASE
               WHEN COUNT(*) OVER (
                   PARTITION BY operator_id, table_name
                   ORDER BY operation_time
                   RANGE BETWEEN INTERVAL 10 SECOND PRECEDING AND INTERVAL 10 SECOND FOLLOWING
               ) > 100 THEN 1
               ELSE 0
           END AS is_batch_operation
    FROM data_audit_log
),
sensitive_table_check AS (
    SELECT log_id,
           table_name,
           CASE WHEN table_name IN ('user', 'policy_master', 'claim_report') THEN 1 ELSE 0 END AS is_sensitive_table
    FROM data_audit_log
),
audit_anomaly_marked AS (
    SELECT wtc.log_id,
           wtc.operator_id,
           wtc.operation_type,
           wtc.table_name,
           wtc.operation_time,
           wtc.record_count,
           wtc.is_off_hours,
           boc.is_batch_operation,
           stc.is_sensitive_table,
           CASE WHEN wtc.is_off_hours = 1
                  OR boc.is_batch_operation = 1
                  OR stc.is_sensitive_table = 1 THEN 1 ELSE 0 END AS is_anomaly
    FROM work_time_check wtc
    INNER JOIN batch_operation_check boc ON wtc.log_id = boc.log_id
    INNER JOIN sensitive_table_check stc ON wtc.log_id = stc.log_id
)
SELECT log_id,
       operator_id,
       operation_type,
       table_name,
       operation_time,
       record_count,
       CASE WHEN is_off_hours = 1 THEN 'Y' ELSE 'N' END AS off_hours_flag,
       CASE WHEN is_batch_operation = 1 THEN 'Y' ELSE 'N' END AS batch_operation_flag,
       CASE WHEN is_sensitive_table = 1 THEN 'Y' ELSE 'N' END AS sensitive_table_flag,
       CASE WHEN is_anomaly = 1 THEN 'Y' ELSE 'N' END AS anomaly_flag
FROM audit_anomaly_marked
ORDER BY is_anomaly DESC, operation_time DESC;

-- 5.3 异常行为汇总统计
WITH work_time_check AS (
    SELECT log_id,
           CASE WHEN HOUR(operation_time) NOT BETWEEN 9 AND 18 THEN 1 ELSE 0 END AS is_off_hours
    FROM data_audit_log
),
batch_operation_check AS (
    SELECT log_id,
           CASE
               WHEN COUNT(*) OVER (
                   PARTITION BY operator_id, table_name
                   ORDER BY operation_time
                   RANGE BETWEEN INTERVAL 10 SECOND PRECEDING AND INTERVAL 10 SECOND FOLLOWING
               ) > 100 THEN 1
               ELSE 0
           END AS is_batch_operation
    FROM data_audit_log
),
sensitive_table_check AS (
    SELECT log_id,
           CASE WHEN table_name IN ('user', 'policy_master', 'claim_report') THEN 1 ELSE 0 END AS is_sensitive_table
    FROM data_audit_log
),
audit_anomaly_marked AS (
    SELECT wtc.log_id,
           wtc.is_off_hours,
           boc.is_batch_operation,
           stc.is_sensitive_table,
           CASE WHEN wtc.is_off_hours = 1
                  OR boc.is_batch_operation = 1
                  OR stc.is_sensitive_table = 1 THEN 1 ELSE 0 END AS is_anomaly
    FROM work_time_check wtc
    INNER JOIN batch_operation_check boc ON wtc.log_id = boc.log_id
    INNER JOIN sensitive_table_check stc ON wtc.log_id = stc.log_id
)
SELECT COUNT(*) AS total_log_count,
       SUM(is_off_hours) AS off_hours_count,
       SUM(is_batch_operation) AS batch_operation_count,
       SUM(is_sensitive_table) AS sensitive_table_count,
       SUM(is_anomaly) AS anomaly_count,
       ROUND(SUM(is_anomaly) * 100.0 / NULLIF(COUNT(*), 0), 2) AS anomaly_rate_pct
FROM audit_anomaly_marked;

-- 5.4 按操作者统计异常行为次数（TOP10异常操作者）
WITH work_time_check AS (
    SELECT log_id,
           operator_id,
           CASE WHEN HOUR(operation_time) NOT BETWEEN 9 AND 18 THEN 1 ELSE 0 END AS is_off_hours
    FROM data_audit_log
),
batch_operation_check AS (
    SELECT log_id,
           operator_id,
           CASE
               WHEN COUNT(*) OVER (
                   PARTITION BY operator_id, table_name
                   ORDER BY operation_time
                   RANGE BETWEEN INTERVAL 10 SECOND PRECEDING AND INTERVAL 10 SECOND FOLLOWING
               ) > 100 THEN 1
               ELSE 0
           END AS is_batch_operation
    FROM data_audit_log
),
sensitive_table_check AS (
    SELECT log_id,
           CASE WHEN table_name IN ('user', 'policy_master', 'claim_report') THEN 1 ELSE 0 END AS is_sensitive_table
    FROM data_audit_log
),
audit_anomaly_marked AS (
    SELECT wtc.log_id,
           wtc.operator_id,
           wtc.is_off_hours,
           boc.is_batch_operation,
           stc.is_sensitive_table,
           CASE WHEN wtc.is_off_hours = 1
                  OR boc.is_batch_operation = 1
                  OR stc.is_sensitive_table = 1 THEN 1 ELSE 0 END AS is_anomaly
    FROM work_time_check wtc
    INNER JOIN batch_operation_check boc ON wtc.log_id = boc.log_id
    INNER JOIN sensitive_table_check stc ON wtc.log_id = stc.log_id
)
SELECT operator_id,
       COUNT(*) AS total_operation_count,
       SUM(is_anomaly) AS anomaly_count,
       SUM(is_off_hours) AS off_hours_count,
       SUM(is_batch_operation) AS batch_count,
       SUM(is_sensitive_table) AS sensitive_count,
       ROUND(SUM(is_anomaly) * 100.0 / NULLIF(COUNT(*), 0), 2) AS anomaly_rate_pct
FROM audit_anomaly_marked
GROUP BY operator_id
ORDER BY anomaly_count DESC
LIMIT 10;

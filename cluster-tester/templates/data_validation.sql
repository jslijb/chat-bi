-- =====================================================================
-- 数据验证SQL模板
-- 用途：ETL执行后验证目标表数据正确性
-- 参数：{target_table} {source_table} {biz_date} {tolerance_percent}
-- =====================================================================

-- 1. 行数一致性验证：目标表行数 vs 源表行数
-- 预期：目标表行数应接近源表行数（允许聚合后减少）
SELECT
    'row_count_check' AS check_type,
    COUNT(*) AS target_rows,
    (SELECT COUNT(*) FROM {source_table} WHERE dt = '{biz_date}') AS source_rows,
    ABS(COUNT(*) - (SELECT COUNT(*) FROM {source_table} WHERE dt = '{biz_date}')) AS diff
FROM {target_table}
WHERE dt = '{biz_date}';

-- 2. 空值率验证：关键字段空值率应低于阈值
SELECT
    'null_rate_check' AS check_type,
    COUNT(*) AS total_rows,
    SUM(CASE WHEN channel_code IS NULL THEN 1 ELSE 0 END) AS null_channel_count,
    ROUND(SUM(CASE WHEN channel_code IS NULL THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0), 2) AS null_channel_pct,
    SUM(CASE WHEN total_premium IS NULL THEN 1 ELSE 0 END) AS null_premium_count,
    ROUND(SUM(CASE WHEN total_premium IS NULL THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0), 2) AS null_premium_pct
FROM {target_table}
WHERE dt = '{biz_date}';

-- 3. 指标一致性验证：目标表SUM值 vs 源表SUM值
-- 预期：差异率应低于tolerance_percent
SELECT
    'metric_consistency_check' AS check_type,
    SUM(total_premium) AS target_sum,
    (SELECT SUM(premium_amount) FROM {source_table} WHERE dt = '{biz_date}') AS source_sum,
    ROUND(
        ABS(SUM(total_premium) - (SELECT SUM(premium_amount) FROM {source_table} WHERE dt = '{biz_date}'))
        * 100.0
        / NULLIF((SELECT SUM(premium_amount) FROM {source_table} WHERE dt = '{biz_date}'), 0),
        4
    ) AS diff_pct
FROM {target_table}
WHERE dt = '{biz_date}';

-- 4. 分区完整性验证：目标表应有当日分区
SELECT
    'partition_check' AS check_type,
    COUNT(DISTINCT dt) AS partition_count,
    MIN(dt) AS min_dt,
    MAX(dt) AS max_dt,
    CASE WHEN COUNT(DISTINCT dt) > 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM {target_table}
WHERE dt = '{biz_date}';

-- =====================================================================
-- SQL验证示例：验证DWS层ETL脚本的EXPLAIN结果
-- 用途：展示sql-validator的验证流程和输出格式
-- =====================================================================

-- 待验证的ETL SQL（示例）
INSERT OVERWRITE TABLE paimon.cx_dws_safe.dws_policy_premium_daily PARTITION(dt)
SELECT
    policy_no,
    channel_code,
    product_code,
    policy_status,
    SUM(premium_amount)   AS total_premium,
    COUNT(DISTINCT policy_no) AS policy_count,
    CURRENT_TIMESTAMP()   AS etl_time,
    dt
FROM paimon.cx_dwd_safe.dwd_policy_premium_detail
WHERE dt = '${biz_date}'
GROUP BY
    policy_no, channel_code, product_code, policy_status, dt;

-- 验证结果示例：
-- [OK] V-001 语法检查: 通过
-- [OK] V-002 表存在性: paimon.cx_dwd_safe.dwd_policy_premium_detail 存在
-- [OK] V-003 字段存在性: 所有字段验证通过
-- [OK] V-004 无SELECT星号: 通过
-- [OK] V-005 分区裁剪: WHERE dt = '${biz_date}' 包含分区字段
-- [INFO] V-006 数据倾斜: GROUP BY含policy_no(高基数), 建议增加bucket配置

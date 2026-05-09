-- ======================================================
-- G端惠民与公益域补充数据
-- 目的：补充惠民保产品、惠民保参保记录、隐患路段、改造项目、公益积分、农险保单
-- 依赖：user表(1-50), policy_master表(已有保单号)
-- 注意：gov_insurance_policy和agricultural_policy的policy_no需引用policy_master
--       此处先插入对应的policy_master记录，再关联
-- ======================================================
USE `pingan_insurance`;

-- 惠民保产品（5条，product_code如HUIMIN_SH/SZ/GZ/BJ/CD）
INSERT INTO `gov_insurance_product` (product_code, product_name, region, coverage, premium_subsidy, status) VALUES
('HUIMIN_SH', '上海惠民保', '上海', '{"medical": 2000000, "special_drug": 500000}', 15000, 1),
('HUIMIN_SZ', '深圳惠民保', '深圳', '{"medical": 3000000, "special_drug": 800000}', 20000, 1),
('HUIMIN_GZ', '广州惠民保', '广州', '{"medical": 2500000, "special_drug": 600000}', 18000, 1),
('HUIMIN_BJ', '北京惠民保', '北京', '{"medical": 2500000, "special_drug": 700000}', 20000, 1),
('HUIMIN_CD', '成都惠民保', '成都', '{"medical": 2000000, "special_drug": 500000}', 12000, 1);

-- 惠民保参保需要的policy_master记录（20条，需先插入policy_master才能被gov_insurance_policy引用）
INSERT INTO `policy_master` (policy_no, user_id, product_code, premium_total, effective_date, expiry_date, policy_status, issue_date, channel) VALUES
('HUIMIN-P-001', 1, 'CAR_COMPREHENSIVE', 11500, '2026-01-01', '2027-01-01', 1, '2025-12-28 10:00:00', 'APP'),
('HUIMIN-P-002', 2, 'CAR_COMPREHENSIVE', 12000, '2026-01-01', '2027-01-01', 1, '2025-12-28 10:00:00', 'APP'),
('HUIMIN-P-003', 3, 'CAR_COMPREHENSIVE', 11800, '2026-01-01', '2027-01-01', 1, '2025-12-28 10:00:00', 'APP'),
('HUIMIN-P-004', 4, 'CAR_COMPREHENSIVE', 11500, '2026-01-01', '2027-01-01', 1, '2025-12-28 10:00:00', 'APP'),
('HUIMIN-P-005', 5, 'CAR_COMPREHENSIVE', 12000, '2026-02-01', '2027-02-01', 1, '2026-01-28 10:00:00', 'APP'),
('HUIMIN-P-006', 6, 'CAR_COMPREHENSIVE', 11800, '2026-02-01', '2027-02-01', 1, '2026-01-28 10:00:00', 'APP'),
('HUIMIN-P-007', 7, 'CAR_COMPREHENSIVE', 11500, '2026-02-01', '2027-02-01', 1, '2026-01-28 10:00:00', 'APP'),
('HUIMIN-P-008', 8, 'CAR_COMPREHENSIVE', 12000, '2026-02-01', '2027-02-01', 1, '2026-01-28 10:00:00', 'APP'),
('HUIMIN-P-009', 9, 'CAR_COMPREHENSIVE', 11800, '2026-03-01', '2027-03-01', 1, '2026-02-28 10:00:00', 'APP'),
('HUIMIN-P-010', 10, 'CAR_COMPREHENSIVE', 11500, '2026-03-01', '2027-03-01', 1, '2026-02-28 10:00:00', 'APP'),
('HUIMIN-P-011', 11, 'CAR_COMPREHENSIVE', 12000, '2026-03-01', '2027-03-01', 1, '2026-02-28 10:00:00', 'APP'),
('HUIMIN-P-012', 12, 'CAR_COMPREHENSIVE', 11800, '2026-03-01', '2027-03-01', 1, '2026-02-28 10:00:00', 'APP'),
('HUIMIN-P-013', 13, 'CAR_COMPREHENSIVE', 11500, '2026-01-15', '2027-01-15', 1, '2026-01-10 10:00:00', 'OFFLINE'),
('HUIMIN-P-014', 14, 'CAR_COMPREHENSIVE', 12000, '2026-01-15', '2027-01-15', 1, '2026-01-10 10:00:00', 'OFFLINE'),
('HUIMIN-P-015', 15, 'CAR_COMPREHENSIVE', 11800, '2026-02-15', '2027-02-15', 1, '2026-02-10 10:00:00', 'OFFLINE'),
('HUIMIN-P-016', 16, 'CAR_COMPREHENSIVE', 11500, '2026-02-15', '2027-02-15', 1, '2026-02-10 10:00:00', 'OFFLINE'),
('HUIMIN-P-017', 17, 'CAR_COMPREHENSIVE', 12000, '2026-03-15', '2027-03-15', 1, '2026-03-10 10:00:00', 'OFFLINE'),
('HUIMIN-P-018', 18, 'CAR_COMPREHENSIVE', 11800, '2026-03-15', '2027-03-15', 1, '2026-03-10 10:00:00', 'OFFLINE'),
('HUIMIN-P-019', 19, 'CAR_COMPREHENSIVE', 11500, '2026-03-15', '2027-03-15', 1, '2026-03-10 10:00:00', 'OFFLINE'),
('HUIMIN-P-020', 20, 'CAR_COMPREHENSIVE', 12000, '2026-03-15', '2027-03-15', 1, '2026-03-10 10:00:00', 'OFFLINE');

-- 惠民保参保记录（20条，user_id关联1-40用户，product_code关联5个产品）
INSERT INTO `gov_insurance_policy` (policy_no, user_id, product_code, subsidy_amount, self_pay_amount) VALUES
('HUIMIN-P-001', 1, 'HUIMIN_SZ', 20000, 15000),
('HUIMIN-P-002', 2, 'HUIMIN_SZ', 20000, 15000),
('HUIMIN-P-003', 3, 'HUIMIN_GZ', 18000, 12000),
('HUIMIN-P-004', 4, 'HUIMIN_GZ', 18000, 12000),
('HUIMIN-P-005', 5, 'HUIMIN_SH', 15000, 10000),
('HUIMIN-P-006', 6, 'HUIMIN_SH', 15000, 10000),
('HUIMIN-P-007', 7, 'HUIMIN_BJ', 20000, 15000),
('HUIMIN-P-008', 8, 'HUIMIN_BJ', 20000, 15000),
('HUIMIN-P-009', 9, 'HUIMIN_CD', 12000, 8000),
('HUIMIN-P-010', 10, 'HUIMIN_CD', 12000, 8000),
('HUIMIN-P-011', 11, 'HUIMIN_SZ', 20000, 15000),
('HUIMIN-P-012', 12, 'HUIMIN_GZ', 18000, 12000),
('HUIMIN-P-013', 13, 'HUIMIN_SH', 15000, 10000),
('HUIMIN-P-014', 14, 'HUIMIN_BJ', 20000, 15000),
('HUIMIN-P-015', 15, 'HUIMIN_CD', 12000, 8000),
('HUIMIN-P-016', 16, 'HUIMIN_SZ', 20000, 15000),
('HUIMIN-P-017', 17, 'HUIMIN_GZ', 18000, 12000),
('HUIMIN-P-018', 18, 'HUIMIN_SH', 15000, 10000),
('HUIMIN-P-019', 19, 'HUIMIN_BJ', 20000, 15000),
('HUIMIN-P-020', 20, 'HUIMIN_CD', 12000, 8000);

-- 隐患路段（8条，improvement_status覆盖0待改造2条/1改造中3条/2已完成3条）
INSERT INTO `blackspot_road` (road_name, location_gps, risk_type, accident_count, improvement_status, donation_amount) VALUES
('深南大道科技园路口', ST_GeomFromText('POINT(113.95 22.54)'), '弯道盲区', 23, 0, NULL),
('福田保税区桂花路', ST_GeomFromText('POINT(114.06 22.52)'), '行人横穿', 18, 0, NULL),
('天河区黄埔大道隧道', ST_GeomFromText('POINT(113.37 23.13)'), '弯道盲区', 31, 1, 500000),
('海珠区新港中路', ST_GeomFromText('POINT(113.29 23.09)'), '机非混行', 15, 1, 300000),
('浦东新区张杨路', ST_GeomFromText('POINT(121.53 31.23)'), '行人横穿', 27, 1, 400000),
('海淀区西三环辅路', ST_GeomFromText('POINT(116.30 39.96)'), '弯道盲区', 22, 2, 600000),
('武侯区二环路', ST_GeomFromText('POINT(104.06 30.63)'), '机非混行', 19, 2, 350000),
('高新区天府大道', ST_GeomFromText('POINT(104.07 30.54)'), '行人横穿', 12, 2, 250000);

-- 路段改造项目（6条，road_id关联隐患路段1-6，status覆盖1进行中2条/2已完成4条）
INSERT INTO `road_improvement_project` (road_id, project_name, start_date, end_date, budget, status) VALUES
(3, '黄埔大道隧道照明改造工程', '2026-01-15', NULL, 800000, 1),
(4, '新港中路隔离护栏增设工程', '2026-02-01', NULL, 500000, 1),
(5, '张杨路人行天桥建设工程', '2025-10-01', '2026-03-15', 1500000, 2),
(6, '西三环辅路反光镜安装工程', '2025-08-01', '2026-01-20', 300000, 2),
(7, '二环路非机动车道改造工程', '2025-09-01', '2026-02-28', 600000, 2),
(8, '天府大道智能斑马线工程', '2025-11-01', '2026-03-10', 450000, 2);

-- 公益积分（15条，user_id关联1-25用户，source覆盖1安全驾驶8条/2公益活动7条）
INSERT INTO `public_welfare_points` (user_id, points, source, convert_time) VALUES
(1, 500, 1, '2026-01-10 08:00:00'),
(3, 300, 1, '2026-01-15 09:30:00'),
(5, 800, 1, '2026-01-20 10:00:00'),
(7, 200, 1, '2026-02-05 11:30:00'),
(9, 600, 1, '2026-02-10 07:45:00'),
(11, 400, 1, '2026-02-15 08:15:00'),
(13, 350, 1, '2026-03-01 09:00:00'),
(15, 700, 1, '2026-03-05 10:30:00'),
(2, 250, 2, '2026-01-12 14:00:00'),
(4, 150, 2, '2026-01-18 15:30:00'),
(6, 300, 2, '2026-02-08 13:00:00'),
(8, 500, 2, '2026-02-12 16:00:00'),
(10, 200, 2, '2026-02-20 14:30:00'),
(12, 400, 2, '2026-03-02 11:00:00'),
(14, 350, 2, '2026-03-08 15:15:00');

-- 农险保单需要先插入policy_master记录
INSERT INTO `policy_master` (policy_no, user_id, product_code, premium_total, effective_date, expiry_date, policy_status, issue_date, channel) VALUES
('AGRI-P-001', 25, 'CAR_COMPREHENSIVE', 8500, '2026-01-01', '2027-01-01', 1, '2025-12-28 10:00:00', 'OFFLINE'),
('AGRI-P-002', 26, 'CAR_COMPREHENSIVE', 12000, '2026-02-01', '2027-02-01', 1, '2026-01-25 10:00:00', 'OFFLINE'),
('AGRI-P-003', 27, 'CAR_COMPREHENSIVE', 6000, '2026-03-01', '2027-03-01', 1, '2026-02-28 10:00:00', 'OFFLINE');

-- 农险保单（3条）
INSERT INTO `agricultural_policy` (policy_no, farmer_name, crop_type, insured_area, subsidy_rate) VALUES
('AGRI-P-001', '张大壮', '水稻', 150.00, 40.00),
('AGRI-P-002', '李丰收', '小麦', 200.00, 35.00),
('AGRI-P-003', '王春耕', '玉米', 80.00, 30.00);

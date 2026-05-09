-- ======================================================
-- 平安产险业务数据库（好车主 + 好生活）
-- 字符集：utf8mb4（支持emoji，兼容全场景）
-- 存储引擎：InnoDB（支持事务、外键）
-- 版本要求：MySQL 8.0+
-- ======================================================

-- 创建数据库（若已存在则跳过）
CREATE DATABASE IF NOT EXISTS `pingan_insurance`
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

USE `pingan_insurance`;

-- ======================================================
-- 1. 用户与客户域（12张表）
-- ======================================================

-- 用户主表
CREATE TABLE `user` (
    `user_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '用户ID',
    `mobile` VARCHAR(20) NOT NULL COMMENT '手机号',
    `id_type` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '证件类型：1-身份证，2-护照，3-军官证，...',
    `id_no` VARCHAR(32) NOT NULL COMMENT '证件号码（加密存储）',
    `real_name` VARCHAR(64) DEFAULT NULL COMMENT '真实姓名',
    `nickname` VARCHAR(64) DEFAULT NULL COMMENT '昵称',
    `gender` TINYINT UNSIGNED DEFAULT NULL COMMENT '性别：0-未知，1-男，2-女',
    `birth_date` DATE DEFAULT NULL COMMENT '出生日期',
    `register_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '注册时间',
    `last_login_time` DATETIME DEFAULT NULL COMMENT '最后登录时间',
    `status` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '状态：0-冻结，1-正常，2-注销',
    `is_deleted` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '逻辑删除标记：0-未删除，1-已删除',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`user_id`),
    UNIQUE KEY `uk_mobile` (`mobile`),
    UNIQUE KEY `uk_id_type_id_no` (`id_type`, `id_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='个人用户主表';

-- 用户认证信息表
CREATE TABLE `user_auth` (
    `auth_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '认证ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `password_salt` VARCHAR(32) NOT NULL COMMENT '密码盐',
    `password_hash` VARCHAR(128) NOT NULL COMMENT '密码哈希',
    `wechat_openid` VARCHAR(64) DEFAULT NULL COMMENT '微信openid',
    `alipay_userid` VARCHAR(64) DEFAULT NULL COMMENT '支付宝用户ID',
    `unionid` VARCHAR(64) DEFAULT NULL COMMENT '微信unionid',
    `apple_id` VARCHAR(64) DEFAULT NULL COMMENT 'Apple ID',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`auth_id`),
    UNIQUE KEY `uk_user_id` (`user_id`),
    UNIQUE KEY `uk_wechat_openid` (`wechat_openid`),
    UNIQUE KEY `uk_alipay_userid` (`alipay_userid`),
    UNIQUE KEY `uk_apple_id` (`apple_id`),
    CONSTRAINT `fk_user_auth_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户认证信息表';

-- 用户扩展资料表
CREATE TABLE `user_profile` (
    `profile_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '资料ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `occupation` VARCHAR(64) DEFAULT NULL COMMENT '职业',
    `education` VARCHAR(32) DEFAULT NULL COMMENT '学历',
    `annual_income` INT UNSIGNED DEFAULT NULL COMMENT '年收入（元）',
    `household_register` VARCHAR(128) DEFAULT NULL COMMENT '户籍地址',
    `address` VARCHAR(256) DEFAULT NULL COMMENT '现住址',
    `marital_status` TINYINT UNSIGNED DEFAULT NULL COMMENT '婚姻状况：1-未婚，2-已婚，3-离异，4-丧偶',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`profile_id`),
    UNIQUE KEY `uk_user_id` (`user_id`),
    CONSTRAINT `fk_user_profile_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户扩展资料表';

-- 用户车辆档案表
CREATE TABLE `user_vehicle` (
    `vehicle_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '车辆档案ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '车主用户ID',
    `license_plate` VARCHAR(16) NOT NULL COMMENT '车牌号',
    `vin` VARCHAR(17) NOT NULL COMMENT '车架号(VIN)',
    `brand` VARCHAR(32) NOT NULL COMMENT '品牌',
    `model` VARCHAR(64) NOT NULL COMMENT '车型',
    `model_code` VARCHAR(32) DEFAULT NULL COMMENT '车型编码（关联定价）',
    `register_date` DATE NOT NULL COMMENT '首次上牌日期',
    `first_register_date` DATE DEFAULT NULL COMMENT '车辆首次登记日期（新车/二手）',
    `engine_no` VARCHAR(32) DEFAULT NULL COMMENT '发动机号',
    `seat_count` TINYINT UNSIGNED DEFAULT NULL COMMENT '核定载客数',
    `vehicle_type` TINYINT UNSIGNED DEFAULT NULL COMMENT '车辆类型：1-私家车，2-企业车，3-营运车',
    `is_deleted` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '逻辑删除标记',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`vehicle_id`),
    UNIQUE KEY `uk_vin` (`vin`),
    UNIQUE KEY `uk_license_plate` (`license_plate`),
    KEY `idx_user_id` (`user_id`),
    CONSTRAINT `fk_user_vehicle_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户车辆档案表';

-- 用户风险评分表
CREATE TABLE `user_risk_score` (
    `score_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '评分ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `score` DECIMAL(5,2) NOT NULL COMMENT '风险评分（0-100）',
    `score_date` DATE NOT NULL COMMENT '评分日期',
    `model_version` VARCHAR(32) NOT NULL COMMENT '模型版本',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`score_id`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_score_date` (`score_date`),
    CONSTRAINT `fk_user_risk_score_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户风险评分表（历史记录）';

-- 企业客户主表
CREATE TABLE `enterprise` (
    `enterprise_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '企业ID',
    `name` VARCHAR(128) NOT NULL COMMENT '企业名称',
    `credit_code` VARCHAR(18) NOT NULL COMMENT '统一社会信用代码',
    `legal_person` VARCHAR(64) DEFAULT NULL COMMENT '法定代表人',
    `contact_phone` VARCHAR(20) NOT NULL COMMENT '联系电话',
    `contact_person` VARCHAR(64) DEFAULT NULL COMMENT '联系人',
    `address` VARCHAR(256) DEFAULT NULL COMMENT '注册地址',
    `industry` VARCHAR(64) DEFAULT NULL COMMENT '所属行业',
    `status` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '状态：0-冻结，1-正常',
    `is_deleted` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '逻辑删除标记',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`enterprise_id`),
    UNIQUE KEY `uk_credit_code` (`credit_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='企业客户主表';

-- 企业用户关联表
CREATE TABLE `enterprise_user` (
    `rel_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '关联ID',
    `enterprise_id` BIGINT UNSIGNED NOT NULL COMMENT '企业ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `role` TINYINT UNSIGNED NOT NULL COMMENT '角色：1-管理员，2-员工，3-经办人',
    `bind_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '绑定时间',
    `unbind_time` DATETIME DEFAULT NULL COMMENT '解绑时间',
    `status` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '状态：1-生效，0-失效',
    PRIMARY KEY (`rel_id`),
    UNIQUE KEY `uk_enterprise_user` (`enterprise_id`, `user_id`),
    KEY `idx_user_id` (`user_id`),
    CONSTRAINT `fk_enterprise_user_enterprise_id` FOREIGN KEY (`enterprise_id`) REFERENCES `enterprise` (`enterprise_id`) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_enterprise_user_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='企业-用户关联表';

-- 代理人信息表
CREATE TABLE `agent` (
    `agent_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '代理人ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '关联用户ID',
    `agent_code` VARCHAR(32) NOT NULL COMMENT '代理人编号',
    `level` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '职级：1-普通，2-主管，3-经理',
    `org_id` BIGINT UNSIGNED NOT NULL COMMENT '所属机构ID',
    `hire_date` DATE NOT NULL COMMENT '入职日期',
    `status` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '状态：1-在职，0-离职',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`agent_id`),
    UNIQUE KEY `uk_agent_code` (`agent_code`),
    UNIQUE KEY `uk_user_id` (`user_id`),
    CONSTRAINT `fk_agent_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='代理人信息表';

-- 代理人-客户关系表
CREATE TABLE `agent_customer` (
    `rel_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '关系ID',
    `agent_id` BIGINT UNSIGNED NOT NULL COMMENT '代理人ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '客户用户ID',
    `bind_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '绑定时间',
    `unbind_time` DATETIME DEFAULT NULL COMMENT '解绑时间',
    `source` VARCHAR(32) DEFAULT NULL COMMENT '绑定来源',
    PRIMARY KEY (`rel_id`),
    UNIQUE KEY `uk_agent_customer` (`agent_id`, `user_id`),
    KEY `idx_user_id` (`user_id`),
    CONSTRAINT `fk_agent_customer_agent_id` FOREIGN KEY (`agent_id`) REFERENCES `agent` (`agent_id`) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_agent_customer_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='代理人-客户关系表';

-- 黑名单表
CREATE TABLE `blacklist` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'ID',
    `target_type` TINYINT UNSIGNED NOT NULL COMMENT '对象类型：1-用户，2-车辆，3-企业',
    `target_id` VARCHAR(64) NOT NULL COMMENT '对象ID（user_id/vehicle_id/enterprise_id）',
    `reason` VARCHAR(256) NOT NULL COMMENT '列入原因',
    `operator` VARCHAR(64) NOT NULL COMMENT '操作人',
    `add_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '列入时间',
    `expire_time` DATETIME DEFAULT NULL COMMENT '过期时间（NULL表示永久）',
    `status` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '状态：1-生效，0-已解除',
    `remove_time` DATETIME DEFAULT NULL COMMENT '解除时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_target` (`target_type`, `target_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='黑名单表';

-- 用户会话表
CREATE TABLE `session` (
    `session_id` VARCHAR(64) NOT NULL COMMENT '会话ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `token` VARCHAR(512) NOT NULL COMMENT '认证Token',
    `expire_time` DATETIME NOT NULL COMMENT '过期时间',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`session_id`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_expire_time` (`expire_time`),
    CONSTRAINT `fk_session_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户会话表';

-- 用户设备信息表
CREATE TABLE `device` (
    `device_id` VARCHAR(64) NOT NULL COMMENT '设备唯一标识',
    `user_id` BIGINT UNSIGNED DEFAULT NULL COMMENT '用户ID（未登录可为空）',
    `os_type` VARCHAR(16) DEFAULT NULL COMMENT '操作系统：iOS/Android',
    `app_version` VARCHAR(16) DEFAULT NULL COMMENT 'APP版本号',
    `push_token` VARCHAR(256) DEFAULT NULL COMMENT '推送Token',
    `last_active_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '最后活跃时间',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '首次记录时间',
    PRIMARY KEY (`device_id`),
    KEY `idx_user_id` (`user_id`),
    CONSTRAINT `fk_device_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户设备信息表';

-- ======================================================
-- 2. 保单域（18张表）
-- ======================================================

-- 保险产品定义表
CREATE TABLE `product_definition` (
    `product_code` VARCHAR(32) NOT NULL COMMENT '产品代码',
    `product_name` VARCHAR(128) NOT NULL COMMENT '产品名称',
    `product_type` TINYINT UNSIGNED NOT NULL COMMENT '产品类型：1-车险，2-健康险，3-家财险，4-旅行险，5-宠物险，6-意外险',
    `risk_list_json` JSON NOT NULL COMMENT '所含险种列表JSON',
    `price_formula` TEXT COMMENT '定价公式（表达式）',
    `description` VARCHAR(512) DEFAULT NULL COMMENT '产品说明',
    `status` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '状态：1-在售，0-停售',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`product_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='保险产品定义表';

-- 定价因子配置表
CREATE TABLE `price_factor` (
    `factor_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '因子ID',
    `product_code` VARCHAR(32) NOT NULL COMMENT '产品代码',
    `factor_name` VARCHAR(64) NOT NULL COMMENT '因子名称（如NCD系数、年龄系数）',
    `factor_type` TINYINT UNSIGNED NOT NULL COMMENT '因子类型：1-连续，2-离散',
    `factor_values` JSON NOT NULL COMMENT '因子取值范围/映射',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`factor_id`),
    KEY `idx_product_code` (`product_code`),
    CONSTRAINT `fk_price_factor_product_code` FOREIGN KEY (`product_code`) REFERENCES `product_definition` (`product_code`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='定价因子配置表';

-- 核保规则表
CREATE TABLE `underwriting_rule` (
    `rule_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '规则ID',
    `product_code` VARCHAR(32) NOT NULL COMMENT '产品代码',
    `rule_name` VARCHAR(128) NOT NULL COMMENT '规则名称',
    `rule_expression` TEXT NOT NULL COMMENT '规则表达式（如 age > 65）',
    `action` TINYINT UNSIGNED NOT NULL COMMENT '动作：1-通过，2-拒绝，3-人工审核',
    `priority` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '优先级（数值越小越高）',
    `status` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '状态：1-启用，0-停用',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`rule_id`),
    KEY `idx_product_code` (`product_code`),
    CONSTRAINT `fk_underwriting_rule_product_code` FOREIGN KEY (`product_code`) REFERENCES `product_definition` (`product_code`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='核保规则表';

-- 保单主表
CREATE TABLE `policy_master` (
    `policy_no` VARCHAR(32) NOT NULL COMMENT '保单号',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '投保人用户ID',
    `vehicle_id` BIGINT UNSIGNED DEFAULT NULL COMMENT '车辆ID（车险必填）',
    `enterprise_id` BIGINT UNSIGNED DEFAULT NULL COMMENT '企业ID（企业保单）',
    `product_code` VARCHAR(32) NOT NULL COMMENT '产品代码',
    `premium_total` INT UNSIGNED NOT NULL COMMENT '总保费（分）',
    `effective_date` DATE NOT NULL COMMENT '起保日期',
    `expiry_date` DATE NOT NULL COMMENT '终保日期',
    `policy_status` TINYINT UNSIGNED NOT NULL COMMENT '保单状态：1-有效，2-已终止，3-已过期，4-待生效',
    `issue_date` DATETIME NOT NULL COMMENT '出单日期',
    `underwriter` VARCHAR(64) DEFAULT NULL COMMENT '承保人',
    `channel` VARCHAR(32) DEFAULT NULL COMMENT '销售渠道',
    `agent_id` BIGINT UNSIGNED DEFAULT NULL COMMENT '代理人ID',
    `is_deleted` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '逻辑删除标记',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`policy_no`),
    UNIQUE KEY `uk_policy_no` (`policy_no`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_vehicle_id` (`vehicle_id`),
    KEY `idx_enterprise_id` (`enterprise_id`),
    KEY `idx_product_code` (`product_code`),
    KEY `idx_agent_id` (`agent_id`),
    KEY `idx_effective_expiry` (`effective_date`, `expiry_date`),
    CONSTRAINT `fk_policy_master_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_policy_master_vehicle_id` FOREIGN KEY (`vehicle_id`) REFERENCES `user_vehicle` (`vehicle_id`) ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT `fk_policy_master_enterprise_id` FOREIGN KEY (`enterprise_id`) REFERENCES `enterprise` (`enterprise_id`) ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT `fk_policy_master_product_code` FOREIGN KEY (`product_code`) REFERENCES `product_definition` (`product_code`) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_policy_master_agent_id` FOREIGN KEY (`agent_id`) REFERENCES `agent` (`agent_id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='保单主表';

-- 险种明细表
CREATE TABLE `policy_risk_detail` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'ID',
    `policy_no` VARCHAR(32) NOT NULL COMMENT '保单号',
    `risk_code` VARCHAR(32) NOT NULL COMMENT '险种代码',
    `risk_name` VARCHAR(64) NOT NULL COMMENT '险种名称',
    `premium` INT UNSIGNED NOT NULL COMMENT '保费（分）',
    `limit_amount` INT UNSIGNED DEFAULT NULL COMMENT '保额（分）',
    `deductible` INT UNSIGNED DEFAULT NULL COMMENT '免赔额（分）',
    `status` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '状态：1-有效，0-失效',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    KEY `idx_policy_no` (`policy_no`),
    CONSTRAINT `fk_policy_risk_detail_policy_no` FOREIGN KEY (`policy_no`) REFERENCES `policy_master` (`policy_no`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='险种明细表';

-- 车险车辆信息表
CREATE TABLE `policy_vehicle_detail` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'ID',
    `policy_no` VARCHAR(32) NOT NULL COMMENT '保单号',
    `vehicle_id` BIGINT UNSIGNED NOT NULL COMMENT '车辆ID',
    `ncd_coefficient` DECIMAL(3,2) NOT NULL COMMENT 'NCD系数',
    `risk_score` DECIMAL(5,2) DEFAULT NULL COMMENT '平安内部风险评分',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_policy_no` (`policy_no`),
    KEY `idx_vehicle_id` (`vehicle_id`),
    CONSTRAINT `fk_policy_vehicle_detail_policy_no` FOREIGN KEY (`policy_no`) REFERENCES `policy_master` (`policy_no`) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_policy_vehicle_detail_vehicle_id` FOREIGN KEY (`vehicle_id`) REFERENCES `user_vehicle` (`vehicle_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='车险车辆信息表';

-- 被保险人信息表
CREATE TABLE `policy_insured` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'ID',
    `policy_no` VARCHAR(32) NOT NULL COMMENT '保单号',
    `insured_name` VARCHAR(64) NOT NULL COMMENT '被保险人姓名',
    `insured_id_type` TINYINT UNSIGNED NOT NULL COMMENT '证件类型',
    `insured_id_no` VARCHAR(32) NOT NULL COMMENT '证件号码',
    `relation_to_applicant` TINYINT UNSIGNED DEFAULT NULL COMMENT '与投保人关系：1-本人，2-配偶，3-子女，4-父母',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`id`),
    KEY `idx_policy_no` (`policy_no`),
    CONSTRAINT `fk_policy_insured_policy_no` FOREIGN KEY (`policy_no`) REFERENCES `policy_master` (`policy_no`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='被保险人信息表';

-- 批改记录表
CREATE TABLE `policy_endorsement` (
    `endorsement_no` VARCHAR(32) NOT NULL COMMENT '批单号',
    `policy_no` VARCHAR(32) NOT NULL COMMENT '保单号',
    `endorsement_type` TINYINT UNSIGNED NOT NULL COMMENT '批改类型：1-增加险种，2-减少险种，3-变更保额，4-过户，5-车牌变更',
    `before_json` JSON NOT NULL COMMENT '批改前快照',
    `after_json` JSON NOT NULL COMMENT '批改后快照',
    `effective_date` DATE NOT NULL COMMENT '生效日期',
    `status` TINYINT UNSIGNED NOT NULL COMMENT '状态：1-已申请，2-已生效，3-已作废',
    `apply_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '申请时间',
    `approve_time` DATETIME DEFAULT NULL COMMENT '审核时间',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`endorsement_no`),
    KEY `idx_policy_no` (`policy_no`),
    CONSTRAINT `fk_policy_endorsement_policy_no` FOREIGN KEY (`policy_no`) REFERENCES `policy_master` (`policy_no`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='批改记录表';

-- 非车险保单扩展表
CREATE TABLE `nonauto_policy` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'ID',
    `policy_no` VARCHAR(32) NOT NULL COMMENT '保单号',
    `policy_type` TINYINT UNSIGNED NOT NULL COMMENT '险种类别：1-健康险，2-家财险，3-旅行险，4-宠物险，5-意外险',
    `health_condition` JSON DEFAULT NULL COMMENT '健康告知条件（健康险）',
    `property_address` VARCHAR(256) DEFAULT NULL COMMENT '房产地址（家财险）',
    `travel_destination` VARCHAR(128) DEFAULT NULL COMMENT '旅行目的地（旅行险）',
    `pet_id` BIGINT UNSIGNED DEFAULT NULL COMMENT '宠物ID（宠物险）',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_policy_no` (`policy_no`),
    CONSTRAINT `fk_nonauto_policy_policy_no` FOREIGN KEY (`policy_no`) REFERENCES `policy_master` (`policy_no`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='非车险保单扩展表';

-- 健康险专有表
CREATE TABLE `health_policy` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'ID',
    `policy_no` VARCHAR(32) NOT NULL COMMENT '保单号',
    `health_questions_json` JSON NOT NULL COMMENT '健康问卷答案',
    `underwriting_result` VARCHAR(32) NOT NULL COMMENT '核保结论：标准体/加费/除外/拒保',
    `waiting_period` SMALLINT UNSIGNED DEFAULT NULL COMMENT '等待期（天）',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_policy_no` (`policy_no`),
    CONSTRAINT `fk_health_policy_policy_no` FOREIGN KEY (`policy_no`) REFERENCES `policy_master` (`policy_no`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='健康险专有表';

-- 宠物险专有表
CREATE TABLE `pet_policy` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'ID',
    `policy_no` VARCHAR(32) NOT NULL COMMENT '保单号',
    `pet_id` BIGINT UNSIGNED NOT NULL COMMENT '宠物ID',
    `pet_name` VARCHAR(64) NOT NULL COMMENT '宠物名称',
    `pet_species` VARCHAR(32) NOT NULL COMMENT '宠物种类',
    `pet_age` TINYINT UNSIGNED DEFAULT NULL COMMENT '年龄',
    `microchip_no` VARCHAR(32) DEFAULT NULL COMMENT '芯片编号',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_policy_no` (`policy_no`),
    CONSTRAINT `fk_pet_policy_policy_no` FOREIGN KEY (`policy_no`) REFERENCES `policy_master` (`policy_no`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='宠物险专有表';

-- 家财险专有表
CREATE TABLE `property_policy` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'ID',
    `policy_no` VARCHAR(32) NOT NULL COMMENT '保单号',
    `property_address` VARCHAR(256) NOT NULL COMMENT '房产地址',
    `building_area` DECIMAL(10,2) DEFAULT NULL COMMENT '建筑面积（平方米）',
    `construction_type` VARCHAR(32) DEFAULT NULL COMMENT '建筑结构',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_policy_no` (`policy_no`),
    CONSTRAINT `fk_property_policy_policy_no` FOREIGN KEY (`policy_no`) REFERENCES `policy_master` (`policy_no`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='家财险专有表';

-- 旅行险专有表
CREATE TABLE `travel_policy` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'ID',
    `policy_no` VARCHAR(32) NOT NULL COMMENT '保单号',
    `destination` VARCHAR(128) NOT NULL COMMENT '旅行目的地',
    `travel_start_date` DATE NOT NULL COMMENT '出发日期',
    `travel_end_date` DATE NOT NULL COMMENT '返回日期',
    `insured_person_list` JSON NOT NULL COMMENT '被保险人列表JSON',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_policy_no` (`policy_no`),
    CONSTRAINT `fk_travel_policy_policy_no` FOREIGN KEY (`policy_no`) REFERENCES `policy_master` (`policy_no`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='旅行险专有表';

-- 核保日志表
CREATE TABLE `underwriting_log` (
    `log_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '日志ID',
    `policy_no` VARCHAR(32) NOT NULL COMMENT '保单号',
    `rule_id` BIGINT UNSIGNED DEFAULT NULL COMMENT '命中的规则ID',
    `hit_result` TINYINT UNSIGNED NOT NULL COMMENT '命中结果：1-通过，2-拒绝，3-人工',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '核保时间',
    PRIMARY KEY (`log_id`),
    KEY `idx_policy_no` (`policy_no`),
    KEY `idx_rule_id` (`rule_id`),
    CONSTRAINT `fk_underwriting_log_policy_no` FOREIGN KEY (`policy_no`) REFERENCES `policy_master` (`policy_no`) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_underwriting_log_rule_id` FOREIGN KEY (`rule_id`) REFERENCES `underwriting_rule` (`rule_id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='核保日志表';

-- 再保记录表
CREATE TABLE `reinsurance` (
    `reinsurance_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '再保记录ID',
    `policy_no` VARCHAR(32) NOT NULL COMMENT '保单号',
    `ceding_company` VARCHAR(128) NOT NULL COMMENT '分出公司',
    `ceding_percentage` DECIMAL(5,2) NOT NULL COMMENT '分出比例（%）',
    `ceded_premium` INT UNSIGNED NOT NULL COMMENT '分出保费（分）',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`reinsurance_id`),
    KEY `idx_policy_no` (`policy_no`),
    CONSTRAINT `fk_reinsurance_policy_no` FOREIGN KEY (`policy_no`) REFERENCES `policy_master` (`policy_no`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='再保记录表';

-- 中保信上传日志表
CREATE TABLE `policy_upload_log` (
    `log_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '日志ID',
    `policy_no` VARCHAR(32) NOT NULL COMMENT '保单号',
    `upload_time` DATETIME NOT NULL COMMENT '上传时间',
    `upload_status` TINYINT UNSIGNED NOT NULL COMMENT '状态：1-成功，2-失败，3-重试中',
    `response_msg` VARCHAR(512) DEFAULT NULL COMMENT '响应信息',
    `retry_count` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '重试次数',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`log_id`),
    KEY `idx_policy_no` (`policy_no`),
    KEY `idx_upload_status` (`upload_status`),
    CONSTRAINT `fk_policy_upload_log_policy_no` FOREIGN KEY (`policy_no`) REFERENCES `policy_master` (`policy_no`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='中保信上传日志表';

-- 保费支付记录表
CREATE TABLE `premium_payment` (
    `payment_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '支付ID',
    `policy_no` VARCHAR(32) NOT NULL COMMENT '保单号',
    `amount` INT UNSIGNED NOT NULL COMMENT '支付金额（分）',
    `payment_channel` TINYINT UNSIGNED NOT NULL COMMENT '支付渠道：1-微信，2-支付宝，3-银行卡，4-积分抵扣',
    `transaction_id` VARCHAR(64) NOT NULL COMMENT '支付平台交易号',
    `payment_time` DATETIME NOT NULL COMMENT '支付时间',
    `status` TINYINT UNSIGNED NOT NULL COMMENT '状态：1-成功，2-失败，3-退款',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`payment_id`),
    UNIQUE KEY `uk_transaction_id` (`transaction_id`),
    KEY `idx_policy_no` (`policy_no`),
    KEY `idx_payment_time` (`payment_time`),
    CONSTRAINT `fk_premium_payment_policy_no` FOREIGN KEY (`policy_no`) REFERENCES `policy_master` (`policy_no`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='保费支付记录表';

-- 保费对账表
CREATE TABLE `premium_reconciliation` (
    `reconciliation_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '对账ID',
    `payment_id` BIGINT UNSIGNED NOT NULL COMMENT '支付ID',
    `channel_bill_file` VARCHAR(256) NOT NULL COMMENT '渠道账单文件路径',
    `channel_amount` INT UNSIGNED NOT NULL COMMENT '渠道清算金额（分）',
    `diff_amount` INT NOT NULL COMMENT '差异金额（分，正数为我方多，负数为渠道多）',
    `reconcile_status` TINYINT UNSIGNED NOT NULL COMMENT '对账状态：1-平账，2-我方长款，3-渠道长款，4-待处理',
    `reconcile_time` DATETIME DEFAULT NULL COMMENT '对账时间',
    `remark` VARCHAR(256) DEFAULT NULL COMMENT '备注',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`reconciliation_id`),
    KEY `idx_payment_id` (`payment_id`),
    KEY `idx_reconcile_status` (`reconcile_status`),
    CONSTRAINT `fk_premium_reconciliation_payment_id` FOREIGN KEY (`payment_id`) REFERENCES `premium_payment` (`payment_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='保费对账表';

-- ======================================================
-- 3. 理赔域（15张表）
-- ======================================================

-- 报案主表
CREATE TABLE `claim_report` (
    `claim_no` VARCHAR(32) NOT NULL COMMENT '理赔单号',
    `policy_no` VARCHAR(32) NOT NULL COMMENT '保单号',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '报案人用户ID',
    `accident_date` DATETIME NOT NULL COMMENT '出险时间',
    `accident_location` VARCHAR(256) NOT NULL COMMENT '出险地点',
    `accident_desc` VARCHAR(512) DEFAULT NULL COMMENT '事故描述',
    `report_channel` TINYINT UNSIGNED NOT NULL COMMENT '报案渠道：1-95511，2-APP，3-微信，4-代理人',
    `claim_status` TINYINT UNSIGNED NOT NULL COMMENT '理赔状态：1-已报案，2-查勘中，3-定损中，4-核赔中，5-已结案，6-拒赔',
    `is_deleted` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '逻辑删除标记',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`claim_no`),
    KEY `idx_policy_no` (`policy_no`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_claim_status` (`claim_status`),
    CONSTRAINT `fk_claim_report_policy_no` FOREIGN KEY (`policy_no`) REFERENCES `policy_master` (`policy_no`) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_claim_report_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='报案主表';

-- 车险理赔车辆信息表
CREATE TABLE `claim_vehicle` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'ID',
    `claim_no` VARCHAR(32) NOT NULL COMMENT '理赔单号',
    `vehicle_id` BIGINT UNSIGNED NOT NULL COMMENT '车辆ID',
    `driver_name` VARCHAR(64) DEFAULT NULL COMMENT '驾驶员姓名',
    `driver_license` VARCHAR(32) DEFAULT NULL COMMENT '驾驶证号',
    `accident_type` VARCHAR(32) DEFAULT NULL COMMENT '事故类型',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_claim_no` (`claim_no`),
    KEY `idx_vehicle_id` (`vehicle_id`),
    CONSTRAINT `fk_claim_vehicle_claim_no` FOREIGN KEY (`claim_no`) REFERENCES `claim_report` (`claim_no`) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_claim_vehicle_vehicle_id` FOREIGN KEY (`vehicle_id`) REFERENCES `user_vehicle` (`vehicle_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='车险理赔车辆信息表';

-- 人伤案件信息表
CREATE TABLE `claim_injury` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'ID',
    `claim_no` VARCHAR(32) NOT NULL COMMENT '理赔单号',
    `injured_person_name` VARCHAR(64) NOT NULL COMMENT '伤者姓名',
    `injured_type` TINYINT UNSIGNED NOT NULL COMMENT '伤者类型：1-驾驶员，2-乘客，3-第三方',
    `injury_desc` VARCHAR(256) DEFAULT NULL COMMENT '伤情描述',
    `hospital_name` VARCHAR(128) DEFAULT NULL COMMENT '就诊医院',
    `hospitalization_days` SMALLINT UNSIGNED DEFAULT NULL COMMENT '住院天数',
    `disability_level` TINYINT UNSIGNED DEFAULT NULL COMMENT '伤残等级（1-10级）',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`id`),
    KEY `idx_claim_no` (`claim_no`),
    CONSTRAINT `fk_claim_injury_claim_no` FOREIGN KEY (`claim_no`) REFERENCES `claim_report` (`claim_no`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='人伤案件信息表';

-- 医疗垫付记录表
CREATE TABLE `medical_advance` (
    `advance_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '垫付ID',
    `claim_no` VARCHAR(32) NOT NULL COMMENT '理赔单号',
    `amount` INT UNSIGNED NOT NULL COMMENT '垫付金额（分）',
    `hospital_name` VARCHAR(128) NOT NULL COMMENT '垫付医院',
    `advance_time` DATETIME NOT NULL COMMENT '垫付时间',
    `status` TINYINT UNSIGNED NOT NULL COMMENT '状态：1-已垫付，2-已结算，3-已核销',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`advance_id`),
    KEY `idx_claim_no` (`claim_no`),
    CONSTRAINT `fk_medical_advance_claim_no` FOREIGN KEY (`claim_no`) REFERENCES `claim_report` (`claim_no`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='医疗垫付记录表';

-- 查勘任务表
CREATE TABLE `survey_task` (
    `task_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '查勘任务ID',
    `claim_no` VARCHAR(32) NOT NULL COMMENT '理赔单号',
    `surveyor_id` BIGINT UNSIGNED NOT NULL COMMENT '查勘员ID',
    `assign_time` DATETIME NOT NULL COMMENT '派单时间',
    `arrive_time` DATETIME DEFAULT NULL COMMENT '到达现场时间',
    `survey_result` VARCHAR(512) DEFAULT NULL COMMENT '查勘结果',
    `status` TINYINT UNSIGNED NOT NULL COMMENT '状态：1-已派单，2-已到达，3-已完成',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`task_id`),
    KEY `idx_claim_no` (`claim_no`),
    KEY `idx_surveyor_id` (`surveyor_id`),
    CONSTRAINT `fk_survey_task_claim_no` FOREIGN KEY (`claim_no`) REFERENCES `claim_report` (`claim_no`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='查勘任务表';

-- 查勘员信息表
CREATE TABLE `surveyor` (
    `surveyor_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '查勘员ID',
    `name` VARCHAR(64) NOT NULL COMMENT '姓名',
    `phone` VARCHAR(20) NOT NULL COMMENT '电话',
    `org_id` BIGINT UNSIGNED NOT NULL COMMENT '所属机构ID',
    `gps_last_location` POINT DEFAULT NULL COMMENT '最后位置（空间坐标）',
    `status` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '状态：1-在职，0-离职',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`surveyor_id`),
    UNIQUE KEY `uk_phone` (`phone`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='查勘员信息表';

-- 查勘员实时位置表
CREATE TABLE `surveyor_location` (
    `location_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '位置ID',
    `surveyor_id` BIGINT UNSIGNED NOT NULL COMMENT '查勘员ID',
    `gps` POINT NOT NULL COMMENT 'GPS坐标',
    `report_time` DATETIME NOT NULL COMMENT '上报时间',
    PRIMARY KEY (`location_id`),
    KEY `idx_surveyor_id` (`surveyor_id`),
    KEY `idx_report_time` (`report_time`),
    CONSTRAINT `fk_surveyor_location_surveyor_id` FOREIGN KEY (`surveyor_id`) REFERENCES `surveyor` (`surveyor_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='查勘员实时位置表';

-- 受损照片表
CREATE TABLE `damage_photo` (
    `photo_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '照片ID',
    `claim_no` VARCHAR(32) NOT NULL COMMENT '理赔单号',
    `photo_type` TINYINT UNSIGNED NOT NULL COMMENT '照片类型：1-全景，2-部件特写，3-证件',
    `photo_url` VARCHAR(256) NOT NULL COMMENT 'OSS存储路径',
    `upload_time` DATETIME NOT NULL COMMENT '上传时间',
    `ai_damage_part` VARCHAR(64) DEFAULT NULL COMMENT 'AI识别受损部件',
    `ai_damage_level` TINYINT UNSIGNED DEFAULT NULL COMMENT 'AI损伤程度（1-5）',
    `ai_model_version` VARCHAR(32) DEFAULT NULL COMMENT 'AI模型版本',
    `is_manual_review` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '是否人工复核',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`photo_id`),
    KEY `idx_claim_no` (`claim_no`),
    CONSTRAINT `fk_damage_photo_claim_no` FOREIGN KEY (`claim_no`) REFERENCES `claim_report` (`claim_no`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='受损照片表';

-- 定损表
CREATE TABLE `damage_assessment` (
    `assessment_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '定损单号',
    `claim_no` VARCHAR(32) NOT NULL COMMENT '理赔单号',
    `damage_part_code` VARCHAR(32) NOT NULL COMMENT '受损部件编码',
    `repair_type` TINYINT UNSIGNED NOT NULL COMMENT '维修类型：1-换件，2-维修',
    `part_price` INT UNSIGNED DEFAULT NULL COMMENT '配件价格（分）',
    `labor_fee` INT UNSIGNED DEFAULT NULL COMMENT '工时费（分）',
    `estimated_amount` INT UNSIGNED NOT NULL COMMENT 'AI预估金额（分）',
    `manual_adjust_amount` INT UNSIGNED DEFAULT NULL COMMENT '人工调整金额（分）',
    `actual_amount` INT UNSIGNED NOT NULL COMMENT '核赔确认金额（分）',
    `is_auto_settled` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '是否自动核赔',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`assessment_id`),
    KEY `idx_claim_no` (`claim_no`),
    CONSTRAINT `fk_damage_assessment_claim_no` FOREIGN KEY (`claim_no`) REFERENCES `claim_report` (`claim_no`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='定损表';

-- 配件价格库表
CREATE TABLE `damage_part_master` (
    `part_code` VARCHAR(32) NOT NULL COMMENT '配件编码',
    `part_name` VARCHAR(128) NOT NULL COMMENT '配件名称',
    `brand` VARCHAR(64) NOT NULL COMMENT '品牌',
    `price` INT UNSIGNED NOT NULL COMMENT '价格（分）',
    `effective_date` DATE NOT NULL COMMENT '生效日期',
    `expiry_date` DATE DEFAULT NULL COMMENT '失效日期',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`part_code`),
    KEY `idx_effective_date` (`effective_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='配件价格库表';

-- 工时费标准表
CREATE TABLE `labor_fee_standard` (
    `standard_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '标准ID',
    `city_code` VARCHAR(16) NOT NULL COMMENT '城市代码',
    `repair_type` VARCHAR(32) NOT NULL COMMENT '维修类型（如钣金、喷漆）',
    `labor_fee` INT UNSIGNED NOT NULL COMMENT '工时费（分）',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`standard_id`),
    UNIQUE KEY `uk_city_repair` (`city_code`, `repair_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='工时费标准表';

-- 核赔审批表
CREATE TABLE `claim_approval` (
    `approval_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '审批ID',
    `claim_no` VARCHAR(32) NOT NULL COMMENT '理赔单号',
    `approver_id` BIGINT UNSIGNED NOT NULL COMMENT '审批人ID',
    `approval_amount` INT UNSIGNED NOT NULL COMMENT '审批金额（分）',
    `approval_time` DATETIME NOT NULL COMMENT '审批时间',
    `approval_result` TINYINT UNSIGNED NOT NULL COMMENT '结果：1-通过，2-驳回',
    `remark` VARCHAR(256) DEFAULT NULL COMMENT '备注',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`approval_id`),
    KEY `idx_claim_no` (`claim_no`),
    CONSTRAINT `fk_claim_approval_claim_no` FOREIGN KEY (`claim_no`) REFERENCES `claim_report` (`claim_no`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='核赔审批表';

-- 赔款支付表
CREATE TABLE `claim_payment` (
    `payment_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '支付ID',
    `claim_no` VARCHAR(32) NOT NULL COMMENT '理赔单号',
    `payee_type` TINYINT UNSIGNED NOT NULL COMMENT '收款方类型：1-车主，2-修理厂，3-医院',
    `payee_account` VARCHAR(64) NOT NULL COMMENT '收款账号',
    `amount` INT UNSIGNED NOT NULL COMMENT '支付金额（分）',
    `payment_time` DATETIME NOT NULL COMMENT '支付时间',
    `transaction_id` VARCHAR(64) NOT NULL COMMENT '交易流水号',
    `status` TINYINT UNSIGNED NOT NULL COMMENT '状态：1-成功，2-失败',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`payment_id`),
    KEY `idx_claim_no` (`claim_no`),
    CONSTRAINT `fk_claim_payment_claim_no` FOREIGN KEY (`claim_no`) REFERENCES `claim_report` (`claim_no`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='赔款支付表';

-- 三免信用赔表
CREATE TABLE `claim_fast_payment` (
    `fast_pay_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '快速赔案ID',
    `claim_no` VARCHAR(32) NOT NULL COMMENT '理赔单号',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `eligible_score` DECIMAL(5,2) NOT NULL COMMENT '符合条件时的安驾分',
    `payment_time` DATETIME NOT NULL COMMENT '赔付时间',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`fast_pay_id`),
    UNIQUE KEY `uk_claim_no` (`claim_no`),
    KEY `idx_user_id` (`user_id`),
    CONSTRAINT `fk_claim_fast_payment_claim_no` FOREIGN KEY (`claim_no`) REFERENCES `claim_report` (`claim_no`) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_claim_fast_payment_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='三免信用赔表';

-- 反欺诈关系表
CREATE TABLE `claim_anti_fraud` (
    `fraud_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '欺诈分析ID',
    `claim_no` VARCHAR(32) NOT NULL COMMENT '理赔单号',
    `related_entity_type` TINYINT UNSIGNED NOT NULL COMMENT '关联实体类型：1-用户，2-车辆，3-修理厂，4-查勘员',
    `related_entity_id` VARCHAR(64) NOT NULL COMMENT '关联实体ID',
    `relationship_graph` JSON DEFAULT NULL COMMENT '关系图谱（节点关系）',
    `fraud_score` DECIMAL(5,2) DEFAULT NULL COMMENT '欺诈评分',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`fraud_id`),
    KEY `idx_claim_no` (`claim_no`),
    KEY `idx_related_entity` (`related_entity_type`, `related_entity_id`),
    CONSTRAINT `fk_claim_anti_fraud_claim_no` FOREIGN KEY (`claim_no`) REFERENCES `claim_report` (`claim_no`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='反欺诈关系表';

-- ======================================================
-- 4. 运营域（20张表）
-- ======================================================

-- 活动主表
CREATE TABLE `campaign_master` (
    `campaign_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '活动ID',
    `campaign_name` VARCHAR(128) NOT NULL COMMENT '活动名称',
    `campaign_type` TINYINT UNSIGNED NOT NULL COMMENT '活动类型：1-节日营销，2-裂变活动，3-直播活动，4-签到活动',
    `start_time` DATETIME NOT NULL COMMENT '开始时间',
    `end_time` DATETIME NOT NULL COMMENT '结束时间',
    `budget` INT UNSIGNED DEFAULT NULL COMMENT '预算（分）',
    `status` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '状态：1-未开始，2-进行中，3-已结束，4-已取消',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`campaign_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='活动主表';

-- 活动参与记录表
CREATE TABLE `campaign_participation` (
    `participation_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '参与记录ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `campaign_id` BIGINT UNSIGNED NOT NULL COMMENT '活动ID',
    `participation_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '参与时间',
    `reward_status` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '奖励状态：0-未发放，1-已发放',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`participation_id`),
    UNIQUE KEY `uk_user_campaign` (`user_id`, `campaign_id`),
    KEY `idx_campaign_id` (`campaign_id`),
    CONSTRAINT `fk_campaign_participation_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_campaign_participation_campaign_id` FOREIGN KEY (`campaign_id`) REFERENCES `campaign_master` (`campaign_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='活动参与记录表';

-- 用户优惠券表
CREATE TABLE `user_coupon` (
    `coupon_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '优惠券ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `coupon_type` TINYINT UNSIGNED NOT NULL COMMENT '优惠券类型：1-满减券，2-折扣券，3-直减券',
    `face_value` INT UNSIGNED NOT NULL COMMENT '面值（分）或折扣（百分数）',
    `use_condition` INT UNSIGNED DEFAULT NULL COMMENT '使用条件（满多少元可用）',
    `expire_date` DATE NOT NULL COMMENT '过期日期',
    `status` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '状态：1-未使用，2-已使用，3-已过期',
    `source_type` VARCHAR(32) DEFAULT NULL COMMENT '来源类型（活动/签到/购买）',
    `source_id` VARCHAR(64) DEFAULT NULL COMMENT '来源ID',
    `use_time` DATETIME DEFAULT NULL COMMENT '使用时间',
    `order_no` VARCHAR(64) DEFAULT NULL COMMENT '关联订单号',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`coupon_id`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_status_expire` (`status`, `expire_date`),
    CONSTRAINT `fk_user_coupon_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户优惠券表';

-- 积分账户表
CREATE TABLE `points_account` (
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `total_points` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '累计获取积分',
    `available_points` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '可用积分',
    `frozen_points` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '冻结积分',
    `total_consumed` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '累计消费积分',
    `version` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '乐观锁版本号',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`user_id`),
    CONSTRAINT `fk_points_account_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='积分账户表';

-- 积分流水表
CREATE TABLE `points_transaction` (
    `trans_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '流水ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `trans_type` TINYINT UNSIGNED NOT NULL COMMENT '类型：1-获取，2-消费，3-过期，4-冻结，5-解冻',
    `points_amount` INT NOT NULL COMMENT '变动积分数量',
    `source_type` VARCHAR(32) NOT NULL COMMENT '来源类型：SIGNIN/PURCHASE/SERVICE/ACTIVITY',
    `source_id` VARCHAR(64) NOT NULL COMMENT '来源单号：订单号/活动ID',
    `balance_before` INT UNSIGNED NOT NULL COMMENT '变动前余额',
    `balance_after` INT UNSIGNED NOT NULL COMMENT '变动后余额',
    `expire_date` DATE DEFAULT NULL COMMENT '积分过期日期',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`trans_id`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_create_time` (`create_time`),
    CONSTRAINT `fk_points_transaction_user_id` FOREIGN KEY (`user_id`) REFERENCES `points_account` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='积分流水表';

-- 签到记录表
CREATE TABLE `signin_log` (
    `sign_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '签到ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `sign_date` DATE NOT NULL COMMENT '签到日期',
    `points_earned` INT UNSIGNED NOT NULL COMMENT '获得积分',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`sign_id`),
    UNIQUE KEY `uk_user_date` (`user_id`, `sign_date`),
    CONSTRAINT `fk_signin_log_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='签到记录表';

-- 邀请关系表
CREATE TABLE `invite_relation` (
    `invite_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '邀请ID',
    `inviter_user_id` BIGINT UNSIGNED NOT NULL COMMENT '邀请人用户ID',
    `invitee_user_id` BIGINT UNSIGNED NOT NULL COMMENT '被邀请人用户ID',
    `invite_channel` VARCHAR(32) DEFAULT NULL COMMENT '邀请渠道（微信/朋友圈/QQ）',
    `invite_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '邀请时间',
    `is_registered` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '是否已注册',
    `is_purchased` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '是否已完成首购',
    `reward_status` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '奖励状态：0-未发放，1-已发放',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`invite_id`),
    UNIQUE KEY `uk_inviter_invitee` (`inviter_user_id`, `invitee_user_id`),
    KEY `idx_invitee_user_id` (`invitee_user_id`),
    CONSTRAINT `fk_invite_relation_inviter` FOREIGN KEY (`inviter_user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_invite_relation_invitee` FOREIGN KEY (`invitee_user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='邀请关系表';

-- 推送任务表
CREATE TABLE `push_task` (
    `task_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '任务ID',
    `task_name` VARCHAR(128) NOT NULL COMMENT '任务名称',
    `target_user_segment` JSON NOT NULL COMMENT '目标用户分群（JSON条件）',
    `push_content` VARCHAR(512) NOT NULL COMMENT '推送内容',
    `send_time` DATETIME NOT NULL COMMENT '计划发送时间',
    `status` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '状态：1-待发送，2-发送中，3-已发送，4-已取消',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`task_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='推送任务表';

-- 推送记录表
CREATE TABLE `push_record` (
    `record_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '记录ID',
    `task_id` BIGINT UNSIGNED NOT NULL COMMENT '任务ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `send_time` DATETIME NOT NULL COMMENT '发送时间',
    `status` TINYINT UNSIGNED NOT NULL COMMENT '状态：1-成功，2-失败',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`record_id`),
    KEY `idx_task_id` (`task_id`),
    KEY `idx_user_id` (`user_id`),
    CONSTRAINT `fk_push_record_task_id` FOREIGN KEY (`task_id`) REFERENCES `push_task` (`task_id`) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_push_record_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='推送记录表';

-- 站内信表
CREATE TABLE `inbox_message` (
    `msg_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '消息ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `msg_title` VARCHAR(128) NOT NULL COMMENT '标题',
    `msg_content` VARCHAR(1024) NOT NULL COMMENT '内容',
    `is_read` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '是否已读',
    `read_time` DATETIME DEFAULT NULL COMMENT '阅读时间',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`msg_id`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_is_read` (`is_read`),
    CONSTRAINT `fk_inbox_message_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='站内信表';

-- 公众号粉丝表
CREATE TABLE `wechat_follower` (
    `openid` VARCHAR(64) NOT NULL COMMENT '微信openid',
    `user_id` BIGINT UNSIGNED DEFAULT NULL COMMENT '关联用户ID',
    `nickname` VARCHAR(64) DEFAULT NULL COMMENT '昵称',
    `subscribe_time` DATETIME NOT NULL COMMENT '关注时间',
    `unsubscribe_time` DATETIME DEFAULT NULL COMMENT '取消关注时间',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`openid`),
    KEY `idx_user_id` (`user_id`),
    CONSTRAINT `fk_wechat_follower_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='公众号粉丝表';

-- 公众号互动表
CREATE TABLE `wechat_interaction` (
    `interaction_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '互动ID',
    `openid` VARCHAR(64) NOT NULL COMMENT '粉丝openid',
    `interaction_type` TINYINT UNSIGNED NOT NULL COMMENT '互动类型：1-点击菜单，2-发送消息，3-扫码',
    `content` VARCHAR(512) DEFAULT NULL COMMENT '互动内容',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`interaction_id`),
    KEY `idx_openid` (`openid`),
    KEY `idx_create_time` (`create_time`),
    CONSTRAINT `fk_wechat_interaction_openid` FOREIGN KEY (`openid`) REFERENCES `wechat_follower` (`openid`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='公众号互动表';

-- 外呼任务表
CREATE TABLE `outbound_call_task` (
    `call_task_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '外呼任务ID',
    `campaign_id` BIGINT UNSIGNED DEFAULT NULL COMMENT '关联活动ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `scheduled_time` DATETIME NOT NULL COMMENT '计划外呼时间',
    `call_status` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '状态：0-待呼叫，1-呼叫中，2-已接通，3-未接通，4-失败',
    `call_result` VARCHAR(128) DEFAULT NULL COMMENT '通话结果',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`call_task_id`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_campaign_id` (`campaign_id`),
    CONSTRAINT `fk_outbound_call_task_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_outbound_call_task_campaign_id` FOREIGN KEY (`campaign_id`) REFERENCES `campaign_master` (`campaign_id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='外呼任务表';

-- 通话记录表
CREATE TABLE `call_record` (
    `call_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '通话记录ID',
    `call_task_id` BIGINT UNSIGNED NOT NULL COMMENT '外呼任务ID',
    `start_time` DATETIME NOT NULL COMMENT '开始时间',
    `end_time` DATETIME DEFAULT NULL COMMENT '结束时间',
    `duration` SMALLINT UNSIGNED DEFAULT NULL COMMENT '通话时长（秒）',
    `recording_url` VARCHAR(256) DEFAULT NULL COMMENT '录音文件URL',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`call_id`),
    KEY `idx_call_task_id` (`call_task_id`),
    CONSTRAINT `fk_call_record_call_task_id` FOREIGN KEY (`call_task_id`) REFERENCES `outbound_call_task` (`call_task_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='通话记录表';

-- 分享记录表
CREATE TABLE `share_record` (
    `share_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '分享ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '分享用户ID',
    `share_type` TINYINT UNSIGNED NOT NULL COMMENT '分享类型：1-活动，2-商品，3-文章',
    `target_page` VARCHAR(256) NOT NULL COMMENT '目标页面',
    `share_channel` VARCHAR(32) NOT NULL COMMENT '分享渠道：微信/朋友圈/QQ',
    `share_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '分享时间',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`share_id`),
    KEY `idx_user_id` (`user_id`),
    CONSTRAINT `fk_share_record_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='分享记录表';

-- 直播间表
CREATE TABLE `live_room` (
    `room_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '直播间ID',
    `room_name` VARCHAR(128) NOT NULL COMMENT '直播间名称',
    `anchor` VARCHAR(64) NOT NULL COMMENT '主播',
    `start_time` DATETIME NOT NULL COMMENT '开始时间',
    `end_time` DATETIME DEFAULT NULL COMMENT '结束时间',
    `status` TINYINT UNSIGNED NOT NULL COMMENT '状态：1-预约中，2-直播中，3-已结束',
    `total_viewers` INT UNSIGNED DEFAULT NULL COMMENT '累计观看人次',
    `peak_viewers` INT UNSIGNED DEFAULT NULL COMMENT '峰值在线人数',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`room_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='直播间表';

-- 直播商品关联表
CREATE TABLE `live_product` (
    `live_product_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '直播商品ID',
    `room_id` BIGINT UNSIGNED NOT NULL COMMENT '直播间ID',
    `product_id` BIGINT UNSIGNED NOT NULL COMMENT '商品ID（关联商城商品）',
    `live_price` INT UNSIGNED NOT NULL COMMENT '直播价（分）',
    `stock` INT UNSIGNED NOT NULL COMMENT '直播专享库存',
    `sold_count` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '已售数量',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`live_product_id`),
    KEY `idx_room_id` (`room_id`),
    CONSTRAINT `fk_live_product_room_id` FOREIGN KEY (`room_id`) REFERENCES `live_room` (`room_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='直播商品关联表';

-- 直播实时数据表（仅存聚合快照，真实实时数据由Flink维护）
CREATE TABLE `live_realtime_data` (
    `data_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '数据ID',
    `room_id` BIGINT UNSIGNED NOT NULL COMMENT '直播间ID',
    `stat_time` DATETIME NOT NULL COMMENT '统计时间（秒级）',
    `current_viewers` INT UNSIGNED NOT NULL COMMENT '当前在线人数',
    `accum_viewers` INT UNSIGNED NOT NULL COMMENT '累计观看人次',
    `order_count` INT UNSIGNED NOT NULL COMMENT '累计下单数',
    `pay_amount` BIGINT UNSIGNED NOT NULL COMMENT '累计支付金额（分）',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`data_id`),
    KEY `idx_room_id` (`room_id`),
    KEY `idx_stat_time` (`stat_time`),
    CONSTRAINT `fk_live_realtime_data_room_id` FOREIGN KEY (`room_id`) REFERENCES `live_room` (`room_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='直播实时数据表（快照）';

-- 直播订单表
CREATE TABLE `live_order` (
    `order_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '订单ID',
    `room_id` BIGINT UNSIGNED NOT NULL COMMENT '直播间ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `product_id` BIGINT UNSIGNED NOT NULL COMMENT '商品ID',
    `order_amount` INT UNSIGNED NOT NULL COMMENT '订单金额（分）',
    `pay_time` DATETIME DEFAULT NULL COMMENT '支付时间',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`order_id`),
    KEY `idx_room_id` (`room_id`),
    KEY `idx_user_id` (`user_id`),
    CONSTRAINT `fk_live_order_room_id` FOREIGN KEY (`room_id`) REFERENCES `live_room` (`room_id`) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_live_order_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='直播订单表';

-- ======================================================
-- 5. 车服务域（12张表）
-- ======================================================

-- 服务订单主表
CREATE TABLE `service_order` (
    `order_no` VARCHAR(32) NOT NULL COMMENT '订单号',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `service_type` TINYINT UNSIGNED NOT NULL COMMENT '服务类型：1-加油，2-充电，3-洗车，4-代驾，5-保养，6-救援',
    `order_status` TINYINT UNSIGNED NOT NULL COMMENT '订单状态：1-待支付，2-已支付，3-服务中，4-已完成，5-已取消',
    `total_amount` INT UNSIGNED NOT NULL COMMENT '总金额（分）',
    `pay_amount` INT UNSIGNED DEFAULT NULL COMMENT '实付金额（分）',
    `coupon_id` BIGINT UNSIGNED DEFAULT NULL COMMENT '使用的优惠券ID',
    `points_used` INT UNSIGNED DEFAULT NULL COMMENT '使用的积分',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `pay_time` DATETIME DEFAULT NULL COMMENT '支付时间',
    `complete_time` DATETIME DEFAULT NULL COMMENT '完成时间',
    PRIMARY KEY (`order_no`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_service_type` (`service_type`),
    KEY `idx_order_status` (`order_status`),
    CONSTRAINT `fk_service_order_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_service_order_coupon_id` FOREIGN KEY (`coupon_id`) REFERENCES `user_coupon` (`coupon_id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='服务订单主表';

-- 加油订单表
CREATE TABLE `fuel_order` (
    `order_no` VARCHAR(32) NOT NULL COMMENT '订单号',
    `station_id` BIGINT UNSIGNED NOT NULL COMMENT '加油站ID',
    `fuel_type` VARCHAR(16) NOT NULL COMMENT '油品类型（92#/95#/98#）',
    `liter` DECIMAL(10,2) NOT NULL COMMENT '加油量（升）',
    `unit_price` INT UNSIGNED NOT NULL COMMENT '单价（分）',
    `total_price` INT UNSIGNED NOT NULL COMMENT '总价（分）',
    `discount` INT UNSIGNED DEFAULT NULL COMMENT '优惠金额（分）',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`order_no`),
    KEY `idx_station_id` (`station_id`),
    CONSTRAINT `fk_fuel_order_order_no` FOREIGN KEY (`order_no`) REFERENCES `service_order` (`order_no`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='加油订单表';

-- 加油站表
CREATE TABLE `fuel_station` (
    `station_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '加油站ID',
    `station_name` VARCHAR(128) NOT NULL COMMENT '加油站名称',
    `address` VARCHAR(256) NOT NULL COMMENT '地址',
    `gps` POINT NOT NULL COMMENT '经纬度',
    `brand` VARCHAR(32) NOT NULL COMMENT '品牌（中石化/中石油/其他）',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`station_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='加油站表';

-- 充电订单表
CREATE TABLE `charge_order` (
    `order_no` VARCHAR(32) NOT NULL COMMENT '订单号',
    `pile_id` BIGINT UNSIGNED NOT NULL COMMENT '充电桩ID',
    `charge_start` DATETIME NOT NULL COMMENT '开始充电时间',
    `charge_end` DATETIME NOT NULL COMMENT '结束充电时间',
    `power` DECIMAL(10,2) NOT NULL COMMENT '充电量（度）',
    `total_fee` INT UNSIGNED NOT NULL COMMENT '总费用（分）',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`order_no`),
    KEY `idx_pile_id` (`pile_id`),
    CONSTRAINT `fk_charge_order_order_no` FOREIGN KEY (`order_no`) REFERENCES `service_order` (`order_no`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='充电订单表';

-- 充电桩表
CREATE TABLE `charge_pile` (
    `pile_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '充电桩ID',
    `station_id` BIGINT UNSIGNED NOT NULL COMMENT '所属场站ID',
    `pile_type` VARCHAR(16) NOT NULL COMMENT '桩类型（快充/慢充）',
    `power` DECIMAL(5,2) NOT NULL COMMENT '功率（kW）',
    `status` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '状态：1-空闲，2-使用中，3-故障',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`pile_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='充电桩表';

-- 洗车订单表
CREATE TABLE `car_wash_order` (
    `order_no` VARCHAR(32) NOT NULL COMMENT '订单号',
    `shop_id` BIGINT UNSIGNED NOT NULL COMMENT '洗车店ID',
    `wash_type` TINYINT UNSIGNED NOT NULL COMMENT '洗车类型：1-普洗，2-精洗',
    `price` INT UNSIGNED NOT NULL COMMENT '价格（分）',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`order_no`),
    KEY `idx_shop_id` (`shop_id`),
    CONSTRAINT `fk_car_wash_order_order_no` FOREIGN KEY (`order_no`) REFERENCES `service_order` (`order_no`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='洗车订单表';

-- 洗车店表
CREATE TABLE `car_wash_shop` (
    `shop_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '洗车店ID',
    `shop_name` VARCHAR(128) NOT NULL COMMENT '店铺名称',
    `address` VARCHAR(256) NOT NULL COMMENT '地址',
    `gps` POINT NOT NULL COMMENT '经纬度',
    `price_standard` JSON NOT NULL COMMENT '价格标准（普洗/精洗价格）',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='洗车店表';

-- 代驾订单表
CREATE TABLE `designated_driver_order` (
    `order_no` VARCHAR(32) NOT NULL COMMENT '订单号',
    `start_gps` POINT NOT NULL COMMENT '起点经纬度',
    `end_gps` POINT NOT NULL COMMENT '终点经纬度',
    `distance` INT UNSIGNED NOT NULL COMMENT '距离（米）',
    `duration` SMALLINT UNSIGNED NOT NULL COMMENT '预估时长（分钟）',
    `fee` INT UNSIGNED NOT NULL COMMENT '费用（分）',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`order_no`),
    CONSTRAINT `fk_designated_driver_order_order_no` FOREIGN KEY (`order_no`) REFERENCES `service_order` (`order_no`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='代驾订单表';

-- 保养订单表
CREATE TABLE `maintenance_order` (
    `order_no` VARCHAR(32) NOT NULL COMMENT '订单号',
    `shop_id` BIGINT UNSIGNED NOT NULL COMMENT '保养店ID',
    `service_items` JSON NOT NULL COMMENT '服务项目列表',
    `cost` INT UNSIGNED NOT NULL COMMENT '费用（分）',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`order_no`),
    CONSTRAINT `fk_maintenance_order_order_no` FOREIGN KEY (`order_no`) REFERENCES `service_order` (`order_no`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='保养订单表';

-- 救援订单表
CREATE TABLE `rescue_order` (
    `order_no` VARCHAR(32) NOT NULL COMMENT '订单号',
    `rescue_type` TINYINT UNSIGNED NOT NULL COMMENT '救援类型：1-拖车，2-搭电，3-换胎，4-送油',
    `location` POINT NOT NULL COMMENT '救援地点',
    `rescue_time_arrive` DATETIME DEFAULT NULL COMMENT '到达时间',
    `fee` INT UNSIGNED DEFAULT NULL COMMENT '费用（分）',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`order_no`),
    CONSTRAINT `fk_rescue_order_order_no` FOREIGN KEY (`order_no`) REFERENCES `service_order` (`order_no`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='救援订单表';

-- 违章查询日志表
CREATE TABLE `violation_query_log` (
    `log_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '日志ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `vehicle_id` BIGINT UNSIGNED NOT NULL COMMENT '车辆ID',
    `query_time` DATETIME NOT NULL COMMENT '查询时间',
    `result` JSON DEFAULT NULL COMMENT '查询结果JSON',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`log_id`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_vehicle_id` (`vehicle_id`),
    CONSTRAINT `fk_violation_query_log_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_violation_query_log_vehicle_id` FOREIGN KEY (`vehicle_id`) REFERENCES `user_vehicle` (`vehicle_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='违章查询日志表';

-- 一键挪车请求表
CREATE TABLE `move_car_request` (
    `request_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '请求ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '请求用户ID',
    `target_plate` VARCHAR(16) NOT NULL COMMENT '目标车牌',
    `location` POINT NOT NULL COMMENT '位置',
    `request_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '请求时间',
    `status` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '状态：0-待处理，1-已通知，2-已取消',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`request_id`),
    KEY `idx_user_id` (`user_id`),
    CONSTRAINT `fk_move_car_request_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='一键挪车请求表';

-- ======================================================
-- 6. 商城域（8张表）
-- ======================================================

-- 商品表
CREATE TABLE `mall_product` (
    `product_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '商品ID',
    `product_name` VARCHAR(128) NOT NULL COMMENT '商品名称',
    `category` TINYINT UNSIGNED NOT NULL COMMENT '分类：1-车品，2-食品，3-家居，4-卡券',
    `price` INT UNSIGNED NOT NULL COMMENT '售价（分）',
    `points_price` INT UNSIGNED DEFAULT NULL COMMENT '积分兑换价格',
    `stock` INT UNSIGNED NOT NULL COMMENT '库存',
    `status` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '状态：1-上架，0-下架',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`product_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='商品表';

-- 商城订单表
CREATE TABLE `mall_order` (
    `order_no` VARCHAR(32) NOT NULL COMMENT '订单号',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `total_amount` INT UNSIGNED NOT NULL COMMENT '总金额（分）',
    `pay_amount` INT UNSIGNED NOT NULL COMMENT '实付金额（分）',
    `points_used` INT UNSIGNED DEFAULT NULL COMMENT '使用的积分',
    `order_status` TINYINT UNSIGNED NOT NULL COMMENT '状态：1-待支付，2-已支付，3-已发货，4-已完成，5-已取消',
    `pay_time` DATETIME DEFAULT NULL COMMENT '支付时间',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`order_no`),
    KEY `idx_user_id` (`user_id`),
    CONSTRAINT `fk_mall_order_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='商城订单表';

-- 订单商品明细表
CREATE TABLE `order_item` (
    `item_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '明细ID',
    `order_no` VARCHAR(32) NOT NULL COMMENT '订单号',
    `product_id` BIGINT UNSIGNED NOT NULL COMMENT '商品ID',
    `quantity` INT UNSIGNED NOT NULL COMMENT '数量',
    `price` INT UNSIGNED NOT NULL COMMENT '单价（分）',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`item_id`),
    KEY `idx_order_no` (`order_no`),
    KEY `idx_product_id` (`product_id`),
    CONSTRAINT `fk_order_item_order_no` FOREIGN KEY (`order_no`) REFERENCES `mall_order` (`order_no`) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_order_item_product_id` FOREIGN KEY (`product_id`) REFERENCES `mall_product` (`product_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单商品明细表';

-- 积分兑换订单表
CREATE TABLE `points_exchange_order` (
    `exchange_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '兑换ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `product_id` BIGINT UNSIGNED NOT NULL COMMENT '商品ID',
    `points_used` INT UNSIGNED NOT NULL COMMENT '使用积分',
    `order_status` TINYINT UNSIGNED NOT NULL COMMENT '状态：1-待发货，2-已发货，3-已完成',
    `exchange_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '兑换时间',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`exchange_id`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_product_id` (`product_id`),
    CONSTRAINT `fk_points_exchange_order_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_points_exchange_order_product_id` FOREIGN KEY (`product_id`) REFERENCES `mall_product` (`product_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='积分兑换订单表';

-- 助农产品表（继承商品）
CREATE TABLE `agricultural_product` (
    `product_id` BIGINT UNSIGNED NOT NULL COMMENT '商品ID',
    `origin` VARCHAR(128) NOT NULL COMMENT '产地',
    `farmer_info` VARCHAR(256) DEFAULT NULL COMMENT '农户信息',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`product_id`),
    CONSTRAINT `fk_agricultural_product_product_id` FOREIGN KEY (`product_id`) REFERENCES `mall_product` (`product_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='助农产品表';

-- 商家表（B端）
CREATE TABLE `merchant` (
    `merchant_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '商家ID',
    `merchant_name` VARCHAR(128) NOT NULL COMMENT '商家名称',
    `merchant_type` TINYINT UNSIGNED NOT NULL COMMENT '类型：1-洗车店，2-保养店，3-加油站，4-代驾公司，5-体检机构，6-家政公司',
    `contact_phone` VARCHAR(20) NOT NULL COMMENT '联系电话',
    `address` VARCHAR(256) DEFAULT NULL COMMENT '地址',
    `status` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '状态：1-正常，0-冻结',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`merchant_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='商家表';

-- 商家商品关联表
CREATE TABLE `merchant_product` (
    `merchant_product_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '关联ID',
    `merchant_id` BIGINT UNSIGNED NOT NULL COMMENT '商家ID',
    `product_id` BIGINT UNSIGNED NOT NULL COMMENT '商品ID',
    `supply_price` INT UNSIGNED NOT NULL COMMENT '供货价（分）',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`merchant_product_id`),
    UNIQUE KEY `uk_merchant_product` (`merchant_id`, `product_id`),
    KEY `idx_product_id` (`product_id`),
    CONSTRAINT `fk_merchant_product_merchant_id` FOREIGN KEY (`merchant_id`) REFERENCES `merchant` (`merchant_id`) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_merchant_product_product_id` FOREIGN KEY (`product_id`) REFERENCES `mall_product` (`product_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='商家商品关联表';

-- 用户收货地址表
CREATE TABLE `user_address` (
    `address_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '地址ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `consignee` VARCHAR(64) NOT NULL COMMENT '收货人',
    `phone` VARCHAR(20) NOT NULL COMMENT '联系电话',
    `province` VARCHAR(32) NOT NULL COMMENT '省',
    `city` VARCHAR(32) NOT NULL COMMENT '市',
    `district` VARCHAR(32) NOT NULL COMMENT '区',
    `detail` VARCHAR(256) NOT NULL COMMENT '详细地址',
    `is_default` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '是否默认地址',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`address_id`),
    KEY `idx_user_id` (`user_id`),
    CONSTRAINT `fk_user_address_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户收货地址表';

-- ======================================================
-- 7. B端企业域（10张表）
-- ======================================================

-- 企业保单扩展表（继承policy_master）
CREATE TABLE `enterprise_policy` (
    `policy_no` VARCHAR(32) NOT NULL COMMENT '保单号',
    `enterprise_id` BIGINT UNSIGNED NOT NULL COMMENT '企业ID',
    `employee_count` INT UNSIGNED DEFAULT NULL COMMENT '雇员数量',
    `industry` VARCHAR(64) DEFAULT NULL COMMENT '行业',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`policy_no`),
    KEY `idx_enterprise_id` (`enterprise_id`),
    CONSTRAINT `fk_enterprise_policy_policy_no` FOREIGN KEY (`policy_no`) REFERENCES `policy_master` (`policy_no`) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_enterprise_policy_enterprise_id` FOREIGN KEY (`enterprise_id`) REFERENCES `enterprise` (`enterprise_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='企业保单扩展表';

-- 企业理赔扩展表
CREATE TABLE `enterprise_claim` (
    `claim_no` VARCHAR(32) NOT NULL COMMENT '理赔单号',
    `enterprise_id` BIGINT UNSIGNED NOT NULL COMMENT '企业ID',
    `claim_type` TINYINT UNSIGNED NOT NULL COMMENT '理赔类型',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`claim_no`),
    KEY `idx_enterprise_id` (`enterprise_id`),
    CONSTRAINT `fk_enterprise_claim_claim_no` FOREIGN KEY (`claim_no`) REFERENCES `claim_report` (`claim_no`) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_enterprise_claim_enterprise_id` FOREIGN KEY (`enterprise_id`) REFERENCES `enterprise` (`enterprise_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='企业理赔扩展表';

-- 企业风险评估表
CREATE TABLE `enterprise_risk_assessment` (
    `assessment_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '评估ID',
    `enterprise_id` BIGINT UNSIGNED NOT NULL COMMENT '企业ID',
    `risk_score` DECIMAL(5,2) NOT NULL COMMENT '风险评分',
    `report_url` VARCHAR(256) DEFAULT NULL COMMENT '评估报告URL',
    `assessment_date` DATE NOT NULL COMMENT '评估日期',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`assessment_id`),
    KEY `idx_enterprise_id` (`enterprise_id`),
    CONSTRAINT `fk_enterprise_risk_assessment_enterprise_id` FOREIGN KEY (`enterprise_id`) REFERENCES `enterprise` (`enterprise_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='企业风险评估表';

-- 灾害预警表
CREATE TABLE `disaster_warning` (
    `warning_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '预警ID',
    `enterprise_id` BIGINT UNSIGNED NOT NULL COMMENT '企业ID',
    `warning_type` TINYINT UNSIGNED NOT NULL COMMENT '预警类型：1-台风，2-暴雨，3-火灾，4-地震',
    `warning_content` VARCHAR(512) NOT NULL COMMENT '预警内容',
    `push_time` DATETIME NOT NULL COMMENT '推送时间',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`warning_id`),
    KEY `idx_enterprise_id` (`enterprise_id`),
    CONSTRAINT `fk_disaster_warning_enterprise_id` FOREIGN KEY (`enterprise_id`) REFERENCES `enterprise` (`enterprise_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='灾害预警表';

-- 智慧巡检记录表
CREATE TABLE `smart_inspection` (
    `inspection_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '巡检ID',
    `enterprise_id` BIGINT UNSIGNED NOT NULL COMMENT '企业ID',
    `inspection_date` DATE NOT NULL COMMENT '巡检日期',
    `inspection_result` JSON NOT NULL COMMENT '巡检结果JSON',
    `photo_url` VARCHAR(256) DEFAULT NULL COMMENT '照片URL',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`inspection_id`),
    KEY `idx_enterprise_id` (`enterprise_id`),
    CONSTRAINT `fk_smart_inspection_enterprise_id` FOREIGN KEY (`enterprise_id`) REFERENCES `enterprise` (`enterprise_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='智慧巡检记录表';

-- 企业健康服务表
CREATE TABLE `enterprise_health_service` (
    `service_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '服务ID',
    `enterprise_id` BIGINT UNSIGNED NOT NULL COMMENT '企业ID',
    `service_type` TINYINT UNSIGNED NOT NULL COMMENT '服务类型：1-在线问诊，2-体检预约，3-健康课堂',
    `service_date` DATE NOT NULL COMMENT '服务日期',
    `employee_count` INT UNSIGNED NOT NULL COMMENT '参与员工数',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`service_id`),
    KEY `idx_enterprise_id` (`enterprise_id`),
    CONSTRAINT `fk_enterprise_health_service_enterprise_id` FOREIGN KEY (`enterprise_id`) REFERENCES `enterprise` (`enterprise_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='企业健康服务表';

-- 企业财税服务表
CREATE TABLE `enterprise_finance` (
    `finance_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '服务ID',
    `enterprise_id` BIGINT UNSIGNED NOT NULL COMMENT '企业ID',
    `service_type` TINYINT UNSIGNED NOT NULL COMMENT '服务类型：1-财税咨询，2-财务工具',
    `request_time` DATETIME NOT NULL COMMENT '请求时间',
    `status` TINYINT UNSIGNED NOT NULL COMMENT '状态：1-处理中，2-已完成',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`finance_id`),
    KEY `idx_enterprise_id` (`enterprise_id`),
    CONSTRAINT `fk_enterprise_finance_enterprise_id` FOREIGN KEY (`enterprise_id`) REFERENCES `enterprise` (`enterprise_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='企业财税服务表';

-- 商家评分表
CREATE TABLE `merchant_score` (
    `merchant_id` BIGINT UNSIGNED NOT NULL COMMENT '商家ID',
    `total_orders` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '总服务单数',
    `completion_rate` DECIMAL(5,2) NOT NULL DEFAULT 100.00 COMMENT '履约率（%）',
    `avg_rating` DECIMAL(3,2) NOT NULL DEFAULT 5.00 COMMENT '用户平均评分(1-5)',
    `complaint_count` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '投诉数量',
    `on_time_rate` DECIMAL(5,2) NOT NULL DEFAULT 100.00 COMMENT '准时率（%）',
    `score_level` CHAR(1) NOT NULL DEFAULT 'A' COMMENT '评分等级：S/A/B/C/D',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`merchant_id`),
    CONSTRAINT `fk_merchant_score_merchant_id` FOREIGN KEY (`merchant_id`) REFERENCES `merchant` (`merchant_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='商家评分表';

-- 商家投诉表
CREATE TABLE `merchant_complaint` (
    `complaint_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '投诉ID',
    `merchant_id` BIGINT UNSIGNED NOT NULL COMMENT '商家ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '投诉用户ID',
    `complaint_content` VARCHAR(512) NOT NULL COMMENT '投诉内容',
    `complaint_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '投诉时间',
    `handle_status` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '处理状态：0-未处理，1-处理中，2-已处理',
    `handle_result` VARCHAR(256) DEFAULT NULL COMMENT '处理结果',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`complaint_id`),
    KEY `idx_merchant_id` (`merchant_id`),
    KEY `idx_user_id` (`user_id`),
    CONSTRAINT `fk_merchant_complaint_merchant_id` FOREIGN KEY (`merchant_id`) REFERENCES `merchant` (`merchant_id`) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_merchant_complaint_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='商家投诉表';

-- 商家资质表
CREATE TABLE `merchant_qualification` (
    `qual_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '资质ID',
    `merchant_id` BIGINT UNSIGNED NOT NULL COMMENT '商家ID',
    `cert_type` VARCHAR(32) NOT NULL COMMENT '证件类型（营业执照/行业许可证）',
    `cert_no` VARCHAR(64) NOT NULL COMMENT '证件编号',
    `cert_image` VARCHAR(256) NOT NULL COMMENT '证件图片URL',
    `expire_date` DATE DEFAULT NULL COMMENT '有效期',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`qual_id`),
    KEY `idx_merchant_id` (`merchant_id`),
    CONSTRAINT `fk_merchant_qualification_merchant_id` FOREIGN KEY (`merchant_id`) REFERENCES `merchant` (`merchant_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='商家资质表';

-- ======================================================
-- 8. G端惠民与公益域（6张表）
-- ======================================================

-- 惠民保产品表
CREATE TABLE `gov_insurance_product` (
    `product_code` VARCHAR(32) NOT NULL COMMENT '产品代码',
    `product_name` VARCHAR(128) NOT NULL COMMENT '产品名称',
    `region` VARCHAR(64) NOT NULL COMMENT '地区（省/市）',
    `coverage` JSON NOT NULL COMMENT '保障范围',
    `premium_subsidy` INT UNSIGNED NOT NULL COMMENT '政府补贴金额（分）',
    `status` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '状态：1-在售，0-停售',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`product_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='惠民保产品表';

-- 惠民保单表
CREATE TABLE `gov_insurance_policy` (
    `policy_no` VARCHAR(32) NOT NULL COMMENT '保单号',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `product_code` VARCHAR(32) NOT NULL COMMENT '产品代码',
    `subsidy_amount` INT UNSIGNED NOT NULL COMMENT '补贴金额（分）',
    `self_pay_amount` INT UNSIGNED NOT NULL COMMENT '个人自付金额（分）',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`policy_no`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_product_code` (`product_code`),
    CONSTRAINT `fk_gov_insurance_policy_policy_no` FOREIGN KEY (`policy_no`) REFERENCES `policy_master` (`policy_no`) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_gov_insurance_policy_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_gov_insurance_policy_product_code` FOREIGN KEY (`product_code`) REFERENCES `gov_insurance_product` (`product_code`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='惠民保单表';

-- 公益积分表
CREATE TABLE `public_welfare_points` (
    `welfare_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '公益ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `points` INT UNSIGNED NOT NULL COMMENT '公益积分',
    `source` TINYINT UNSIGNED NOT NULL COMMENT '来源：1-安全驾驶，2-公益活动',
    `convert_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '转化时间',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`welfare_id`),
    KEY `idx_user_id` (`user_id`),
    CONSTRAINT `fk_public_welfare_points_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='公益积分表';

-- 隐患路段表
CREATE TABLE `blackspot_road` (
    `road_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '路段ID',
    `road_name` VARCHAR(128) NOT NULL COMMENT '路段名称',
    `location_gps` POINT NOT NULL COMMENT '经纬度',
    `risk_type` VARCHAR(32) NOT NULL COMMENT '风险类型（弯道盲区/行人横穿等）',
    `accident_count` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '历史事故数量',
    `improvement_status` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '改造状态：0-待改造，1-改造中，2-已完成',
    `donation_amount` INT UNSIGNED DEFAULT NULL COMMENT '平安捐赠金额（分）',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`road_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='隐患路段表';

-- 路段改造项目表
CREATE TABLE `road_improvement_project` (
    `project_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '项目ID',
    `road_id` BIGINT UNSIGNED NOT NULL COMMENT '路段ID',
    `project_name` VARCHAR(128) NOT NULL COMMENT '项目名称',
    `start_date` DATE NOT NULL COMMENT '开始日期',
    `end_date` DATE DEFAULT NULL COMMENT '结束日期',
    `budget` INT UNSIGNED NOT NULL COMMENT '预算（分）',
    `status` TINYINT UNSIGNED NOT NULL COMMENT '状态：1-进行中，2-已完成，3-暂停',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`project_id`),
    KEY `idx_road_id` (`road_id`),
    CONSTRAINT `fk_road_improvement_project_road_id` FOREIGN KEY (`road_id`) REFERENCES `blackspot_road` (`road_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='路段改造项目表';

-- 政策性农险保单扩展表
CREATE TABLE `agricultural_policy` (
    `policy_no` VARCHAR(32) NOT NULL COMMENT '保单号',
    `farmer_name` VARCHAR(64) NOT NULL COMMENT '农户姓名',
    `crop_type` VARCHAR(64) NOT NULL COMMENT '作物类型',
    `insured_area` DECIMAL(10,2) NOT NULL COMMENT '投保面积（亩）',
    `subsidy_rate` DECIMAL(5,2) NOT NULL COMMENT '补贴比例（%）',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`policy_no`),
    CONSTRAINT `fk_agricultural_policy_policy_no` FOREIGN KEY (`policy_no`) REFERENCES `policy_master` (`policy_no`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='政策性农险保单扩展表';

-- ======================================================
-- 9. 监管与合规域（5张表）
-- ======================================================

-- 监管报表表
CREATE TABLE `compliance_report` (
    `report_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '报表ID',
    `report_type` VARCHAR(32) NOT NULL COMMENT '报表类型（如偿付能力报告）',
    `report_date` DATE NOT NULL COMMENT '报表日期',
    `file_url` VARCHAR(256) NOT NULL COMMENT '文件URL',
    `status` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '状态：1-已生成，2-已报送',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`report_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='监管报表表';

-- 数据审计日志表
CREATE TABLE `data_audit_log` (
    `log_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '日志ID',
    `operator_id` BIGINT UNSIGNED DEFAULT NULL COMMENT '操作人ID',
    `operation_type` TINYINT UNSIGNED NOT NULL COMMENT '操作类型：1-INSERT，2-UPDATE，3-DELETE',
    `table_name` VARCHAR(64) NOT NULL COMMENT '表名',
    `record_id` VARCHAR(64) NOT NULL COMMENT '记录主键',
    `before_json` JSON DEFAULT NULL COMMENT '修改前JSON',
    `after_json` JSON DEFAULT NULL COMMENT '修改后JSON',
    `operation_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '操作时间',
    PRIMARY KEY (`log_id`),
    KEY `idx_table_name` (`table_name`),
    KEY `idx_operation_time` (`operation_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='数据审计日志表';

-- 消费者投诉表
CREATE TABLE `complaint_record` (
    `complaint_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '投诉ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '投诉用户ID',
    `policy_no` VARCHAR(32) DEFAULT NULL COMMENT '关联保单号',
    `claim_no` VARCHAR(32) DEFAULT NULL COMMENT '关联理赔单号',
    `complaint_content` VARCHAR(1024) NOT NULL COMMENT '投诉内容',
    `handle_result` VARCHAR(512) DEFAULT NULL COMMENT '处理结果',
    `close_time` DATETIME DEFAULT NULL COMMENT '结案时间',
    `status` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '状态：0-待处理，1-处理中，2-已结案',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`complaint_id`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_policy_no` (`policy_no`),
    KEY `idx_claim_no` (`claim_no`),
    CONSTRAINT `fk_complaint_record_user_id` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='消费者投诉表';

-- 反欺诈图数据表（简化版，实际可选用图数据库）
CREATE TABLE `anti_fraud_graph` (
    `node_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '节点ID',
    `node_type` TINYINT UNSIGNED NOT NULL COMMENT '节点类型：1-用户，2-车辆，3-修理厂，4-查勘员',
    `node_properties_json` JSON NOT NULL COMMENT '节点属性',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`node_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='反欺诈图数据表（节点）';

-- 系统参数配置表
CREATE TABLE `system_config` (
    `config_key` VARCHAR(64) NOT NULL COMMENT '配置键',
    `config_value` TEXT NOT NULL COMMENT '配置值',
    `description` VARCHAR(256) DEFAULT NULL COMMENT '说明',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`config_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='系统参数配置表';

-- ======================================================
-- 10. 公共域（4张表）
-- ======================================================

-- 数据字典表
CREATE TABLE `dict` (
    `dict_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '字典ID',
    `dict_type` VARCHAR(32) NOT NULL COMMENT '字典类型',
    `dict_key` VARCHAR(32) NOT NULL COMMENT '字典键',
    `dict_value` VARCHAR(128) NOT NULL COMMENT '字典值',
    `sort_order` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '排序',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`dict_id`),
    UNIQUE KEY `uk_dict_type_key` (`dict_type`, `dict_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='数据字典表';

-- 行政区划表
CREATE TABLE `region` (
    `region_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '区域ID',
    `parent_id` BIGINT UNSIGNED DEFAULT NULL COMMENT '上级区域ID',
    `region_name` VARCHAR(64) NOT NULL COMMENT '区域名称',
    `region_code` VARCHAR(16) NOT NULL COMMENT '区域代码（行政区划代码）',
    `level` TINYINT UNSIGNED NOT NULL COMMENT '层级：1-省，2-市，3-区县',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`region_id`),
    KEY `idx_parent_id` (`parent_id`),
    KEY `idx_region_code` (`region_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='行政区划表';

-- 组织机构表
CREATE TABLE `org` (
    `org_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '机构ID',
    `parent_id` BIGINT UNSIGNED DEFAULT NULL COMMENT '上级机构ID',
    `org_name` VARCHAR(128) NOT NULL COMMENT '机构名称',
    `org_code` VARCHAR(32) NOT NULL COMMENT '机构代码',
    `org_type` TINYINT UNSIGNED NOT NULL COMMENT '机构类型：1-总公司，2-分公司，3-支公司，4-营销服务部',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`org_id`),
    KEY `idx_parent_id` (`parent_id`),
    UNIQUE KEY `uk_org_code` (`org_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='组织机构表';

-- 用户行为埋点表（分区表，按年分区）
CREATE TABLE `user_behavior_log` (
    `log_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '日志ID',
    `user_id` BIGINT UNSIGNED DEFAULT NULL COMMENT '用户ID（未登录可为空）',
    `device_id` VARCHAR(64) DEFAULT NULL COMMENT '设备ID',
    `event_name` VARCHAR(64) NOT NULL COMMENT '事件名称',
    `event_params_json` JSON NOT NULL COMMENT '事件参数',
    `page_name` VARCHAR(128) DEFAULT NULL COMMENT '页面名称',
    `session_id` VARCHAR(64) DEFAULT NULL COMMENT '会话ID',
    `event_time` DATETIME NOT NULL COMMENT '事件时间',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`log_id`, `event_time`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_event_name` (`event_name`),
    KEY `idx_event_time` (`event_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户行为埋点表'
PARTITION BY RANGE (YEAR(event_time))
(
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION p2026 VALUES LESS THAN (2027),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

-- ======================================================
-- 新增 ods 表（补充缺失的 ODS 表，按业务域）
-- ======================================================

-- 1. 代理人业绩追踪表
CREATE TABLE `agent_performance` (
    `performance_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '业绩ID',
    `agent_id` BIGINT UNSIGNED NOT NULL COMMENT '代理人ID',
    `stat_date` DATE NOT NULL COMMENT '统计日期',
    `policy_count` INT UNSIGNED DEFAULT 0 COMMENT '出单数量',
    `premium_total` BIGINT UNSIGNED DEFAULT 0 COMMENT '总保费（分）',
    `commission_total` BIGINT UNSIGNED DEFAULT 0 COMMENT '总佣金（分）',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`performance_id`),
    KEY `idx_agent_id` (`agent_id`),
    KEY `idx_stat_date` (`stat_date`),
    CONSTRAINT `fk_agent_performance_agent` FOREIGN KEY (`agent_id`) REFERENCES `agent` (`agent_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='代理人业绩表';

-- 2. 代理人展业工具日志
CREATE TABLE `agent_tool_log` (
    `log_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '日志ID',
    `agent_id` BIGINT UNSIGNED NOT NULL COMMENT '代理人ID',
    `tool_type` TINYINT UNSIGNED NOT NULL COMMENT '工具类型(1-展业码 2-分享链接 3-APP)',
    `target_id` VARCHAR(64) DEFAULT NULL COMMENT '目标对象ID(保单号/活动ID等)',
    `operate_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '操作时间',
    `etl_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'ETL时间',
    PRIMARY KEY (`log_id`),
    KEY `idx_agent_id` (`agent_id`),
    KEY `idx_operate_time` (`operate_time`),
    CONSTRAINT `fk_agent_tool_log_agent` FOREIGN KEY (`agent_id`) REFERENCES `agent` (`agent_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='代理人展业工具日志';

-- 3. 续保记录表
CREATE TABLE `policy_renewal` (
    `renewal_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '续保ID',
    `original_policy_no` VARCHAR(32) NOT NULL COMMENT '原保单号',
    `new_policy_no` VARCHAR(32) NOT NULL COMMENT '新保单号',
    `renewal_date` DATE NOT NULL COMMENT '续保日期',
    `renewal_channel` VARCHAR(32) DEFAULT NULL COMMENT '续保渠道',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`renewal_id`),
    KEY `idx_original_policy` (`original_policy_no`),
    KEY `idx_new_policy` (`new_policy_no`),
    CONSTRAINT `fk_renewal_original` FOREIGN KEY (`original_policy_no`) REFERENCES `policy_master` (`policy_no`) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_renewal_new` FOREIGN KEY (`new_policy_no`) REFERENCES `policy_master` (`policy_no`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='续保记录表';

-- 4. 补贴记录表（政策性农险等）
CREATE TABLE `subsidy_record` (
    `subsidy_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '补贴ID',
    `policy_no` VARCHAR(32) NOT NULL COMMENT '保单号',
    `subsidy_type` VARCHAR(32) NOT NULL COMMENT '补贴类型(农险补贴/惠民保补贴)',
    `subsidy_amount` INT UNSIGNED NOT NULL COMMENT '补贴金额（分）',
    `subsidy_date` DATE NOT NULL COMMENT '补贴日期',
    `source` VARCHAR(64) DEFAULT NULL COMMENT '补贴来源(政府/公司)',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`subsidy_id`),
    KEY `idx_policy_no` (`policy_no`),
    CONSTRAINT `fk_subsidy_policy` FOREIGN KEY (`policy_no`) REFERENCES `policy_master` (`policy_no`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='补贴记录表';

-- 5. 财务报告表（监管）
CREATE TABLE `financial_report` (
    `report_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '报告ID',
    `report_type` VARCHAR(32) NOT NULL COMMENT '报告类型(偿付能力/资产负债)',
    `report_date` DATE NOT NULL COMMENT '报告日期',
    `file_url` VARCHAR(256) NOT NULL COMMENT '文件路径',
    `status` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '状态(1-已生成 2-已报送)',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`report_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='财务报告表';

-- 6. 购物车表
CREATE TABLE `shopping_cart` (
    `cart_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '购物车ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `product_id` BIGINT UNSIGNED NOT NULL COMMENT '商品ID',
    `quantity` INT UNSIGNED NOT NULL DEFAULT 1 COMMENT '数量',
    `add_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '加入时间',
    PRIMARY KEY (`cart_id`),
    UNIQUE KEY `uk_user_product` (`user_id`, `product_id`),
    CONSTRAINT `fk_cart_user` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_cart_product` FOREIGN KEY (`product_id`) REFERENCES `mall_product` (`product_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='购物车表';

-- 7. 用户反馈表
CREATE TABLE `user_feedback` (
    `feedback_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '反馈ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `feedback_type` TINYINT UNSIGNED NOT NULL COMMENT '类型(1-评价 2-投诉 3-建议)',
    `target_id` VARCHAR(64) DEFAULT NULL COMMENT '关联对象ID(保单号/订单号)',
    `content` VARCHAR(1024) NOT NULL COMMENT '反馈内容',
    `score` TINYINT UNSIGNED DEFAULT NULL COMMENT '评分(1-5)',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`feedback_id`),
    KEY `idx_user_id` (`user_id`),
    CONSTRAINT `fk_feedback_user` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户反馈表';

-- 8. 企业法律服务表
CREATE TABLE `enterprise_legal` (
    `service_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '服务ID',
    `enterprise_id` BIGINT UNSIGNED NOT NULL COMMENT '企业ID',
    `request_time` DATETIME NOT NULL COMMENT '请求时间',
    `service_type` VARCHAR(32) NOT NULL COMMENT '服务类型(法律咨询/找律师)',
    `status` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '状态(1-处理中 2-已完成)',
    `result` VARCHAR(512) DEFAULT NULL COMMENT '处理结果',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`service_id`),
    KEY `idx_enterprise_id` (`enterprise_id`),
    CONSTRAINT `fk_legal_enterprise` FOREIGN KEY (`enterprise_id`) REFERENCES `enterprise` (`enterprise_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='企业法律服务表';

-- 9. 企业助手服务表
CREATE TABLE `enterprise_assistant` (
    `service_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '服务ID',
    `enterprise_id` BIGINT UNSIGNED NOT NULL COMMENT '企业ID',
    `service_type` VARCHAR(32) NOT NULL COMMENT '服务类型(企业培训/年检代办)',
    `request_time` DATETIME NOT NULL COMMENT '请求时间',
    `status` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '状态(1-处理中 2-已完成)',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`service_id`),
    KEY `idx_enterprise_id` (`enterprise_id`),
    CONSTRAINT `fk_assistant_enterprise` FOREIGN KEY (`enterprise_id`) REFERENCES `enterprise` (`enterprise_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='企业助手服务表';

-- 10. 车队管理表
CREATE TABLE `fleet_management` (
    `fleet_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '车队ID',
    `enterprise_id` BIGINT UNSIGNED NOT NULL COMMENT '企业ID',
    `vehicle_id` BIGINT UNSIGNED NOT NULL COMMENT '车辆ID',
    `driver_id` BIGINT UNSIGNED DEFAULT NULL COMMENT '驾驶员ID(关联用户)',
    `add_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '添加时间',
    `remove_time` DATETIME DEFAULT NULL COMMENT '移除时间',
    PRIMARY KEY (`fleet_id`),
    KEY `idx_enterprise_id` (`enterprise_id`),
    KEY `idx_vehicle_id` (`vehicle_id`),
    CONSTRAINT `fk_fleet_enterprise` FOREIGN KEY (`enterprise_id`) REFERENCES `enterprise` (`enterprise_id`) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_fleet_vehicle` FOREIGN KEY (`vehicle_id`) REFERENCES `user_vehicle` (`vehicle_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='车队管理表';

-- 11. 员工福利表（企业客户员工）
CREATE TABLE `employee_benefit` (
    `benefit_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '福利ID',
    `enterprise_id` BIGINT UNSIGNED NOT NULL COMMENT '企业ID',
    `employee_id` BIGINT UNSIGNED NOT NULL COMMENT '员工用户ID',
    `benefit_type` VARCHAR(32) NOT NULL COMMENT '福利类型(健康/体检/卡券)',
    `benefit_amount` INT UNSIGNED DEFAULT NULL COMMENT '福利金额（分）',
    `benefit_time` DATETIME NOT NULL COMMENT '发放时间',
    `status` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '状态(1-有效 0-已使用)',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`benefit_id`),
    KEY `idx_enterprise_id` (`enterprise_id`),
    KEY `idx_employee_id` (`employee_id`),
    CONSTRAINT `fk_benefit_enterprise` FOREIGN KEY (`enterprise_id`) REFERENCES `enterprise` (`enterprise_id`) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_benefit_employee` FOREIGN KEY (`employee_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='员工福利表';

-- 12. 服务保障记录表（如洗车重洗承诺）
CREATE TABLE `service_guarantee` (
    `guarantee_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '保障ID',
    `service_order_no` VARCHAR(32) NOT NULL COMMENT '服务订单号',
    `guarantee_type` VARCHAR(32) NOT NULL COMMENT '保障类型(洗车重洗/代驾补偿)',
    `trigger_time` DATETIME NOT NULL COMMENT '触发时间',
    `compensation_amount` INT UNSIGNED DEFAULT NULL COMMENT '补偿金额（分）',
    `status` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '状态(1-待处理 2-已处理)',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`guarantee_id`),
    KEY `idx_service_order` (`service_order_no`),
    CONSTRAINT `fk_guarantee_order` FOREIGN KEY (`service_order_no`) REFERENCES `service_order` (`order_no`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='服务保障记录表';

-- 13. 商家区域覆盖表
CREATE TABLE `merchant_region` (
    `region_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '区域ID',
    `merchant_id` BIGINT UNSIGNED NOT NULL COMMENT '商家ID',
    `province` VARCHAR(32) NOT NULL COMMENT '省',
    `city` VARCHAR(32) NOT NULL COMMENT '市',
    `district` VARCHAR(32) DEFAULT NULL COMMENT '区',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`region_id`),
    KEY `idx_merchant_id` (`merchant_id`),
    CONSTRAINT `fk_merchant_region_merchant` FOREIGN KEY (`merchant_id`) REFERENCES `merchant` (`merchant_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='商家区域覆盖表';

-- 14. 商家服务类型表
CREATE TABLE `merchant_service_type` (
    `type_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '类型ID',
    `merchant_id` BIGINT UNSIGNED NOT NULL COMMENT '商家ID',
    `service_type` TINYINT UNSIGNED NOT NULL COMMENT '服务类型(1-洗车 2-保养 3-加油...)',
    `price_standard` JSON DEFAULT NULL COMMENT '价格标准',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`type_id`),
    UNIQUE KEY `uk_merchant_type` (`merchant_id`, `service_type`),
    CONSTRAINT `fk_service_type_merchant` FOREIGN KEY (`merchant_id`) REFERENCES `merchant` (`merchant_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='商家服务类型表';

-- 15. 公益权益表
CREATE TABLE `welfare_entitlement` (
    `entitlement_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '权益ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `entitlement_type` VARCHAR(32) NOT NULL COMMENT '权益类型(道路救援/三免理赔)',
    `grant_time` DATETIME NOT NULL COMMENT '授予时间',
    `expire_time` DATETIME DEFAULT NULL COMMENT '过期时间',
    `status` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '状态(1-有效 0-已使用)',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`entitlement_id`),
    KEY `idx_user_id` (`user_id`),
    CONSTRAINT `fk_welfare_user` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='公益权益表';

-- 16. 安全驾驶评分表
CREATE TABLE `safe_driving_score` (
    `score_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '评分ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `vehicle_id` BIGINT UNSIGNED DEFAULT NULL COMMENT '车辆ID',
    `score_date` DATE NOT NULL COMMENT '评分日期',
    `score` DECIMAL(5,2) NOT NULL COMMENT '评分(0-100)',
    `model_version` VARCHAR(32) DEFAULT NULL COMMENT '模型版本',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`score_id`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_vehicle_id` (`vehicle_id`),
    CONSTRAINT `fk_safe_score_user` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_safe_score_vehicle` FOREIGN KEY (`vehicle_id`) REFERENCES `user_vehicle` (`vehicle_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='安全驾驶评分表';

-- 17. 风险隐患表（企业）
CREATE TABLE `risk_hidden_danger` (
    `danger_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '隐患ID',
    `enterprise_id` BIGINT UNSIGNED NOT NULL COMMENT '企业ID',
    `danger_type` VARCHAR(64) NOT NULL COMMENT '隐患类型',
    `description` VARCHAR(512) NOT NULL COMMENT '描述',
    `discovery_date` DATE NOT NULL COMMENT '发现日期',
    `fix_date` DATE DEFAULT NULL COMMENT '整改日期',
    `status` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '状态(0-未整改 1-已整改)',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`danger_id`),
    KEY `idx_enterprise_id` (`enterprise_id`),
    CONSTRAINT `fk_danger_enterprise` FOREIGN KEY (`enterprise_id`) REFERENCES `enterprise` (`enterprise_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='风险隐患表';

-- 18. 理赔进度查询日志
CREATE TABLE `claim_progress_query_log` (
    `query_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '查询ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `claim_no` VARCHAR(32) NOT NULL COMMENT '理赔单号',
    `query_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '查询时间',
    `result` JSON DEFAULT NULL COMMENT '查询结果快照',
    PRIMARY KEY (`query_id`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_claim_no` (`claim_no`),
    CONSTRAINT `fk_claim_query_user` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_claim_query_claim` FOREIGN KEY (`claim_no`) REFERENCES `claim_report` (`claim_no`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='理赔进度查询日志';

-- 19. 保单查询日志
CREATE TABLE `policy_query_log` (
    `query_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '查询ID',
    `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
    `policy_no` VARCHAR(32) NOT NULL COMMENT '保单号',
    `query_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '查询时间',
    `result` JSON DEFAULT NULL COMMENT '查询结果快照',
    PRIMARY KEY (`query_id`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_policy_no` (`policy_no`),
    CONSTRAINT `fk_policy_query_user` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_policy_query_policy` FOREIGN KEY (`policy_no`) REFERENCES `policy_master` (`policy_no`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='保单查询日志';
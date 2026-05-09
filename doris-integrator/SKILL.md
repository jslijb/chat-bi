---
name: doris-integrator
description: Doris集成引擎，实现DWS→Doris手动同步、ADS+Doris共存路由、报表存储引擎迁移
version: 1.0.0
author: BI Team
trigger_keywords:
  - Doris同步
  - 同步到Doris
  - bi-doris
  - 存储迁移
  - Doris健康检查
upstream_skill: cluster-tester
downstream_skill: null
---

# Doris集成引擎

## 技能描述
实现DWS层Paimon数据到Doris的手动同步，支持ADS+Doris共存架构。

**当前模式**：sync_mode=manual（Doris未部署，保留功能，初期手动触发）

## ADS+Doris共存架构

```
报表查询请求
    │
    ▼
ReportStorageRouter
    │
    ├── storage_engine=ADS → Spark SQL查询Paimon ADS层
    │
    └── storage_engine=Doris
        │
        ├── Doris可用 → Doris SQL查询
        │
        └── Doris不可用 → 自动降级到Spark SQL查询Paimon
```

## 核心接口

### 1. 手动同步
```bash
bi-doris sync --table dws_policy_premium_daily
bi-doris sync-report --report-id R001  # 同步报表依赖的所有DWS表
```

### 2. 同步状态
```bash
bi-doris status  # 查看所有同步表状态
bi-doris check   # 检查Doris与Paimon数据差异
```

### 3. 模式切换
```bash
bi-doris mode manual   # 手动同步（默认）
bi-doris mode auto     # 自动同步（Doris部署后）
```

### 4. 存储引擎迁移
```bash
bi-doris migrate-to-doris --report-id R001  # ADS→Doris
bi-doris migrate-to-ads --report-id R001    # Doris→ADS
```

### 5. 健康检查
```bash
bi-doris health  # 检查Doris集群可用性
```

## Doris建表映射规则

| Paimon类型 | Doris类型 | 说明 |
|-----------|----------|------|
| STRING | VARCHAR(65533) | Doris需指定长度 |
| BIGINT | BIGINT | 直接映射 |
| INT | INT | 直接映射 |
| DECIMAL(p,s) | DECIMAL(p,s) | 直接映射 |
| TIMESTAMP | DATETIME | Doris用DATETIME |
| BOOLEAN | BOOLEAN | 直接映射 |

## 目录结构
```
doris-integrator/
├── SKILL.md
└── examples/
    └── doris_sync.py
```

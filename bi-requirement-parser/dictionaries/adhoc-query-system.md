# 临时取数系统设计文档

## 一、核心概念

临时取数和正式报表是同一需求光谱的两端：

```
纯临时取数 ←————————————————————————————→ 正式报表
特征：                              特征：
- 一次性的                          - 定期的（日/周/月）
- 个人使用                          - 多人/团队使用
- 不需要留存                        - 需要留存
- 响应快（秒~分钟级）               - 精度要求高
- SQL 直接查 ODS/DWD               - 建表 + ETL + 调度
- 不进入需求管理流程                - 完整需求管理流程
```

**核心理念**：临时取数不是"丢弃"的数据需求，而是"尚未被发现价值"的潜在报表。通过缓存和模式识别，让高频临时取数自动"进化"为正式报表。

---

## 二、需求类型判断（AI 自动 + 人类互动）

### 2.1 三级判断机制

```
用户输入
  ↓
Level 1: 显式关键词（自动判断）
  ├── 命中临时取数关键词 → 走临时取数流程
  ├── 命中报表关键词 → 走正式报表流程
  └── 未命中 ↓
Level 2: 语义分析（AI 推断）
  ├── AI 判断有 ≥80% 置信度 → 走对应流程
  └── AI 不确定 ↓
Level 3: 人类互动（追问 1-2 个问题）
  └── 用户回答 → 最终判定
```

### 2.2 Level 1: 关键词匹配表

**临时取数信号词**：

| 关键词/短语 | 置信度 | 说明 |
|------------|--------|------|
| 帮我取一下、取个数据 | 100% | 明确取数意图 |
| 临时看一下、临时查一下 | 95% | 明确一次性 |
| 跑一下数据、查一下 | 90% | 偏临时 |
| 数据给我、我只要数据 | 90% | 不要报表只要数据 |
| 不要报表、不用做报表 | 100% | 显式排除报表 |
| 导出一下、导个 CSV | 95% | 明确导出意图 |
| 多少、有几个、前N名 | 85% | 简单查询 |
| 有没有、是否 | 80% | 存在性判断 |

**正式报表信号词**：

| 关键词/短语 | 置信度 | 说明 |
|------------|--------|------|
| 做一个报表、建报表 | 100% | 明确报表意图 |
| 做成看板、做看板 | 100% | 明确看板意图 |
| 需要定期、每天/每周/每月 | 95% | 周期性需求 |
| 上线、发布、部署 | 90% | 产品化意图 |
| 给业务用、给领导看 | 90% | 多人使用 |
| 监控、预警、告警 | 85% | 持续监控需求 |
| 做成标准、规范化 | 85% | 长期运营 |

### 2.3 Level 2: AI 语义推断

当关键词不明确时，AI 根据上下文推断：

```
推断依据：
1. 时间词：有"每天/每周" → 报表；有"今天/现在" → 临时
2. 人称词：有"给我" → 临时；有"给大家/给团队" → 报表
3. 动作词：有"查/看/取" → 临时；有"建/做/设计" → 报表
4. 结果词：有"数据/结果/数字" → 临时；有"趋势/报表/图表" → 报表
```

### 2.4 Level 3: 人类互动（最多问 1 个问题）

当 AI 置信度 < 80% 时，追问：

```
"这个数据你需要定期看（比如每天/每周自动跑），
 还是临时查一次就行？"

用户回复：
  "定期" / "每天" / "每周" → 正式报表
  "一次" / "临时" / "现在看看" → 临时取数
  "看情况" → 默认临时取数（保守策略，避免过度建设）
```

---

## 三、临时取数执行流程（轻量级）

### 3.1 流程图

```
用户输入临时取数需求
        ↓
AI 分析需求 → 确认表和字段
        ↓
查缓存：是否有完全相同的近期查询？
  ├── 命中（<24h） → 直接返回缓存结果 + "这是昨天的查询结果"
  └── 未命中 ↓
生成 SQL（SELECT 语句，不建表）
        ↓
EXPLAIN 语法验证
        ↓
提交到集群执行
        ↓
返回结果（表格/CSV）
        ↓
记录到临时取数缓存（fingerprint + 元数据）
        ↓
检查是否触发提升规则（见第四章）
```

### 3.2 与正式报表流程的对比

| 环节 | 临时取数 | 正式报表 |
|------|---------|---------|
| 需求解析 | 简化版（1轮对话） | 完整版（最多3轮） |
| 去重检查 | 不做 | 必须 |
| 影响分析 | 不做 | 必须 |
| 人工审批 | 不需要 | 必须两道门禁 |
| 代码产出 | 仅 SELECT SQL | DDL + ETL + 测试 |
| 语法验证 | EXPLAIN | EXPLAIN |
| 集群执行 | 执行一次 | 建表+跑ETL+验证数据 |
| Git 提交 | 不提交 | 必须提交 |
| 调度配置 | 不配置 | 自动配置 |
| 耗时 | 1-2 分钟 | 5-10 分钟 |

### 3.3 临时取数输出格式

```markdown
## 临时取数结果

**查询 ID**：ADHOC-20260421-001
**查询时间**：2026-04-21 16:30
**查询人**：张三
**需求描述**：查一下最近7天车险保单量 TOP10 渠道

**执行的 SQL**：
```sql
SELECT payment_channel, COUNT(*) AS policy_count, SUM(amount) AS total_premium
FROM paimon.cx_ods_safe.pingan_insurance_premium_payment
WHERE payment_time BETWEEN '2026-04-14' AND '2026-04-21'
  AND product_type = '车险'
GROUP BY payment_channel
ORDER BY policy_count DESC
LIMIT 10
```

**查询结果**：

| 渠道 | 保单数 | 保费总额(元) |
|------|--------|-------------|
| 线上直营 | 1,234 | 567,890 |
| 代理人 | 987 | 432,100 |
| ... | ... | ... |

**执行耗时**：3.2 秒
**结果行数**：10 行

---
💡 **提示**：这是临时查询结果。如需定期获取此数据，可以升级为正式报表。
```

---

## 四、缓存与模式识别

### 4.1 查询指纹（Query Fingerprint）

每个临时取数生成一个"指纹"，用于判断查询是否相似：

```python
def compute_fingerprint(tables, dimensions, metrics, filters):
    """
    查询指纹 = hash(排序后的 表集合 + 维度集合 + 指标集合)
    
    示例：
    fingerprint("查最近7天车险保单量TOP10渠道")
    = hash({
        tables: ["paimon.cx_ods_safe.pingan_insurance_premium_payment"],
        dimensions: ["payment_channel"],
        metrics: ["count(*)", "sum(amount)"],
        filters: ["payment_time in 7d", "product_type=车险"]
    })
    = "fp_a3b2c1d4"
    """
    components = sorted(tables) + sorted(dimensions) + sorted(metrics)
    return hashlib.md5("|".join(components).encode()).hexdigest()[:12]
```

**相似度计算**：

```
两个查询 A 和 B 的相似度 = |A.components ∩ B.components| / |A.components ∪ B.components|

相似度阈值：
  ≥ 1.0 → 完全相同（精确匹配）
  ≥ 0.7 → 高度相似（同一模式）
  ≥ 0.5 → 中度相似（相关模式）
  < 0.5 → 不同查询
```

### 4.2 缓存存储表

```sql
-- 临时取数查询缓存表
use paimon.cx_dwp_safe;
CREATE TABLE IF NOT EXISTS adhoc_query_cache (
    query_id          STRING        COMMENT '查询唯一ID，格式 ADHOC-YYYYMMDD-NNN',
    user_id           STRING        COMMENT '请求人',
    query_time        TIMESTAMP     COMMENT '查询时间',
    requirement       STRING        COMMENT '原始需求描述（自然语言）',
    sql_text          STRING        COMMENT '生成的 SQL 语句',
    tables_used       ARRAY<STRING> COMMENT '使用的源表列表',
    dimensions        ARRAY<STRING> COMMENT '分析维度列表',
    metrics           ARRAY<STRING> COMMENT '分析指标列表',
    query_fingerprint STRING        COMMENT '查询指纹 hash',
    result_rows       INT           COMMENT '结果行数',
    execution_time_ms INT           COMMENT '执行耗时(毫秒)',
    status            STRING        COMMENT '状态：temporary / candidate / promoted',
    promote_score     INT           COMMENT '提升得分，初始0',
    created_at        TIMESTAMP     COMMENT '创建时间'
) PARTITIONED BY (dt STRING comment '分区字段')
TBLPROPERTIES ('parquet.compression'='SNAPPY');

-- 查询模式聚合表（用于模式识别）
use paimon.cx_dwp_safe;
CREATE TABLE IF NOT EXISTS adhoc_query_pattern (
    pattern_id        STRING        COMMENT '模式唯一ID',
    fingerprint       STRING        COMMENT '查询指纹',
    pattern_desc      STRING        COMMENT '模式描述（人类可读）',
    query_count       INT           COMMENT '累计被查询次数',
    unique_users      INT           COMMENT '独立查询人数',
    first_query_time  TIMESTAMP     COMMENT '首次查询时间',
    last_query_time   TIMESTAMP     COMMENT '最近查询时间',
    promote_status    STRING        COMMENT 'monitoring / candidate / promoted / rejected',
    promote_score     INT           COMMENT '提升得分',
    suggested_report  STRING        COMMENT '建议的报表名称',
    suggested_dims    ARRAY<STRING> COMMENT '建议固化的维度',
    suggested_metrics ARRAY<STRING> COMMENT '建议固化的指标',
    suggested_freq    STRING        COMMENT '建议产出频率：daily/weekly/monthly',
    updated_at        TIMESTAMP     COMMENT '更新时间'
) PARTITIONED BY (dt STRING comment '分区字段')
TBLPROPERTIES ('parquet.compression'='SNAPPY');
```

### 4.3 缓存命中逻辑

```
用户发起临时取数
    ↓
AI 解析需求 → 提取 表/维度/指标/过滤条件
    ↓
计算 query_fingerprint
    ↓
查 adhoc_query_cache：
  ├── fingerprint 完全匹配 AND query_time < 24h
  │     → 缓存命中，直接返回结果
  │
  ├── fingerprint 完全匹配 AND query_time >= 24h
  │     → SQL 复用（参数更新时间条件），重新执行
  │
  ├── fingerprint 相似度 ≥ 0.7
  │     → "有相似的查询，是否参考？"（展示历史查询）
  │
  └── 无匹配
        → 全新生成 SQL
```

---

## 五、自动物化提升规则

### 5.1 提升得分（Promote Score）

每次临时取数命中已有模式时，该模式的 `promote_score` 递增：

| 触发条件 | 加分 | 说明 |
|----------|------|------|
| 同一模式被**同一用户**再次查询 | +2 | 个人高频需求 |
| 同一模式被**不同用户**查询 | +5 | 跨用户共性需求 |
| 同一模式 **7天内**被查询 ≥ 3次 | +10 | 紧迫度信号 |
| 同一模式 **30天内**被查询 ≥ 10次 | +15 | 高频需求 |
| 查询结果被用户**二次追问**（基于结果继续分析） | +3 | 需求深度信号 |
| 单次查询**耗时 > 60秒** | +5 | 性能优化价值 |
| 查询涉及 **3张以上表 JOIN** | +3 | 复杂度高，值得物化 |
| 查询结果被用户**导出**或**分享** | +5 | 结果有分发价值 |

### 5.2 提升阈值与动作

| 得分区间 | 状态 | 动作 |
|----------|------|------|
| 0 ~ 14 | 🟢 monitoring（监控中） | 仅缓存，不提醒 |
| 15 ~ 29 | 🟡 candidate（候选） | 查询时提示："这个数据最近被查了 N 次，是否要做成定期报表？" |
| 30 ~ 49 | 🟠 recommended（推荐） | 主动推送建议给数据开发："以下模式建议物化为报表"，附带完整提升方案 |
| ≥ 50 | 🔴 auto_promote（自动提升） | AI 自动生成正式需求文档，进入需求评审流程（仍需人工最终审批） |

### 5.3 提升流程详解

```
临时取数缓存积累
        ↓
模式得分 ≥ 15（候选）
        ↓
下一次用户查询时，AI 追问：
  "💡 这个「车险保单量TOP10渠道」的查询，近30天已被查询了8次（5人）。
   是否要做成每周自动产出的报表？做成后查询从秒级提升到毫秒级。
   回复「好」我帮你生成报表需求。"
        ↓ 用户确认
AI 自动将临时取数转化为正式需求：
  - 需求编号：C-REQ-xxx v1.0
  - 一句话需求：每周统计车险保单量 TOP10 渠道
  - 建议产出频率：weekly
  - 建议物化表：paimon.cx_dws_safe.dws_policy_channel_weekly
  - 数据源：从临时取数的 SQL 自动推导
        ↓
进入正式流程：
  需求去重 → 影响分析 → 人工审批 → code-updater → sql-validator → 集群测试 → git-merger → scheduler-updater
        ↓
物化完成
        ↓
后续查询路由：
  用户再问类似问题 → AI 优先推荐查物化表（毫秒级）
```

### 5.4 物化后的查询路由

```
用户发起查询
    ↓
AI 解析需求 → 计算 fingerprint
    ↓
查 adhoc_query_pattern：
  ├── promote_status = 'promoted'
  │     → "这个数据已有物化报表：paimon.cx_dws_safe.dws_policy_channel_weekly"
  │     → 直接查物化表（毫秒级）
  │     → "需要看明细吗？可以查原始表 paimon.cx_ods_safe.pingan_insurance_premium_payment（秒级）"
  │
  ├── promote_status = 'candidate' / 'recommended'
  │     → "这个数据最近被频繁查询，已有候选报表方案"
  │     → "直接查（秒级）还是等报表上线（毫秒级）？"
  │
  └── promote_status = 'monitoring' 或无匹配
        → 正常临时取数流程
```

---

## 六、AI 的判断能力与边界

### 6.1 AI 能做的

| 能力 | 说明 | 准确率 |
|------|------|--------|
| 关键词分类 | 显式关键词匹配 | ~95% |
| 语义推断 | 上下文分析判断类型 | ~80% |
| 指纹生成 | 提取表/维度/指标并 hash | ~95% |
| 模式匹配 | 比较指纹相似度 | ~90% |
| 提升建议 | 根据得分推荐物化方案 | ~85% |
| SQL 生成 | 根据需求生成 SELECT 语句 | ~80% |

### 6.2 需要人类决策的

| 决策点 | 原因 |
|--------|------|
| 模糊需求的类型判断 | AI 不确定时必须问人 |
| 是否提升为报表 | 提升需要人工确认 |
| 物化方案审批 | 涉及资源消耗，需人工审批 |
| 敏感数据取数 | 涉及隐私合规，需人工审批 |

### 6.3 保守原则

- **不确定就问**：AI 置信度 < 80% 时必须追问，宁可多问一个问题
- **默认临时**：无法判断时默认走临时取数流程（避免过度建设）
- **用户可覆盖**：用户随时可以手动将临时取数升级为报表
- **降级不升级**：物化表查询失败时自动降级到原始表查询

---

## 七、与现有 Skill 链路的集成

### 7.1 完整链路图

```
用户输入
    ↓
bi-requirement-parser
    ├── 需求类型判断
    │     ├── 临时取数 → 临时取数流程 ↓
    │     └── 正式报表 → 正式报表流程 ↓
    │
    ├── [临时取数流程]
    │     AI 解析 → 生成 SQL → 查缓存 → 执行 → 返回结果 → 写缓存
    │     → 检查提升规则 → 候选则提示用户
    │
    └── [正式报表流程]
          AI 分析 → 追问 → 确认 → 去重 → 影响分析 → 审批
          → code-updater → sql-validator → cluster-tester → git-merger → scheduler-updater
```

### 7.2 临时取数 → 报表 提升路径

```
临时取数 (adhoc_query_cache)
    ↓ 模式累积
候选报表 (promote_score ≥ 15)
    ↓ 用户确认
bi-requirement-parser (自动生成需求文档)
    ↓
需求去重检查
    ↓
影响分析 + 审批门禁
    ↓ 审批通过
requirement-diff-analyzer (如有变更)
    ↓
code-updater (生成 DDL + ETL)
    ↓
sql-validator (EXPLAIN 验证)
    ↓
cluster-tester (集群执行测试)
    ↓
git-merger (合并确认)
    ↓
scheduler-updater (配置调度)
    ↓
报表上线 → adhoc_query_pattern.promote_status = 'promoted'
```

---

## 八、落地建议

### Phase 1（立即可以做）

1. 在 `bi-requirement-parser` 中增加需求类型判断（关键词 + AI 推断 + 人类互动）
2. 临时取数走轻量级流程（生成 SQL → EXPLAIN → 执行 → 返回结果）
3. 用本地文件（JSON）缓存临时取数记录

### Phase 2（需要 Hadoop 集群支持）

1. 创建 `adhoc_query_cache` 和 `adhoc_query_pattern` 表
2. 实现查询指纹计算和模式匹配
3. 实现提升得分计算和阈值判断

### Phase 3（需要团队运营）

1. 建立物化决策机制（谁审批、资源预算）
2. 定期 Review 候选报表（周会）
3. 物化效果追踪（查询耗时对比、用户满意度）

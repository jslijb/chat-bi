# Chat-BI 智能数据仓库代码生成系统

> 基于 OpenClaw + RAG + 大语言模型的 BI 需求理解与数据仓库代码自动生成平台

version: 6.2.0  (2026-05-10: 修复 faiss/KB路径/硬编码密码等 bug; 强化隐私安全; README 全面校对)

---

## 项目简介

### 背景

传统数据仓库开发面临三大痛点：

1. **需求理解成本高** — 业务方用自然语言提需求，开发人员需反复沟通确认
2. **SQL 编写耗时** — DDL/ETL/查询 SQL 全靠手写，128 张表的字典查阅低效
3. **变更影响难追踪** — 需求一变，代码改动范围难以评估

### 目标

构建一个 AI 驱动的数据仓库代码生成流水线，让业务需求 → 可执行 SQL 的转化自动化。
通过 OpenClaw Skill 编排 + 数据字典 RAG 检索 + 大模型代码生成，实现从自然语言到生产可用的 Paimon 表与 Spark SQL 的全链路自动化。

### 解决的问题

- ✅ **自然语言 → 结构化需求**：业务人员口述需求，AI 解析为标准需求文档
- ✅ **数据字典语义检索**：128 张表(126KB)的字典通过 RAG 检索，Token 消耗降低约 77%
- ✅ **SQL 自动生成**：DDL/ETL/查询全自动生成，符合 Spark SQL 编写规范
- ✅ **变更影响分析**：新旧需求对比，自动评估影响范围
- ✅ **集群验证 + 部署**：EXPLAIN 验证 → 集群真实执行 → Git 提交 → 调度更新
- ✅ **经验沉淀**：错题本机制，验证失败/通过的 SQL 自动入库供下次检索

### 技术栈

| 层级 | 技术 | 用途 |
|------|------|------|
| AI 编排 | OpenClaw | Skill 调度与执行 |
| LLM | Qwen 3.5 Plus（默认）/ DeepSeek（可选） | 需求解析、SQL 生成 |
| Embedding | BAAI/bge-large-zh-v1.5 (1024维) | 语义向量化 |
| 向量检索 | FAISS (IndexFlatIP) | RAG 语义检索 |
| 模型下载 | ModelScope | 国内镜像加速 |
| 数据湖 | Apache Paimon | 表格式 |
| 计算引擎 | Spark SQL / Hive | SQL 执行 |
| 存储 | HDFS | 数据存储 |
| 调度 | DolphinScheduler / cron | 任务调度 |
| 配置 | YAML + `${VAR}` 环境变量占位符 | 配置管理（敏感信息不入库） |
| 版本控制 | Gitee | 代码托管与 PR |
| 语言 | Python 3 + Bash | 工具脚本 |

### 业务背景

平安产险数据湖 BI 项目 — 128 张 ODS 表（产品/代理人/保单/理赔/缴费/客户等），覆盖 C/B/G 三端共 20 个 BI 需求。

### Skill 流水线总览

```
用户输入业务需求
       │
       ▼
bi-requirement-parser     -->  结构化需求文档
       │
       ▼ (需求变更时)
requirement-diff-analyzer -->  变更影响报告
       │
       ▼
sql-code-generator        -->  DDL / ETL / SELECT 代码
       │
       ├-> sql-validator      -->  EXPLAIN 验证
       │       │
       │       ├-> cluster-tester  -->  集群执行 (可选)
       │       │        │
       │       │        ▼
       │       └-> git-merger      -->  合并主分支
       │                │
       │                ▼
       └-> scheduler-updater -->  更新调度任务
```

---

## 目录

1. [部署架构总览](#一部署架构总览)
2. [目录映射关系](#二目录映射关系)
3. [手动部署步骤](#三手动部署步骤)
4. [配置文件说明](#四配置文件说明)
5. [Skill 详细介绍](#五skill-详细介绍)
6. [工具脚本说明](#六工具脚本说明)
7. [Python 环境](#七python-环境)
8. [数据字典 RAG](#八数据字典-rag)
9. [SQL 知识库](#九sql-知识库)
10. [模型切换](#十模型切换)
11. [测试数据与本地验证](#十一测试数据与本地验证)
12. [一键部署脚本](#十二一键部署脚本)
13. [部署检查清单](#十三部署检查清单)

---

## 一、部署架构总览

### 本地开发环境

```
d:\Python\chat_bi\
├── config.yaml                    -- 业务配置模板（${VAR} 占位符）
├── config_loader.py               -- 配置加载器（支持 ${VAR} 替换）
├── dict_rag_requirements.txt      -- Python 依赖清单
├── .gitignore
│
├── Python 工具脚本
│   ├── build_dict_rag.py          -- RAG 索引构建 + 检索（支持 --er-file）
│   ├── sql_knowledge_base.py      -- SQL 知识库管理
│   ├── generate_data_dictionary.py-- 数据字典生成器
│   └── generate_data.py           -- 测试数据生成器
│
├── Shell 封装脚本
│   ├── run_py.sh                  -- 统一 Python 执行入口
│   ├── kb.sh                      -- SQL 知识库快捷命令
│   ├── rag.sh                     -- 数据字典 RAG 快捷命令
│   └── switch-model.sh            -- LLM 模型切换
│
├── rag/                           -- RAG Python 包（升级版网关，含 CLI/检索器/向量索引）
│   ├── rag_gateway.py             -- RAG 统一网关
│   ├── cli.py                     -- 命令行入口（build/search/stats）
│   ├── retriever.py / vector_index.py / index_manager.py
│   ├── ddl_parser.py / cte_parser.py / dependency_graph.py
│   ├── impact_assessor.py / deletion_workflow.py / ref_count_manager.py
│   ├── model_registry.py / vector_state_manager.py
│   └── indices/                   -- 索引输出目录
│
├── Skill 定义目录（15个，每个含 SKILL.md）
│   ├── bi-requirement-parser/     -- 主 Skill（入口：需求解析）
│   ├── sql-code-generator/        -- SQL 代码生成（DDL/ETL/查询）
│   ├── requirement-diff-analyzer/ -- 需求变更分析
│   ├── code-updater/              -- 代码自动修改+Git提交
│   ├── sql-validator/             -- SQL EXPLAIN验证
│   ├── cluster-tester/            -- 集群真实执行
│   ├── git-merger/                -- Git分支合并
│   ├── scheduler-updater/         -- 调度任务更新
│   ├── template-manager/          -- 模板管理
│   ├── lineage-manager/           -- 血缘关系管理
│   ├── dict-sync/                 -- 数据字典同步
│   ├── doris-integrator/          -- Doris集成
│   ├── adhoc-engine/              -- 临时取数引擎
│   ├── priority-manager/          -- 优先级管理
│   └── async-task-scheduler/      -- 异步任务调度
│
├── data_src/                      -- DDL + 基础测试数据源
│   ├── create_table.sql           -- 全量建表 SQL
│   └── pingan_insurance_data.sql  -- ODS 层基础数据
│
├── supplement_data/               -- 补充测试数据（不部署）
├── verify_sql/                    -- SQL 验证脚本（不部署）
├── output/                        -- generate_data.py 输出目录
│
├── deploy/                        -- 部署脚本目录
│   ├── deploy.env                 -- 部署环境变量（${VAR} 占位符）
│   ├── deploy.sh                  -- 一键部署脚本
│   ├── upload_only.sh             -- 仅上传脚本
│   ├── init_mysql.sh              -- 远程 MySQL 初始化
│   ├── local_verify.sh            -- 本地验证脚本
│   └── requirements.txt           -- 部署依赖
│
└── OPENCLAW_DEPLOY_GUIDE_GITEE.md -- 详细部署指南（Gitee 工作流）
```

### 服务器目标结构

```
/home/openclaw/.openclaw/
├── config.yaml                       -- Hadoop/Git/超时业务配置
├── kb_config.yaml                    -- Embedding 模型配置
│
├── skills/                           -- Skill 定义目录（15个，复数）
│   ├── bi-requirement-parser/        -- 主 Skill（含 dictionaries/examples/templates）
│   ├── sql-code-generator/           -- SQL 编写引擎（含规范+模板+示例）
│   ├── cluster-tester/
│   ├── code-updater/
│   ├── git-merger/
│   ├── requirement-diff-analyzer/
│   ├── scheduler-updater/
│   ├── sql-validator/
│   ├── template-manager/
│   ├── lineage-manager/
│   ├── dict-sync/
│   ├── doris-integrator/
│   ├── adhoc-engine/
│   ├── priority-manager/
│   └── async-task-scheduler/
│
├── bin/                              -- Python 脚本 + Shell 入口
│   ├── run_py.sh                     -- 统一入口（自动激活 venv）
│   ├── kb.sh                         -- SQL 知识库快捷命令
│   ├── rag.sh                        -- 数据字典 RAG 快捷命令
│   ├── switch-model.sh               -- LLM 模型切换
│   ├── build_dict_rag.py             -- RAG 索引构建与检索
│   ├── sql_knowledge_base.py         -- SQL 知识库管理
│   ├── generate_data_dictionary.py   -- 数据字典生成器
│   └── generate_data.py              -- 测试数据生成器
│
└── workspace/                        -- 运行时数据
    ├── .venv/                        -- Python 虚拟环境
    ├── dict_rag_index/               -- RAG 索引（从本地上传或服务器构建）
    ├── ddl/                          -- DWD/DWS/ADS 层DDL（ODS由flink-cdc自动创建）
    │   └── create_table.sql          -- 全量建表SQL
    ├── dwd/                          -- DWD 层加工脚本
    └── dws/                          -- DWS 层加工脚本
```

---

## 二、目录映射关系

| 服务器路径 | 内容 | 本地来源 | 说明 |
|-----------|------|---------|------|
| `~/.openclaw/config.yaml` | 业务配置 | `config.yaml` | 部署时需编辑填真实值 |
| `~/.openclaw/kb_config.yaml` | Embedding 配置 | `bi-requirement-parser/dictionaries/kb_config.yaml` | 与 config.yaml embedding 段功能重叠 |
| `~/.openclaw/skills/*` | 15 个 Skill 目录 | `bi-requirement-parser/` 等 | 含 SKILL.md + 字典 + 模板 |
| `~/.openclaw/bin/*` | .py 脚本 + .sh | 根目录 `*.py` + `*.sh` | run_py.sh 统一入口 |
| `~/.openclaw/workspace/*` | venv + RAG 索引 | 本地构建后上传 / 服务器构建 | 运行时产生 |
| `~/.openclaw/workspace/ddl/` | DWD/DWS/ADS层DDL | 大模型生成 | ODS由flink-cdc自动创建，不在此列 |
| `~/.openclaw/workspace/dwd/` | DWD 层脚本 | 本地加工产出 | 分层目录 |
| `~/.openclaw/workspace/dws/` | DWS 层脚本 | 本地加工产出 | 分层目录 |

### 文件类型分类

| 类型 | 文件/目录 | 是独立Skill? | 说明 |
|------|----------|:---:|------|
| **Skill** | `bi-requirement-parser/`, `sql-code-generator/` 等 15 个 | YES | 有 SKILL.md frontmatter, OpenClaw 可加载执行 |
| **Python 包** | `rag/` | NO | RAG 升级版网关，被 build_dict_rag.py / cli.py 调用 |
| **工具脚本** | `build_dict_rag.py`, `sql_knowledge_base.py` 等 | NO | 通过 bin/ 下 .sh 调用 |
| **配置** | `config.yaml`, `kb_config.yaml`, `deploy.env` | NO | 部署时填真实值（敏感信息走 `${VAR}`） |
| **部署脚本** | `deploy.sh`, `upload_only.sh`, `local_verify.sh`, `init_mysql.sh` | NO | 辅助部署与验证 |
| **测试数据** | `data_src/`, `supplement_data/`, `verify_sql/` | NO | **不部署到服务器** |

### 不部署的内容

以下文件/目录**不是项目产出物**，仅用于本地 MySQL 验证大模型生成的 DWD/DWS SQL 是否正确，**不参与部署**：

- `data_src/create_table.sql` — 全量建表 SQL（本地验证用）
- `data_src/pingan_insurance_data.sql` — 平安保险 ODS 基础数据
- `supplement_data/` — 补充测试数据（按业务域分文件）
- `verify_sql/` — SQL 验证脚本（C/B/G 三端）
- `output/` — `generate_data.py` 输出目录

---

## 三、手动部署步骤

### 第一步：准备信息

| 信息 | 示例 | 从哪获取 |
|------|------|----------|
| HDFS NameNode | `hdfs://192.168.1.100:8020` | 运维管理员 |
| YARN 队列名 | `default` | 运维管理员 |
| Spark 版本 | `3.5.8` | 服务器 `spark-sql --version` |
| Gitee 仓库 | `https://gitee.com/xxx/yyy.git` | 你创建的仓库 |
| Gitee Token | `${GITEE_TOKEN}`（环境变量） | Gitee -> 设置 -> 私人令牌 |
| MySQL 密码 | `${MYSQL_PASSWORD}`（环境变量） | 自定义 |

> ⚠️ **安全提示**：所有敏感信息（Token、密码）通过环境变量注入，**不要写入文件**。
> 参见 [隐私安全章节](#十三部署检查清单)。

### 第二步：上传到服务器

```bash
# === 在本地 PowerShell/CMD 执行 ===

SERVER="openclaw@你的服务器IP"

# 1. 创建远程目录（注意是 skills 复数）
ssh $SERVER "mkdir -p ~/.openclaw/{skills,bin,workspace/{ddl,dwd,dws}}"

# 2. 上传全部 15 个 Skill 目录
scp -r bi-requirement-parser      $SERVER:~/.openclaw/skills/
scp -r sql-code-generator          $SERVER:~/.openclaw/skills/
scp -r cluster-tester              $SERVER:~/.openclaw/skills/
scp -r code-updater                $SERVER:~/.openclaw/skills/
scp -r git-merger                  $SERVER:~/.openclaw/skills/
scp -r requirement-diff-analyzer   $SERVER:~/.openclaw/skills/
scp -r scheduler-updater           $SERVER:~/.openclaw/skills/
scp -r sql-validator               $SERVER:~/.openclaw/skills/
scp -r template-manager            $SERVER:~/.openclaw/skills/
scp -r lineage-manager             $SERVER:~/.openclaw/skills/
scp -r dict-sync                   $SERVER:~/.openclaw/skills/
scp -r doris-integrator            $SERVER:~/.openclaw/skills/
scp -r adhoc-engine                $SERVER:~/.openclaw/skills/
scp -r priority-manager            $SERVER:~/.openclaw/skills/
scp -r async-task-scheduler        $SERVER:~/.openclaw/skills/

# 3. 上传 DWD/DWS/ADS 建表脚本到 workspace/ddl/（ODS由flink-cdc自动创建）
scp data_src/create_table.sql      $SERVER:~/.openclaw/workspace/ddl/

# 4. 上传 Python 脚本 + Shell 到 bin/
scp build_dict_rag.py              $SERVER:~/.openclaw/bin/
scp sql_knowledge_base.py          $SERVER:~/.openclaw/bin/
scp generate_data_dictionary.py    $SERVER:~/.openclaw/bin/
scp generate_data.py               $SERVER:~/.openclaw/bin/
scp run_py.sh                      $SERVER:~/.openclaw/bin/
scp kb.sh                          $SERVER:~/.openclaw/bin/
scp rag.sh                         $SERVER:~/.openclaw/bin/
scp switch-model.sh                $SERVER:~/.openclaw/bin/

# 5. 上传 RAG Python 包
scp -r rag/                        $SERVER:~/.openclaw/bin/

# 6. 上传配置文件
scp config.yaml                    $SERVER:~/.openclaw/config.yaml
scp bi-requirement-parser/dictionaries/kb_config.yaml $SERVER:~/.openclaw/kb_config.yaml
```

### 第三步：编辑配置

```bash
ssh openclaw@服务器IP

nano ~/.openclaw/config.yaml
# 必须改（或通过环境变量注入）：
#   hadoop.clusters.prod.hdfs.namenode -> 实际HDFS地址
#   git.remote.origin                  -> 实际Gitee仓库
#   git.auth.token                     -> 通过 $GITEE_TOKEN 环境变量注入
#   hadoop.clusters.prod.spark.version -> 实际Spark版本

chmod 600 ~/.openclaw/config.yaml ~/.openclaw/kb_config.yaml
chmod +x ~/.openclaw/bin/*.sh

# 设置敏感环境变量（建议写入 ~/.bashrc 或 secrets 文件，权限 600）
export GITEE_TOKEN="你的真实Token"
export MYSQL_PASSWORD="你的MySQL密码"
```

### 第四步：Python 环境 + 验证

```bash
# 创建 venv + 安装依赖
python3 -m venv ~/.openclaw/workspace/.venv
source ~/.openclaw/workspace/.venv/bin/activate
pip install -r dict_rag_requirements.txt
deactivate

# 验证
ls ~/.openclaw/skills/*/SKILL.md    # 预期: 15 个 SKILL.md
ls ~/.openclaw/workspace/ddl/        # 预期: DWD/DWS/ADS建表SQL
ls ~/.openclaw/workspace/dwd/        # 预期: 目录存在
ls ~/.openclaw/workspace/dws/        # 预期: 目录存在
~/.openclaw/bin/kb.sh stats          # 预期: 统计信息
```

---

## 四、配置文件说明

| 配置文件 | 谁管理 | 用途 |
|----------|--------|------|
| `~/.openclaw/openclaw.json` | OpenClaw 自身 (`openclaw onboard`) | 模型/网关/核心配置 **勿手动改** |
| `~/.openclaw/config.yaml` | 我们编辑 | Hadoop/Git/超时/Embedding 业务配置 |
| `~/.openclaw/kb_config.yaml` | 我们编辑 | Embedding 模型名 + 向量维度 |
| `deploy/deploy.env` | 我们编辑 | 部署脚本环境变量（服务器IP/端口/路径） |
| `config_loader.py` | 我们维护 | 配置加载器，自动替换 `${VAR}` 为环境变量值 |

**config.yaml 关键项**：

| 配置段 | 常见需改项 |
|--------|-----------|
| `hadoop.clusters.prod.spark.*` | queue, version, deploy-mode |
| `hadoop.clusters.prod.hdfs.namenode` | **必须改** |
| `git.remote.origin` | **必须改** |
| `git.auth.token` | 通过 `${GITEE_TOKEN}` 注入 |
| `embedding.model_name` | 默认 `BAAI/bge-large-zh-v1.5` |

**deploy.env 关键项**（与 `deploy/deploy.env` 实际变量名一致）：

| 变量 | 示例值 | 说明 |
|------|--------|------|
| `REMOTE_HOST` | `192.168.1.100` | 服务器 IP |
| `REMOTE_USER` | `openclaw` | SSH 用户名 |
| `REMOTE_PORT` | `22` | SSH 端口 |
| `REMOTE_BASE_DIR` | `/home/openclaw/.openclaw` | 远程部署根路径 |
| `SKILLS_DIR` | `${REMOTE_BASE_DIR}/skills` | 远程 Skill 目录（复数） |
| `BIN_DIR` | `${REMOTE_BASE_DIR}/bin` | 远程脚本目录 |
| `WORKSPACE_DIR` | `${REMOTE_BASE_DIR}/workspace` | 远程工作区 |
| `DDL_DIR` | `${WORKSPACE_DIR}/ddl` | DWD/DWS/ADS 层 DDL |
| `DWD_DIR` | `${WORKSPACE_DIR}/dwd` | DWD 层 SQL |
| `DWS_DIR` | `${WORKSPACE_DIR}/dws` | DWS 层 SQL |
| `MYSQL_HOST` | `127.0.0.1` | MySQL 主机 |
| `MYSQL_USER` | `root` | MySQL 用户 |
| `MYSQL_PASSWORD` | `${MYSQL_PASSWORD:-}` | **环境变量注入，勿写明文** |
| `MYSQL_DATABASE` | `pingan_insurance` | 业务库 |
| `RAG_INDEX_DIR` | `${SKILLS_DIR}/rag/indices` | RAG 索引目录 |
| `RAG_MAX_CACHED_MODELS` | `1` | LRU 缓存模型数 |
| `PYTHON_BIN` / `PIP_BIN` | `python3` / `pip3` | Python 解释器 |

> 🔒 **安全机制**：`MYSQL_PASSWORD` 默认为 `${MYSQL_PASSWORD:-}` 占位符，运行时从环境变量读取。
> 若未设置则展开为空字符串。**禁止在 deploy.env 中写明文密码**。

---

## 五、Skill 详细介绍

### 5.1 bi-requirement-parser — BI 需求解析 (主入口) ⭐

| 属性 | 值 |
|------|-----|
| 版本 | 2.0.0 |
| 定位 | **系统入口**（第一个被触发的 Skill） |
| 触发关键词 | 需求、分析、统计、报表、看板、趋势、对比、异常、流水 |

**功能**: 自然语言 → 结构化 BI 需求文档。含 AI 主动分析、智能追问、术语规范。

**目录**:
```
bi-requirement-parser/
├── SKILL.md                          -- Skill 定义
├── dictionaries/
│   ├── data_dictionary.yaml          -- 机器可读字典 (128表, 126KB)
│   ├── data_dictionary_index.yaml    -- 表名速查索引
│   ├── ods_er.txt                    -- ER 关系图（FK 解析源）
│   ├── fuzzy_terms.yaml              -- 业务术语模糊匹配
│   ├── kb_config.yaml                -- Embedding 配置
│   ├── adhoc-query-system.md         -- 临时取数子系统设计文档
│   └── dict_rag_index/               -- FAISS RAG 索引
├── examples/
│   └── requirements.txt              -- 20个需求样本
└── templates/
    ├── 需求模板.txt
    └── requirement.md
```

### 5.2 sql-code-generator — SQL 代码生成 ⭐

| 属性 | 值 |
|------|-----|
| 版本 | 1.0.0 |
| 上游 | bi-requirement-parser (需求文档) |
| 下游 | sql-validator (验证) |
| 触发关键词 | 生成SQL、写SQL、建表、ETL、落地实现 |

**功能**: 从结构化需求 → 可直接执行的 Spark SQL 代码。
- **DDL**: Paimon CREATE TABLE（含完整注释/TBLPROPERTIES）
- **ETL**: INSERT OVERWRITE 幂等写入（CTE 组织逻辑）
- **SELECT**: 报表查询 / 临时取数（含同比环比）

**强制约束**: 所有代码符合 `dictionaries/spark-sql-standards.md` 编写规范。

**目录**:
```
sql-code-generator/
├── SKILL.md                          -- Skill 定义（含完整编写流程）
├── dictionaries/
│   ├── spark-sql-standards.md        -- Spark SQL 编写规范（强约束）
│   └── sql_patterns.yaml             -- 常用函数/表达式模式库
├── templates/
│   ├── ddl_template.sql              -- Paimon DDL 建表模板
│   ├── etl_template.sql              -- ETL 取数逻辑模板
│   └── query_template.sql            -- 报表/临时取数模板
└── examples/
    ├── example_ddl_output.sql        -- DDL 示例(车险保费汇总表)
    ├── example_etl_output.sql        -- ETL 示例(日汇总加工)
    └── example_query_output.sql      -- 查询示例(渠道保费趋势)
```

### 5.3 requirement-diff-analyzer — 需求变更分析

对比新旧需求版本(v1 vs v2)，输出变更清单 + 影响范围评估。

### 5.4 code-updater — 代码自动修改 + Git 提交

根据变更影响报告，自动生成/修改 SQL 代码 → Git 分支提交 → PR 创建。
> 注意: **SQL 编写本身已委托给 sql-code-generator**, code-updater 负责 Git 操作和文件管理。

### 5.5 sql-validator — SQL 验证

在 Hadoop 集群执行 EXPLAIN 验证 SQL 语法正确性(Hive / Spark SQL)。

### 5.6 cluster-tester — 集群测试

在 Hadoop 集群真实执行 DDL/ETL/数据验证。

### 5.7 git-merger — 代码合并

PR/MR 创建 → 人工确认 → Squash merge 到主分支。

### 5.8 scheduler-updater — 调度更新

更新调度任务(cron / Airflow DAG / DolphinScheduler)。流水线终点。

### 5.9 template-manager — 模板管理

管理 SQL 模板的版本、参数化、复用。支持模板继承与变量替换。

### 5.10 lineage-manager — 血缘关系管理

追踪表/字段级血缘关系，维护数据流向图谱。支持上下游影响分析。

### 5.11 dict-sync — 数据字典同步

多环境数据字典同步（开发/测试/生产），确保字典一致性。

### 5.12 doris-integrator — Doris 集成

Apache Doris 查询引擎集成，支持 Doris SQL 方言生成与执行。

### 5.13 adhoc-engine — 临时取数引擎

即时查询引擎，处理临时取数请求，含权限控制与结果缓存。

### 5.14 priority-manager — 优先级管理

任务优先级调度与管理，支持紧急需求插队和资源分配。

### 5.15 async-task-scheduler — 异步任务调度

长耗时任务异步执行框架，支持任务状态追踪、超时处理、重试机制。

### Skill 执行流水线

```
用户输入业务需求
       │
       ▼
bi-requirement-parser     -->  结构化需求文档
       │
       ▼ (需求变更时)
requirement-diff-analyzer -->  变更影响报告
       │
       ▼
sql-code-generator   -->  DDL / ETL / SELECT 代码     ★ 专职
       │
       ├-> sql-validator      -->  EXPLAIN 验证
       │       │
       │       ├-> cluster-tester  -->  集群执行 (可选)
       │       │        │
       │       │        ▼
       │       └-> git-merger      -->  合并主分支
       │                │
       │                ▼
       └-> scheduler-updater -->  更新调度任务
```

> **cluster-tester 和 git-merger 是并行下游**, sql-validator 通过后任选其一或都执行。

---

## 六、工具脚本说明

### Python 脚本 (bin/)

| 脚本 | 功能 | 调用方式 |
|------|------|---------|
| `build_dict_rag.py` | RAG 索引构建+检索(**支持 --er-file FK补充**) | `rag build` / `rag --search` |
| `sql_knowledge_base.py` | SQL 知识库(增删查统计导入导出) | `kb search/add/stats/export/import` |
| `generate_data_dictionary.py` | 从数据库元数据生成 data_dictionary.yaml | 直接运行 |
| `generate_data.py` | 生成测试数据，输出到 `output/` 目录 | 直接运行 |

### Python 包 (bin/rag/)

`rag/` 是 RAG 升级版网关，提供模块化组件：

| 模块 | 功能 |
|------|------|
| `rag_gateway.py` | 统一网关，整合构建/检索/统计 |
| `cli.py` | 命令行入口：`python -m rag.cli build/search/stats` |
| `retriever.py` | 检索器（含 FK 图谱扩展） |
| `vector_index.py` | FAISS 索引管理 |
| `index_manager.py` | 索引生命周期管理 |
| `ddl_parser.py` | DDL 解析（提取表结构） |
| `cte_parser.py` | CTE 语句解析 |
| `dependency_graph.py` | 表依赖图谱 |
| `impact_assessor.py` | 影响评估 |
| `deletion_workflow.py` | 表删除工作流 |
| `ref_count_manager.py` | 引用计数管理 |
| `model_registry.py` | Embedding 模型注册 |
| `vector_state_manager.py` | 向量状态管理 |

### Shell 快捷命令 (bin/)

| 命令 | 实际执行 | 用途 |
|------|---------|------|
| `rag <yaml>` | build_dict_rag.py <yaml> | 全量构建 RAG 索引 |
| `rag <yaml> --append` | ... --append | 增量追加新表 |
| `rag <yaml> --er-file <er.txt>` | ... --er-file <er.txt> | **全量+ER外键补充(推荐)** |
| `rag --search "关键词"` | ... --search "关键词" | 语义检索表 |
| `kb search -r "关键词"` | sql_knowledge_base.py search | 查历史 SQL |
| `kb add --type correct/error ...` | sql_knowledge_base.py add | 入库 SQL 经验 |
| `kb stats` | sql_knowledge_base.py stats | 知识库统计 |
| `kb export/import` | sql_knowledge_base.py export/import | 备份恢复 |
| `switch-model.sh` | 编辑 openclaw.json + 重启 daemon | 切换 LLM 模型 |

### run_py.sh — 统一入口

自动激活 `~/.openclaw/workspace/.venv`，查找顺序: `bin/` → `workspace/` → 当前目录。

---

## 七、Python 环境

```bash
# 一次性搭建
python3 -m venv ~/.openclaw/workspace/.venv
cat > ~/.openclaw/workspace/.venv/pip/pip.conf << 'EOF'
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
trusted-host = pypi.tuna.tsinghua.edu.cn
EOF
source ~/.openclaw/workspace/.venv/bin/activate

# 推荐方式：从 dict_rag_requirements.txt 安装
pip install -r dict_rag_requirements.txt

# 或手动安装同等依赖
# pip install faiss-cpu numpy pyyaml sentence-transformers modelscope

deactivate
```

依赖清单（`dict_rag_requirements.txt`）：

| 包 | 用途 |
|----|------|
| `faiss-cpu` | 向量检索 |
| `numpy` | 数值计算 |
| `pyyaml` | YAML 配置解析 |
| `sentence-transformers` | Embedding 模型加载 |
| `modelscope` | 国内模型下载加速 |

首次运行时从魔塔社区下载 BGE Embedding 模型(~1.2GB)，只需一次。

---

## 八、数据字典 RAG

data_dictionary.yaml 含 ~128 张表(126KB), AI 全文读取消耗 ~35K token。
RAG 语义检索只取 Top-K 相关表(~5-8K token), **节省约 77%**。

### 切片策略（Chunking）

**核心：按表级别切片，1张表 = 1个chunk = 1个FAISS向量**

当前128张表 → 索引中128个向量。

**chunk文本构造**（`build_table_search_text()`函数）：

```
表:{表名} | 注释:{表注释} | 主键:{主键列} | 字段:{前30个字段名(注释)} | 关联:{外键关系}
```

| 控制项 | 值 | 说明 |
|--------|-----|------|
| 切片粒度 | 表级别 | 每张表一个chunk，非字段级别 |
| 字段数上限 | **30** | `col_parts[:30]`，避免chunk过长 |
| Token/字符硬限制 | 无 | 依赖自然截断，实际约50-200 token/chunk |
| 检索命中后 | 返回完整表结构 | 完整字段定义存在`tables.json`，切片只影响检索文本 |

**chunk元数据**：

| 字段 | 说明 | 示例 |
|------|------|------|
| `table` | 表名 | `pingan_insurance_agent` |
| `domain` | 业务域 | `代理人域` |
| `comment` | 表注释 | `代理人信息表` |
| `column_count` | 字段总数 | 9 |
| `columns` | 字段名列表 | `["agent_id", "user_id", ...]` |
| `foreign_keys` | 外键关系 | `[]` |
| `score` | 检索相似度 | 0.85 |
| `source` | 匹配来源 | `direct`或`related`（外键扩展） |

### 索引参数

| 参数 | 值 | 说明 |
|------|-----|------|
| 索引类型 | `faiss.IndexFlatIP` | 暴力搜索+内积（向量已归一化，内积=余弦相似度） |
| 向量维度 | 1024 | bge-large-zh-v1.5 |
| Top-K默认 | 5 | CLI `--top-k` 可调 |
| 关联扩展候选 | Top-K × 2 | 开启FK扩展时取2倍候选 |
| 量化/近似 | 无 | 128条向量，暴力搜索极快 |

### 检索增强：外键图谱自动扩展

命中表后通过`fk_graph.json`自动扩展关联表：
- **正向扩展**：命中表的外键引用了哪些表（我引用了谁）
- **反向扩展**：哪些表通过外键引用了命中表（谁引用了我）

例如：命中 `policy_master` → 自动扩展 `premium_payment`、`claim_report` 等。
可通过 `--no-related` 关闭此功能。

### 构建

```bash
# 方式A: 本地构建后上传整个 dict_rag_index/
python build_dict_rag.py `
    bi-requirement-parser/dictionaries/data_dictionary.yaml `
    --er-file bi-requirement-parser/dictionaries/ods_er.txt

# 方式B: 服务器上构建
cd ~/.openclaw/workspace
~/.openclaw/bin/rag.sh ../skills/bi-requirement-parser/dictionaries/data_dictionary.yaml \
  --er-file ../skills/bi-requirement-parser/dictionaries/ods_er.txt

# 方式C: 使用 rag/ 升级版 CLI（推荐）
python -m rag.cli build
python -m rag.cli search --query "代理人业绩"
python -m rag.cli stats
```

### ER 外键补充 (--er-file)

当 data_dictionary.yaml 中没有 foreign_keys 字段时 fk_graph.json 会为空。
使用 `--er-file ods_er.txt` 从手写 ER 关系文档中解析逻辑外键关系(100+条)。

**数据来源优先级**:
1. YAML 中 tables[].foreign_keys (DDL 物理外键, 高优先级)
2. ods_er.txt 解析结果 (逻辑外键 + 业务关联, fallback 补充)

### 索引文件

```
dict_rag_index/
├── index.faiss    -- FAISS 向量索引
├── idmap.pkl      -- 表名 ID 映射
├── tables.json    -- 完整表结构(检索命中后读此文件)
├── domains.json   -- 域信息
└── fk_graph.json  -- 外键图谱(DLL FK + ods_er.txt)
```

### 可用模型

| 模型名 | 维度 | 大小 | 特点 |
|--------|------|------|------|
| BAAI/bge-large-zh-v1.5 | **1024** | ~1.2GB | **当前默认**, 中文最佳 |
| BAAI/bge-base-zh-v1.5 | 768 | ~400MB | 平衡速度精度 |
| BAAI/bge-small-zh-v1.5 | 512 | ~100MB | 最快轻量 |

---

## 九、SQL 知识库

动态积累的 "错题本", **初始为空**。

```
Day 1   -> 空 (0条)
Day 1+  -> 验证通过 -> 自动入库(correct) / 验证失败 -> 入库(error)
Day N   -> 积累N条经验, 查询命中率越来越高
```

位置: `~/.openclaw/knowledge/sql_knowledge_base/index.faiss + idmap.pkl + metadata.json`

备份: `kb export -o backup.json` / `kb import -i backup.json`

### 两个RAG的切片对比

| 对比项 | 数据字典 RAG | SQL 知识库 RAG |
|--------|-------------|----------------|
| 切片粒度 | **表级别**（1表=1 chunk） | **SQL记录级别**（1条SQL=1 chunk） |
| chunk文本 | 表名+注释+字段摘要+外键 | 需求描述+表名+SQL关键字+表引用 |
| 索引类型 | `IndexFlatIP` | `IndexFlatIP` |
| Embedding | bge-large-zh-v1.5 (1024维) | bge-large-zh-v1.5 (1024维) |
| Top-K | 5（+外键图谱扩展） | 5（正确/错误各取3） |
| 元数据存储 | `tables.json` + `metadata.json` | `metadata.json`（单文件） |
| 增量构建 | `--append`支持 | 自动追加 |

---

## 十、模型切换

```bash
# 推荐：使用 switch-model.sh 一键切换
bash bin/switch-model.sh                       # 查看当前模型 + 可用模型列表
bash bin/switch-model.sh deepseek/deepseek-chat  # 切换并重启
bash bin/switch-model.sh qwen/qwen-plus          # 切换到 qwen-plus

# 手动切换（备用）
cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.bak
nano ~/.openclaw/openclaw.json   # 改 default_model
openclaw daemon restart
```

### 可用模型参考（与 switch-model.sh 一致）

| 分类 | 模型 | 说明 |
|------|------|------|
| 当前默认 | `qwen/qwen3.5-plus` | 通义千问 3.5（有免费额度限制） |
| 免费/低价 | `qwen/qwen-plus` | 千问 Plus（稳定） |
| 免费/低价 | `qwen/qwen-turbo` | 千问 Turbo（快+便宜） |
| 付费-高性价比 | `deepseek/deepseek-chat` | DeepSeek V3（中文强，便宜） |
| 付费-高性价比 | `deepseek/deepseek-reasoner` | DeepSeek R1（推理强） |
| 付费-高质量（可选） | `openai/gpt-4o` / `gpt-4o-mini` | 综合最强 / 便宜（项目未实际使用） |

注意: **换 LLM 不影响 RAG 索引**(两者独立)。

---

## 十一、测试数据与本地验证

> **重要**: 测试数据（`data_src/`、`supplement_data/`、`verify_sql/`）**不是项目产出物**，仅用于本地 MySQL 验证大模型生成的 DWD/DWS SQL 是否正确，**不参与部署**。

### 目的

个人项目没有生产数据，需要造数据来验证大模型生成的 SQL 是否正确。通过本地 MySQL 加载测试数据，执行生成的 DWD/DWS SQL，验证结果是否符合预期。

### 测试数据文件清单

实际文件位于 `data_src/`、`supplement_data/`、`verify_sql/` 三个目录：

| 文件 | 说明 |
|------|------|
| `data_src/create_table.sql` | 全量建表 SQL（ODS/DWD/DWS/ADS） |
| `data_src/pingan_insurance_data.sql` | 平安保险 ODS 层基础数据 |
| `supplement_data/01_user_domain_extend.sql` | 用户域补充数据 |
| `supplement_data/02_agent_domain.sql` | 代理人域补充数据 |
| `supplement_data/03_policy_domain_extend.sql` | 保单域补充数据 |
| `supplement_data/04_claim_domain.sql` | 理赔域补充数据 |
| `supplement_data/05_operation_domain.sql` | 运营域补充数据 |
| `supplement_data/06_car_service_domain.sql` | 车服务域补充数据 |
| `supplement_data/07_mall_domain.sql` | 商城域补充数据 |
| `supplement_data/08_enterprise_domain.sql` | 企业域补充数据 |
| `supplement_data/09_gov_domain.sql` | 政务域补充数据 |
| `supplement_data/10_regulatory_domain.sql` | 监管域补充数据 |
| `verify_sql/01_c_req_verify.sql` | C 端需求验证 SQL |
| `verify_sql/02_b_req_verify.sql` | B 端需求验证 SQL |
| `verify_sql/03_g_req_verify.sql` | G 端需求验证 SQL |

### 本地验证步骤

```bash
# 方式一：手动 mysql 命令验证（密码会通过 MYSQL_PWD 隐藏）
export MYSQL_PWD="your_password"
mysql -u root test_db < data_src/create_table.sql
mysql -u root test_db < data_src/pingan_insurance_data.sql
mysql -u root test_db < supplement_data/01_user_domain_extend.sql
# ... 加载所有补充数据
mysql -u root test_db < verify_sql/01_c_req_verify.sql

# 方式二：使用本地验证脚本（自动从 deploy.env 读取配置）
bash deploy/local_verify.sh
```

### 覆盖的 BI 需求列表

测试数据覆盖以下 20 个 BI 需求，按端分类：

**C端（8个）**：
| # | 需求 | 覆盖关键表 |
|---|------|-----------|
| 1 | 我的保单概览 | ods_policy_info, ods_customer_info |
| 2 | 理赔进度查询 | ods_claim_info, ods_policy_info |
| 3 | 缴费记录查询 | ods_payment_info, ods_policy_info |
| 4 | 保障利益明细 | ods_benefit_info, ods_policy_info |
| 5 | 产品推荐 | ods_product_info, ods_customer_info |
| 6 | 代理人服务 | ods_agent_info, ods_policy_info |
| 7 | 理赔金额统计 | ods_claim_info, ods_payment_info |
| 8 | 保费趋势 | ods_payment_info, ods_policy_info |

**B端（7个）**：
| # | 需求 | 覆盖关键表 |
|---|------|-----------|
| 9 | 渠道销售统计 | ods_channel_info, ods_policy_info |
| 10 | 代理人业绩排名 | ods_agent_info, ods_policy_info |
| 11 | 产品销量分析 | ods_product_info, ods_policy_info |
| 12 | 理赔率分析 | ods_claim_info, ods_policy_info |
| 13 | 区域保费分布 | ods_area_info, ods_policy_info |
| 14 | 客户画像统计 | ods_customer_info, ods_policy_info |
| 15 | 风险预警监控 | ods_risk_info, ods_claim_info |

**G端（5个）**：
| # | 需求 | 覆盖关键表 |
|---|------|-----------|
| 16 | 行业保费总览 | ods_policy_info, ods_payment_info |
| 17 | 监管指标分析 | ods_claim_info, ods_risk_info |
| 18 | 区域发展对比 | ods_area_info, ods_policy_info |
| 19 | 偿付能力监控 | ods_payment_info, ods_claim_info |
| 20 | 市场份额分析 | ods_channel_info, ods_policy_info |

---

## 十二、一键部署脚本

deploy/ 目录下提供 5 个部署辅助文件，简化部署流程。

### 文件说明

| 文件 | 功能 | 使用场景 |
|------|------|---------|
| `deploy.env` | 部署环境变量配置 | 部署前必须编辑，填入服务器信息 |
| `deploy.sh` | 一键完整部署 | 首次部署或全量更新 |
| `upload_only.sh` | 仅上传文件到服务器 | 已完成配置，只需同步代码 |
| `init_mysql.sh` | 远程 MySQL 初始化 | 在服务器上执行 DDL/DML/验证 SQL |
| `local_verify.sh` | 本地验证脚本 | 部署前本地验证测试数据 |

### deploy.env 配置项

```bash
# === 服务器连接 ===
REMOTE_HOST="192.168.1.100"
REMOTE_USER="openclaw"
REMOTE_PORT=22

# === 远程路径 ===
REMOTE_BASE_DIR="/home/openclaw/.openclaw"
SKILLS_DIR="${REMOTE_BASE_DIR}/skills"     # 注意：复数
BIN_DIR="${REMOTE_BASE_DIR}/bin"
WORKSPACE_DIR="${REMOTE_BASE_DIR}/workspace"
DDL_DIR="${WORKSPACE_DIR}/ddl"             # DWD/DWS/ADS层DDL（ODS由flink-cdc自动创建）
DWD_DIR="${WORKSPACE_DIR}/dwd"
DWS_DIR="${WORKSPACE_DIR}/dws"

# === MySQL 连接（init_mysql.sh 用） ===
MYSQL_HOST="127.0.0.1"
MYSQL_PORT=3306
MYSQL_USER="root"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"       # 通过环境变量注入
MYSQL_DATABASE="pingan_insurance"

# === RAG 向量索引 ===
RAG_INDEX_DIR="${SKILLS_DIR}/rag/indices"
RAG_MAX_CACHED_MODELS=1

# === Python 环境 ===
PYTHON_BIN="python3"
PIP_BIN="pip3"
```

### 使用方法

```bash
# 1. 编辑环境变量
nano deploy/deploy.env

# 2. 设置敏感环境变量（不写入文件）
export MYSQL_PASSWORD="你的MySQL密码"

# 3. 一键完整部署（首次部署推荐）
bash deploy/deploy.sh

# 4. 仅上传代码（配置已在服务器上编辑好）
bash deploy/upload_only.sh

# 5. 本地验证测试数据
bash deploy/local_verify.sh

# 6. 远程 MySQL 初始化（在服务器上执行）
ssh openclaw@服务器IP
bash ~/.openclaw/bin/init_mysql.sh all
```

---

## 十三、部署检查清单

### Skill 与代码
- [ ] `~/.openclaw/skills/` 有 **15 个** Skill 目录, 每个都有 SKILL.md
- [ ] `~/.openclaw/bin/` 有 .py 和 .sh 且完整（含 `switch-model.sh`）
- [ ] `~/.openclaw/bin/rag/` Python 包已上传
- [ ] Shell 有执行权限(`chmod +x`)

### 配置
- [ ] `~/.openclaw/config.yaml` 已编辑(namenode/repo 已填)
- [ ] `~/.openclaw/kb_config.yaml` 已部署
- [ ] config.yaml 权限 600(保护配置)
- [ ] `$GITEE_TOKEN` 环境变量已设置（不写入文件）
- [ ] `$MYSQL_PASSWORD` 环境变量已设置（不写入文件）

### Python 环境
- [ ] Python venv 已创建
- [ ] 依赖已安装：`pip install -r dict_rag_requirements.txt`
- [ ] `kb.sh stats` 能正常运行

### 数据
- [ ] `dict_rag_index/` 已部署到 workspace(或准备服务器构建)
- [ ] `~/.openclaw/workspace/ddl/` 目录存在，含DWD/DWS/ADS建表SQL（ODS由flink-cdc自动创建）
- [ ] `~/.openclaw/workspace/dwd/` 目录存在
- [ ] `~/.openclaw/workspace/dws/` 目录存在

### Gitee
- [ ] Gitee Token 有效（通过 `$GITEE_TOKEN` 注入）

---

## 变更日志

| 版本 | 日期 | 变更内容 |
|------|------|----------|
| **6.2.0** | 2026-05-10 | **README 全面校对**：修正本地路径(`d:\data_lake\`→`d:\Python\chat_bi\`)、去除 `.codebuddy/skills/` 前缀、修正 `skill/`→`skills/`(复数)、更新 `deploy.env` 变量名(`SERVER_*`→`REMOTE_*`)、更新服务器 IP(192.168.128.200→192.168.1.100)、补全测试数据文件清单（按业务域编号）、新增项目简介与技术栈章节。**Bug 修复**：`build_dict_rag.py` 中 `faiss.__version__` 改为 `getattr` 安全访问；`--append` 模式补全 `idmap.pkl` 存在性检查；`sql_knowledge_base.py` `DEFAULT_KB_DIR` 修正一层 `dirname`；`generate_data.py` 硬编码路径改为相对路径。**隐私安全**：`config_loader.py` Token 掩码逻辑改为 `${GITEE_TOKEN}` 精确匹配；`deploy.env` `MYSQL_PASSWORD` 改为环境变量占位符；`init_mysql.sh`/`local_verify.sh` 密码改为 `MYSQL_PWD` 环境变量（不暴露在命令行）；`dolphinscheduler_adapter.py` 移除 `changeme` 默认密码。 |
| **6.1.0** | 2026-04-27 | 新增RAG切片策略详解; 两个RAG对比; 修正workspace/ddl为DWD/DWS/ADS层DDL(ODS由flink-cdc创建) |
| **6.0.0** | 2026-04-27 | 新增7个Skill; workspace分层(ddl/dwd/dws); 部署脚本; 测试数据说明; Skill总数8→15 |
| 5.0.0 | 2026-04-23 | 大重构: 对齐项目清理; 新增 **sql-code-generator** Skill; 删除 split_data_doc.py 引用; 新增 --er-file FK 补充; spark-sql-standards.md 归入 sql-code-generator/dictionaries/; adhoc-query-system.md 归入 bi-requirement-parser/dictionaries/; 更新所有路径; Skill 总数 7→8 |
| 4.0.0 | 之前 | 初始版本 |

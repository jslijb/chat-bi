---
name: git-merger
description: 人类验证通过后，自动将 Git 特性分支合并到开发分支，支持 PR 创建、代码审查检查、自动合并
version: 1.0.0
author: BI Team
trigger_keywords:
  - 合并分支
  - 合并代码
  - 提交 PR
  - 代码合并
  - 合并到开发分支
  - 合并到主分支
  - merge
  - 验证通过
upstream_skill: cluster-tester
downstream_skill: scheduler-updater
---

# 技能名称：git-merger

## 技能描述
Git 合并助手。在 SQL 验证通过后，创建 Pull Request 等待人类验证。当用户确认"验证通过"后，自动将特性分支合并到主分支（配置项 `git.default_branch`），并触发下游调度更新。

## 触发条件

**场景 1 - 等待人工确认（首次触发）**：
- 由 `sql-validator` 输出验证通过后自动触发
- 输出"等待人工确认"状态

**场景 2 - 执行合并（人工确认后）**：
- 用户明确说"验证通过"、"可以合并"、"合并代码"、"确认合并"等
- 用户提及 PR/MR 编号并确认合并

> **前置条件**：必须通过 `sql-validator` 验证，且代码审查无阻塞问题

## 输入格式
- SQL 验证报告（由 sql-validator 输出）
- Git 分支信息（由 code-updater 创建）
- 目标分支（从配置 `git.default_branch` 读取，如 `master` 或 `main`）

## 输出格式

### 场景 1：等待人工确认

```markdown
# 合并等待确认：{需求编号}

**当前状态**：⏳ 等待人工验证
**特性分支**：`upgrade/{需求编号}`
**目标分支**：`develop`
**SQL 验证**：✅ 已通过

---

## 变更摘要

| 类型 | 数量 | 说明 |
|------|------|------|
| DDL 文件 | N | 新增/修改表结构 |
| ETL 文件 | N | SQL/Python 脚本 |
| 测试文件 | N | 验证脚本 |

---

## 待确认事项

请在确认前检查：

- [ ] DDL 语句在测试环境已验证
- [ ] ETL 逻辑符合需求文档
- [ ] 代码审查无重大问题
- [ ] 回滚方案已准备

---

## 确认指令

当验证完成后，请对我说以下任意指令触发自动合并：

```
验证通过，合并代码
确认合并到开发分支
PR 已通过，执行合并
可以合并
```

---

## PR 链接

[查看 Pull Request #{PR编号}]({PR链接})
```

### 场景 2：执行合并后

```markdown
# 合并完成报告：{需求编号}

**合并状态**：✅ 合并成功
**合并时间**：{YYYY-MM-DD HH:mm}
**特性分支**：`upgrade/{需求编号}`
**目标分支**：`develop`
**合并提交**：`{commit_hash}`

---

## 合并详情

| 项目 | 内容 |
|------|------|
| PR 编号 | #{PR编号} |
| 合并方式 | Squash Merge / Merge Commit |
| 冲突解决 | 无冲突 / 已解决 |
| 删除源分支 | 已删除 / 保留 |

---

## 合并后的提交信息

```
Merge pull request #{PR编号} from upgrade/{需求编号}

chore: upgrade requirement {需求编号} to v{版本}

- 新增字段 xxx
- 修改口径 xxx
- SQL 验证通过
```

---

## 后续步骤

1. ✅ 代码已合并到 `{git.default_branch}`
2. ⏳ 触发 `cluster-tester` **正式执行模式**（生产部署：DDL 建表 + ETL 全量跑数 + 数据验证）
3. ⏳ 正式执行通过后，触发 `scheduler-updater` 更新调度任务
4. ⏳ 观察 3 天，监控调度运行情况

> **重要**: 合并代码后**不要直接配置调度**！必须先通过 cluster-tester 正式执行确认数据正确。

---

## 回滚指令

如需回滚本次合并，执行：

```bash
git checkout develop
git revert {commit_hash}
git push origin develop
```
```

## 执行流程

### 场景 1：创建 PR 并等待确认

**第一步：创建 Pull Request**
```bash
# 使用 Git CLI 或 GitHub/GitLab API 创建 PR
git checkout upgrade/{需求编号}

# GitHub
gh pr create \
    --title "chore: upgrade requirement {需求编号} to v{版本}" \
    --body "$(cat .codebuddy/skills/code-updater/change-report-{需求编号}.md)" \
    --base {git.default_branch} \
    --head upgrade/{需求编号}

# GitLab / Gitee
glab mr create \
    --title "chore: upgrade requirement {需求编号}" \
    --description "变更内容详见报告" \
    --target-branch {git.default_branch} \
    --source-branch upgrade/{需求编号}
```

**第二步：输出等待确认报告**
- 显示变更摘要
- 提供确认指令说明
- 提供 PR 链接

**第三步：等待用户确认**
- Skill 进入等待状态
- 监听用户确认指令

### 场景 2：执行合并

**第一步：检查合并条件**
- ✅ SQL 验证已通过
- ✅ 用户明确确认
- ⚠️ 可选：检查代码审查状态（若配置了 CI/CD）

**第二步：执行合并**
```bash
# 获取最新目标分支
git checkout {git.default_branch}
git pull origin {git.default_branch}

# 合并特性分支
git merge --no-ff upgrade/{需求编号} -m "Merge pull request: upgrade/{需求编号}"

# 或使用 squash 合并
git merge --squash upgrade/{需求编号}
git commit -m "chore: upgrade requirement {需求编号}"

# 推送到远程
git push origin {git.default_branch}
```

**第三步：清理**
```bash
# 删除远程特性分支（可选）
git push origin --delete upgrade/{需求编号}

# 删除本地特性分支
git branch -d upgrade/{需求编号}

# 关闭 PR/MR
gh pr close {PR编号} --comment "已合并到 develop"
```

**第四步：触发下游**
- 输出合并完成报告
- 自动触发 `scheduler-updater` 更新调度

## 与上下游 Skill 的衔接

| 角色 | Skill名称 | 触发条件 | 传递内容 |
|------|-----------|----------|----------|
| 上游 | `sql-validator` | SQL 验证通过后 | 验证报告 + 分支信息 |
| 下游 | `scheduler-updater` | 代码合并后 | 合并报告 |

**完整需求生命周期状态机**：
```
bi-requirement-parser (需求解析)
        ↓
requirement-diff-analyzer (变更分析)
        ↓
code-updater (代码生成 + 提交分支)
        ↓
sql-validator (SQL EXPLAIN 验证)
        ↓
git-merger (等待确认 → 合并)
        ↓
scheduler-updater (调度更新)
        ↓
需求上线
```

## 异常处理

- 若合并冲突，输出冲突文件列表，返回 `code-updater` 解决
- 若目标分支保护规则阻止合并，提示联系管理员
- 若用户长时间未确认（超过 7 天），发送提醒
- 若用户说"不合并"、"有问题"，中止流程并记录原因

## 注意事项

- 合并前必须完成 SQL 验证
- 建议配置分支保护规则，要求至少 1 人 code review
- 合并后保留特性分支 7 天，便于回滚
- 生产环境部署需额外审批流程（本 Skill 只合并到开发分支）
- 合并失败时保留完整日志，便于排查

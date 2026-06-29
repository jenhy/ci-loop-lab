# CI Loop Lab — 项目工作原理

## 概述

`ci-loop-lab` 是一个 **Loop Engineering 教学项目**，演示如何构建自动检测 CI 失败并修复的闭环系统。每天自动注入一个回归 bug，一小时后自动检测、定位、修复、通知。

## 核心思想

> **模型会遗忘，但仓库不会。** — Addy Osmani《Loop Engineering》

所有状态存储在磁盘上（git history、STATE.md、GitHub Issues），循环每次从干净的上下文开始，不依赖上一次对话的记忆。

## 项目结构

```
ci-loop-lab/
├── .github/workflows/
│   ├── ci.yml                       # 日常 CI（每次 push 跑测试）
│   ├── ci-fix-loop.yml              # 🔁 修复循环（每天 08:00）
│   └── regression-injector.yml      # 💉 回归注入（每天 07:00）
│
├── scripts/
│   ├── ci-fix-loop.sh               # 修复循环主脚本（六步闭环）
│   ├── inject-regression.sh         # 手动注入回归工具
│   ├── run-and-collect-failures.sh  # 检测阶段（已废弃，逻辑并入 ci-fix-loop.sh）
│   ├── auto-fix.sh                  # 诊断+修复（已废弃，逻辑并入 ci-fix-loop.sh）
│   └── notify.sh                    # 通知阶段（已废弃，逻辑并入 ci-fix-loop.sh）
│
├── src/
│   ├── math.ts                      # 目标代码（回归注入点）
│   └── __tests__/math.test.ts       # 单元测试
│
├── docs/
│   └── lessons-learned.md           # 踩坑记录
│
├── STATE.md                         # 运行状态记录
├── package.json                     # Node.js + Vitest 配置
└── tsconfig.json / vitest.config.ts
```

## 三个工作流

### 1. CI (`ci.yml`)

| 属性 | 值 |
|------|-----|
| 触发 | 每次 push / PR 到 main |
| 作用 | 跑测试，上传失败日志 |
| 输出 | ✅ 通过 或 ❌ 失败 |

**设计意图**：模拟真实的日常 CI 管线。回归注入后自动失败，修复后自动通过。

### 2. Regression Injector (`regression-injector.yml`)

| 属性 | 值 |
|------|-----|
| 触发 | 每天 07:00 UTC（cron）|
| 作用 | 注入回归 bug 并推送 |

**流程**：
```
1. checkout 代码
2. npm ci
3. 安全阀：确认当前测试通过（防止在已损坏的代码上注入）
4. sed 修改 src/math.ts：add(a,b) → add(a,b)+1
5. git commit -m "chore: [regression-sim] intentional bug injection YYYY-MM-DD"
6. git push
```

**关键设计**：commit message 带 `[regression-sim]` 标记，CI Fix Loop 通过此标记定位回归提交。

### 3. CI Fix Loop (`ci-fix-loop.yml`)

| 属性 | 值 |
|------|-----|
| 触发 | 每天 08:00 UTC（cron）+ 手动 |
| 核心 | `bash scripts/ci-fix-loop.sh`（一个脚本完成全部逻辑）|

**六步闭环**：

```
┌─────────────────────────────────────────────────┐
│                                                 │
│  STEP 1:  DETECT   ─ npx vitest run            │
│            ↓ 失败                                │
│  STEP 2:  DIAGNOSE ─ git log --grep regress     │
│            ↓ 找到 bad commit                     │
│  STEP 3:  FIX      ─ git revert                 │
│            ↓ revert 成功                         │
│  STEP 4:  PUSH     ─ git push origin main       │
│            ↓                                    │
│  STEP 5:  NOTIFY   ─ gh issue create            │
│            ↓                                    │
│  STEP 6:  STATE    ─ 更新 STATE.md              │
│                                                 │
│  → 退出 0（如果测试全绿，STEP 1 就退出）          │
└─────────────────────────────────────────────────┘
```

**如果测试全部通过**：STEP 1 检测到 `EXIT_CODE=0`，直接 exit 0，什么也不做。

## 每日自动化时间线

```
UTC 时间        北京时间      事件
────────────────────────────────────────────────────
07:00           15:00        Regression Injector 注入回归
                              → push [regression-sim] commit
                              → 触发 ci.yml（❌ 失败，预期行为）

08:00           16:00        CI Fix Loop 触发
                              → DETECT 检测到测试失败
                              → DIAGNOSE 定位回归提交
                              → FIX git revert
                              → PUSH 推送到 main
                              → NOTIFY 创建 Issue
                              → STATE 更新 STATE.md
                              → 触发 ci.yml（✅ 通过）

08:01+          16:01+       代码恢复到干净状态
                              Issue 记录可供人工复核
                              等待明天 07:00 的下一轮
```

## 回归模拟机制

```
正常代码:
  commit A: add(a,b) → return a + b      ✅ add(1,2) = 3

注入回归:
  commit B: add(a,b) → return a + b + 1  ❌ add(1,2) = 4
  message: "chore: [regression-sim] ..."

自动修复:
  git revert B                           ✅ add(1,2) = 3
  恢复为 commit A 的状态
```

**为什么用 commit 标记而不是日期判断？** `git bisect` 依赖 git 历史定位回归提交。运行时条件（如 `if date is odd`）不在 git 历史中，bisect 无法检测。

## 核心设计决策

| 决策 | 选择 | 原因 |
|------|------|------|
| 所有逻辑一个脚本 | `ci-fix-loop.sh` | 消除跨步骤 GITHUB_OUTPUT 通信，避免环境差异 |
| 用退出码不用 JSON | `$?` 而非 `test-results.json` | 退出码跨版本稳定，JSON schema 可能变化 |
| revert 而非 AI 修复 | `git revert` | 确定性操作，零成本，适合教学 |
| Issue 而非 PR | `gh issue create` | Issue 是记录工具，PR 是审查工具 |
| 单 repo 架构 | 全部在 ci-loop-lab | 学习阶段不需要分布式架构 |

## 关键技术细节

### 如何定位回归提交

```bash
# 搜索 commit message 包含 [regression-sim] 的提交
BAD_COMMIT=$(git log --oneline --grep="regression-sim" --format="%H" -1)
```

而非使用 `git bisect`（因为只有两次提交，bisect 是杀鸡用牛刀）。

### 安全检查

```bash
COMMIT_MSG=$(git log --format=%s "$BAD_COMMIT" -1)
if [[ "$COMMIT_MSG" != *"regression-sim"* ]]; then
  # 如果不是我们的标记提交，拒绝自动 revert
  exit 0
fi
```

防止意外 revert 重要的代码变更。

### 测试判断

```bash
set +e
npx vitest run
EXIT_CODE=$?
set -e

if [ "$EXIT_CODE" -eq 0 ]; then
  # 全部通过，无事发生
  exit 0
fi
```

简单的退出码判断，比解析 JSON 可靠得多。

## 成功标准

每天观察以下指标确认循环正常运行：

1. **GitHub Actions** — Regression Injector 和 CI Fix Loop 都显示 ✅
2. **git log** — 每天看到一条 `[regression-sim]` commit + 一条 revert commit
3. **GitHub Issues** — 每天一个 auto-fix 报告 Issue
4. **STATE.md** — 运行记录持续更新

## 扩展方向

- **Phase 2**: 引入 Claude Code skill 体系（`ci-triage/SKILL.md`），让 AI 分析失败原因
- **Phase 3**: 引入子代理分工（`ci-fixer` + `code-reviewer`），AI 驱动的修复与审查
- **高级**: 处理多种失败类型（lint 错误、类型错误、快照不匹配等）
- **生产化**: 添加 Slack/企业微信通知、成本监控、人工审批闸门

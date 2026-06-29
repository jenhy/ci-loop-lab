#!/bin/bash
# 通知阶段：创建 GitHub Issue 记录修复详情
#
# 输入环境变量:
#   BAD_COMMIT — 被 revert 的回归提交 hash
#
# 依赖: gh CLI（GitHub Actions 中预装）

set -euo pipefail

# 如果 BAD_COMMIT 未设置，尝试从 git 历史获取
BAD_COMMIT="${BAD_COMMIT:-$(git log --oneline --grep="regression-sim" --format="%H" -1)}"
FIX_DATE=$(date +%Y-%m-%d)

echo "📝 [NOTIFY] 创建 GitHub Issue..."

# 获取坏提交信息
BAD_MSG=$(git log --format="%s" "$BAD_COMMIT" -1 2>/dev/null || echo "unknown")
BAD_AUTHOR=$(git log --format="%an" "$BAD_COMMIT" -1 2>/dev/null || echo "unknown")
BAD_DATE=$(git log --format="%ai" "$BAD_COMMIT" -1 2>/dev/null || echo "unknown")

# 生成 Issue 内容
ISSUE_TITLE="[auto-fix] CI 回归修复报告 — ${FIX_DATE}"
ISSUE_BODY=$(cat << EOF
## 🔁 CI 自动修复报告

**日期**: ${FIX_DATE}
**状态**: ✅ 已自动修复

### 检测到的回归

| 项目 | 内容 |
|------|------|
| 责任提交 | \`${BAD_COMMIT}\` |
| 提交信息 | ${BAD_MSG} |
| 作者 | ${BAD_AUTHOR} |
| 提交日期 | ${BAD_DATE} |
| 修复方式 | 自动 revert |

### 时间线

1. **08:00** — cron 触发修复循环
2. **08:01** — 测试检测到失败 (\`npx vitest run\`)
3. **08:02** — git bisect 定位回归提交
4. **08:03** — 自动 revert 完成
5. **08:04** — 修复已推送到 main 分支

### 建议

如果这是一个手动引入的 bug，请检查 revert 是否丢失了预期功能变更。
EOF
)

# 创建 Issue（捕获输出以获取 Issue 编号）
ISSUE_URL=$(gh issue create \
  --title "$ISSUE_TITLE" \
  --body "$ISSUE_BODY" \
  --label "auto-fix,regression" 2>&1)

echo "✅ [NOTIFY] Issue 已创建: $ISSUE_URL"

# 保存 Issue 编号用于 STATE.md
ISSUE_NUMBER=$(echo "$ISSUE_URL" | grep -oP '\d+$' || echo "?")
echo "issue_number=$ISSUE_NUMBER" >> "$GITHUB_OUTPUT"
echo "issue_url=$ISSUE_URL" >> "$GITHUB_OUTPUT"

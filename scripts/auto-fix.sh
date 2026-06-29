#!/bin/bash
# 诊断 + 修复阶段：git bisect 定位回归提交，然后自动 revert
#
# 输出（通过 GITHUB_OUTPUT）:
#   fix_applied=true|false
#   bad_commit=<commit-hash>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

echo "🔍 [DIAGNOSE] git bisect 定位回归提交..."

# 找最近一个 [regression-sim] 提交作为 bad 的候选
CURRENT_MSG=$(git log --format=%s -1)
if [[ "$CURRENT_MSG" == *"regression-sim"* ]]; then
  LAST_GOOD=$(git rev-parse HEAD~1)
  echo "  当前是回归提交，父提交作为 good: $(git log --oneline $LAST_GOOD -1)"
else
  LAST_SIM=$(git log --oneline --grep="regression-sim" --format="%H" -1)
  if [ -n "$LAST_SIM" ]; then
    LAST_GOOD=$(git rev-parse "$LAST_SIM~1")
    echo "  回归标记提交: $(git log --oneline $LAST_SIM -1)"
    echo "  其父提交作为 good: $(git log --oneline $LAST_GOOD -1)"
  else
    LAST_GOOD=$(git rev-parse HEAD~1)
    echo "  未找到回归标记，使用 HEAD~1: $(git log --oneline $LAST_GOOD -1)"
  fi
fi

echo ""
echo "  bad:  HEAD  ($(git log --oneline HEAD -1))"
echo "  good: $LAST_GOOD ($(git log --oneline $LAST_GOOD -1))"

# 创建 bisect 判断脚本
# git bisect 在每次 checkout 后运行此脚本，当前目录 = 查出的 commit
cat > /tmp/bisect-test.sh << 'BISECT_SCRIPT'
#!/bin/bash
set -euo pipefail

# npm ci 失败则回退到 npm install（处理 node_modules 缺失的情况）
# 注意：不能用 --silent，npm 8+ 已移除此参数
npm ci 2>/dev/null || npm install 2>/dev/null

# vitest 退出码：0=good, 非0=bad
npx vitest run --reporter=verbose 2>&1
BISECT_SCRIPT
chmod +x /tmp/bisect-test.sh

echo ""
echo "  开始 bisect..."
git bisect start HEAD "$LAST_GOOD"
git bisect run bash /tmp/bisect-test.sh 2>&1 || true

# 重置 bisect 状态
git bisect reset 2>/dev/null || true

# 提取回归标记提交
BAD_COMMIT=$(git log --oneline --grep="regression-sim" --format="%H" -1 || echo "")

if [ -z "$BAD_COMMIT" ]; then
  echo "⚠️ [DIAGNOSE] 未找到回归提交，跳过修复"
  echo "fix_applied=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

echo ""
echo "✅ [DIAGNOSE] 定位到回归提交: $BAD_COMMIT"
echo "  $(git log --oneline $BAD_COMMIT -1 2>/dev/null || echo 'unknown')"

COMMIT_MSG=$(git log --format=%s "$BAD_COMMIT" -1 2>/dev/null || echo "")

# 安全检查：只 revert 标记为 regression-sim 的提交
if [[ "$COMMIT_MSG" != *"regression-sim"* ]]; then
  echo "⚠️ [DIAGNOSE] 回归提交不是模拟标记，手动检查后再处理"
  echo "fix_applied=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

echo ""
echo "🔧 [FIX] 开始 revert 回归提交: $BAD_COMMIT"

if git revert --no-edit "$BAD_COMMIT" 2>&1; then
  echo "✅ [FIX] revert 成功"
  echo "fix_applied=true" >> "$GITHUB_OUTPUT"
  echo "bad_commit=$BAD_COMMIT" >> "$GITHUB_OUTPUT"
else
  echo "⚠️ [FIX] revert 冲突，尝试 strategy=resolve..."
  git revert --abort 2>/dev/null || true
  if git revert --no-edit --strategy=resolve "$BAD_COMMIT" 2>&1; then
    echo "✅ [FIX] resolve 策略 revert 成功"
    echo "fix_applied=true" >> "$GITHUB_OUTPUT"
    echo "bad_commit=$BAD_COMMIT" >> "$GITHUB_OUTPUT"
  else
    echo "❌ [FIX] revert 失败，需要人工处理"
    git revert --abort 2>/dev/null || true
    echo "fix_applied=false" >> "$GITHUB_OUTPUT"
  fi
fi

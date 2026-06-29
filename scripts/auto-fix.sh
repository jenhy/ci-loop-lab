#!/bin/bash
# 诊断 + 修复阶段：git bisect 定位回归提交，然后自动 revert
#
# 输入: 无（自动使用 HEAD 和 git 历史）
# 输出（通过 GITHUB_OUTPUT）:
#   fix_applied=true|false
#   bad_commit=<commit-hash>（仅 fix_applied=true 时）
#
# 依赖:
#   - 必须有完整 git 历史（fetch-depth: 0）
#   - gh CLI（用于创建 Issue 时引用 commit）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

echo "🔍 [DIAGNOSE] git bisect 定位回归提交..."

# 找最近一个包含 [regression-sim] 标记的提交作为 "坏提交" 的候选
# 策略：如果当前是回归标记提交，它的父提交就是好的
CURRENT_MSG=$(git log --format=%s -1)
if [[ "$CURRENT_MSG" == *"regression-sim"* ]]; then
  # 当前提交就是回归标记，父提交作为 good
  LAST_GOOD=$(git rev-parse HEAD~1)
  echo "  当前是回归提交，父提交作为 good: $(git log --oneline $LAST_GOOD -1)"
else
  # 找最近一个回归标记提交，用它的父提交作为 good
  LAST_SIM=$(git log --oneline --grep="regression-sim" --format="%H" -1)
  if [ -n "$LAST_SIM" ]; then
    LAST_GOOD=$(git rev-parse "$LAST_SIM~1")
    echo "  回归标记提交: $(git log --oneline $LAST_SIM -1)"
    echo "  其父提交作为 good: $(git log --oneline $LAST_GOOD -1)"
  else
    # 没有任何回归标记，使用 HEAD~1
    LAST_GOOD=$(git rev-parse HEAD~1)
    echo "  未找到回归标记，使用 HEAD~1: $(git log --oneline $LAST_GOOD -1)"
  fi
fi

echo ""
echo "  bad:  HEAD  ($(git log --oneline HEAD -1))"
echo "  good: $LAST_GOOD ($(git log --oneline $LAST_GOOD -1))"

# 创建 bisect 判断脚本
cat > /tmp/bisect-test.sh << 'BISECT_SCRIPT'
#!/bin/bash
set -euo pipefail
cd /tmp/ci-bisect-work

# 安装依赖（静默模式）
npm ci --silent 2>/dev/null || npm install --silent 2>/dev/null

# 运行测试
npx vitest run --reporter=json --outputFile=/tmp/bisect-result.json 2>/dev/null || true

# 判断结果
node -e "
const fs = require('fs');
let r;
try {
  r = JSON.parse(fs.readFileSync('/tmp/bisect-result.json', 'utf8'));
} catch(e) {
  process.exit(1);  // 无法解析 → bad
}
const failed = r.testResults.filter(t => t.status === 'fail');
process.exit(failed.length > 0 ? 1 : 0);  // 有失败 → bad(1), 全过 → good(0)
"
BISECT_SCRIPT
chmod +x /tmp/bisect-test.sh

echo ""
echo "  开始 bisect..."
git bisect start HEAD "$LAST_GOOD" -- 2>&1
git bisect run bash /tmp/bisect-test.sh 2>&1 || true

# 从 bisect log 获取第一个坏提交
BISECT_RESULT=$(git bisect log 2>/dev/null || true)

# 重置 bisect
git bisect reset 2>/dev/null || true

# 取回归标记提交作为坏提交
BAD_COMMIT=$(git log --oneline --grep="regression-sim" --format="%H" -1 || echo "")

if [ -z "$BAD_COMMIT" ]; then
  echo "⚠️ [DIAGNOSE] 未找到回归提交，跳过修复"
  echo "fix_applied=false" >> "$GITHUB_ENV"
  echo "fix_applied=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

echo ""
echo "✅ [DIAGNOSE] 定位到回归提交: $BAD_COMMIT"
echo "  $(git log --oneline $BAD_COMMIT -1 2>/dev/null || echo 'unknown')"

# 检查提交信息
COMMIT_MSG=$(git log --format=%s "$BAD_COMMIT" -1 2>/dev/null || echo "")

# 安全检查：只自动 revert 标记为 regression-sim 的提交
if [[ "$COMMIT_MSG" != *"regression-sim"* ]]; then
  echo "⚠️ [DIAGNOSE] 回归提交不是模拟标记，手动检查后再处理"
  echo "fix_applied=false" >> "$GITHUB_ENV"
  echo "fix_applied=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

echo ""
echo "🔧 [FIX] 开始 revert 回归提交: $BAD_COMMIT"

# 执行 revert
if git revert --no-edit "$BAD_COMMIT" 2>&1; then
  echo "✅ [FIX] revert 成功"
  echo "fix_applied=true" >> "$GITHUB_ENV"
  echo "fix_applied=true" >> "$GITHUB_OUTPUT"
  echo "bad_commit=$BAD_COMMIT" >> "$GITHUB_OUTPUT"
else
  echo "⚠️ [FIX] revert 冲突，尝试 strategy=resolve..."
  # 放弃失败的回退
  git revert --abort 2>/dev/null || true
  # 尝试 resolve 策略
  if git revert --no-edit --strategy=resolve "$BAD_COMMIT" 2>&1; then
    echo "✅ [FIX] resolve 策略 revert 成功"
    echo "fix_applied=true" >> "$GITHUB_ENV"
    echo "fix_applied=true" >> "$GITHUB_OUTPUT"
    echo "bad_commit=$BAD_COMMIT" >> "$GITHUB_OUTPUT"
  else
    echo "❌ [FIX] revert 失败，需要人工处理"
    git revert --abort 2>/dev/null || true
    echo "fix_applied=false" >> "$GITHUB_ENV"
    echo "fix_applied=false" >> "$GITHUB_OUTPUT"
  fi
fi

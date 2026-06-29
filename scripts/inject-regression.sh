#!/bin/bash
# 回归模拟工具
# 在 src/math.ts 中注入一个 +1 bug，模拟"昨天绿今天红"的回归场景
# 用途：教学辅助，手动运行以创建可供 ci-fix-loop 修复的回归
#
# 用法: bash scripts/inject-regression.sh

set -euo pipefail

# 检查工作区是否干净
if [ -n "$(git status --porcelain)" ]; then
  echo "❌ 工作区有未提交的更改，请先提交或 stash"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

echo "🔧 注入回归 bug..."

# 在 add 函数中注入 +1 bug
sed -i 's/return a + b;/return a + b + 1; \/\/ BUG: injected regression/' src/math.ts

echo "✅ bug 已注入: src/math.ts 中的 add 函数现在返回 a + b + 1"

# 验证测试现在会失败
echo ""
echo "📋 运行测试确认失败..."
npx vitest run 2>&1 || true

echo ""
echo "=========================================="
echo "回归已注入！现在:"
echo "  1. git add src/math.ts"
echo "  2. git commit -m \"chore: [regression-sim] intentional bug injection $(date +%Y-%m-%d)\""
echo "  3. git push"
echo "  4. 等待 ci-fix-loop 明天自动修复"
echo "  或手动触发: gh workflow run ci-fix-loop.yml"
echo "=========================================="

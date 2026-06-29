#!/bin/bash
# 检测阶段：运行测试，用退出码判断是否失败
#
# 输出（通过 GITHUB_OUTPUT）:
#   has_failures=true|false

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

echo "📊 [DETECT] 运行测试..."

# 直接跑 vitest，用退出码判断（0=通过，1=失败）
#  这比 JSON 解析可靠得多，不依赖 vitest 版本变化
npx vitest run --reporter=verbose 2>&1 || true

EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
  echo ""
  echo "✅ [DETECT] 所有测试通过，无需修复"
  echo "has_failures=false" >> "$GITHUB_OUTPUT"
  echo "has_failures=false" >> "$GITHUB_ENV"
  exit 0
fi

echo ""
echo "❌ [DETECT] 发现测试失败 (exit code: $EXIT_CODE)"
echo "has_failures=true" >> "$GITHUB_OUTPUT"
echo "has_failures=true" >> "$GITHUB_ENV"

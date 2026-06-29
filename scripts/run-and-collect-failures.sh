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

# set +e: 临时关闭 errexit，手动捕获 vitest 退出码
# 不能用 || true，因为那会让 $? 永远为 0
set +e
npx vitest run --reporter=verbose 2>&1
EXIT_CODE=$?
set -e

if [ "$EXIT_CODE" -eq 0 ]; then
  echo ""
  echo "✅ [DETECT] 所有测试通过，无需修复"
  echo "has_failures=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

echo ""
echo "❌ [DETECT] 发现测试失败 (exit code: $EXIT_CODE)"
echo "has_failures=true" >> "$GITHUB_OUTPUT"

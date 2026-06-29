#!/bin/bash
# 检测阶段：运行测试，用退出码判断是否失败
# 同时写入 /tmp/ci_status 供 workflow 读取
set -euo pipefail

cd "$(dirname "$0")/.."

echo "📊 [DETECT] 运行测试..."

set +e
npx vitest run --reporter=verbose 2>&1
EXIT_CODE=$?
set -e

if [ "$EXIT_CODE" -eq 0 ]; then
  echo ""
  echo "✅ [DETECT] 所有测试通过，无需修复"
  echo "HAS_FAILURES=false" >> "$GITHUB_ENV"
  echo "has_failures=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

echo ""
echo "❌ [DETECT] 发现测试失败 (vitest exit: $EXIT_CODE)"
echo "HAS_FAILURES=true" >> "$GITHUB_ENV"
echo "has_failures=true" >> "$GITHUB_OUTPUT"

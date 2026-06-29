#!/bin/bash
# 检测阶段：运行测试，收集失败信息
#
# 输出（通过 GITHUB_OUTPUT）:
#   has_failures=true|false
#
# 文件输出:
#   test-results.json — vitest 原始 JSON 输出
#   test-failures.json — 提取的失败详情（仅 has_failures=true 时）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

echo "📊 [DETECT] 运行测试..."
npx vitest run --reporter=json --outputFile=test-results.json 2>&1 || true

# 解析 JSON 结果判断是否有失败
FAILURE_COUNT=$(node -e "
const r = require('./test-results.json');
const failed = r.testResults.filter(t => t.status === 'fail');
console.log(failed.length);
")

if [ "$FAILURE_COUNT" -eq 0 ]; then
  echo "✅ [DETECT] 所有测试通过，无需修复"
  echo "has_failures=false" >> "$GITHUB_ENV"
  echo "has_failures=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

echo "❌ [DETECT] 发现 $FAILURE_COUNT 个测试文件失败"

# 提取失败详情
node -e "
const r = require('./test-results.json');
const failed = r.testResults.filter(t => t.status === 'fail');
const details = failed.map(t => ({
  file: t.name,
  numFailingTests: t.numFailingTests,
  message: t.assertionResults ? t.assertionResults[0]?.failureDetails?.[0]?.message || t.message : t.message
}));
require('fs').writeFileSync('./test-failures.json', JSON.stringify(details, null, 2));
console.log('失败详情已保存到 test-failures.json');
"

echo "has_failures=true" >> "$GITHUB_ENV"
echo "has_failures=true" >> "$GITHUB_OUTPUT"

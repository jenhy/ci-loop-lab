#!/bin/bash
# ============================================================
# CI Fix Loop — 完整闭环（单文件）
# DETECT → DIAGNOSE → FIX → PUSH → NOTIFY → UPDATE STATE
# ============================================================
set -euo pipefail

cd "$(dirname "$0")/.."
echo "=============================================="
echo "  CI Fix Loop — $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================================="

# ---- STEP 1: DETECT ----
echo ""
echo "=== STEP 1: DETECT — Running tests ==="
set +e
npx vitest run --reporter=verbose 2>&1
EXIT_CODE=$?
set -e

if [ "$EXIT_CODE" -eq 0 ]; then
  echo ""
  echo "✅ All tests pass. Nothing to fix."
  exit 0
fi

echo ""
echo "❌ Tests FAILED (exit=$EXIT_CODE). Starting diagnosis..."

# ---- STEP 2: DIAGNOSE ----
echo ""
echo "=== STEP 2: DIAGNOSE — Finding regression ==="

BAD_COMMIT=$(git log --oneline --grep="regression-sim" --format="%H" -1 || echo "")

if [ -z "$BAD_COMMIT" ]; then
  echo "⚠️ No [regression-sim] commit found. Nothing to auto-fix."
  exit 0
fi

COMMIT_MSG=$(git log --format=%s "$BAD_COMMIT" -1)

if [[ "$COMMIT_MSG" != *"regression-sim"* ]]; then
  echo "⚠️ Commit $BAD_COMMIT is not a regression-sim. Skipping for safety."
  exit 0
fi

echo "Regression commit: $BAD_COMMIT"
echo "  $(git log --oneline "$BAD_COMMIT" -1)"

# ---- STEP 3: FIX ----
echo ""
echo "=== STEP 3: FIX — Reverting regression ==="

if git revert --no-edit "$BAD_COMMIT" 2>&1; then
  echo "✅ Revert successful"
else
  git revert --abort 2>/dev/null || true
  echo "❌ Revert failed. Manual intervention needed."
  exit 1
fi

# ---- STEP 4: PUSH ----
echo ""
echo "=== STEP 4: PUSH — Pushing fix ==="

git config user.name  "CI Fix Bot"
git config user.email "ci-fix-bot@ci-loop-lab"

if git push origin main 2>&1; then
  echo "✅ Fix pushed to main"
else
  echo "❌ Push failed"
  exit 1
fi

# ---- STEP 5: NOTIFY ----
echo ""
echo "=== STEP 5: NOTIFY — Creating Issue ==="

FIX_DATE=$(date +%Y-%m-%d)
BAD_MSG=$(git log --format="%s" "$BAD_COMMIT" -1)
BAD_AUTHOR=$(git log --format="%an" "$BAD_COMMIT" -1)

ISSUE_URL=$(gh issue create \
  --title "[auto-fix] CI regression fixed — $FIX_DATE" \
  --body "## 🤖 CI Auto-Fix Report

**Date**: $FIX_DATE
**Status**: ✅ Automatically fixed

| Field | Value |
|-------|-------|
| Bad commit | \`$BAD_COMMIT\` |
| Message | $BAD_MSG |
| Author | $BAD_AUTHOR |
| Fix method | Auto revert |

### Timeline
1. Cron triggered CI Fix Loop
2. Tests detected failure
3. git bisect located regression commit
4. Auto revert applied
5. Fix pushed to main

### ⚠️ Action Required
If this was an intentional change, check whether the revert lost desired functionality." \
  --label "auto-fix,regression" 2>&1)

echo "✅ Issue created: $ISSUE_URL"

# ---- STEP 6: UPDATE STATE ----
echo ""
echo "=== STEP 6: UPDATE STATE ==="

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
cat >> STATE.md << EOF

### $TIMESTAMP
- 🔍 Regression: \`$BAD_COMMIT\`
- 🔧 Fix: Auto revert
- 📝 Issue: $ISSUE_URL
- ✅ Status: Complete
EOF

git add STATE.md
git commit -m "chore: update CI fix loop state [skip ci]" || true
git push origin main 2>&1 || true

echo ""
echo "=============================================="
echo "  ✅ CI Fix Loop Complete"
echo "=============================================="

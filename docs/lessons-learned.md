# Loop Engineering CI Fix Loop — 踩坑记录

> 所有在构建 `ci-loop-lab` Loop Engineering 实战项目中遇到的 bug 与教训。

---

## 1. Bash 脚本

### 1.1 `|| true` 让 `$?` 永远为 0

```bash
# ❌ 错误
npx vitest run || true
EXIT_CODE=$?          # 永远是 0，因为 true 永远成功

# ✅ 正确
set +e
npx vitest run
EXIT_CODE=$?
set -e
```

**教训**：`cmd || true` 的唯一作用是防止 `set -e` 杀死脚本。如果需要捕获退出码，必须用 `set +e`/`set -e` 包裹。

### 1.2 `set -e` 在命令失败时直接退出

```bash
# ❌ 错误
set -euo pipefail
npx vitest run        # 测试失败返回 1 → 脚本立即被杀死
EXIT_CODE=$?          # 永远执行不到

# ✅ 正确
set +e
npx vitest run
EXIT_CODE=$?
set -e
```

**教训**：任何可能返回非零退出码的命令，如果需要后续处理，必须用 `set +e` 包裹。

### 1.3 `git config` 必须在 `git revert` 之前

```bash
# ❌ 错误
git revert --no-edit HEAD    # 失败: "Author identity unknown"
git config user.name "Bot"

# ✅ 正确
git config user.name "CI Fix Bot"
git config user.email "ci-fix-bot@ci-loop-lab"
git revert --no-edit HEAD
```

**教训**：任何需要 git 身份的操作（revert、commit）前，先设置 `user.name` 和 `user.email`。GitHub Actions 不会自动配置这些。

---

## 2. npm / Node.js 环境差异

### 2.1 `npm --silent` 在 npm 8+ 已移除

```bash
# ❌ 错误（GitHub Actions ubuntu-latest 是 npm 10+）
npm ci --silent           # 直接报错: unknown option

# ✅ 正确
npm ci 2>/dev/null
```

**教训**：不要假设本地 npm 版本和 CI 环境一致。GitHub Actions 的 `ubuntu-latest` 镜像会持续更新 npm 版本。`--silent` 从 npm 8 开始已被废除。

### 2.2 Vitest 2.x JSON reporter 输出格式可能变化

```bash
# ❌ 脆弱：依赖 vitest JSON 格式的内部结构
npx vitest run --reporter=json --outputFile=result.json
node -e "const r=require('./result.json'); r.testResults.filter(t=>t.status==='fail')"

# ✅ 可靠：用退出码判断
npx vitest run
if [ $? -ne 0 ]; then echo "FAILED"; fi
```

**教训**：退出码是跨版本的稳定接口，JSON schema 不是。

---

## 3. GitHub Actions

### 3.1 跨步骤 `GITHUB_OUTPUT` + `if:` 通信不可靠

```yaml
# ❌ 脆弱：DETECT 和 DIAGNOSE 分属两个 step
- name: DETECT
  id: detect
  run: bash scripts/detect.sh    # 写 GITHUB_OUTPUT

- name: DIAGNOSE
  if: steps.detect.outputs.has_failures == 'true'    # 可能读不到
  run: bash scripts/fix.sh

# ✅ 可靠：整个流程放在一个 step 里
- name: CI Fix Loop
  run: bash scripts/ci-fix-loop.sh
  # 脚本内部完成: detect → diagnose → fix → push → notify → state
```

**教训**：Loop Engineering 的核心思想——把所有逻辑写在一个闭环里，不要依赖环境变量跨步骤传递状态。

### 3.2 `gh issue create --label` 在标签不存在时报错

```bash
# ❌ 错误
gh issue create --label "auto-fix,regression"   # 标签不存在 → exit 1

# ✅ 正确：先创建标签，或用 `--label` 仅在标签存在时使用
# 方案 1: 去掉 label
gh issue create --title "..." --body-file /tmp/body.md
# 方案 2: 通过 gh CLI 先创建标签
gh label create "auto-fix" --color "0366d6" || true
```

**教训**：新仓库没有自定义标签。要么在脚本里先 `gh label create`，要么不用 `--label`。

### 3.3 多行 `--body "..."` 在 bash 中容易出错

```bash
# ❌ 脆弱
gh issue create --body "line 1
line 2
line 3"     # 内嵌引号、变量展开都可能出问题

# ✅ 可靠
cat > /tmp/body.md << EOF
line 1
line 2
line 3
EOF
gh issue create --body-file /tmp/body.md
```

**教训**：复杂的命令行参数（尤其含多行文本的）用 `--body-file` / `--file` 传递，避免 shell 转义问题。

### 3.4 `ci.yml` 和 `ci-fix-loop.yml` 容易混淆

| 工作流 | 触发方式 | 用途 |
|--------|---------|------|
| `ci.yml` | push/PR 自动 | 日常 CI，只跑测试 |
| `ci-fix-loop.yml` | cron + 手动 | 修复循环，检测→修复→通知 |

**教训**：直观命名。在文档中明确区分"被监控的 CI"和"执行修复的 CI Fix Loop"。

---

## 4. GitHub MCP / API

### 4.1 MCP token 权限不足

- `mcp__github__create_repository` 第一次失败 (403)，第二次成功。token 权限可能不稳定
- 用 `gh` CLI（需预装）作为 fallback

**教训**：不要假设 MCP token 总是有完整权限。在需要写操作的场景准备多种方案。

### 4.2 Playwright MCP 无法操作需要登录的页面

触发 `workflow_dispatch` 需要登录 GitHub。Playwright 浏览器未登录时看不到 "Run workflow" 按钮。

**教训**：触发 GitHub Actions 最可靠的方式是用户自己在浏览器里操作，或使用 `gh workflow run` CLI。

---

## 5. 设计教训

### 5.1 先写伪代码，再写真代码

初版设计用 JSON reporter 解析 vitest 输出——在 2.x 版本上测试通过，但在 GitHub Actions 的 exact 版本（2.1.9）上有微妙差异。**退出码是唯一稳定的接口**。

### 5.2 单文件优于多文件 + 跨文件通信

最初的五步分离架构（`detect.sh` → `auto-fix.sh` → `notify.sh`，通过 GITHUB_OUTPUT 串联）看起来"模块化"，但每个跨步骤通信点都是一个潜在的故障点。最终的单文件 `ci-fix-loop.sh` 方案消除了所有跨步骤通信。

### 5.3 先在本地用相同环境测试

```bash
# 模拟 GitHub Actions 环境的最简方式
export GITHUB_OUTPUT=/tmp/test_output.txt
export GITHUB_ENV=/tmp/test_env.txt
bash scripts/ci-fix-loop.sh
cat /tmp/test_output.txt
```

---

## 最终架构

```
ci-fix-loop.yml (6行有效代码)
  └── bash scripts/ci-fix-loop.sh (110行)
        ├── DETECT   ─ 跑测试，退出码判断
        ├── DIAGNOSE ─ git log --grep 找回归提交
        ├── FIX      ─ git revert
        ├── PUSH     ─ git push
        ├── NOTIFY   ─ gh issue create
        └── STATE    ─ 更新 STATE.md
```

**核心原则**：一个脚本，一个闭环，零跨步骤通信。

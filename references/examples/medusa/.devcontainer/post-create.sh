#!/usr/bin/env bash
set -euo pipefail

echo "→ 权限修复..."
sudo chown -R vscode:vscode node_modules /commandhistory ~/.local ~/.cargo ~/go ~/.npm-global 2>/dev/null || true

echo "→ npm global prefix → volume..."
mkdir -p ~/.npm-global && npm config set prefix ~/.npm-global

echo "→ 启用 pnpm..."
corepack enable
corepack prepare pnpm@latest --activate

echo "→ 安装 Bun（volume 命中则跳过）..."
if [ ! -x "$HOME/.bun/bin/bun" ]; then
  curl -fsSL https://bun.sh/install | bash
fi

echo "→ 装 Claude Code CLI + Medusa CLI..."
npm i -g @anthropic-ai/claude-code @anthropic-ai/claude-agent-sdk
# Medusa v2 CLI（v1 用 @medusajs/medusa-cli）
npm i -g @medusajs/cli || true

echo "→ 默认 skill 集合（含 ecommerce + medusa-dev 相关）..."
npx -y skills add vercel-labs/agent-browser@agent-browser -g -y || true
npx -y skills add anthropics/skills@skill-creator -g -y || true
npx -y skills add vercel-labs/agent-skills@react-best-practices -g -y || true
# Medusa / ecommerce storefront 用户已装 plugin，skill 自带；这里仅确保

echo "→ 安装 Linuxbrew..."
if [ ! -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  sudo chown -R vscode:vscode /home/linuxbrew/.linuxbrew || true
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

echo "→ 配置 shell..."
touch /commandhistory/.zsh_history
if ! grep -q 'container-creator 默认配置' ~/.zshrc 2>/dev/null; then
  cat >> ~/.zshrc <<'EOF'

# container-creator 默认配置
alias claude='claude --dangerously-skip-permissions'
export HISTFILE=/commandhistory/.zsh_history
export HISTSIZE=10000 SAVEHIST=10000
setopt INC_APPEND_HISTORY SHARE_HISTORY

export PATH="$HOME/.bun/bin:$HOME/.npm-global/bin:$HOME/.local/bin:$HOME/.cargo/bin:$HOME/go/bin:$PATH"

if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

if [ -f "${TOOLS_LIST%/*}/bin/tools-wrapper.sh" ]; then
  source "${TOOLS_LIST%/*}/bin/tools-wrapper.sh"
fi
EOF
fi

echo "→ 同步 tools.list..."
if [ -f .devcontainer/tools.list ]; then
  [ -x /home/linuxbrew/.linuxbrew/bin/brew ] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  bash .devcontainer/bin/install-tools.sh || echo "⚠ install-tools 部分失败"
fi

echo "→ 等待 Postgres 就绪..."
for i in {1..20}; do
  if pg_isready -h db -U postgres -d medusa >/dev/null 2>&1; then break; fi
  sleep 1
done

echo "→ 安装项目依赖（若 monorepo/单仓库）..."
if [ -f pnpm-workspace.yaml ] || [ -f package.json ]; then
  pnpm install || npm install
fi

echo "→ 跑 Medusa 迁移（如有 medusa-config.js）..."
if [ -f medusa-config.js ] || [ -f medusa-config.ts ]; then
  npx medusa db:migrate || echo "⚠ db:migrate 未执行（项目或未初始化）"
fi

echo "→ git 初始化（仅当仓库未 init）..."
if [ ! -d .git ]; then
  git init -q -b main
  [ -f .devcontainer/.gitignore.template ] && cp .devcontainer/.gitignore.template .gitignore
  git add -A
  if [ -n "$(git config user.email 2>/dev/null)" ]; then
    git commit -q -m "chore: bootstrap devcontainer" && echo "  ✓ 初始 commit 完成"
  else
    echo "  ⚠ 未配 git user.email，跳过 commit"
  fi
fi

echo ""
echo "✓ 容器就绪"
echo "  - Medusa backend: cd apps/backend && npx medusa develop   (→ :9000)"
echo "  - Next.js storefront: cd apps/storefront && pnpm dev       (→ :8000)"
echo "  - Postgres: psql postgres://postgres:postgres@db:5432/medusa"
echo "  - Redis:    redis-cli -h redis"
echo "  - Claude Code 全自动模式已配好"

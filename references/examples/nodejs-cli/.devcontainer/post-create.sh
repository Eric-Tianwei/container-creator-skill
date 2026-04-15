#!/usr/bin/env bash
set -euo pipefail

echo "→ 权限修复..."
sudo chown -R vscode:vscode node_modules /commandhistory ~/.local ~/.cargo ~/go ~/.npm-global 2>/dev/null || true

echo "→ npm global prefix → volume..."
mkdir -p ~/.npm-global && npm config set prefix ~/.npm-global

echo "→ 启用 pnpm（Node CLI 项目推荐）..."
corepack enable
corepack prepare pnpm@latest --activate

echo "→ 安装 Bun（volume 命中则跳过）..."
if [ ! -x "$HOME/.bun/bin/bun" ]; then
  curl -fsSL https://bun.sh/install | bash
fi

echo "→ 装 Claude Code CLI..."
npm i -g @anthropic-ai/claude-code @anthropic-ai/claude-agent-sdk

echo "→ 默认 skill 集合..."
npx -y skills add vercel-labs/agent-browser@agent-browser -g -y || true
npx -y skills add anthropics/skills@skill-creator -g -y || true

echo "→ 安装 Linuxbrew（首次约 1 分钟，volume 命中秒级）..."
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

echo ""
echo "✓ 容器就绪"
echo "  - Node $(node --version), pnpm $(pnpm --version 2>/dev/null || echo '未装'), bun $($HOME/.bun/bin/bun --version 2>/dev/null || echo '未装')"
echo "  - 纯 Node 脚本 / CLI 开发环境。直接写 .ts/.js，用 bun/tsx/node --run 跑"
echo "  - 加工具用 brew install / cargo install / npm i -g（自动记录 tools.list）"

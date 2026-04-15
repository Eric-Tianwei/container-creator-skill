#!/usr/bin/env bash
set -euo pipefail

echo "→ 修复 volume 目录权限..."
sudo chown -R vscode:vscode node_modules .next /commandhistory ~/.local ~/.cargo ~/go ~/.npm-global 2>/dev/null || true

echo "→ 配置 npm global prefix → volume..."
mkdir -p ~/.npm-global
npm config set prefix ~/.npm-global

echo "→ 启用 pnpm..."
corepack enable
corepack prepare pnpm@latest --activate

echo "→ 安装 Bun（volume 命中则跳过）..."
if [ ! -x "$HOME/.bun/bin/bun" ]; then
  curl -fsSL https://bun.sh/install | bash
fi

echo "→ 安装 Claude Code CLI + Vercel CLI..."
npm i -g @anthropic-ai/claude-code @anthropic-ai/claude-agent-sdk vercel

echo "→ 安装默认 skill 集合（已有则跳过）..."
npx -y skills add vercel-labs/agent-browser@agent-browser -g -y || true
npx -y skills add anthropics/skills@skill-creator -g -y || true
npx -y skills add vercel-labs/agent-skills@react-best-practices -g -y || true

echo "→ 安装 Linuxbrew（跨项目共享的 system CLI 工具链，首次约 1 分钟，后续 volume 命中秒级）..."
if [ ! -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  sudo chown -R vscode:vscode /home/linuxbrew/.linuxbrew || true
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

echo "→ 配置 shell（历史持久化 + claude 全自动 + PATH + tools-wrapper）..."
touch /commandhistory/.zsh_history
if ! grep -q 'container-creator 默认配置' ~/.zshrc 2>/dev/null; then
  cat >> ~/.zshrc <<'EOF'

# container-creator 默认配置
alias claude='claude --dangerously-skip-permissions'
export HISTFILE=/commandhistory/.zsh_history
export HISTSIZE=10000 SAVEHIST=10000
setopt INC_APPEND_HISTORY SHARE_HISTORY

# 用户级 CLI volume → PATH
export PATH="$HOME/.bun/bin:$HOME/.npm-global/bin:$HOME/.local/bin:$HOME/.cargo/bin:$HOME/go/bin:$PATH"

# Linuxbrew
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# 透明 wrapper（brew/cargo/npm/pipx/go install 自动记录到 tools.list）
if [ -f "${TOOLS_LIST%/*}/bin/tools-wrapper.sh" ]; then
  source "${TOOLS_LIST%/*}/bin/tools-wrapper.sh"
fi
EOF
fi

echo "→ 按 tools.list 同步 CLI 工具（已装跳过）..."
if [ -f .devcontainer/tools.list ]; then
  # 先加载 brew 环境以便 install-tools.sh 可用
  [ -x /home/linuxbrew/.linuxbrew/bin/brew ] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  bash .devcontainer/bin/install-tools.sh || echo "⚠ install-tools.sh 部分失败，不阻塞容器启动"
fi

echo "→ 安装项目依赖..."
if [ -f package.json ]; then
  pnpm install
fi

echo ""
echo "✓ 容器就绪"
echo "  - Node $(node --version), pnpm $(pnpm --version), bun $($HOME/.bun/bin/bun --version 2>/dev/null || echo '未装')"
echo "  - brew $(brew --version 2>/dev/null | head -1 || echo '未装')"
echo "  - Claude Code 已配好全自动模式；skills 沿用宿主机"
echo "  - 加 CLI 直接用 brew install / cargo install / npm i -g / pipx install（会自动记录到 tools.list）"
echo "  - 启动开发：pnpm dev"

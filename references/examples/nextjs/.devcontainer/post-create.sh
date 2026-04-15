#!/usr/bin/env bash
set -euo pipefail

echo "→ 修复 volume 目录权限..."
sudo chown -R vscode:vscode node_modules .next || true

echo "→ 启用 pnpm..."
corepack enable
corepack prepare pnpm@latest --activate

echo "→ 安装 Claude Code CLI + Vercel CLI..."
npm i -g @anthropic-ai/claude-code @anthropic-ai/claude-agent-sdk vercel

echo "→ 安装默认 skill 集合（已有则跳过）..."
npx -y skills add vercel-labs/agent-browser@agent-browser -g -y || true
npx -y skills add anthropics/skills@skill-creator -g -y || true
npx -y skills add vercel-labs/agent-skills@react-best-practices -g -y || true

echo "→ 持久化 shell 历史..."
mkdir -p /commandhistory
touch /commandhistory/.zsh_history
sudo chown -R vscode:vscode /commandhistory
if ! grep -q 'container-creator 默认配置' ~/.zshrc 2>/dev/null; then
  cat >> ~/.zshrc <<'EOF'

# container-creator 默认配置
alias claude='claude --dangerously-skip-permissions'
export HISTFILE=/commandhistory/.zsh_history
export HISTSIZE=10000
export SAVEHIST=10000
setopt INC_APPEND_HISTORY SHARE_HISTORY
EOF
fi

echo "→ 安装项目依赖..."
if [ -f package.json ]; then
  pnpm install
fi

echo ""
echo "✓ 容器就绪"
echo "  - Node $(node --version), pnpm $(pnpm --version)"
echo "  - Claude Code: $(claude --version 2>/dev/null || echo '未登录则跑 claude 登录')"
echo "  - 启动开发：pnpm dev"

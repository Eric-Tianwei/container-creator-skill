#!/usr/bin/env bash
set -euo pipefail

echo "→ 权限修复..."
sudo chown -R vscode:vscode .venv /commandhistory ~/.local ~/.cargo ~/go ~/.npm-global ~/.cache 2>/dev/null || true

echo "→ 配置 npm global prefix → volume..."
mkdir -p ~/.npm-global && npm config set prefix ~/.npm-global

echo "→ 安装 uv（快的 Python 包管理器）..."
if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi

echo "→ 安装 pipx（隔离安装 Python CLI）..."
if ! command -v pipx >/dev/null 2>&1; then
  python3 -m pip install --user pipx
  python3 -m pipx ensurepath
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

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/go/bin:$HOME/.npm-global/bin:$PATH"

# Python：优先用项目 .venv
if [ -f .venv/bin/activate ]; then
  source .venv/bin/activate
fi

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

echo "→ 安装项目依赖（如有 pyproject.toml）..."
if [ -f pyproject.toml ]; then
  uv sync || echo "⚠ uv sync 跳过（首次或 lockfile 不存在）"
fi

echo ""
echo "✓ 容器就绪"
echo "  - Python $(python3 --version 2>&1), uv $(uv --version 2>/dev/null || echo '未装')"
echo "  - 纯 Python 脚本 / CLI 开发。推荐 uv run <script>.py / uv sync 管理依赖"
echo "  - 加工具用 brew install / cargo install / pipx install / npm i -g（自动记录 tools.list）"

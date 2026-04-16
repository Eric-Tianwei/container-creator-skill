#!/usr/bin/env bash
# 容器首次 create 时跑。幂等，重跑无害。
set -euo pipefail

echo "[post-create] start: $(date -Iseconds)"

# 1. 权限：shared / cache / cmdhistory volume 首次挂进来是 root
sudo chown -R vscode:vscode /opt/dcc /commandhistory ~/.bun 2>/dev/null || true
sudo chown -R vscode:vscode "$(pwd)/node_modules" 2>/dev/null || true

# 2. shared volume 内部结构 + Linuxbrew 软链
mkdir -p /opt/dcc/{linuxbrew,cargo,go,npm-global,bun,pipx,uv/bin,uv/python,uv/tools,local}
if [ ! -L /home/linuxbrew/.linuxbrew ]; then
  sudo mkdir -p /home/linuxbrew
  sudo ln -sfn /opt/dcc/linuxbrew /home/linuxbrew/.linuxbrew
  sudo chown -R vscode:vscode /home/linuxbrew
fi

# 3. 环境变量写 ~/.profile（只写一次）
if ! grep -q 'container-creator shared volume' ~/.profile 2>/dev/null; then
  cat >> ~/.profile <<'EOF'

# container-creator shared volume 路径
export CARGO_HOME=/opt/dcc/cargo
export GOPATH=/opt/dcc/go
export NPM_CONFIG_PREFIX=/opt/dcc/npm-global
export BUN_INSTALL=/opt/dcc/bun
export PIPX_HOME=/opt/dcc/pipx
export PIPX_BIN_DIR=/opt/dcc/pipx/bin
export UV_INSTALL_DIR=/opt/dcc/uv/bin
export UV_PYTHON_INSTALL_DIR=/opt/dcc/uv/python
export UV_TOOL_DIR=/opt/dcc/uv/tools
export PATH="/opt/dcc/cargo/bin:/opt/dcc/go/bin:/opt/dcc/npm-global/bin:/opt/dcc/bun/bin:/opt/dcc/pipx/bin:/opt/dcc/uv/bin:/home/linuxbrew/.linuxbrew/bin:$PATH"
EOF
fi
# shellcheck disable=SC1091
source ~/.profile

# 4. 安装 Linuxbrew（如果还没装）
if [ ! -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true
fi

# 5. Claude Code + Agent SDK
npm i -g @anthropic-ai/claude-code @anthropic-ai/claude-agent-sdk
npx -y skills add vercel-labs/agent-browser@agent-browser -g -y || true
npx -y skills add anthropics/skills@skill-creator -g -y || true

# 6. uv（Python 按需运行时）
if ! command -v uv >/dev/null; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi

# 7. Bun
if ! command -v bun >/dev/null; then
  curl -fsSL https://bun.sh/install | bash
fi

# 8. 透明 wrapper + claude 全自动模式 + 历史持久化（写 ~/.zshrc 一次）
if ! grep -q 'container-creator 默认配置' ~/.zshrc 2>/dev/null; then
  cat >> ~/.zshrc <<'EOF'

# container-creator 默认配置
[ -f ~/.profile ] && source ~/.profile
[ -f /workspaces/*/.devcontainer/bin/tools-wrapper.sh ] && source /workspaces/*/.devcontainer/bin/tools-wrapper.sh 2>/dev/null || true
alias claude='claude --dangerously-skip-permissions'
export HISTFILE=/commandhistory/.zsh_history
export HISTSIZE=10000
export SAVEHIST=10000
setopt INC_APPEND_HISTORY SHARE_HISTORY
EOF
fi
touch /commandhistory/.zsh_history

# 9. tools.list 里登记的 CLI 幂等安装
bash "$(dirname "$0")/bin/install-tools.sh" || true

# 10. 项目专用 skill 软链（如果 repo 里有 .claude/skills/）
if [ -d ./.claude/skills ]; then
  mkdir -p ~/.claude/skills
  for d in ./.claude/skills/*/; do
    [ -d "$d" ] || continue
    ln -sfn "$(realpath "$d")" ~/.claude/skills/"$(basename "$d")"
  done
fi


# 11. 业务步骤占位（按项目替换 / 删除）
# Node:   sudo corepack enable && pnpm install
# Python: uv python install 3.13 && uv sync

echo "[post-create] done: $(date -Iseconds)"

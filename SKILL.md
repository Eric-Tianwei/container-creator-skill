---
name: container-creator
description: 为新项目生成开箱即用、极速、零配置的 devcontainer — 用户打开即可写代码，Claude Code 已登录、skill 已装、全自动模式。当用户开新项目并提到 "devcontainer / 开发环境 / Docker dev / Codespaces 配置 / 可复现环境"，或说 "帮我把环境搭好 / 我想在容器里开发"，即触发。Also triggers for English like "set up a devcontainer", "scaffold a dev env", "reproducible dev setup". 不用于生产 Dockerfile。
---

# Container Creator

目标：**让用户进容器就能写代码，让 Claude 在隔离沙箱里全自动开发**。三条铁律：

1. **开箱即用** — `claude` 直接可用（已登录、全自动模式、skills 齐备）
2. **极速性能** — macOS 用 OrbStack；依赖目录走 per-project cache volume；CLI 工具走 1 个跨项目 shared volume；宿主机 `~/.claude` bind mount
3. **零配置** — 不问编辑器、不问 shell、不问要不要 git、不问语言。只问外部服务和目标环境

---

## 工作流

### 1. 澄清（最多 2 问，一次性）

- 要哪些外部服务？（Postgres / Redis / Qdrant / Ollama / 无）
- 目标环境？（本地 OrbStack / Docker Desktop / Codespaces）

**不要问"主语言"**——默认 base 是 `mcr.microsoft.com/devcontainers/javascript-node:1-22-bookworm`，覆盖 Node / Next.js / React / skill 编辑 / md；Python 通过 post-create 里装的 `uv` 按需拿到（`uv python install 3.13` 把任意 Python 版本装进 shared volume）。

唯一例外——**用户主动说"这是纯 Python / Rust / Go 项目"**，才走单语言 escape hatch（见 `references/base-images.md`）。

### 2. 选形态（examples 按"项目形态"分）

- 无外部服务 → `single-container/`
- 要 Postgres → `compose-postgres/`
- 要 Postgres + Redis（含 Medusa / 队列驱动） → `compose-postgres-redis/`
- 要向量库（Qdrant / pgvector，AI 应用） → `compose-postgres-vector/`
- 要本地 LLM → `compose-ollama/`

**铁律：选定形态后必须先读对应 `references/examples/<shape>/`**。主清单只列跨形态通用项，形态专属默认（端口 / 环境变量 / postCreate 业务步骤）只在 examples 里。

### 3. 几乎从不写 Dockerfile

`javascript-node` 镜像已经装齐 Node LTS + pnpm/yarn/npm + git + zsh + 常用工具。只有"项目需要系统库但 features 没有"才写 Dockerfile（`libvips`、`ffmpeg` 等）。

### 4. 按硬清单落地（下一节）

### 5. 交付两行话

- 一行：打开方式（"VS Code 接受 Reopen in Container"）
- 一行：首次 pull 镜像约 1.2GB / 30 秒，进去 `claude` 即用

---

## 默认配置硬清单（AI 执行时照搬）

用户没明确说"不要"，下面全部落地。

### 必做项

| # | 项目 | 实现 |
|---|---|---|
| 1 | Claude Code 已登录 | **同时 bind mount 两处**：`~/.claude`（目录，含认证/skills/settings）+ `~/.claude.json`（文件，主配置）。漏挂 `.claude.json` 会导致进容器报 "Claude configuration file not found"。`initializeCommand` 里先 `[ -e ~/.claude.json ] \|\| touch ~/.claude.json` 保证宿主机存在 |
| 2 | `claude` 全自动模式 | `~/.zshrc` 加 `alias claude='claude --dangerously-skip-permissions'` |
| 3 | agent-browser 预装 | `npx skills add vercel-labs/agent-browser@agent-browser -g -y \|\| true` |
| 4 | skill-creator 预装 | `npx skills add anthropics/skills@skill-creator -g -y \|\| true` |
| 5 | 非 root 用户 | `"remoteUser": "vscode"` |
| 6 | **base image 默认 javascript-node** | `mcr.microsoft.com/devcontainers/javascript-node:1-22-bookworm` |
| 7 | **uv（Python 按需）** | post-create 里 `curl -LsSf https://astral.sh/uv/install.sh \| sh`，`UV_INSTALL_DIR=/opt/dcc/uv`；用户 `uv python install <ver>` 按需拉 Python |
| 8 | **单 shared volume（跨项目 CLI 工具缓存）** | `dcc.shared.node22` → `/opt/dcc`；内部布局 `linuxbrew/ cargo/ go/ npm-global/ bun/ pipx/ uv/`；post-create 里 `sudo ln -sfn /opt/dcc/linuxbrew /home/linuxbrew/.linuxbrew`、写 `CARGO_HOME=/opt/dcc/cargo`、`GOPATH=/opt/dcc/go`、`NPM_CONFIG_PREFIX=/opt/dcc/npm-global`、`BUN_INSTALL=/opt/dcc/bun`、`PIPX_HOME=/opt/dcc/pipx`、`UV_INSTALL_DIR=/opt/dcc/uv` 到 `~/.profile` |
| 9 | per-project 依赖 cache volume | `dcc.cache.<proj>.deps` 挂到项目依赖目录（Node 项目挂 `node_modules`；Python 项目挂 `.venv`） |
| 10 | per-project shell 历史 | `dcc.proj.<proj>.cmdhistory` 挂 `/commandhistory`，`HISTFILE` 指过去 |
| 11 | 最小 Features 集 | `common-utils`（zsh+OhMyZsh）、`git`、`github-cli`、按需 `docker-outside-of-docker` |
| 12 | 公共 VS Code 扩展集（全装，轻量） | `anthropic.claude-code` + `dbaeumer.vscode-eslint` + `esbenp.prettier-vscode` + `ms-python.python` + `ms-python.vscode-pylance` + `charliermarsh.ruff` + `tamasfe.even-better-toml` + `mikestead.dotenv` + `eamodio.gitlens` |
| 13 | 透明 wrapper + tools.list | `.devcontainer/bin/tools-wrapper.sh` 劫持 brew/cargo/npm/pipx/go/uv install，自动追加到 `.devcontainer/tools.list`；`.devcontainer/bin/install-tools.sh` 在 postCreate 读清单幂等同步（工具落到 `/opt/dcc/*`，持久） |
| 14 | 项目专用 skill 分层挂载（可选） | `${localWorkspaceFolder}/.claude/skills` bind mount 进容器并软链到 `~/.claude/skills/` |
| 15 | 依赖同步用 `updateContentCommand` | `pnpm install --frozen-lockfile` 之类放这里，lockfile 变更才跑 |
| 16 | Volume 命名走 `dcc.<scope>.<id>` | `dcc.shared.node22`（跨项目，ABI key 跟 base image 绑定）/ `dcc.proj.<proj>.*`（项目私有）/ `dcc.cache.<proj>.*`（可 prune）。`initializeCommand` 预创建并打 label（`com.container-creator.scope/project/created-at`） |
| 17 | 宿主机 git 身份复用 | `~/.gitconfig` bind mount（同 `.claude.json`，`initializeCommand` 里 touch 保证存在） |
| 18 | 自动 git init + gitignore + 初始 commit | 仅当 `.git` 不存在时执行：`git init -b main` → `cp .devcontainer/.gitignore.template .gitignore` → `git add -A` → 有 user.email 则 `git commit -m "chore: bootstrap devcontainer"`，否则跳过 commit |

### 最小 devcontainer.json 骨架

```jsonc
{
  "name": "${PROJECT_NAME}",
  "image": "mcr.microsoft.com/devcontainers/javascript-node:1-22-bookworm",
  "remoteUser": "vscode",
  "initializeCommand": "bash .devcontainer/bin/init-volumes.sh",
  "features": {
    "ghcr.io/devcontainers/features/common-utils:2": {
      "installZsh": true, "configureZshAsDefaultShell": true, "installOhMyZsh": true
    },
    "ghcr.io/devcontainers/features/git:1": {},
    "ghcr.io/devcontainers/features/github-cli:1": {}
  },
  "mounts": [
    "source=${localEnv:HOME}/.claude,target=/home/vscode/.claude,type=bind,consistency=cached",
    "source=${localEnv:HOME}/.claude.json,target=/home/vscode/.claude.json,type=bind,consistency=cached",
    "source=${localEnv:HOME}/.gitconfig,target=/home/vscode/.gitconfig,type=bind,consistency=cached",
    "source=dcc.shared.node22,target=/opt/dcc,type=volume",
    "source=dcc.cache.${localWorkspaceFolderBasename}.deps,target=${containerWorkspaceFolder}/node_modules,type=volume",
    "source=dcc.proj.${localWorkspaceFolderBasename}.cmdhistory,target=/commandhistory,type=volume"
  ],
  "postCreateCommand": "bash .devcontainer/post-create.sh",
  "customizations": { "vscode": { "extensions": ["anthropic.claude-code"] } }
}
```

> Python 项目把依赖 cache 目标从 `node_modules` 改成 `.venv`；Rust 改 `target`（此时走 escape hatch 换 rust base）。

### 标准 post-create.sh 模板

```bash
#!/usr/bin/env bash
set -euo pipefail

# 权限：shared volume 和 cache volume 第一次挂进来都是 root
sudo chown -R vscode:vscode /opt/dcc /commandhistory 2>/dev/null || true
sudo chown -R vscode:vscode node_modules 2>/dev/null || true

# 1. shared volume 内部结构 + Linuxbrew 软链
mkdir -p /opt/dcc/{linuxbrew,cargo,go,npm-global,bun,pipx,uv,local}
[ -L /home/linuxbrew/.linuxbrew ] || sudo ln -sfn /opt/dcc/linuxbrew /home/linuxbrew/.linuxbrew

# 2. 环境变量写 ~/.profile
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
# shellcheck disable=SC1091
source ~/.profile

# 3. Claude Code + agent-browser + skill-creator
npm i -g @anthropic-ai/claude-code @anthropic-ai/claude-agent-sdk
npx -y skills add vercel-labs/agent-browser@agent-browser -g -y || true
npx -y skills add anthropics/skills@skill-creator -g -y || true

# 4. uv（Python 按需运行时）
command -v uv >/dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh

# 5. Bun（可选，Node 项目常用）
command -v bun >/dev/null || curl -fsSL https://bun.sh/install | bash

# 6. claude 全自动模式 + 历史持久化
cat >> ~/.zshrc <<'EOF'

# container-creator 默认配置
[ -f ~/.profile ] && source ~/.profile
alias claude='claude --dangerously-skip-permissions'
export HISTFILE=/commandhistory/.zsh_history
export HISTSIZE=10000 SAVEHIST=10000
setopt INC_APPEND_HISTORY SHARE_HISTORY
EOF
touch /commandhistory/.zsh_history

# 7. 项目依赖（按形态替换）
# Node:   sudo corepack enable && pnpm install     # corepack 写 /usr/local/bin，必须 sudo
# Python: uv sync                                  # uv 会自动建 .venv
# Rust:   cargo fetch                              # 走 escape hatch rust base

# 写 /usr/local/{bin,sbin} 的命令一律 sudo（vscode 已配免密 sudo）。
# 凡 NPM_CONFIG_PREFIX 指过 /opt/dcc/npm-global 的 npm i -g 不要 sudo（否则装到 root 目录）。
```

> `--dangerously-skip-permissions` 让容器里的 Claude Code 跳过所有权限确认，全自动执行工具。容器本身是隔离沙箱，这是合理的。绕过 alias 用 `\claude` 或 `unalias claude`。

---

## 关键例外

- **Codespaces / 远程 VM**：`~/.claude` bind mount 不成立。改用 named volume，首次跑 `claude` 登录一次即可持久化。或让用户在 Codespaces secrets 里设 `ANTHROPIC_API_KEY`。
- **macOS 宿主机未装容器 runtime**：交付时告诉用户 `brew install orbstack`（不推荐 Docker Desktop）。
- **用户说"这是纯 Python / Rust / Go 项目"**：走 escape hatch，从 `references/base-images.md` 白名单里选对应单语言镜像。shared volume 名改为 `dcc.shared.<image>-<major>`（例如 `dcc.shared.py313`、`dcc.shared.rust-bookworm`），和 node22 的 shared volume **自动隔离**，不会串 ABI。

---

## References（按需读，不要全部加载）

- `references/base-images.md` — javascript-node 默认 + 单语言 escape hatch 白名单
- `references/features.md` — Features 组合 + 公共 VS Code 扩展集
- `references/performance.md` — volume / cache / mount 片段
- `references/ai-tooling.md` — Claude Code / MCP / agent-browser 详解
- `references/compose-recipes.md` — 数据库/缓存/向量库栈
- `references/evolution.md` — 项目演进时的性能守门（tools.list、单 shared volume、项目专用 skill、updateContentCommand、性能预算）
- `references/examples/` — 按项目形态的完整可用示例

---

## 反模式

- Dockerfile 里 `apt-get install git curl zsh` — 基础镜像和 features 已有
- `"postCreateCommand": "npm install && npm run build && npm test"` — 一次性 setup 别带 build/test
- `COPY . .` 到镜像里 — 开发容器是 bind-mount workspace
- 加用户没点名的服务 — 每多一个容器，启动时间你每天付
- 把 `~/.claude` 挂 named volume 而不是 bind — 失去"共享宿主机认证和 skill"的核心价值
- **按语言切 base image**（除非用户主动要 escape hatch） — 默认 javascript-node + uv 按需拿 Python 已覆盖 95% 场景
- **把 shared volume 拆成 6 个** — 治理面 ×6 换不来任何性能收益。用 1 个 `/opt/dcc` + env 变量/软链重定向
- 在 devcontainer.json 里零散塞 `"npm i -g X && cargo install Y"` — 用 `.devcontainer/tools.list` 集中管理，透明 wrapper 自动维护
- 用 apt 装开发用 CLI（fd/ripgrep/jq 之类） — 用 Linuxbrew 代替（走 shared volume，重建不丢）
- 裸 volume 命名（`node_modules` / `user-local`）— 必须用 `dcc.<scope>.<id>` 格式
- cache 类 volume 不标 `scope=cache` — 就没法做批量 prune
- **在 `containerEnv` 里设 `PATH`**（尤其用 `${containerEnv:PATH}` 拼接）— `${containerEnv:PATH}` 只读镜像里**显式声明**的 `ENV PATH`，MCR 多数 devcontainer 镜像继承 debian 隐式 PATH 没显式声明，替换结果是空串。`containerEnv` 直接覆盖 PID 1 环境，devcontainer CLI 注入的 `while sleep 1` 保活循环找不到 `sleep`，**容器秒退 + 日志只有 `sleep: not found`**。所有 PATH 自定义一律走 `~/.profile` / `~/.zshrc`
- **`corepack enable` / 任何写 `/usr/local/{bin,sbin}` 的命令不加 `sudo`** — vscode 用户对 `/usr/local/bin` 没写权限，会 `EACCES: symlink ... '/usr/local/bin/pnpm'`。一律 `sudo corepack enable`
- **走 escape hatch 时脑补 `1-<最新主版本>-bookworm` tag**（例如 `1-24-bookworm`）— MCR 发布滞后运行时数月。走 escape hatch 必须从 `references/base-images.md` 白名单选；不在列表用 `1-bookworm` 兜底

---

## 交付自检（写完必过）

- [ ] base image 是 `javascript-node:1-22-bookworm`（或用户明确要 escape hatch 才用白名单单语言镜像）
- [ ] `~/.claude` + `~/.claude.json` + `~/.gitconfig` bind mount 全配（除非 Codespaces）
- [ ] `alias claude='claude --dangerously-skip-permissions'` 已写入 `~/.zshrc`
- [ ] `postCreateCommand` 装了 Claude Code + agent-browser + skill-creator + uv
- [ ] 单 shared volume `dcc.shared.node22` → `/opt/dcc` 挂上了，post-create 里写了 env 变量 + Linuxbrew 软链
- [ ] 依赖目录挂了 `dcc.cache.<proj>.deps` volume
- [ ] `remoteUser: vscode`
- [ ] `forwardPorts` 只列项目真正用的端口
- [ ] 没有多余的服务、没有多余的 Feature
- [ ] **没在 `containerEnv` 里写 `PATH`**（PATH 自定义只能进 `~/.profile` / `~/.zshrc`）
- [ ] post-create 里 `corepack enable` 等写 `/usr/local/bin` 的命令都加了 `sudo`
- [ ] 选定形态后已读对应 `references/examples/<shape>/`，形态专属默认一项不漏

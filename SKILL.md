---
name: container-creator
description: 为新项目生成开箱即用、极速、零配置的 devcontainer — 用户打开即可写代码，Claude Code 已登录、skill 已装、全自动模式。当用户开新项目并提到 "devcontainer / 开发环境 / Docker dev / Codespaces 配置 / 可复现环境"，或说 "帮我把环境搭好 / 我想在容器里开发"，即触发。Also triggers for English like "set up a devcontainer", "scaffold a dev env", "reproducible dev setup". 不用于生产 Dockerfile。
---

# Container Creator

目标：**用户进容器就能写代码**。三条铁律：

1. **开箱即用** — `claude` 直接可用（已登录、全自动模式、skills 齐备）
2. **极速性能** — macOS 用 OrbStack；依赖目录走 named volume；bind mount 宿主机 `~/.claude`
3. **零配置** — 不问编辑器、不问 shell、不问要不要 git。只问语言/框架、要什么外部服务、是否 Codespaces

---

## 工作流

### 1. 澄清（最多 3 问，一次性）

- 主语言/框架？（Next.js / FastAPI / Rust CLI / …）
- 要哪些外部服务？（Postgres / Redis / Qdrant / Ollama / 无）
- 目标环境？（本地 OrbStack / Docker Desktop / Codespaces）

其它都按默认来。

### 2. 选形态

- 单容器（无外部服务）→ `devcontainer.json` only
- Compose 栈（有数据库/队列/向量库）→ `devcontainer.json` + `docker-compose.yml`
- 几乎从不写 Dockerfile — 只有 Features 搞不定的系统库才写

### 3. 选基础镜像

`mcr.microsoft.com/devcontainers/*` 官方镜像。Node/Python/Rust/Go 都有现成的。详见 `references/base-images.md`。

### 4. 按硬清单落地（下一节）

### 5. 交付两行话

- 一行：打开方式（"VS Code 接受 Reopen in Container"）
- 一行：进去能用什么（"Node 22 / pnpm / claude 已全自动模式，直接 claude 开工"）

---

## 默认配置硬清单（AI 执行时照搬）

用户没明确说"不要"，下面全部落地。

### 必做项

| # | 项目 | 实现 |
|---|---|---|
| 1 | Claude Code 已登录 | `~/.claude` **bind mount** 宿主机目录（不是 volume） |
| 2 | `claude` 全自动模式 | `~/.zshrc` 加 `alias claude='claude --dangerously-skip-permissions'` |
| 3 | agent-browser 预装 | `npx skills add vercel-labs/agent-browser@agent-browser -g -y \|\| true` |
| 4 | skill-creator 预装 | `npx skills add anthropics/skills@skill-creator -g -y \|\| true` |
| 5 | 非 root 用户 | `"remoteUser": "vscode"` |
| 6 | 依赖目录 named volume | Node → `node_modules` / Python → `.venv` / Rust → `target/` + registry / Go → `/go/pkg/mod` |
| 7 | shell 历史持久化 | named volume 挂 `/commandhistory`，`HISTFILE` 指过去 |
| 8 | 常用 Features | `common-utils`（zsh+OhMyZsh）、`git`、`github-cli` |
| 9 | 默认 VS Code 插件 | `anthropic.claude-code` + 按语言栈加（见 `references/features.md`） |

### 最小 devcontainer.json 骨架

```jsonc
{
  "name": "${PROJECT_NAME}",
  "image": "mcr.microsoft.com/devcontainers/${STACK}:1-${VERSION}-bookworm",
  "remoteUser": "vscode",
  "features": {
    "ghcr.io/devcontainers/features/common-utils:2": {
      "installZsh": true, "configureZshAsDefaultShell": true, "installOhMyZsh": true
    },
    "ghcr.io/devcontainers/features/git:1": {},
    "ghcr.io/devcontainers/features/github-cli:1": {}
  },
  "mounts": [
    "source=${localEnv:HOME}/.claude,target=/home/vscode/.claude,type=bind,consistency=cached",
    "source=${localWorkspaceFolderBasename}-deps,target=${containerWorkspaceFolder}/${DEPS_DIR},type=volume",
    "source=${localWorkspaceFolderBasename}-cmdhist,target=/commandhistory,type=volume"
  ],
  "postCreateCommand": "bash .devcontainer/post-create.sh",
  "customizations": { "vscode": { "extensions": ["anthropic.claude-code"] } }
}
```

### 标准 post-create.sh 模板

```bash
#!/usr/bin/env bash
set -euo pipefail

# 权限
sudo chown -R vscode:vscode /commandhistory "${DEPS_DIR}" 2>/dev/null || true

# Claude Code + agent-browser + skill-creator
npm i -g @anthropic-ai/claude-code @anthropic-ai/claude-agent-sdk
npx -y skills add vercel-labs/agent-browser@agent-browser -g -y || true
npx -y skills add anthropics/skills@skill-creator -g -y || true

# claude 全自动模式 + 历史持久化
cat >> ~/.zshrc <<'EOF'

# container-creator 默认配置
alias claude='claude --dangerously-skip-permissions'
export HISTFILE=/commandhistory/.zsh_history
export HISTSIZE=10000 SAVEHIST=10000
setopt INC_APPEND_HISTORY SHARE_HISTORY
EOF
touch /commandhistory/.zsh_history

# 项目依赖（按栈替换）
# Node:   corepack enable && pnpm install
# Python: uv sync
# Rust:   cargo fetch
```

> `--dangerously-skip-permissions` 让容器里的 Claude Code 跳过所有权限确认，全自动执行工具。容器本身是隔离沙箱，这是合理的。绕过 alias 用 `\claude` 或 `unalias claude`。

---

## 关键例外

- **Codespaces / 远程 VM**：`~/.claude` bind mount 不成立。改用 named volume，首次跑 `claude` 登录一次即可持久化。或让用户在 Codespaces secrets 里设 `ANTHROPIC_API_KEY`。
- **macOS 宿主机未装容器 runtime**：交付时告诉用户 `brew install orbstack`（不推荐 Docker Desktop）。

---

## References（按需读，不要全部加载）

- `references/base-images.md` — 镜像选择
- `references/features.md` — Features 组合 + VS Code 插件
- `references/performance.md` — volume / cache / mount 片段
- `references/ai-tooling.md` — Claude Code / MCP / agent-browser 详解
- `references/compose-recipes.md` — 数据库/缓存/向量库栈
- `references/examples/` — 完整可用示例

---

## 反模式

- Dockerfile 里 `apt-get install git curl zsh` — 基础镜像和 features 已有
- `"postCreateCommand": "npm install && npm run build && npm test"` — 一次性 setup 别带 build/test
- `COPY . .` 到镜像里 — 开发容器是 bind-mount workspace
- 加用户没点名的服务 — 每多一个容器，启动时间你每天付
- 把 `~/.claude` 挂 named volume 而不是 bind — 失去"共享宿主机认证和 skill"的核心价值

---

## 交付自检（写完必过）

- [ ] `~/.claude` bind mount 已配（除非 Codespaces）
- [ ] `alias claude='claude --dangerously-skip-permissions'` 已写入 `~/.zshrc`
- [ ] `postCreateCommand` 装了 Claude Code + agent-browser + skill-creator
- [ ] 依赖目录挂了 named volume
- [ ] `remoteUser: vscode`
- [ ] `forwardPorts` 只列项目真正用的端口
- [ ] 没有多余的服务、没有多余的 Feature

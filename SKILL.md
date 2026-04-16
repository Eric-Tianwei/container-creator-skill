---
name: container-creator
description: 为新项目生成开箱即用、极速、零配置的 devcontainer — 用户打开即可写代码，Claude Code 已登录、skill 已装、全自动模式。当用户开新项目并提到 "devcontainer / 开发环境 / Docker dev / Codespaces 配置 / 可复现环境"，或说 "帮我把环境搭好 / 我想在容器里开发"，即触发。Also triggers for English like "set up a devcontainer", "scaffold a dev env", "reproducible dev setup". 不用于生产 Dockerfile。
---

# Container Creator

**目标**：用户进容器就能写代码，Claude 在隔离沙箱全自动开发。三条铁律：**开箱即用**（`claude` 已登录+全自动+skills 齐）/ **极速**（OrbStack + 依赖 cache volume + 单 shared volume + `~/.claude` bind）/ **零配置**（只问外部服务和目标环境，不问语言/shell/编辑器）。

---

## 工作流

1. **澄清（≤2 问）**：外部服务？（Postgres/Redis/Qdrant/Ollama/无）目标环境？（OrbStack/Docker Desktop/Codespaces）。**不要问主语言**——默认 `javascript-node:1-22-bookworm` 覆盖 Node/Next/React/md/skill；Python 用 post-create 装的 `uv` 按需拉（`uv python install 3.13`）。唯一例外：用户主动说"纯 Python/Rust/Go"才走 `references/base-images.md` 的 escape hatch。

2. **选形态并照搬 example**（`references/examples/<shape>/` 下已是**完整可用** `.devcontainer/`，直接 `cp -a` 到新项目）：

   > ⚠️ scaffold 是**隐藏目录** `.devcontainer/`（点开头）。用 `ls -la` 才看得到，`ls` / Glob `*` 默认会漏。**必须用 `cp -a references/examples/<shape>/.devcontainer <project>/` 整目录复制**，不要手撸 post-create.sh / init-volumes.sh —— 例子里已处理 linuxbrew 父目录、gitconfig staging cp、`/home/linuxbrew` 坏 symlink 兜底等所有踩过的坑。
   - 无外部服务 → `single-container/`
   - Postgres → `compose-postgres/`
   - Postgres+Redis（Medusa/队列） → `compose-postgres-redis/`
   - 向量库（AI/RAG） → `compose-postgres-vector/`
   - 本地 LLM → `compose-ollama/`

3. **按硬清单核对**（下一节）。

4. **交付两行话**：打开方式（"VS Code 接受 Reopen in Container"）；首跑 ~1.2GB / 30s，进去 `claude` 即用。

**几乎从不写 Dockerfile**——`javascript-node` 已有 Node LTS + pnpm/yarn/npm + git + zsh。只有"要系统库 features 没有"（`libvips`/`ffmpeg` 等）才写。

---

## 硬清单（用户没说"不要"就全落地）

| # | 项目 | 要点 |
|---|---|---|
| 1 | Claude Code 已登录 | **两处都要 bind**：`~/.claude`（目录）+ `~/.claude.json`（文件）。漏挂 `.claude.json` 进去报 "Claude configuration file not found"。**macOS**：`initializeCommand` 里从 Keychain 导出 `~/.claude/.credentials.json`（新版 Claude Code 把 OAuth token 存 Keychain 不存文件，容器读不到 Keychain） |
| 2 | `claude` 全自动 | `~/.zshrc` 加 `alias claude='claude --dangerously-skip-permissions'` |
| 3 | agent-browser + skill-creator 预装 | post-create `npx -y skills add vercel-labs/agent-browser@agent-browser -g -y` 同理 skill-creator |
| 4 | 非 root | `"remoteUser": "vscode"` |
| 5 | **base 默认** | `mcr.microsoft.com/devcontainers/javascript-node:1-22-bookworm` |
| 6 | **uv（Python 按需）** | post-create 装 uv，`UV_INSTALL_DIR=/opt/dcc/uv/bin` |
| 7 | **单 shared volume** | `dcc.shared.node22` → `/opt/dcc`，内部 `linuxbrew/cargo/go/npm-global/bun/pipx/uv/`；post-create 把 `CARGO_HOME/GOPATH/NPM_CONFIG_PREFIX/BUN_INSTALL/PIPX_HOME/UV_INSTALL_DIR` 指进去 + Linuxbrew 软链 |
| 8 | per-project 依赖 cache | `dcc.cache.<proj>.deps` 挂依赖目录（Node→`node_modules`；Python→`.venv`） |
| 9 | per-project shell 历史 | `dcc.proj.<proj>.cmdhistory` → `/commandhistory`，`HISTFILE` 指过去 |
| 10 | Features | `common-utils` + `git` + `github-cli`，按需 `docker-outside-of-docker`。Chromium（agent-browser 依赖）**不走 feature**（`ghcr.io/devcontainers-contrib/features/chromium:1` 已不可用），改在 post-create 里 `sudo apt-get install -y --no-install-recommends chromium` |
| 11 | VS Code 扩展 | `anthropic.claude-code` + eslint/prettier/python/pylance/ruff/even-better-toml/dotenv/gitlens |
| 12 | 透明 wrapper + tools.list | `.devcontainer/bin/tools-wrapper.sh` 劫持 brew/cargo/npm/pipx/go/uv install 自动记录；`install-tools.sh` postCreate 幂等重放 |
| 13 | 项目专用 skill（可选） | `${localWorkspaceFolder}/.claude/skills` bind + 软链进 `~/.claude/skills/` |
| 14 | 依赖同步走 `updateContentCommand` | `pnpm install --frozen-lockfile` / `uv sync` 之类放这里，lockfile 变才跑 |
| 15 | Volume 命名 `dcc.<scope>.<id>` | `dcc.shared.<abi>` / `dcc.proj.<proj>.*` / `dcc.cache.<proj>.*`；`initializeCommand` 预创建并打 label（`com.container-creator.scope/project/abi/created-at`） |
| 16 | git 身份复用 | `.gitconfig` **只读**挂到 `/tmp/host-gitconfig`，post-create 里 `cp` 成本地文件。**不能**直接 bind 到 `~/.gitconfig` |

> 完整可用的 `devcontainer.json` / `post-create.sh` / `init-volumes.sh` / `tools-wrapper.sh` / `install-tools.sh` 全在 `references/examples/<shape>/.devcontainer/`，**照搬即可，不要手撸**。`--dangerously-skip-permissions` 绕过：`\claude` 或 `unalias claude`。

---

## 关键例外

- **Codespaces**：`~/.claude` bind 失效，改 named volume + 首次 `claude` 登录；或 secrets 里 `ANTHROPIC_API_KEY`
- **macOS 无容器 runtime**：告诉用户 `brew install orbstack`（不推荐 Docker Desktop）
- **escape hatch（纯 Py/Rust/Go）**：从 `references/base-images.md` 白名单选；shared volume 名改成 `dcc.shared.<image>-<major>`（`dcc.shared.py313` / `dcc.shared.rust-bookworm` 等），和 node22 自动隔离

---

## 反模式（每条都踩过坑，别重新发明）

- **按语言切 base image**（除非用户主动 escape hatch）——默认 javascript-node + uv 已覆盖 95% 场景
- **把 shared volume 拆 6 个**——治理面 ×6 无性能收益
- **`containerEnv` 里设 `PATH`**——`${containerEnv:PATH}` 只读镜像**显式** `ENV PATH`，MCR 多数镜像无显式声明，替换成空串；PID 1 PATH 没 `sleep`，devcontainer CLI 的 `while sleep 1` 保活循环炸，**容器秒退只报 `sleep: not found`**。PATH 只走 `~/.profile` / `~/.zshrc`
- **`corepack enable` / 写 `/usr/local/{bin,sbin}` 不加 `sudo`**——vscode 没权限，`EACCES`
- **走 escape hatch 脑补 `1-<最新主版本>-bookworm` tag**（如 `1-24-bookworm`）——MCR 发布滞后运行时数月，不在白名单就用 `1-bookworm` 兜底
- **`.gitconfig` 单文件 bind 到 `~/.gitconfig`**——Linux 锁 inode，`git config` 原子 rename 炸 `Device or resource busy`（VS Code 启动时自动注入 credential-helper 必中）。只读挂 staging 再 cp
- **`~/.claude` 挂 named volume 而不是 bind**——失去"共享宿主认证和 skill"的核心价值
- **零散在 devcontainer.json 塞 `npm i -g X && cargo install Y`**——用 `tools.list` + wrapper
- **apt 装开发 CLI（fd/ripgrep/jq）**——用 Linuxbrew（走 shared volume 持久）
- **裸 volume 命名 / cache 不标 `scope=cache`**——必须 `dcc.<scope>.<id>`，否则没法批量 prune
- **`postCreateCommand` 塞 build/test**——一次性 setup 别混业务跑
- **`COPY . .` 到镜像** / **Dockerfile 里 `apt-get install git curl zsh`**——开发容器是 bind-mount workspace，基础镜像和 features 已有
- **手撸 `post-create.sh` / `init-volumes.sh` 而不是 `cp -a` 例子的**——例子里已处理一堆隐式陷阱：`/home/linuxbrew` 父目录不存在 / 是坏 symlink 时的兜底、gitconfig 只读 staging→cp、shared volume chown、env 写 `~/.profile` 而非 `containerEnv`。手撸十有八九漏其中一项，post-create 直接 exit 1

---

## References（按需读）

- `references/examples/<shape>/` — **首选**，完整可用 scaffold
- `references/base-images.md` — escape hatch 白名单
- `references/features.md` / `references/performance.md` / `references/evolution.md` / `references/compose-recipes.md` / `references/ai-tooling.md`

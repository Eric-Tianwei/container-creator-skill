# 性能优化：挂载、缓存、构建

冷重建和启动慢是开发容器用户弃坑的头号原因。

## macOS：OrbStack 优先

macOS 上默认推荐 **OrbStack**（`brew install orbstack`），不是 Docker Desktop。理由：

- VirtioFS 文件同步比 Docker Desktop 的 gRPC-FUSE 快数倍，bind mount 几乎无痛
- 启动速度秒级，空载内存占用小
- 完全兼容 `docker` / `docker compose` CLI 和 devcontainer 规范
- 和 VS Code / Cursor 的 Dev Containers 插件开箱即用

Docker Desktop 依然可用，作为 fallback。

### 文件同步模型

Linux 容器跑在 VM 里，宿主机 ↔ VM 的文件同步是开发体验的核心变量：

- **Bind mount**（`source=${localWorkspaceFolder},target=/workspaces/foo`）是开发容器标配。OrbStack 下对**大量小文件**（`node_modules`、`.git`）已经够快；Docker Desktop 下仍然慢。
- **Named volume** 完全在 VM 里，速度最接近原生，但宿主机看不到里面的内容。

**策略**：workspace 主体永远用 bind mount（方便 VS Code 看源码），依赖目录（`node_modules` / `target/` / `.venv`）用 named volume。即使在 OrbStack 下，named volume 仍有可感知的启动优势，大项目差距尤其明显。

## 挂载拓扑（javascript-node 方案）

单项目稳定状态下只有三类挂载：

### 1. Bind mount（宿主机即真源）

```jsonc
"mounts": [
  "source=${localEnv:HOME}/.claude,target=/home/vscode/.claude,type=bind,consistency=cached",
  "source=${localEnv:HOME}/.claude.json,target=/home/vscode/.claude.json,type=bind,consistency=cached",
  "source=${localEnv:HOME}/.gitconfig,target=/home/vscode/.gitconfig,type=bind,consistency=cached"
]
```

外加 devcontainer 自动 bind 的 `${localWorkspaceFolder} → /workspaces/<repo>`（源码本体）。

`consistency=cached` 告诉 Docker Desktop 容器侧可以延迟同步宿主机的写入。OrbStack 的 VirtioFS 忽略这个标志，留着兼容无害。

### 2. 单 shared volume（跨项目 CLI 工具缓存）

```jsonc
"source=dcc.shared.node22,target=/opt/dcc,type=volume"
```

ABI key（`node22`）和 base image 绑定。走 escape hatch 用其它 base 时改名（`dcc.shared.py313` 等，见 `base-images.md`）。

内部布局：

```
/opt/dcc/
├── linuxbrew/     ← 软链自 /home/linuxbrew/.linuxbrew（brew bottle hardcode 这个 prefix）
├── cargo/         ← CARGO_HOME
├── go/            ← GOPATH
├── npm-global/    ← NPM_CONFIG_PREFIX
├── bun/           ← BUN_INSTALL
├── pipx/          ← PIPX_HOME + PIPX_BIN_DIR
└── uv/            ← UV_INSTALL_DIR + UV_PYTHON_INSTALL_DIR + UV_TOOL_DIR（按需装任意 Python 版本）
```

post-create 里建子目录 + 写 env 变量到 `~/.profile` + 一条 `sudo ln -sfn /opt/dcc/linuxbrew /home/linuxbrew/.linuxbrew`。见 SKILL.md 里的 post-create 模板。

### 3. per-project cache / proj volume

```jsonc
"source=dcc.cache.${localWorkspaceFolderBasename}.deps,target=${containerWorkspaceFolder}/${DEPS_DIR},type=volume",
"source=dcc.proj.${localWorkspaceFolderBasename}.cmdhistory,target=/commandhistory,type=volume"
```

`${DEPS_DIR}` 按项目定：

| 项目形态 | DEPS_DIR | 说明 |
|---|---|---|
| Node（默认 base） | `node_modules` | |
| Python（escape hatch） | `.venv` | uv sync 建在这里 |
| Rust（escape hatch） | `target` | |

**一般一个项目只挂一种依赖目录**。

## Volume 权限坑

Named volume 第一次挂载时属主是 root，容器里跑 `vscode` 用户写不进去。post-create 里统一 chown：

```bash
sudo chown -R vscode:vscode /opt/dcc /commandhistory "${DEPS_DIR}" 2>/dev/null || true
```

## Shell 历史持久化

用 `dcc.proj.<proj>.cmdhistory` volume 挂 `/commandhistory`，然后在 `~/.zshrc`：

```bash
export HISTFILE=/commandhistory/.zsh_history
export HISTSIZE=10000 SAVEHIST=10000
setopt INC_APPEND_HISTORY SHARE_HISTORY
```

`touch /commandhistory/.zsh_history` 保证文件存在。

## BuildKit cache mount（仅当写 Dockerfile）

自定义 Dockerfile 时，apt / npm / pip / cargo 缓存一定要用 cache mount，不然每次改 Dockerfile 都要重下：

```dockerfile
# syntax=docker/dockerfile:1.4
FROM mcr.microsoft.com/devcontainers/javascript-node:1-22-bookworm

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    libvips-dev \
    && rm -rf /var/lib/apt/lists/*
```

第一行 `# syntax=` 启用 BuildKit 语法。现代 Docker 默认启用 BuildKit，这行是保险。

## postCreate vs postStart vs onCreate vs updateContent

| 钩子 | 何时跑 | 用来做什么 |
|---|---|---|
| `onCreateCommand` | 镜像构建后、容器第一次创建前 | 建目录结构、seed 数据 |
| `postCreateCommand` | 容器第一次创建后 | 装 Claude Code、配 alias、写 ~/.profile |
| `updateContentCommand` | 仓库内容更新后（pull / rebase / 切分支） | `pnpm install --frozen-lockfile` 之类依赖同步 |
| `postStartCommand` | 每次容器启动（包括 resume） | 起后台服务、打印欢迎 |
| `postAttachCommand` | 每次 VS Code attach | 显示 TODO、欢迎信息 |

**常见错误**：把 `npm install` 塞进 postStartCommand，每次启动容器都跑一遍。应该放 `updateContentCommand`——只在 lockfile 变更后触发。

## Prebuild（可选）

GitHub 仓库会在 Codespaces 用，强烈推荐 prebuild：

1. GitHub 仓库 → Settings → Codespaces → Set up prebuild
2. 选 `.devcontainer/devcontainer.json`
3. 触发条件选 "on push to main"

效果：打开 Codespace 从 2-5 分钟降到 10 秒。

本地也可以提前 build：

```bash
npx @devcontainers/cli build --workspace-folder .
```

## 实测参考时间

javascript-node base + `node_modules` 用 per-project cache volume + shared volume 已预装常用 CLI，Mac M3 + OrbStack：

- **首次 pull 镜像**（一次性）：约 30 秒
- **之后每个新项目首次 create**：约 30-60 秒（镜像缓存命中，只跑 postCreate）
- **二次打开同项目**：约 5-10 秒
- **只改源码重启容器**：约 3-5 秒

如果你的配置比这慢很多，大概率是：
- `node_modules` 没走 per-project cache volume
- postCreateCommand 里塞了 build/test
- 装了太多 features
- 镜像被手动 prune 过，每次要重拉

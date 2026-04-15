# 性能优化：挂载、缓存、构建

冷重建和启动慢是开发容器用户弃坑的头号原因。这份文档给出可直接复制的配置。

## macOS：OrbStack 优先

macOS 上默认推荐 **OrbStack**（`brew install orbstack`），不是 Docker Desktop。理由：

- VirtioFS 文件同步比 Docker Desktop 的 gRPC-FUSE 快数倍，bind mount 几乎无痛
- 启动速度秒级，空载内存占用小
- 完全兼容 `docker` / `docker compose` CLI 和 devcontainer 规范
- 和 VS Code / Cursor 的 Dev Containers 插件开箱即用

Docker Desktop 依然可用，但作为 fallback 推荐给已经在用它的用户。

### 文件同步模型

Linux 容器跑在 VM 里，宿主机 ↔ VM 的文件同步是开发体验的核心变量：

- **Bind mount**（`source=${localWorkspaceFolder},target=/workspaces/foo`）是开发容器标配。OrbStack 下对**大量小文件**（`node_modules`、`.git`）已经够快；Docker Desktop 下仍然慢。
- **Named volume** 完全在 VM 里，速度最接近原生，但宿主机看不到里面的内容。

**策略**：workspace 主体永远用 bind mount（方便 VS Code 看源码），依赖目录（`node_modules` / `target/` / `.venv`）用 named volume — 即使在 OrbStack 下，named volume 仍有可感知的启动优势，大项目差距尤其明显。

## 依赖目录的 named volume 配置

按语言栈挂：

### Node

```jsonc
"mounts": [
  "source=${localWorkspaceFolderBasename}-node_modules,target=${containerWorkspaceFolder}/node_modules,type=volume"
]
```

`${localWorkspaceFolderBasename}` 是仓库目录名，保证不同项目的 volume 互不干扰。

### Python (venv)

```jsonc
"mounts": [
  "source=${localWorkspaceFolderBasename}-venv,target=${containerWorkspaceFolder}/.venv,type=volume"
]
```

或者不在项目里建 venv，而是用 uv 的全局缓存：

```jsonc
"containerEnv": {
  "UV_CACHE_DIR": "/home/vscode/.cache/uv"
},
"mounts": [
  "source=uv-cache,target=/home/vscode/.cache/uv,type=volume"
]
```

### Rust

```jsonc
"mounts": [
  "source=${localWorkspaceFolderBasename}-cargo-target,target=${containerWorkspaceFolder}/target,type=volume",
  "source=cargo-registry,target=/usr/local/cargo/registry,type=volume"
]
```

第二个是**跨项目**的共享 registry 缓存，不带 basename，所有 Rust 项目复用。

### Go

```jsonc
"mounts": [
  "source=go-mod-cache,target=/go/pkg/mod,type=volume"
]
```

同样是跨项目共享。

## Volume 权限坑

Named volume 第一次挂载时属主是 root，但容器里默认跑 `vscode` 用户，写不进去。两种解法：

### 方案 A：postCreateCommand 里 chown

```bash
sudo chown -R vscode:vscode node_modules
```

### 方案 B：initializeCommand 提前建好

```jsonc
"initializeCommand": "docker volume create ${localWorkspaceFolderBasename}-node_modules >/dev/null 2>&1 || true",
"postCreateCommand": "sudo chown vscode:vscode node_modules && npm install"
```

推荐方案 A，更简单。

## Shell 历史持久化

每次重建容器都清零 shell 历史很伤。挂一个独立 volume 存历史：

```jsonc
"mounts": [
  "source=${localWorkspaceFolderBasename}-cmdhistory,target=/commandhistory,type=volume"
]
```

然后在 postCreateCommand 里：

```bash
mkdir -p /commandhistory
touch /commandhistory/.zsh_history
echo "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.zsh_history" >> ~/.zshrc
```

## BuildKit cache mount（仅当写 Dockerfile）

如果你写了自定义 Dockerfile，apt / npm / pip / cargo 的缓存一定要用 cache mount，不然每次改 Dockerfile 都要重下：

```dockerfile
# syntax=docker/dockerfile:1.4
FROM mcr.microsoft.com/devcontainers/python:1-3.13-bookworm

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-compile torch transformers
```

注意第一行的 `# syntax=` 启用 BuildKit 语法。现代 Docker 默认启用 BuildKit，这行是保险。

## postCreate vs postStart vs onCreate

| 钩子 | 何时跑 | 用来做什么 |
|---|---|---|
| `onCreateCommand` | 镜像构建后、容器第一次创建前 | 建目录结构、seed 数据 |
| `postCreateCommand` | 容器第一次创建后 | 装依赖、初始化 git hooks、下载模型 |
| `postStartCommand` | 每次容器启动（包括 resume） | 起后台服务、打印欢迎 |
| `postAttachCommand` | 每次 VS Code attach | 显示 TODO、欢迎信息 |

**常见错误**：把 `npm install` 塞进 postStartCommand，每次启动容器都跑一遍。应该放 postCreateCommand。

## Prebuild（可选）

如果仓库会在 GitHub Codespaces 用，强烈推荐 prebuild：

1. GitHub 仓库 → Settings → Codespaces → Set up prebuild
2. 选 `.devcontainer/devcontainer.json`
3. 触发条件选 "on push to main"

效果：打开 Codespace 从 2-5 分钟降到 10 秒。个人项目完全够用 free tier。

本地也可以提前 build：

```bash
npx @devcontainers/cli build --workspace-folder .
```

## 实测参考时间

以 Next.js + `node_modules` named volume + Claude Code 预装为例，Mac M3 + OrbStack：

- 首次创建（含镜像 pull）：约 90 秒
- 二次打开（镜像已拉）：约 15 秒
- 只改源码重启容器：约 5 秒

如果你的配置比这慢很多，大概率是：
- `node_modules` 没走 named volume
- postCreateCommand 里塞了 build/test
- 装了太多 features

# Devcontainer Features 参考

Features 是写在 `devcontainer.json` 的 `"features"` 字段里的可组合包，每个 feature 在容器构建时安装一组工具。比自己在 Dockerfile 里 `apt-get` 好的点：

- 顺序无关（features 会按依赖图解析）
- 官方维护，CVE 跟进
- 可以带参数

官方目录：<https://containers.dev/features>

## 新项目默认三件套

任何项目都直接放：

```jsonc
"features": {
  "ghcr.io/devcontainers/features/common-utils:2": {
    "installZsh": true,
    "configureZshAsDefaultShell": true,
    "installOhMyZsh": true,
    "username": "vscode"
  },
  "ghcr.io/devcontainers/features/git:1": {},
  "ghcr.io/devcontainers/features/github-cli:1": {}
}
```

Claude Code 不作为 feature 装，通过 postCreateCommand 的 `npm i -g @anthropic-ai/claude-code` 装，这样和 skills、settings 的挂载解耦。

## 按需追加（只有真用到才加）

### Docker / Compose（项目本身起容器）

```jsonc
"ghcr.io/devcontainers/features/docker-outside-of-docker:1": {}
```

把宿主机的 docker socket 挂进来，容器里 `docker` 实际操作宿主机。**别用** `docker-in-docker`（DinD），除非真的需要隔离——慢、费资源、权限配起来痛苦。

### Kubernetes 本地开发

```jsonc
"ghcr.io/devcontainers/features/kubectl-helm-minikube:1": {}
```

### 云 CLI（按需）

```jsonc
"ghcr.io/devcontainers/features/aws-cli:1": {},
"ghcr.io/devcontainers/features/azure-cli:1": {},
"ghcr.io/dhoeric/features/google-cloud-cli:1": {}
```

Vercel CLI / Supabase CLI / 等走 `npm i -g`，不做 feature。

## 不需要加的 features

默认 base = `javascript-node`，shared volume + tools.list 已经覆盖：

- ❌ Node / pnpm / yarn / bun feature — 镜像自带 + bun 由 post-create 装到 `/opt/dcc/bun`
- ❌ Python feature — debian 自带 `python3`，深度 Python 用 `uv python install`
- ❌ Rust / Go feature — 通过 shared volume（`/opt/dcc/cargo`、`/opt/dcc/go`）按需装
- ❌ 装完立刻要的 CLI（fd、ripgrep、jq）— 写进 `.devcontainer/tools.list`，由 install-tools.sh 经 Linuxbrew 装

## 公共 VS Code 扩展集（全装，体积轻）

```jsonc
"customizations": {
  "vscode": {
    "extensions": [
      "anthropic.claude-code",
      "dbaeumer.vscode-eslint",
      "esbenp.prettier-vscode",
      "ms-python.python",
      "ms-python.vscode-pylance",
      "charliermarsh.ruff",
      "tamasfe.even-better-toml",
      "mikestead.dotenv",
      "eamodio.gitlens",
      "EditorConfig.EditorConfig",
      "usernamehw.errorlens"
    ]
  }
}
```

按项目按需加：

| 场景 | 扩展 |
|---|---|
| Tailwind / Next.js | `bradlc.vscode-tailwindcss` |
| Rust（走 escape hatch） | `rust-lang.rust-analyzer` |
| Go（走 escape hatch） | `golang.go` |
| Docker 项目 | `ms-azuretools.vscode-docker` |

扩展是 MB 级，启动无感。全装换零配置，划算。

## Anti-pattern

- 把所有 feature 都加上 — 每个 feature 都增加构建时间，按需加
- 用 feature 装 Node 然后还 `npm i -g` 装一遍 — 冲突
- 在 Dockerfile 里装 zsh 然后再用 common-utils feature — 重复
- 用 feature 装 CLI（fd / ripgrep / jq 等） — 走 `tools.list` + Linuxbrew 更轻、可持久化

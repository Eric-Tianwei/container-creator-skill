# Devcontainer Features 参考

Features 是写在 `devcontainer.json` 的 `"features"` 字段里的可组合包，每个 feature 在容器构建时安装一组工具。比自己在 Dockerfile 里 `apt-get` 好的点：

- 顺序无关（features 会按依赖图解析）
- 官方维护，CVE 跟进
- 可以带参数（例如 Node 版本、Python 版本）

官方目录：<https://containers.dev/features>

## 新项目默认四件套

任何语言的新项目都可以直接把这四个放进去：

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

（Claude Code 不作为 feature 装，通过 postCreateCommand 的 `npm i -g @anthropic-ai/claude-code` 装，这样可以和 skills、settings 的挂载解耦。）

## 按栈追加

### Node / Frontend

基础镜像已经带 Node，但 pnpm / yarn / bun 要额外加：

```jsonc
"ghcr.io/devcontainers-contrib/features/pnpm:2": {},
"ghcr.io/devcontainers-contrib/features/bun:1": {}
```

或者用 `corepack enable` 在 postCreateCommand 里直接开 pnpm/yarn（Node 18+ 自带 corepack，不需要 feature）：

```json
"postCreateCommand": "corepack enable && corepack prepare pnpm@latest --activate"
```

### Python

基础镜像带 Python + pip。推荐再装 uv（快得多）：

```jsonc
"ghcr.io/va-h/devcontainers-features/uv:1": {}
```

或者 postCreateCommand 里：

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

### Docker / Kubernetes

项目本身会起容器（测试、集成、Compose）才装：

```jsonc
"ghcr.io/devcontainers/features/docker-outside-of-docker:1": {}
```

这个 feature 会把宿主机的 docker socket 挂进来，容器里 `docker` 命令实际操作的是宿主机。**别用** `docker-in-docker`（DinD），除非真的需要隔离 — 慢、费资源、权限配起来痛苦。

K8s 开发用 kind / minikube：

```jsonc
"ghcr.io/devcontainers/features/kubectl-helm-minikube:1": {}
```

### 云 CLI

按需加：

```jsonc
"ghcr.io/devcontainers/features/aws-cli:1": {},
"ghcr.io/devcontainers/features/azure-cli:1": {},
"ghcr.io/dhoeric/features/google-cloud-cli:1": {}
```

Vercel CLI 不做成 feature 更直接：`npm i -g vercel`。

## 常见组合

### Next.js + AI 应用

```jsonc
"image": "mcr.microsoft.com/devcontainers/javascript-node:1-22-bookworm",
"features": {
  "ghcr.io/devcontainers/features/common-utils:2": { "installZsh": true, "configureZshAsDefaultShell": true, "installOhMyZsh": true },
  "ghcr.io/devcontainers/features/git:1": {},
  "ghcr.io/devcontainers/features/github-cli:1": {}
},
"postCreateCommand": "corepack enable && npm i -g @anthropic-ai/claude-code vercel && bash .devcontainer/post-create.sh"
```

### FastAPI + Postgres

见 `compose-recipes.md`（Compose 栈）。

### Rust CLI

```jsonc
"image": "mcr.microsoft.com/devcontainers/rust:1-bookworm",
"features": {
  "ghcr.io/devcontainers/features/common-utils:2": { "installZsh": true, "configureZshAsDefaultShell": true, "installOhMyZsh": true },
  "ghcr.io/devcontainers/features/github-cli:1": {}
},
"postCreateCommand": "cargo install cargo-watch cargo-nextest && npm i -g @anthropic-ai/claude-code"
```

## VS Code 插件（customizations.vscode.extensions）

Features 装 CLI，`customizations` 装编辑器插件。AI-Native 开发者的默认集：

```jsonc
"customizations": {
  "vscode": {
    "extensions": [
      "anthropic.claude-code",
      "GitHub.copilot-chat",
      "eamodio.gitlens",
      "EditorConfig.EditorConfig",
      "usernamehw.errorlens",
      "mikestead.dotenv"
    ]
  }
}
```

按栈加：

| 栈 | 插件 ID |
|---|---|
| TypeScript / JS | `dbaeumer.vscode-eslint`, `esbenp.prettier-vscode` |
| Python | `ms-python.python`, `ms-python.vscode-pylance`, `charliermarsh.ruff` |
| Rust | `rust-lang.rust-analyzer`, `tamasfe.even-better-toml` |
| Go | `golang.go` |
| Docker | `ms-azuretools.vscode-docker` |
| Tailwind | `bradlc.vscode-tailwindcss` |

## Anti-pattern

- 把所有 feature 都加上 — 每个 feature 都增加构建时间，按需加
- 用 feature 装 Node 然后还 apt-get install node — 冲突
- 在 Dockerfile 里装 zsh 然后再用 common-utils feature — 重复

# single-container 示例

**适用：** 无外部服务。覆盖：

- Node / TypeScript 脚本、CLI 工具、npm 包开发
- Next.js / React 前端应用（数据库由 hosted 服务提供，例如 Supabase / PlanetScale）
- Python 脚本（`uv run` / `uv python install` 按需拿运行时）
- skill 编辑 / md 写作仓库

## 特征

- 单容器，无 Compose
- Base: `javascript-node:1-22-bookworm` + post-create 装 uv
- 无默认 `forwardPorts`（Next.js 项目加 `3000`；脚本不需要）
- 硬清单全部条目：`~/.claude` bind、`claude` 全自动、agent-browser、skill-creator、tools.list、单 shared volume `/opt/dcc`

## 直接使用

```bash
cp -r .devcontainer/ /path/to/your/new-project/
cd /path/to/your/new-project
# 在 VS Code / Cursor 打开，接受 "Reopen in Container"
```

进容器后直接 `claude` 开工。

加 CLI：`brew install <name>` / `cargo install <name>` / `npm i -g <name>` / `uv tool install <name>`，透明 wrapper 自动记录到 `tools.list`。

Python 版本：`uv python install 3.13`（装到 `/opt/dcc/uv/python`，持久）。

## Next.js 项目的 tweak

在 `devcontainer.json` 加：

```jsonc
"forwardPorts": [3000],
"portsAttributes": {
  "3000": { "label": "Next.js", "onAutoForward": "openPreview" }
}
```

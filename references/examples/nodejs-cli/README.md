# nodejs-cli 示例

**适用：** 纯 Node.js / TypeScript 脚本或 CLI 工具开发。无 UI、无数据库、无外部服务。

## 特征

- 单容器（无 Compose）
- Node 22 LTS（bookworm）+ pnpm（corepack）
- 无 forwardPorts（脚本不监听端口；需要时用户自己加）
- 包含默认硬清单全部条目（~/.claude bind、claude 全自动、agent-browser、tools.list、user volume、Linuxbrew）

## 直接使用

```bash
cp -r .devcontainer/ /path/to/your/new-project/
cd /path/to/your/new-project
# 在 VS Code / Cursor 打开，接受 "Reopen in Container"
```

进容器后直接 `claude` 开工。加新 CLI 用 `brew install <name>` / `cargo install <name>` / `npm i -g <name>`，自动记录到 `tools.list`。

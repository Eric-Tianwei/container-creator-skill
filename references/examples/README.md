# 示例目录

按项目类型挑一份完整 `.devcontainer/` 直接复制到你的仓库根目录即可使用。

| 示例 | 适用 | 形态 | 外部服务 |
|---|---|---|---|
| `nodejs-cli/` | Node/TS 脚本、CLI 工具、npm 包开发（含 Bun） | 单容器 | 无 |
| `nextjs-web/` | Next.js 网站 / 前端应用（含 Bun） | 单容器 | 无 |
| `python-cli/` | Python 3.13 脚本 / CLI（uv + pipx） | 单容器 | 无 |
| `medusa/` | Medusa 电商（Next.js storefront + backend CLI，含 Bun） | Compose 栈 | Postgres 16 + Redis 7 |

每份都已落地硬清单全部条目：`~/.claude` bind mount、`claude --dangerously-skip-permissions` alias、agent-browser + skill-creator 预装、`dcc.*` volume 命名、`initializeCommand` 预打 label、透明 wrapper + tools.list、user-level CLI volume、Linuxbrew。

复制后流程（以 medusa 为例）：

```bash
cp -r references/examples/medusa/.devcontainer/ /path/to/my-shop/
cd /path/to/my-shop
# VS Code / Cursor 打开，接受 "Reopen in Container"
```

macOS 用户先装 [OrbStack](https://orbstack.dev/)（`brew install orbstack`），比 Docker Desktop 快很多。

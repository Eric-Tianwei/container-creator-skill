# 示例目录（按项目形态分）

按**项目形态**挑示例，不按语言。所有示例 base image 统一为 `javascript-node:1-22-bookworm`（覆盖 Node/Next/React/skill/md；Python 走 uv；其它语言走 `references/base-images.md` 的 escape hatch）。

| 示例 | 适用 | 外部服务 |
|---|---|---|
| `single-container/` | 纯脚本 / CLI / Next.js / React / skill 编辑 / md 仓库 | 无 |
| `compose-postgres/` | 大多数 web app（带数据库） | Postgres 17 |
| `compose-postgres-redis/` | Medusa、队列驱动、会话缓存 | Postgres 17 + Redis 7 |
| `compose-postgres-vector/` | AI 应用（RAG / embeddings） | Postgres 17 + Qdrant |
| `compose-ollama/` | 本地 LLM 实验 | Ollama（M 系列 Mac 建议跑宿主机，见文） |

每份都落地硬清单全部条目：`~/.claude` bind mount、`claude --dangerously-skip-permissions` alias、agent-browser + skill-creator 预装、`dcc.*` volume 命名、`initializeCommand` 预打 label、透明 wrapper + tools.list、单 shared volume `/opt/dcc`、uv 按需 Python。

复制后流程：

```bash
cp -r references/examples/compose-postgres/.devcontainer/ /path/to/my-app/
cd /path/to/my-app
# VS Code / Cursor 打开，接受 "Reopen in Container"
```

macOS 用户先装 [OrbStack](https://orbstack.dev/)（`brew install orbstack`），比 Docker Desktop 快很多。

## 选形态的决策树

```
有外部服务吗？
├─ 无 → single-container
└─ 有
   ├─ 只要数据库 → compose-postgres
   ├─ 要队列/缓存/Medusa → compose-postgres-redis
   ├─ 要向量搜索 → compose-postgres-vector
   └─ 要本地 LLM → compose-ollama
```

多个组合需求（例如 Postgres + Redis + Qdrant）时，从最接近的示例复制，按 `compose-recipes.md` 补 service。

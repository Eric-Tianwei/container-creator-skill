# compose-postgres 示例

**适用：** 项目需要一个 Postgres。大多数 web app（Rails/Django/FastAPI/Next.js + Prisma 等）。

## 关键点

- `devcontainer.json` 引用 `docker-compose.yml`，`service: app`
- app service base = `javascript-node:1-22-bookworm`（Python 项目走 uv，不换 base）
- db service = `postgres:17-alpine`（named volume `postgres-data` 保留数据）
- app 连接串：`postgres://postgres:postgres@db:5432/app`（服务名通信，不走 localhost）
- 端口：`forwardPorts: [3000, 5432]`（5432 仅为宿主机连 psql 方便；不需要可删）

## docker-compose.yml 片段

```yaml
services:
  app:
    image: mcr.microsoft.com/devcontainers/javascript-node:1-22-bookworm
    volumes:
      - ../..:/workspaces:cached
      - ${HOME}/.claude:/home/vscode/.claude
      - ${HOME}/.claude.json:/home/vscode/.claude.json
      - ${HOME}/.gitconfig:/home/vscode/.gitconfig
      - dcc.shared.node22:/opt/dcc
      - dcc-cache-deps:/workspaces/${PROJECT_DIR}/node_modules
      - dcc-proj-cmdhist:/commandhistory
    command: sleep infinity
    depends_on: [db]
    environment:
      DATABASE_URL: postgres://postgres:postgres@db:5432/app

  db:
    image: postgres:17-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: app
    volumes:
      - postgres-data:/var/lib/postgresql/data

volumes:
  dcc.shared.node22:
    external: true
  dcc-cache-deps:
  dcc-proj-cmdhist:
  postgres-data:
```

post-create 里在装完 uv / bun / claude 之后跑迁移：

```bash
# 按 ORM 替换
# Prisma:  pnpm prisma migrate deploy
# Drizzle: pnpm drizzle-kit push
# Django:  uv run python manage.py migrate
```

见 `compose-recipes.md` 的完整片段和多服务组合。

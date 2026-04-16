# compose-postgres-redis 示例

**适用：** Medusa、BullMQ / 队列驱动项目、会话缓存项目。

## 新增 service（在 `compose-postgres` 基础上）

```yaml
  redis:
    image: redis:7-alpine
    restart: unless-stopped
    command: redis-server --appendonly yes
    volumes:
      - redis-data:/data

volumes:
  redis-data:
```

app 新增环境变量：

```yaml
environment:
  REDIS_URL: redis://redis:6379
```

`depends_on: [db, redis]`。

## Medusa 专属

Medusa backend 默认端口 9000（admin UI 走 9000/app），storefront 常跑 8000。

```jsonc
"forwardPorts": [9000, 8000, 5432],
"portsAttributes": {
  "9000": { "label": "Medusa backend" },
  "8000": { "label": "Storefront" }
}
```

post-create 里：

```bash
# Medusa CLI
sudo corepack enable
pnpm install
pnpm medusa db:migrate
pnpm medusa user -e admin@example.com -p supersecret || true
```

Medusa 强推 Bun（启动快）：post-create 已装 bun 到 `/opt/dcc/bun`，直接 `bun run dev`。

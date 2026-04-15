# Docker Compose 配方

当项目需要外部服务（Postgres / Redis / 队列 / 向量库）时，用 Compose。`devcontainer.json` 引用 `docker-compose.yml`，IDE 会连进 `service` 指定的那个容器，其他服务作为依赖一起起。

## 基本骨架

```yaml
# .devcontainer/docker-compose.yml
services:
  app:
    build:
      context: ..
      dockerfile: .devcontainer/Dockerfile
    # 或者直接用 image，不写 Dockerfile：
    # image: mcr.microsoft.com/devcontainers/javascript-node:1-22-bookworm
    volumes:
      - ../..:/workspaces:cached
      - ${HOME}/.claude:/home/vscode/.claude
      - node_modules:/workspaces/${PROJECT_DIR}/node_modules
    command: sleep infinity
    network_mode: service:db  # 或者 depends_on，见下

volumes:
  node_modules:
```

```jsonc
// .devcontainer/devcontainer.json
{
  "name": "my-project",
  "dockerComposeFile": "docker-compose.yml",
  "service": "app",
  "workspaceFolder": "/workspaces/${localWorkspaceFolderBasename}",
  "remoteUser": "vscode",
  "postCreateCommand": "bash .devcontainer/post-create.sh"
}
```

## Postgres

```yaml
services:
  app:
    # ... 见上
    depends_on:
      - db
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
    ports:
      - "5432:5432"  # 可选，想从宿主机 psql 连就加

volumes:
  postgres-data:
```

## Redis

```yaml
  redis:
    image: redis:7-alpine
    restart: unless-stopped
    volumes:
      - redis-data:/data
    command: redis-server --appendonly yes
```

app 连接串：`redis://redis:6379`

## Qdrant（向量库）

```yaml
  qdrant:
    image: qdrant/qdrant:latest
    restart: unless-stopped
    volumes:
      - qdrant-data:/qdrant/storage
    ports:
      - "6333:6333"
```

## Ollama（本地 LLM）

```yaml
  ollama:
    image: ollama/ollama:latest
    restart: unless-stopped
    volumes:
      - ollama-data:/root/.ollama
    ports:
      - "11434:11434"
    # 如果宿主机有 NVIDIA GPU：
    # deploy:
    #   resources:
    #     reservations:
    #       devices:
    #         - driver: nvidia
    #           count: all
    #           capabilities: [gpu]
```

M 系列 Mac：Ollama 装在宿主机更快（可以用 Metal），别塞进容器。让 app 连 `host.docker.internal:11434`。

## MinIO（S3 兼容对象存储）

```yaml
  minio:
    image: minio/minio:latest
    restart: unless-stopped
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadmin
    volumes:
      - minio-data:/data
    ports:
      - "9000:9000"
      - "9001:9001"  # Web 控制台
```

## Meilisearch / Typesense（全文搜索）

```yaml
  meilisearch:
    image: getmeili/meilisearch:latest
    environment:
      MEILI_MASTER_KEY: dev-master-key
    volumes:
      - meili-data:/meili_data
    ports:
      - "7700:7700"
```

## 组合示例：Next.js + Postgres + Redis + Qdrant

```yaml
services:
  app:
    image: mcr.microsoft.com/devcontainers/javascript-node:1-22-bookworm
    volumes:
      - ../..:/workspaces:cached
      - ${HOME}/.claude:/home/vscode/.claude
      - node_modules:/workspaces/my-app/node_modules
    command: sleep infinity
    depends_on:
      - db
      - redis
      - qdrant
    environment:
      DATABASE_URL: postgres://postgres:postgres@db:5432/app
      REDIS_URL: redis://redis:6379
      QDRANT_URL: http://qdrant:6333

  db:
    image: postgres:17-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: app
    volumes:
      - postgres-data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    volumes:
      - redis-data:/data

  qdrant:
    image: qdrant/qdrant:latest
    volumes:
      - qdrant-data:/qdrant/storage

volumes:
  node_modules:
  postgres-data:
  redis-data:
  qdrant-data:
```

## forwardPorts

在 `devcontainer.json` 里声明要转发到宿主机的端口：

```jsonc
"forwardPorts": [3000, 5432, 6333],
"portsAttributes": {
  "3000": { "label": "Next.js", "onAutoForward": "openPreview" },
  "5432": { "label": "Postgres" },
  "6333": { "label": "Qdrant" }
}
```

只转发**开发时要用**的端口，不要把所有服务端口都 forward。

## 原则

- **默认不加持久端口映射**（`ports:`），用 `forwardPorts` 让 IDE 按需转发，避免冲突
- **服务间通信走服务名**（`db`、`redis`），不要走 localhost
- **数据用 named volume**，别 bind mount 到仓库里（会污染 git）
- **不要加 adminer / pgadmin / redis-commander 之类的 GUI**，IDE 有数据库插件，多一层容器浪费启动时间

# compose-postgres-vector 示例

**适用：** RAG / embeddings / 语义搜索类 AI 应用。

## 两种向量方案

### 方案 A：Qdrant（独立向量库，简单）

```yaml
  qdrant:
    image: qdrant/qdrant:latest
    restart: unless-stopped
    volumes:
      - qdrant-data:/qdrant/storage

volumes:
  qdrant-data:
```

app 环境变量：`QDRANT_URL: http://qdrant:6333`

`forwardPorts: [3000, 6333]`（6333 是 Qdrant 默认 HTTP）。

### 方案 B：pgvector（Postgres 扩展，一个服务搞定）

把 `db` service 镜像换成：

```yaml
  db:
    image: pgvector/pgvector:pg17
    # 其它不变
```

post-create 首次跑时启用扩展：

```bash
psql "$DATABASE_URL" -c 'CREATE EXTENSION IF NOT EXISTS vector;'
```

## 选哪个

- 数据量小、已有 Postgres、想少一个服务 → **pgvector**
- 向量是主要工作负载、需要 HNSW 高级参数、多租户 → **Qdrant**

## Embedding 模型

容器里跑 embedding 模型会慢（除非 GPU）。推荐：

- 走托管 API（OpenAI / Voyage / Cohere）
- 或者本地 Ollama（见 `compose-ollama`），app 通过 `host.docker.internal:11434` 连宿主机 Ollama（M 系列 Mac 能用 Metal 加速）

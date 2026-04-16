# compose-ollama 示例

**适用：** 本地跑 LLM（无外部 API 依赖、隐私敏感数据、offline）。

## 重要：M 系列 Mac 推荐跑宿主机 Ollama

容器里的 Ollama **用不了 Metal**，CPU 推理慢 10-20 倍。在 Apple Silicon 上：

1. 宿主机 `brew install ollama`，`ollama serve` 起后台
2. 容器里连 `http://host.docker.internal:11434`
3. `docker-compose.yml` **不加** ollama service，只通过环境变量给 app：

```yaml
services:
  app:
    # ... 其它配置
    environment:
      OLLAMA_BASE_URL: http://host.docker.internal:11434
    extra_hosts:
      - "host.docker.internal:host-gateway"  # Linux 宿主机才需要；macOS 自动有
```

## Linux 宿主机 + NVIDIA GPU 才把 Ollama 塞容器里

```yaml
  ollama:
    image: ollama/ollama:latest
    restart: unless-stopped
    volumes:
      - ollama-data:/root/.ollama
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]

volumes:
  ollama-data:
```

app 环境变量：`OLLAMA_BASE_URL: http://ollama:11434`。

## 常用模型首跑

进容器后：

```bash
# 走宿主机 Ollama
curl http://host.docker.internal:11434/api/pull -d '{"name":"llama3.2:3b"}'
curl http://host.docker.internal:11434/api/pull -d '{"name":"nomic-embed-text"}'
```

或直接在宿主机 `ollama pull llama3.2:3b`。

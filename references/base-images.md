# 基础镜像选择

## 默认：javascript-node

```
mcr.microsoft.com/devcontainers/javascript-node:1-22-bookworm
```

内置：

- Node 22 LTS + npm / yarn / pnpm（corepack）
- 非 root 用户 `vscode`
- git、zsh、curl、build-essential
- debian bookworm 自带的 `python3`（够跑脚本；要正经 Python 项目走 `uv python install`）

体积 ~1.2GB。首次 pull M3 + OrbStack 约 30 秒。

**为什么默认是它：**

- 覆盖 Node / Next.js / React / skill 编辑 / md（skills 是 npm 包，需要 Node）
- Python 用 `uv`（post-create 装好）按需拿：`uv python install 3.13` 把任意 Python 版本装进 shared volume，秒级
- 单一 base = 单一 tag = 消除脑补风险
- 单一 ABI key（`dcc.shared.node22`）跨项目共享 CLI 工具，不冲突

---

## Escape hatch：单语言镜像白名单

走 escape hatch 的触发条件：**用户主动说"这是纯 Python / Rust / Go / Java / Ruby 项目"**，或"要最小镜像/只装一种语言"。

**铁律**：tag 只能从下表选，或用 rolling 兜底（`1-bookworm`）。**不要自己按"运行时最新主版本"脑补 tag**（例如 Node 24 进入 LTS ≠ MCR 有 `1-24-bookworm`）。MCR 镜像发布通常滞后运行时数月，脑补的 tag 90% 不存在。

| 场景 | 已验证 tag | shared volume 名 |
|---|---|---|
| Node 20（老项目） | `mcr.microsoft.com/devcontainers/javascript-node:1-20-bookworm` | `dcc.shared.node20` |
| Python 3.13 | `mcr.microsoft.com/devcontainers/python:1-3.13-bookworm` | `dcc.shared.py313` |
| Python 3.12 | `mcr.microsoft.com/devcontainers/python:1-3.12-bookworm` | `dcc.shared.py312` |
| Python（不确定版本） | `mcr.microsoft.com/devcontainers/python:1-bookworm` | `dcc.shared.py-bookworm` |
| Rust | `mcr.microsoft.com/devcontainers/rust:1-bookworm` | `dcc.shared.rust-bookworm` |
| Go | `mcr.microsoft.com/devcontainers/go:1-bookworm` | `dcc.shared.go-bookworm` |
| Java | `mcr.microsoft.com/devcontainers/java:1-21-bookworm` | `dcc.shared.java21` |
| Ruby | `mcr.microsoft.com/devcontainers/ruby:1-3-bookworm` | `dcc.shared.ruby3` |
| C++ | `mcr.microsoft.com/devcontainers/cpp:1-bookworm` | `dcc.shared.cpp-bookworm` |
| 极简底座 | `mcr.microsoft.com/devcontainers/base:1-bookworm` | `dcc.shared.base-bookworm` |

**规则**：用户指定的运行时版本在上表 → 用精确 tag；不在或不确定 → 用对应的 `1-bookworm` rolling。绝不要自己凑一个看起来合理的 tag（如 `1-24-bookworm`、`1-3.14-bookworm`）。

### 为什么不同 base 要换 shared volume 名

单语言镜像之间的 ABI（glibc 版本、预装路径、Linuxbrew 兼容性）可能不同。强行共享 `/opt/dcc` 会踩 ABI 问题——brew bottle / pipx venv 绑定到具体 Python / glibc，换 base 就可能错乱。

**简单规则：base 不同 → shared volume 名不同，天然隔离**。

`initializeCommand` 里的 `init-volumes.sh` 根据 base image 自动派生 key，AI 生成时照搬即可。

---

## 什么时候写自定义 Dockerfile

只有三种情况：

1. **需要某个系统库**，没有对应 Feature。例如 `libvips`（sharp）、`ffmpeg`、`tesseract`。
2. **需要一个 MCR 上不存在的工具链版本**。例如 Rust nightly 带特定组件。
3. **需要装一套复杂的 apt 包**。放 Dockerfile 里能利用镜像层缓存。

最小自定义 Dockerfile 模板：

```dockerfile
# syntax=docker/dockerfile:1.4
FROM mcr.microsoft.com/devcontainers/javascript-node:1-22-bookworm

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    libvips-dev \
    && rm -rf /var/lib/apt/lists/*
```

`--mount=type=cache` 需要 BuildKit（现代 Docker 默认启用）。

## 架构兼容

MCR 官方镜像同时发布 amd64 和 arm64，Docker 按宿主机架构自动拉。

**要避免**：Dockerfile 里硬编码 `FROM ... --platform=linux/amd64`。Apple Silicon 用户会被迫走 Rosetta，慢到哭。除非项目真的需要某个只有 x86 的二进制。

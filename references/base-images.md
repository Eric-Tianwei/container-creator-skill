# 基础镜像选择参考

> **⚠ 选 tag 的铁律**：只用下面表格里明文列出的 tag，或者用 rolling 兜底（`1-bookworm` / `1-lts-bookworm`）。**不要自己按"运行时最新主版本号"脑补 tag**——MCR 的镜像发布通常滞后上游运行时几个月到一年，脑补的 tag 90% 不存在，容器一拉就失败。写之前 grep 本文件确认存在。

默认用微软官方 devcontainer 镜像（`mcr.microsoft.com/devcontainers/*`）。这些镜像：

- 非 root 用户 `vscode` 预置好
- 内置 zsh / bash / git / common utils
- 分层缓存优化过，pull 快
- 每月更新 CVE 补丁，tag 带 `1-` 前缀的是 rolling major
- 支持 arm64（Apple Silicon 友好）

## Tag 规律

官方镜像 tag 格式通常是：`<image>:<major>-<variant>-<distro>`

- `<major>` = `1` 表示稳定主版本线
- `<variant>` = 具体工具链版本，例如 `22`（Node）、`3.13`（Python）、没有（跟随 distro 默认）
- `<distro>` = `bookworm`（Debian 12）、`bullseye`（Debian 11）、`ubuntu-24.04` 等

**推荐统一用 bookworm**：新、稳、包全。

## 常用镜像对照（白名单 — 仅用表内 tag，表外的一律用 rolling）

| 场景 | 已验证 tag | 备注 |
|---|---|---|
| Node（默认） | `mcr.microsoft.com/devcontainers/javascript-node:1-22-bookworm` | 当前 LTS，默认选这个 |
| Node 20 | `mcr.microsoft.com/devcontainers/javascript-node:1-20-bookworm` | 兼容老项目 |
| Node（不确定版本） | `mcr.microsoft.com/devcontainers/javascript-node:1-bookworm` | rolling，跟随 MCR 默认 |
| TypeScript / Next.js / React / Vue | 同 Node | TS 用 npm 装，不换 base |
| Python 3.13 | `mcr.microsoft.com/devcontainers/python:1-3.13-bookworm` | 默认 |
| Python 3.12 | `mcr.microsoft.com/devcontainers/python:1-3.12-bookworm` | |
| Python（不确定版本） | `mcr.microsoft.com/devcontainers/python:1-bookworm` | rolling |
| FastAPI / Django / Flask | 同 Python | |
| Rust | `mcr.microsoft.com/devcontainers/rust:1-bookworm` | rolling，含 cargo/rustup |
| Go | `mcr.microsoft.com/devcontainers/go:1-bookworm` | rolling |
| Java / Kotlin | `mcr.microsoft.com/devcontainers/java:1-21-bookworm` | JDK 21；其它 JDK 先查 MCR |
| C++ | `mcr.microsoft.com/devcontainers/cpp:1-bookworm` | rolling |
| Ruby | `mcr.microsoft.com/devcontainers/ruby:1-3-bookworm` | |
| 多语言 / 不确定 | `mcr.microsoft.com/devcontainers/universal:2-linux` | ~10GB，啥都有 |
| 极简底座 | `mcr.microsoft.com/devcontainers/base:1-bookworm` | Debian + common-utils，语言自己加 feature |

**规则：** 用户指定的运行时版本在上面列表里 → 用精确 tag；不在列表或不确定 → 用对应的 `1-bookworm` rolling tag。**绝不要自己凑一个看起来合理的 tag**（如 `1-24-bookworm` / `1-3.14-bookworm`），不存在就是不存在。

## 单语言 vs universal 选哪个

- **知道主语言** → 选对应的单语言镜像。体积小（1-2GB），cold pull 快。
- **polyglot / 还没定 / 要装好几种语言** → `universal:2-linux`。虽然 10GB，但第一次 pull 完后就存在，每个项目 reuse 镜像层。

## 什么时候写自定义 Dockerfile

只有三种情况才写：

1. **需要某个系统库**，但没有对应 Feature。例如 `libvips` 给 sharp 用、`ffmpeg`、`tesseract`。
2. **需要一个 Docker Hub / MCR 上不存在的工具链版本**。例如需要某个 Python nightly、Rust nightly 带特定组件。
3. **需要装一套复杂的 apt 包**。虽然能通过 postCreateCommand 装，但放 Dockerfile 里能利用镜像层缓存。

最小自定义 Dockerfile 模板：

```dockerfile
FROM mcr.microsoft.com/devcontainers/javascript-node:1-22-bookworm

# 例：sharp 依赖 libvips
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    libvips-dev \
    && rm -rf /var/lib/apt/lists/*
```

注意 `--mount=type=cache` 需要 BuildKit（默认启用）。

## 架构兼容

微软官方镜像都同时发布 amd64 和 arm64。Docker 会按宿主机架构自动拉对的。

**要避免**的做法：在 Dockerfile 里硬编码 `FROM ... --platform=linux/amd64`。Apple Silicon 用户会被迫走 Rosetta，慢到哭。除非项目真的需要某个只有 x86 的二进制。

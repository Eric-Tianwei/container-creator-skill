# AI 工具链预装参考

这份文档覆盖把 Claude Code、agent-browser 和默认 skill 集合装进 devcontainer 的具体套路。SKILL.md 里的"默认开发环境配置"是强制清单，这里是解释为什么、以及各种场景下的变体。

## 核心思路：bind mount 宿主机 ~/.claude

Claude Code 把认证、会话历史、`settings.json`、已装 skills、MEMORY 全部放在宿主机 `~/.claude/` 下。开发容器本质是 **宿主机的延伸**，不是一台陌生机器。把 `~/.claude` 直接 bind-mount 进容器，意味着：

- **零重新登录** — 容器里第一次跑 `claude`，直接是已登录状态
- **skill 和 MEMORY 实时同步** — 容器里装的 skill，宿主机也看得到，反之亦然
- **settings 零配置** — 用户的 hooks、权限配置、statusline 全部复用

代价：容器逃逸后能读到认证凭证。对于**个人开发者** + **本地 OrbStack / Docker Desktop** 场景这是可接受的，因为容器本来就是你自己的。**不要** 在面向不可信代码的沙箱里这样挂 — 那种场景下改用 named volume + 用户在容器里登录一次。

### 标准片段（本地 OrbStack / Docker Desktop）

```jsonc
{
  "remoteUser": "vscode",
  "mounts": [
    "source=${localEnv:HOME}/.claude,target=/home/vscode/.claude,type=bind,consistency=cached"
  ],
  "postCreateCommand": "bash .devcontainer/post-create.sh"
}
```

`consistency=cached` 告诉 Docker Desktop（macOS）容器侧可以延迟同步宿主机的写入。OrbStack 的 VirtioFS 会忽略这个标志（不需要），留着兼容性无害。

### 用户不是 vscode 怎么办

如果基础镜像的默认用户是 `node`、`python` 或其他，把 target 换掉：

```
target=/home/node/.claude
```

或者干脆用 `${containerEnv:HOME}` 占位：

```
target=${containerEnv:HOME}/.claude
```

后者更鲁棒，但要求 devcontainer CLI 版本支持（大多数情况下都支持）。

### Codespaces / 远程 VM 场景

这个时候"宿主机"是 GitHub 的 VM，没有你的 `~/.claude`。两个办法：

1. **named volume + 一次性登录**（最简单）：
   ```jsonc
   "mounts": [
     "source=claude-config,target=/home/vscode/.claude,type=volume"
   ]
   ```
   用户第一次 `claude` 时登录一次，之后这个 volume 会在 Codespace 重启间保留。

2. **通过 Codespaces Secret 传 API key**（如果用户想完全无交互）：
   ```jsonc
   "containerEnv": {
     "ANTHROPIC_API_KEY": "${localEnv:ANTHROPIC_API_KEY}"
   }
   ```
   需要用户在 GitHub Codespaces secrets 里配好 `ANTHROPIC_API_KEY`。这会绕过 OAuth，直接走 API key 认证。

## post-create.sh 推荐模板

把 postCreateCommand 从一行字符串抽到脚本里，更好读、好改、好 debug：

```bash
#!/usr/bin/env bash
# .devcontainer/post-create.sh
set -euo pipefail

echo "→ 安装 Claude Code CLI..."
npm i -g @anthropic-ai/claude-code @anthropic-ai/claude-agent-sdk

echo "→ 安装默认 skill 集合（已有则跳过）..."
npx -y skills add vercel-labs/agent-browser@agent-browser -g -y || true
npx -y skills add anthropics/skills@skill-creator -g -y || true

# 按项目栈追加，例如 React 项目：
# npx -y skills add vercel-labs/agent-skills@react-best-practices -g -y || true

echo "→ 持久化 shell 历史..."
mkdir -p /commandhistory
touch /commandhistory/.zsh_history
ln -sf /commandhistory/.zsh_history ~/.zsh_history

echo "✓ 容器初始化完成。试试 'claude' 开始。"
```

记得 `chmod +x .devcontainer/post-create.sh`，或者在 postCreateCommand 里用 `bash .devcontainer/post-create.sh`（不依赖 x 权限）。

## MCP server 预装

如果用户点名了 MCP server（例如 "把 Vercel MCP 也接上"），在 post-create.sh 末尾追加对应的安装/注册命令。**不要凭记忆编 MCP 的命令**，用户提到哪个就 WebFetch 一下它的官方 README 再落地。

常见两种形态：

1. **npm 包型** — `npm i -g <package>` + 在 `~/.claude/settings.json` 注册（但宿主机 settings.json 已经 mount 进来，通常不需要重复注册）
2. **独立二进制** — 下载到 `/usr/local/bin` + 在 settings.json 注册 stdio 命令

## Agent-browser 的特殊性

agent-browser 需要 Chrome。两个选择：

1. **走宿主机的 Chrome**（最省事，macOS/Windows Docker Desktop 默认行为是容器里跑的 playwright 可以通过 host.docker.internal 连回宿主机）。实际用下来不稳，**不推荐**。
2. **容器里装 Chromium**：
   ```bash
   # 在 post-create.sh 或 Dockerfile 里
   apt-get update && apt-get install -y chromium
   ```
   或者用 feature：
   ```jsonc
   "features": {
     "ghcr.io/devcontainers-contrib/features/chromium:1": {}
   }
   ```
   然后 agent-browser 跑的时候走容器内 Chromium。

默认推荐第二种。除非用户明确说"要用我宿主机登录好的 Chrome"，那时再考虑方案 1 + X11 转发，那是另一个话题。

## 自检

确认下面这些都 OK 再交付：

- 进容器后跑 `claude --version` 能出结果
- 跑 `claude` 直接进入已登录状态（或通过 API key / 容器内一次登录得到等效效果）
- 跑 `npx skills list` 能看到 agent-browser
- `~/.claude/skills/` 目录能读能写

# 项目演进时的性能守门

skill 的默认配置解决"首次搭建最优"。项目长期演进会遇到新问题：临时装的 CLI、项目专用 skill、依赖更新——这份文档讲清楚如何用一套机制让这些变化**既被版本控制、又保持极致性能**。

## 一、CLI 工具演进：透明 wrapper + tools.list

### 问题

开发中手动装的 CLI（`brew install fd`、`cargo install ripgrep`、`pipx install httpie`）：

- 不写进配置 → 容器重建丢失、新同事不知道存在、git 无记录
- 每装一个都手改 `devcontainer.json` → 心智负担高，diff 噪音大，大家懒得做

### 方案：透明 wrapper

机制分三块：

1. **`.devcontainer/tools.list`** — 纯文本清单，每行 `<backend>: <pkg...>`，进 git
2. **`.devcontainer/bin/tools-wrapper.sh`** — 劫持 `brew`/`cargo`/`npm`/`pipx`/`go` 的 shell function，install 时顺手追加到 tools.list
3. **`.devcontainer/bin/install-tools.sh`** — 容器 create 时读清单批量安装，**每个后端都做幂等检查**（已装跳过）

**开发体验：**

```bash
$ brew install fd
# ...brew 原生输出...
  ↳ 已记录到 tools.list: brew: fd
```

开发者继续用原生命令，**什么新习惯都不用学**，幕后自动落档。`\brew install X` 绕过 wrapper（一次性临时装）。

### 为什么 rebuild 也快？

配合 **user-level named volume**（`~/.local`、`~/.cargo/bin`、`~/go/bin`、`~/.npm-global`、`/home/linuxbrew/.linuxbrew`），实际 binary 都在 volume 里持久存在。rebuild 时 install-tools.sh 对每个包 grep 一下 "装了吗？" → 命中 → 跳过 → 几十毫秒搞定。

**真实耗时对比：**

| 场景 | 耗时 |
|---|---|
| 开发中 `brew install fd` | 几秒（=brew install 本身） |
| 配置自动落 tools.list | 0 秒 |
| rebuild 容器（20 个 CLI 都在 volume 里） | < 1 秒 |
| 新同事 clone 首次进容器 | ≈ 一次性装所有 CLI 的时间 |

### apt 怎么办？

`apt` 装的是系统路径，无法挂 volume。用 Linuxbrew（`/home/linuxbrew/.linuxbrew`，挂 volume）替代 apt 是推荐方案。只有**真的需要 libfoo-dev 这种系统库**时才写 `apt:` 行（每次 create 会装一遍，几秒）。

## 二、项目专用 skill：分层挂载

### 问题

用户的全局 skill 走宿主机 `~/.claude/skills/` bind mount 完美。但项目演进中会产出"只跟这个项目强相关"的 skill（例如项目的特定 workflow、内部约定）—— 这些不该进全局，但应该在团队内共享。

### 方案：两层 skill 目录

```
<repo>/
├── .claude/
│   └── skills/              ← 项目专用 skill，进 git
│       └── my-internal-flow/
└── .devcontainer/devcontainer.json
```

在 devcontainer.json 里叠加一条 mount，把项目 skill 目录也挂进容器：

```jsonc
"mounts": [
  "source=${localEnv:HOME}/.claude,target=/home/vscode/.claude,type=bind,consistency=cached",
  "source=${localWorkspaceFolder}/.claude/skills,target=/home/vscode/.claude-project-skills,type=bind,consistency=cached"
]
```

post-create 时把项目 skill 软链进全局 skill 目录（Claude Code 会自动识别）：

```bash
mkdir -p ~/.claude/skills
for d in ~/.claude-project-skills/*/; do
  [ -d "$d" ] || continue
  ln -sfn "$d" ~/.claude/skills/"$(basename "$d")"
done
```

**效果：** 容器里 `claude` 能同时看到全局 + 项目 skill；项目 skill 跟代码一起 commit；pull request 能审查 skill 变动。

## 三、依赖更新：updateContentCommand

### 问题

常把 `pnpm install` / `uv sync` / `cargo fetch` 塞进 `postCreateCommand` 的结果：
- **第一次 create**：跑了（应该的）
- **git pull 后 lockfile 变了**：没机制自动重跑，开发者手动 `pnpm install` 才能跑起来

### 方案

用 devcontainer 的 **`updateContentCommand`** 替代放在 postCreate 里的依赖同步：

```jsonc
{
  "postCreateCommand": "bash .devcontainer/post-create.sh",
  "updateContentCommand": "pnpm install --frozen-lockfile"
}
```

`updateContentCommand` 会在**每次仓库内容更新后**自动跑（pull、rebase、切分支），比每次启动容器都跑快得多，又不会错过依赖变更。

## 四、Volume 治理

### 问题

一个项目会产出 8 个 named volume（3 个项目级 + 5 个全局共享）。**N 个项目 = `3N + 5` 个 volume**。没有治理的话，`docker volume ls` 半年后会一团乱：

- 命名撞车（`user-local` 和别的工具的 volume 重名）
- 项目删了 volume 留成僵尸
- 分不清哪些可以 prune、哪些数据不能丢

### 方案：命名空间 + scope + label

**命名：** 所有 devcontainer 生成的 volume 统一前缀 `dcc.`（container-creator 专属，避免撞车）+ scope 分类：

| 命名模式 | scope 含义 | 例子 |
|---|---|---|
| `dcc.shared.<id>` | 全局共享（跨项目） | `dcc.shared.linuxbrew`、`dcc.shared.cargo-bin` |
| `dcc.proj.<project>.<id>` | 项目私有、**要保留** | `dcc.proj.myapp.cmdhistory` |
| `dcc.cache.<project>.<id>` | 项目缓存、**可随时 prune** | `dcc.cache.myapp.node_modules`、`dcc.cache.myapp.next` |

关键判断："这个目录丢了我会难过吗"——难过 = `proj`，不难过 = `cache`。`node_modules` 是 cache（lockfile 能重建），`cmdhistory` 是 proj（丢了就丢了）。

### 实现：initializeCommand 预创建 + 打 label

devcontainer.json 里：

```jsonc
"initializeCommand": "bash .devcontainer/bin/init-volumes.sh"
```

`initializeCommand` 在宿主机上跑（不是容器内），时机是 container create 之前，正好用来预创建 volume 并打 label。

init-volumes.sh：

```bash
#!/usr/bin/env bash
set -euo pipefail
PROJ="$(basename "$PWD")"
CREATED="$(date -Iseconds)"

_v() {
  local name="$1" scope="$2"
  docker volume inspect "$name" >/dev/null 2>&1 && return 0
  docker volume create \
    --label "com.container-creator.scope=${scope}" \
    --label "com.container-creator.project=${PROJ}" \
    --label "com.container-creator.created-at=${CREATED}" \
    "$name" >/dev/null
}

_v dcc.shared.linuxbrew     shared
_v dcc.shared.user-local    shared
_v dcc.shared.cargo-bin     shared
_v dcc.shared.go-bin        shared
_v dcc.shared.npm-global    shared
_v "dcc.proj.${PROJ}.cmdhistory"   project
_v "dcc.cache.${PROJ}.node_modules" cache
_v "dcc.cache.${PROJ}.next"         cache
```

### 治理命令（即席使用，无需装工具）

label 让 `docker volume ls --filter` 变成可用工具：

```bash
# 按 scope 分组看
docker volume ls --filter label=com.container-creator.scope=shared
docker volume ls --filter label=com.container-creator.scope=project
docker volume ls --filter label=com.container-creator.scope=cache

# 某项目有哪些 volume
docker volume ls --filter label=com.container-creator.project=myapp

# 安全清理：所有 cache volume
docker volume ls -q --filter label=com.container-creator.scope=cache | xargs docker volume rm

# 清某个已删项目的所有 volume
docker volume ls -q --filter label=com.container-creator.project=my-old-project | xargs docker volume rm
```

`OrbStack.app` / `Docker Desktop` 的 UI 里所有 `dcc.*` 会按字母序聚集，scope / project 一眼可辨。

## 六、性能预算

给项目定一个"不准越过的线"，定期回头检查：

| 指标 | 预算 | 怎么测 |
|---|---|---|
| 冷启动（第一次 create） | < 90s | `time devcontainer up` |
| 热启动（已 create，重新 attach） | < 10s | 秒表 |
| postCreate 时长 | < 60s | post-create.sh 末尾打 `date` |
| `tools.list` 条目数 | < 30 | `grep -v '^#' .devcontainer/tools.list \| wc -l` |
| Features 数量 | < 8 | 数 devcontainer.json 里 features 字段 |

超过预算就回头审：哪些 CLI 不再用了删掉？哪些 Feature 其实冗余？

## 七、"promote" 工作流：临时 → 规范

`tools.list` 的本质是"所有我装过的 CLI"，不等于"团队都应该有的 CLI"。定期（例如每个迭代末）做一次清理：

```bash
# 人肉过一遍 tools.list，删掉试用过但不常用的
$EDITOR .devcontainer/tools.list

# commit 清理后的结果
git commit .devcontainer/tools.list -m "chore: prune tools.list"
```

或者留个便利命令：

```bash
# 查某个 CLI 最后一次真的被用是什么时候（看 shell history）
grep -c "fd " ~/.zsh_history
```

久不用的删掉 —— 保持清单 clean，保持 create 时间短。

---

## 总结

五条机制组合：

1. **透明 wrapper + tools.list** — 装 CLI 零心智负担、自动落档
2. **user-level named volume** — rebuild 不重装任何东西
3. **项目专用 skill 分层挂载** — 项目 know-how 跟代码一起走
4. **Volume 命名空间 + label** — `dcc.<scope>.<id>` 格式 + `initializeCommand` 预创建打 label，多项目下依然井然有序
5. **updateContentCommand + 性能预算** — 依赖变更自动同步，防止配置腐化

任何项目加一个 CLI 的完整流程：

```
brew install fd
# ↑ 一条命令，和宿主机体感完全一样
# 下面的事自动发生：
#   1. 装进 /home/linuxbrew/.linuxbrew（named volume，持久）
#   2. 追加 "brew: fd" 到 tools.list（git 追踪）
#   3. rebuild / 新成员 → install-tools.sh 读清单秒级恢复
```

# 项目演进时的性能守门

skill 的默认配置解决"首次搭建最优"。项目长期演进会遇到新问题：临时装的 CLI、项目专用 skill、依赖更新——这份文档讲清楚如何用一套机制让这些变化**既被版本控制、又保持极致性能**。

## 一、CLI 工具演进：透明 wrapper + tools.list

### 问题

开发中手动装的 CLI（`brew install fd`、`cargo install ripgrep`、`pipx install httpie`、`uv tool install ruff`）：

- 不写进配置 → 容器重建丢失、新同事不知道存在、git 无记录
- 每装一个都手改 `devcontainer.json` → 心智负担高，diff 噪音大，大家懒得做

### 方案：透明 wrapper

机制分三块：

1. **`.devcontainer/tools.list`** — 纯文本清单，每行 `<backend>: <pkg...>`，进 git
2. **`.devcontainer/bin/tools-wrapper.sh`** — 劫持 `brew`/`cargo`/`npm`/`pipx`/`go`/`uv` 的 shell function，install 时顺手追加到 tools.list
3. **`.devcontainer/bin/install-tools.sh`** — 容器 create 时读清单批量安装，**每个后端都做幂等检查**（已装跳过）

**开发体验：**

```bash
$ brew install fd
# ...brew 原生输出...
  ↳ 已记录到 tools.list: brew: fd
```

开发者继续用原生命令，**什么新习惯都不用学**，幕后自动落档。`\brew install X` 绕过 wrapper（一次性临时装）。

### 为什么 rebuild 也快？

所有后端的安装路径都重定向到了 **单个 shared volume `/opt/dcc/*`**（见 SKILL.md 硬清单第 8 条）。rebuild 时 install-tools.sh 对每个包 grep 一下 "装了吗？" → 命中 → 跳过 → 几十毫秒搞定。

**真实耗时对比：**

| 场景 | 耗时 |
|---|---|
| 开发中 `brew install fd` | 几秒（=brew install 本身） |
| 配置自动落 tools.list | 0 秒 |
| rebuild 容器（20 个 CLI 都在 shared volume 里） | < 1 秒 |
| 新同事 clone 首次进容器 | ≈ 一次性装所有 CLI 的时间 |

### apt 怎么办？

`apt` 装的是系统路径，无法挂 volume。用 Linuxbrew（`/home/linuxbrew/.linuxbrew`，软链到 `/opt/dcc/linuxbrew`）替代 apt 是推荐方案。只有**真的需要 libfoo-dev 这种系统库**时才写 `apt:` 行（每次 create 会装一遍，几秒）。

## 二、单 shared volume 的收益

与其为 brew / cargo / go / npm-global / bun / pipx / uv 各挂一个 volume，不如**挂一个 `/opt/dcc`**，内部按工具分子目录，用 env 变量重定向：

```
/opt/dcc/
├── linuxbrew/     软链到 /home/linuxbrew/.linuxbrew
├── cargo/         CARGO_HOME
├── go/            GOPATH
├── npm-global/    NPM_CONFIG_PREFIX
├── bun/           BUN_INSTALL
├── pipx/          PIPX_HOME
└── uv/            UV_INSTALL_DIR / UV_PYTHON_INSTALL_DIR / UV_TOOL_DIR
```

**好处：**

- `docker volume ls` 里每个项目只多一个 `dcc.shared.*`，不是 6-7 个
- ABI 分桶用 volume 名（`dcc.shared.node22` vs `dcc.shared.py313`）一次切换所有子目录
- 备份 / prune / 删除一次完成
- 多容器并发：shared volume 性质是 cache，撞了就重装；**单机 solo dev 几乎不会并发 install**

**约束：**

- env 变量必须在 PID 1 之前生效 → 写 `~/.profile`（交互 shell + 大多数守护进程能读到），**绝不进 `containerEnv.PATH`**（会让容器秒退，见 SKILL.md 反模式）
- Linuxbrew 只认 `/home/linuxbrew/.linuxbrew`，post-create 里 `sudo ln -sfn /opt/dcc/linuxbrew /home/linuxbrew/.linuxbrew`

## 三、项目专用 skill：分层挂载

### 问题

用户的全局 skill 走宿主机 `~/.claude/skills/` bind mount 完美。但项目演进中会产出"只跟这个项目强相关"的 skill —— 这些不该进全局，但应该在团队内共享。

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

## 四、依赖更新：updateContentCommand

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

## 五、Volume 治理

### 命名空间 + scope + label

所有 devcontainer 生成的 volume 统一前缀 `dcc.`（container-creator 专属）+ scope 分类：

| 命名模式 | scope 含义 | 例子 |
|---|---|---|
| `dcc.shared.<abi-key>` | 全局共享（跨项目，CLI 工具缓存） | `dcc.shared.node22`、`dcc.shared.py313` |
| `dcc.proj.<project>.<id>` | 项目私有、**要保留** | `dcc.proj.myapp.cmdhistory` |
| `dcc.cache.<project>.<id>` | 项目缓存、**可随时 prune** | `dcc.cache.myapp.deps` |

关键判断："这个目录丢了我会难过吗"——难过 = `proj`，不难过 = `cache`。依赖目录是 cache（lockfile 能重建），shell 历史是 proj（丢了就丢了）。shared 是 cache 的一种（丢了 `install-tools.sh` 能重建），但跨项目复用所以单列。

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

# base image 派生 ABI key（AI 生成时按实际 base 写死或从 devcontainer.json 里读）
ABI_KEY="node22"  # 走 escape hatch 时改成 py313 / rust-bookworm / go-bookworm 等

_v() {
  local name="$1" scope="$2"
  docker volume inspect "$name" >/dev/null 2>&1 && return 0
  docker volume create \
    --label "com.container-creator.scope=${scope}" \
    --label "com.container-creator.project=${PROJ}" \
    --label "com.container-creator.abi=${ABI_KEY}" \
    --label "com.container-creator.created-at=${CREATED}" \
    "$name" >/dev/null
}

_v "dcc.shared.${ABI_KEY}"          shared
_v "dcc.proj.${PROJ}.cmdhistory"    project
_v "dcc.cache.${PROJ}.deps"         cache
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

# 按 ABI 分组（升级 base 后旧 volume 清理）
docker volume ls --filter label=com.container-creator.abi=node20

# 安全清理：所有 cache volume
docker volume ls -q --filter label=com.container-creator.scope=cache | xargs docker volume rm

# 清某个已删项目的所有 volume
docker volume ls -q --filter label=com.container-creator.project=my-old-project | xargs docker volume rm
```

`OrbStack.app` / `Docker Desktop` 的 UI 里所有 `dcc.*` 会按字母序聚集，scope / project / abi 一眼可辨。

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
$EDITOR .devcontainer/tools.list
git commit .devcontainer/tools.list -m "chore: prune tools.list"
```

久不用的删掉 —— 保持清单 clean，保持 create 时间短。

---

## 总结

五条机制组合：

1. **透明 wrapper + tools.list** — 装 CLI 零心智负担、自动落档
2. **单 shared volume (`/opt/dcc`) + env 重定向** — rebuild 不重装任何东西，治理面最小
3. **项目专用 skill 分层挂载** — 项目 know-how 跟代码一起走
4. **Volume 命名空间 + label + ABI key** — `dcc.<scope>.<id>` 格式 + `initializeCommand` 预创建打 label，多项目下依然井然有序
5. **updateContentCommand + 性能预算** — 依赖变更自动同步，防止配置腐化

任何项目加一个 CLI 的完整流程：

```
brew install fd
# ↑ 一条命令，和宿主机体感完全一样
# 下面的事自动发生：
#   1. 装进 /opt/dcc/linuxbrew（shared volume，持久）
#   2. 追加 "brew: fd" 到 tools.list（git 追踪）
#   3. rebuild / 新成员 → install-tools.sh 读清单秒级恢复
```

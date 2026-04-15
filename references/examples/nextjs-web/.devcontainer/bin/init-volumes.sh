#!/usr/bin/env bash
# init-volumes.sh — 容器 create 前在宿主机预创建 named volume，并打 label
# 被 devcontainer.json 的 initializeCommand 调用（在宿主机上跑，不是容器里）
set -euo pipefail

PROJ="$(basename "$PWD")"
CREATED_AT="$(date -Iseconds 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"

_v() {
  local name="$1" scope="$2"
  # 存在就跳过（不覆盖已有 label）
  if docker volume inspect "$name" >/dev/null 2>&1; then
    return 0
  fi
  docker volume create \
    --label "com.container-creator.scope=${scope}" \
    --label "com.container-creator.project=${PROJ}" \
    --label "com.container-creator.created-at=${CREATED_AT}" \
    "$name" >/dev/null
  echo "  + 新建 volume [${scope}]: ${name}"
}

# 确保宿主机 ~/.claude.json 存在（否则 bind mount 会被当成目录创建）
[ -e "$HOME/.claude.json" ] || touch "$HOME/.claude.json"

echo "→ 预创建 devcontainer volume（已存在则跳过）..."

# 全局共享
_v dcc.shared.linuxbrew     shared
_v dcc.shared.user-local    shared
_v dcc.shared.cargo-bin     shared
_v dcc.shared.go-bin        shared
_v dcc.shared.npm-global    shared
_v dcc.shared.bun           shared

# 项目私有（需保留：shell 历史）
_v "dcc.proj.${PROJ}.cmdhistory"   project

# 项目缓存（可随时 prune 重建）
_v "dcc.cache.${PROJ}.node_modules" cache
_v "dcc.cache.${PROJ}.next"         cache

echo "✓ volume 就绪"

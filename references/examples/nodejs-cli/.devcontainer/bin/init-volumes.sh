#!/usr/bin/env bash
# 预创建 volume 并打 label（宿主机侧运行）
set -euo pipefail
PROJ="$(basename "$PWD")"
CREATED="$(date -Iseconds 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"

_v() {
  local name="$1" scope="$2"
  docker volume inspect "$name" >/dev/null 2>&1 && return 0
  docker volume create \
    --label "com.container-creator.scope=${scope}" \
    --label "com.container-creator.project=${PROJ}" \
    --label "com.container-creator.created-at=${CREATED}" \
    "$name" >/dev/null
  echo "  + [${scope}] ${name}"
}

# 确保宿主机 ~/.claude.json 存在（否则 bind mount 会被当成目录创建）
[ -e "$HOME/.claude.json" ] || touch "$HOME/.claude.json"

echo "→ 预创建 volume..."
_v dcc.shared.linuxbrew     shared
_v dcc.shared.user-local    shared
_v dcc.shared.cargo-bin     shared
_v dcc.shared.go-bin        shared
_v dcc.shared.npm-global    shared
_v dcc.shared.bun           shared
_v "dcc.proj.${PROJ}.cmdhistory"    project
_v "dcc.cache.${PROJ}.node_modules" cache
echo "✓ volume 就绪"

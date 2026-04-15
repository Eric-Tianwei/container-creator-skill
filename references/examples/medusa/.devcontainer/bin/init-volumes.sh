#!/usr/bin/env bash
# 预创建 volume 并打 label（宿主机侧）
set -euo pipefail
PROJ="medusa"  # 如果要按仓库名动态，用 PROJ="$(basename "$PWD")" 并同步修改 docker-compose.yml 里的 volume 名
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

echo "→ 预创建 volume..."
# shared
_v dcc.shared.linuxbrew     shared
_v dcc.shared.user-local    shared
_v dcc.shared.cargo-bin     shared
_v dcc.shared.go-bin        shared
_v dcc.shared.npm-global    shared
_v dcc.shared.bun           shared
# project（要保留：历史 + 数据库数据）
_v "dcc.proj.${PROJ}.cmdhistory"    project
_v "dcc.proj.${PROJ}.pgdata"        project
# cache（可 prune 重建）
_v "dcc.cache.${PROJ}.node_modules" cache
_v "dcc.cache.${PROJ}.redis"        cache
echo "✓ volume 就绪"

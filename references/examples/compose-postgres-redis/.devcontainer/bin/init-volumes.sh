#!/usr/bin/env bash
# 宿主机跑：container create 之前预创建 volume 并打 label。
# 同时把 PROJECT_DIR / ABI_KEY 写进 .devcontainer/.env，供 docker-compose 读（单容器形态也无害）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVC_DIR="$(dirname "$SCRIPT_DIR")"
PROJ="$(basename "$(cd "$DEVC_DIR/.." && pwd)")"
CREATED="$(date +%Y-%m-%dT%H:%M:%S%z)"

# base image 绑定的 ABI key。escape hatch 时改成 py313 / rust-bookworm / go-bookworm 等。
ABI_KEY="node22"

cat > "$DEVC_DIR/.env" <<EOF
PROJECT_DIR=${PROJ}
ABI_KEY=${ABI_KEY}
EOF

_v() {
  local name="$1" scope="$2"
  if docker volume inspect "$name" >/dev/null 2>&1; then
    return 0
  fi
  docker volume create \
    --label "com.container-creator.scope=${scope}" \
    --label "com.container-creator.project=${PROJ}" \
    --label "com.container-creator.abi=${ABI_KEY}" \
    --label "com.container-creator.created-at=${CREATED}" \
    "$name" >/dev/null
}

_v "dcc.shared.${ABI_KEY}"       shared
_v "dcc.proj.${PROJ}.cmdhistory" project
_v "dcc.cache.${PROJ}.deps"      cache

# 保证宿主机 ~/.claude.json 和 ~/.gitconfig 存在（不然 bind mount 会把它们建成目录）
[ -e "$HOME/.claude.json" ] || touch "$HOME/.claude.json"
[ -e "$HOME/.gitconfig" ]   || touch "$HOME/.gitconfig"

# macOS Keychain → ~/.claude/.credentials.json
# 新版 Claude Code 把 OAuth token 存 Keychain 而不是文件，容器访问不到 Keychain，
# 这里在宿主机侧导出到文件，bind mount ~/.claude 时自动带进容器。
if command -v security >/dev/null 2>&1; then
  cred_json="$(security find-generic-password -s 'Claude Code-credentials' -w 2>/dev/null || true)"
  if [ -n "$cred_json" ]; then
    mkdir -p "$HOME/.claude"
    echo "$cred_json" > "$HOME/.claude/.credentials.json"
    chmod 600 "$HOME/.claude/.credentials.json"
  fi
fi

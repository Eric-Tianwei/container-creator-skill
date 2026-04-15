#!/usr/bin/env bash
# install-tools.sh — 按 .devcontainer/tools.list 批量安装 CLI
# 每个后端都做幂等检查（已装跳过），配合 user-level named volume → rebuild 秒级恢复
set -euo pipefail

LIST="${TOOLS_LIST:-.devcontainer/tools.list}"
[ -f "$LIST" ] || { echo "没有 $LIST，跳过"; exit 0; }

# 辅助：已在 PATH 里就算装了
_have() { command -v "$1" >/dev/null 2>&1; }

while IFS= read -r line || [ -n "$line" ]; do
  line="${line%%#*}"  # strip 注释
  line="${line## }"; line="${line%% }"
  [ -z "$line" ] && continue
  backend="${line%%:*}"; pkgs="${line#*:}"
  backend="${backend## }"; backend="${backend%% }"
  pkgs="${pkgs## }"
  [ -z "$pkgs" ] && continue

  case "$backend" in
    brew)
      _have brew || { echo "⚠ 未装 brew，跳过 brew 行"; continue; }
      for p in $pkgs; do
        brew list "$p" >/dev/null 2>&1 || brew install "$p"
      done
      ;;
    cargo)
      _have cargo || { echo "⚠ 未装 cargo"; continue; }
      for p in $pkgs; do
        cargo install --list 2>/dev/null | grep -q "^${p} " || cargo install "$p"
      done
      ;;
    npm)
      _have npm || continue
      for p in $pkgs; do
        npm list -g --depth=0 2>/dev/null | grep -q " $p@" || npm i -g "$p"
      done
      ;;
    pipx)
      _have pipx || { python3 -m pip install --user pipx && python3 -m pipx ensurepath; }
      for p in $pkgs; do
        pipx list 2>/dev/null | grep -q "package $p " || pipx install "$p"
      done
      ;;
    go)
      _have go || continue
      for p in $pkgs; do
        # go install 只能重装无法查询，交给 go 自己判断（其实是幂等 compile，命中 cache 很快）
        go install "$p"
      done
      ;;
    apt)
      sudo apt-get update -qq
      # shellcheck disable=SC2086
      sudo apt-get install -y --no-install-recommends $pkgs
      ;;
    *)
      echo "⚠ 未知 backend：$backend（跳过）"
      ;;
  esac
done < "$LIST"

echo "✓ tools.list 同步完成"

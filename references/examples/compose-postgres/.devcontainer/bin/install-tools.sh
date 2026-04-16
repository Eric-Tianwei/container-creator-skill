#!/usr/bin/env bash
# 容器内跑：读 .devcontainer/tools.list 幂等装所有 CLI。
# 每行格式：<backend>: <pkg1> [pkg2 ...]
# backend ∈ { brew, cargo, npm, pipx, go, uv tool, apt }
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST="$(dirname "$SCRIPT_DIR")/tools.list"
[ -f "$LIST" ] || { echo "no tools.list, skipping"; exit 0; }

# shellcheck disable=SC1091
[ -f ~/.profile ] && source ~/.profile

_has_brew() { [ -x /home/linuxbrew/.linuxbrew/bin/brew ] && /home/linuxbrew/.linuxbrew/bin/brew list --formula 2>/dev/null | grep -Fxq "$1"; }
_has_cargo() { [ -x "${CARGO_HOME:-/opt/dcc/cargo}/bin/$1" ]; }
_has_npm_g() { [ -d "${NPM_CONFIG_PREFIX:-/opt/dcc/npm-global}/lib/node_modules/$1" ]; }
_has_pipx() { command -v pipx >/dev/null && pipx list --short 2>/dev/null | awk '{print $1}' | grep -Fxq "$1"; }
_has_go() { [ -x "${GOPATH:-/opt/dcc/go}/bin/$(basename "$1" | sed 's/@.*//')" ]; }
_has_uv_tool() { command -v uv >/dev/null && uv tool list 2>/dev/null | awk '{print $1}' | grep -Fxq "$1"; }
_has_apt() { dpkg -s "$1" >/dev/null 2>&1; }

while IFS= read -r raw; do
  line="${raw%%#*}"
  line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [ -z "$line" ] && continue
  backend="${line%%:*}"
  pkgs_str="${line#*:}"
  pkgs_str="$(echo "$pkgs_str" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [ -z "$pkgs_str" ] && continue
  read -r -a pkgs <<< "$pkgs_str"

  case "$backend" in
    brew)
      for p in "${pkgs[@]}"; do _has_brew "$p" || /home/linuxbrew/.linuxbrew/bin/brew install "$p"; done ;;
    cargo)
      for p in "${pkgs[@]}"; do _has_cargo "$p" || cargo install --locked "$p"; done ;;
    npm)
      for p in "${pkgs[@]}"; do _has_npm_g "$p" || npm i -g "$p"; done ;;
    pipx)
      for p in "${pkgs[@]}"; do _has_pipx "$p" || pipx install "$p"; done ;;
    go)
      for p in "${pkgs[@]}"; do _has_go "$p" || go install "$p"; done ;;
    "uv tool")
      for p in "${pkgs[@]}"; do _has_uv_tool "$p" || uv tool install "$p"; done ;;
    apt)
      missing=()
      for p in "${pkgs[@]}"; do _has_apt "$p" || missing+=("$p"); done
      if [ ${#missing[@]} -gt 0 ]; then
        sudo apt-get update -qq
        sudo apt-get install -y --no-install-recommends "${missing[@]}"
      fi ;;
    *)
      echo "unknown backend: $backend" >&2 ;;
  esac
done < "$LIST"

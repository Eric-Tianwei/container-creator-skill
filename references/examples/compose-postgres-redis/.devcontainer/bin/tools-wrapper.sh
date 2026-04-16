#!/usr/bin/env bash
# 透明 wrapper：劫持 brew/cargo/npm/pipx/go/uv 的 install 子命令，把被装的包追加到 tools.list。
# 走 \brew install X 绕过 wrapper（一次性临时装）。
# 由 ~/.zshrc / ~/.profile source，不要直接执行。

_dcc_tools_list() {
  local ws="${DCC_TOOLS_LIST:-}"
  if [ -n "$ws" ]; then echo "$ws"; return; fi
  # 走向上查找 .devcontainer/tools.list
  local d="$PWD"
  while [ "$d" != "/" ]; do
    if [ -f "$d/.devcontainer/tools.list" ]; then
      echo "$d/.devcontainer/tools.list"; return
    fi
    d="$(dirname "$d")"
  done
  echo "${CONTAINER_WORKSPACE_FOLDER:-/workspaces}/.devcontainer/tools.list"
}

_dcc_record() {
  local backend="$1"; shift
  local pkgs=("$@")
  [ ${#pkgs[@]} -eq 0 ] && return 0
  local list
  list="$(_dcc_tools_list)"
  [ -f "$list" ] || return 0
  local line="${backend}: ${pkgs[*]}"
  if ! grep -Fxq "$line" "$list" 2>/dev/null; then
    echo "$line" >> "$list"
    echo "  -> 已记录到 tools.list: $line"
  fi
}

brew() {
  if [ "${1:-}" = "install" ]; then
    command brew "$@" && shift && _dcc_record brew "$@"
  else
    command brew "$@"
  fi
}

cargo() {
  if [ "${1:-}" = "install" ]; then
    command cargo "$@" && shift && _dcc_record cargo "$@"
  else
    command cargo "$@"
  fi
}

npm() {
  # 只劫持 -g 全局装
  if [ "${1:-}" = "i" ] || [ "${1:-}" = "install" ]; then
    local args=("$@"); shift
    command npm "${args[@]}" || return $?
    local pkgs=() is_global=0
    for a in "$@"; do
      case "$a" in
        -g|--global) is_global=1 ;;
        -*) ;;
        *) pkgs+=("$a") ;;
      esac
    done
    [ $is_global -eq 1 ] && _dcc_record npm "${pkgs[@]}"
  else
    command npm "$@"
  fi
}

pipx() {
  if [ "${1:-}" = "install" ]; then
    command pipx "$@" && shift && _dcc_record pipx "$@"
  else
    command pipx "$@"
  fi
}

go() {
  if [ "${1:-}" = "install" ]; then
    command go "$@" && shift && _dcc_record go "$@"
  else
    command go "$@"
  fi
}

uv() {
  if [ "${1:-}" = "tool" ] && [ "${2:-}" = "install" ]; then
    command uv "$@" && shift 2 && _dcc_record "uv tool" "$@"
  else
    command uv "$@"
  fi
}

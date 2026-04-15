#!/usr/bin/env bash
# tools-wrapper.sh — 透明劫持常见包管理器的 install 子命令
# 装了什么 → 自动追加到 $TOOLS_LIST（.devcontainer/tools.list）
#
# 使用：在 ~/.zshrc 里 source 这个文件即可生效。
# 绕过 wrapper：用 \brew / \cargo / \npm / \pipx / \go

# tools.list 路径：优先用 env 变量，否则从当前目录向上找
_tools_list_path() {
  if [ -n "${TOOLS_LIST:-}" ] && [ -f "$TOOLS_LIST" ]; then
    echo "$TOOLS_LIST"; return
  fi
  local d="$PWD"
  while [ "$d" != "/" ]; do
    [ -f "$d/.devcontainer/tools.list" ] && echo "$d/.devcontainer/tools.list" && return
    d="$(dirname "$d")"
  done
  return 1
}

# 追加一个包到 tools.list 指定 backend 行（去重 + 行内 append）
_tools_record() {
  local backend="$1"; shift
  local list; list="$(_tools_list_path)" || return 0
  for pkg in "$@"; do
    # 跳过 flags 和 install 子命令本身
    case "$pkg" in -*|install|i|add|global) continue ;; esac
    [ -z "$pkg" ] && continue
    # 已存在就跳过
    if grep -qE "(^|[[:space:]])${pkg}([[:space:]]|$)" <(grep "^${backend}:" "$list" || echo ""); then
      continue
    fi
    if grep -qE "^${backend}:" "$list"; then
      # append 到现有行尾
      awk -v b="$backend" -v p="$pkg" '
        $0 ~ "^"b":" { print $0" "p; next } { print }
      ' "$list" > "${list}.tmp" && mv "${list}.tmp" "$list"
    else
      echo "${backend}: ${pkg}" >> "$list"
    fi
    echo "  ↳ 已记录到 tools.list: ${backend}: ${pkg}"
  done
}

# ---- 包管理器 wrapper ----

brew() {
  if [ "${1:-}" = "install" ]; then
    command brew "$@" && _tools_record brew "${@:2}"
  else
    command brew "$@"
  fi
}

cargo() {
  if [ "${1:-}" = "install" ]; then
    command cargo "$@" && _tools_record cargo "${@:2}"
  else
    command cargo "$@"
  fi
}

pipx() {
  if [ "${1:-}" = "install" ]; then
    command pipx "$@" && _tools_record pipx "${@:2}"
  else
    command pipx "$@"
  fi
}

# npm 的 global install 有多种形式：npm i -g X / npm install --global X
npm() {
  local sub="${1:-}" is_global=0 pkgs=()
  case "$sub" in install|i|add)
    shift
    for a in "$@"; do
      case "$a" in
        -g|--global) is_global=1 ;;
        -*) ;;
        *) pkgs+=("$a") ;;
      esac
    done
    command npm "$sub" "$@"
    local rc=$?
    if [ $is_global -eq 1 ] && [ $rc -eq 0 ] && [ ${#pkgs[@]} -gt 0 ]; then
      _tools_record npm "${pkgs[@]}"
    fi
    return $rc
    ;;
  esac
  command npm "$@"
}

# go install 记录完整模块路径（例如 github.com/foo/bar@latest）
go() {
  if [ "${1:-}" = "install" ]; then
    command go "$@"
    local rc=$?
    if [ $rc -eq 0 ]; then
      shift
      for a in "$@"; do
        case "$a" in -*) continue ;; esac
        _tools_record go "$a"
      done
    fi
    return $rc
  fi
  command go "$@"
}

# 提示已激活（容器首次进终端时输出一次）
if [ -z "${TOOLS_WRAPPER_ANNOUNCED:-}" ]; then
  export TOOLS_WRAPPER_ANNOUNCED=1
  echo "✓ tools-wrapper 已激活：brew/cargo/npm/pipx/go install 会自动写入 .devcontainer/tools.list"
  echo "  绕过 wrapper：用 \\brew / \\cargo / \\npm / \\pipx / \\go"
fi

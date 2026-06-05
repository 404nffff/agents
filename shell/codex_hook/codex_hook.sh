#!/usr/bin/env bash
set -euo pipefail

# Codex hooks 通用入口：安装 hooks 配置，或把 stdin/file payload 交给 Python 事件层。

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd -- "$(dirname "$0")" && pwd -L)"
PY_HOOK="${SCRIPT_DIR}/hook.py"

usage() {
  cat <<EOF
用法:
  ./${SCRIPT_NAME} create [linux|win]
  ./${SCRIPT_NAME} [hook-json-file]
  ./${SCRIPT_NAME} -h|--help

说明:
  通用 Codex hooks 入口。事件处理在 hook.py，通知渠道通过 plugins/ 插件调用。
  插件通过 CODEX_HOOK_EVENTS='事件:插件列表;事件:插件列表' 配置。

动作:
  create              按当前系统生成 ~/.codex/hooks.json
  create linux        强制生成 Linux/macOS Bash hooks 配置
  create win          强制生成 Windows PowerShell hooks 配置
  hook-json-file      从指定 JSON 文件读取 hook payload，便于本地调试

常用环境变量:
  CODEX_HOOK_EVENTS                  事件到插件路由，例如 Stop:feishu,xxxx;SessionStart:feishu
  CODEX_HOOK_PAYLOAD_LOG_PATH        脱敏 payload 日志路径
  FEISHU_CODEX_HOOK_ENABLE_PUSH      true 时由 feishu 插件发送飞书通知

示例:
  ./${SCRIPT_NAME} create
  CODEX_HOOK_EVENTS='Stop:feishu' FEISHU_CODEX_HOOK_ENABLE_PUSH=true ./${SCRIPT_NAME} ./payload.json
EOF
}

resolve_hooks_platform() {
  local requested="${1:-auto}"
  local uname_s
  case "${requested}" in
    auto|"")
      uname_s="$(uname -s 2>/dev/null || printf '')"
      if [[ "${OS:-}" == "Windows_NT" || "${uname_s}" == MINGW* || "${uname_s}" == MSYS* || "${uname_s}" == CYGWIN* ]]; then
        printf 'win\n'
      else
        printf 'linux\n'
      fi
      ;;
    linux|win)
      printf '%s\n' "${requested}"
      ;;
    *)
      printf '不支持的平台参数: %s\n' "${requested}" >&2
      return 1
      ;;
  esac
}

to_windows_path() {
  local path="$1"
  local drive rest
  if [[ "${path}" =~ ^([A-Za-z]):/(.*)$ ]]; then
    drive="${BASH_REMATCH[1]}"
    rest="${BASH_REMATCH[2]}"
    printf '%s\n' "${drive^^}:\\${rest//\//\\}"
    return 0
  fi
  if [[ "${path}" =~ ^/([A-Za-z])/(.*)$ ]]; then
    drive="${BASH_REMATCH[1]}"
    rest="${BASH_REMATCH[2]}"
    printf '%s\n' "${drive^^}:\\${rest//\//\\}"
    return 0
  fi
  printf '%s\n' "${path//\//\\}"
}

build_hook_command() {
  local platform="$1"
  if [[ "${platform}" == "win" ]]; then
    printf 'powershell -NoProfile -ExecutionPolicy Bypass -File "%s"\n' "$(to_windows_path "${SCRIPT_DIR}/codex_hook.ps1")"
    return 0
  fi
  printf 'bash %s\n' "${SCRIPT_DIR}/codex_hook.sh"
}

write_hooks_json_file() {
  local output_path="$1"
  local command_text="$2"
  local output_dir
  output_dir="$(dirname "${output_path}")"
  mkdir -p "${output_dir}"
  CODEX_HOOK_COMMAND="${command_text}" python3 - "${output_path}" <<'PY'
import json
import os
import sys

output_path = sys.argv[1]
command_text = os.environ["CODEX_HOOK_COMMAND"]
events = [
    ("SessionStart", False),
    ("SubagentStart", False),
    ("PreToolUse", True),
    ("PermissionRequest", True),
    ("PostToolUse", True),
    ("PreCompact", False),
    ("PostCompact", False),
    ("UserPromptSubmit", False),
    ("SubagentStop", False),
    ("Stop", False),
]

hooks = {}
for event_name, with_matcher in events:
    item = {"hooks": [{"type": "command", "command": command_text}]}
    if with_matcher:
        item["matcher"] = "*"
    hooks[event_name] = [item]

with open(output_path, "w", encoding="utf-8") as handle:
    json.dump({"hooks": hooks}, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
}

create_hooks_json_file() {
  local requested_platform="${1:-auto}"
  local platform command_text output_path
  platform="$(resolve_hooks_platform "${requested_platform}")" || return 1
  command_text="$(build_hook_command "${platform}")"
  output_path="${HOME}/.codex/hooks.json"
  write_hooks_json_file "${output_path}" "${command_text}"
  printf '已生成 %s hooks 配置:\n' "${platform}"
  printf '  %s\n' "${output_path}"
}

run_hook() {
  if ! command -v python3 >/dev/null 2>&1; then
    exit 0
  fi
  python3 "${PY_HOOK}" "$@" >/dev/null 2>&1 || true
}

case "${1:-}" in
  -h|--help|help)
    usage
    exit 0
    ;;
  create)
    shift || true
    create_hooks_json_file "${1:-auto}"
    exit 0
    ;;
esac

run_hook "$@"
exit 0

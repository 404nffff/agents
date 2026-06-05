#!/usr/bin/env bash
set -euo pipefail

# Codex hooks 飞书通知：兼容 SessionStart / SubagentStart / PreToolUse /
# PermissionRequest / PostToolUse / PreCompact / PostCompact / UserPromptSubmit /
# SubagentStop / Stop。
#
# Codex hooks.json 配置示例：
# {
#   "hooks": {
#     "SessionStart": [{ "hooks": [{ "type": "command", "command": "bash /mnt/sync2/www/agents/shell/feishu_bot/feishu_codex_hook.sh" }] }],
#     "SubagentStart": [{ "hooks": [{ "type": "command", "command": "bash /mnt/sync2/www/agents/shell/feishu_bot/feishu_codex_hook.sh" }] }],
#     "PreToolUse": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "bash /mnt/sync2/www/agents/shell/feishu_bot/feishu_codex_hook.sh" }] }],
#     "PermissionRequest": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "bash /mnt/sync2/www/agents/shell/feishu_bot/feishu_codex_hook.sh" }] }],
#     "PostToolUse": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "bash /mnt/sync2/www/agents/shell/feishu_bot/feishu_codex_hook.sh" }] }],
#     "PreCompact": [{ "hooks": [{ "type": "command", "command": "bash /mnt/sync2/www/agents/shell/feishu_bot/feishu_codex_hook.sh" }] }],
#     "PostCompact": [{ "hooks": [{ "type": "command", "command": "bash /mnt/sync2/www/agents/shell/feishu_bot/feishu_codex_hook.sh" }] }],
#     "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "bash /mnt/sync2/www/agents/shell/feishu_bot/feishu_codex_hook.sh" }] }],
#     "SubagentStop": [{ "hooks": [{ "type": "command", "command": "bash /mnt/sync2/www/agents/shell/feishu_bot/feishu_codex_hook.sh" }] }],
#     "Stop": [{ "hooks": [{ "type": "command", "command": "bash /mnt/sync2/www/agents/shell/feishu_bot/feishu_codex_hook.sh" }] }]
#   }
# }
#
# .env 常用配置：
#   FEISHU_CODEX_HOOK_ENABLE_PUSH='false'        # true 时发送飞书通知
#   FEISHU_CODEX_HOOK_EVENTS=''                  # 空表示全部；也可填 Stop,PostToolUse
#   FEISHU_CODEX_HOOK_UPDATE_SESSION_TITLE='false' # true 时同步更新 Codex 会话标题
# create 模式：
#   ./feishu_codex_hook.sh create             # 按当前系统写入 ~/.codex/hooks.json
#   ./feishu_codex_hook.sh create linux|win   # 强制按指定平台写入 ~/.codex/hooks.json
#
# Codex hooks stdin payload 字段说明（自动含义）：
# 1. SessionStart
#    - session_id: 当前会话 ID
#    - cwd: 当前工作目录
#    - transcript_path: 当前会话 transcript 路径
#    - hook_event_name: 固定为 SessionStart
#    - model: 当前模型名
#    - permission_mode: 当前权限模式
#    - source: 触发来源，通常是 startup / resume / clear
# 2. SubagentStart
#    - session_id / turn_id / cwd / transcript_path / hook_event_name / model / permission_mode
#    - agent_id: 子代理会话 ID
#    - agent_type: 子代理角色类型
# 3. PreToolUse
#    - session_id / turn_id / cwd / transcript_path / hook_event_name / model / permission_mode
#    - tool_name: 即将调用的工具名
#    - tool_input: 工具入参
#    - tool_use_id: 本次工具调用 ID
# 4. PermissionRequest
#    - session_id / turn_id / cwd / transcript_path / hook_event_name / model / permission_mode
#    - tool_name: 申请权限的工具名
#    - tool_input: 工具入参
# 5. PostToolUse
#    - session_id / turn_id / cwd / transcript_path / hook_event_name / model / permission_mode
#    - tool_name: 已调用完成的工具名
#    - tool_input: 工具入参
#    - tool_response: 工具返回结果
#    - tool_use_id: 本次工具调用 ID
# 6. PreCompact
#    - session_id / turn_id / cwd / transcript_path / hook_event_name / model
#    - trigger: 压缩触发来源，通常是 manual / auto
# 7. PostCompact
#    - session_id / turn_id / cwd / transcript_path / hook_event_name / model
#    - trigger: 压缩触发来源，通常是 manual / auto
# 8. UserPromptSubmit
#    - session_id / turn_id / cwd / transcript_path / hook_event_name / model / permission_mode
#    - prompt: 用户刚提交的提示词正文
# 9. SubagentStop
#    - session_id / turn_id / cwd / transcript_path / hook_event_name / model / permission_mode
#    - agent_id: 子代理会话 ID
#    - agent_type: 子代理角色类型
#    - last_assistant_message: 子代理最后一条回复
# 10. Stop
#    - session_id / turn_id / cwd / transcript_path / hook_event_name / model / permission_mode
#    - stop_hook_active: Stop hook 是否已经进入过一次继续链路。false 表示首次 Stop；
#      true 表示前一个 Stop hook 已经要求“继续一轮”后再次进入，常用于防止循环拦截。
#    - last_assistant_message: 当前回合最后一条助手回复

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd -- "$(dirname "$0")" && pwd -L)"
PUSH_SCRIPT="${SCRIPT_DIR}/feishu_bot_push.sh"
DEFAULT_ENV_FILE="${SCRIPT_DIR}/.env"
LEGACY_ENV_FILE="${SCRIPT_DIR}/feishu.env"
ENV_FILE="${FEISHU_ENV_FILE:-${FEISHU_BOT_ENV_FILE:-${DEFAULT_ENV_FILE}}}"

load_feishu_env_file() {
  local env_file="${1:-}"
  local -a preserved_names=()
  local -A preserved_values=()
  local var_name
  [[ -n "${env_file}" ]] || return 0
  if [[ "${env_file}" == "${DEFAULT_ENV_FILE}" && ! -f "${env_file}" && -f "${LEGACY_ENV_FILE}" ]]; then
    env_file="${LEGACY_ENV_FILE}"
  fi
  [[ -f "${env_file}" ]] || return 0

  while IFS= read -r var_name; do
    [[ -n "${var_name}" ]] || continue
    preserved_names+=("${var_name}")
    preserved_values["${var_name}"]="${!var_name}"
  done < <(compgen -A variable FEISHU_ || true)

  # shellcheck disable=SC1090
  . "${env_file}"

  for var_name in "${preserved_names[@]}"; do
    printf -v "${var_name}" '%s' "${preserved_values[${var_name}]}"
    export "${var_name}"
  done
}

load_feishu_env_file "${ENV_FILE}"

PAYLOAD_LOG_PATH="${FEISHU_CODEX_HOOK_PAYLOAD_LOG_PATH:-${SCRIPT_DIR}/codex_hook_payload.log}"
MAX_MESSAGE_CHARS="${FEISHU_CODEX_HOOK_MAX_CHARS:-3000}"
HOOK_TEMPLATE="${FEISHU_CODEX_HOOK_TEMPLATE:-${FEISHU_CODEX_NOTIFY_TEMPLATE:-blue}}"
HOOK_FOOTER="${FEISHU_CODEX_HOOK_FOOTER:-由 Codex hooks 自动发送}"
HOOK_EVENTS="${FEISHU_CODEX_HOOK_EVENTS:-}"
HOOK_INCLUDE_PAYLOAD="${FEISHU_CODEX_HOOK_INCLUDE_PAYLOAD:-false}"
HOOK_ENABLE_PUSH="${FEISHU_CODEX_HOOK_ENABLE_PUSH:-false}"
TITLE_STATE_PATH="${FEISHU_CODEX_HOOK_TITLE_STATE_PATH:-${SCRIPT_DIR}/codex_hook_title_state.json}"
UPDATE_SESSION_TITLE="${FEISHU_CODEX_HOOK_UPDATE_SESSION_TITLE:-false}"
CODEX_APP_SERVER_TIMEOUT="${FEISHU_CODEX_HOOK_CODEX_APP_SERVER_TIMEOUT:-5}"
CODEX_APP_SERVER_DRAIN_SECONDS="${FEISHU_CODEX_HOOK_CODEX_APP_SERVER_DRAIN_SECONDS:-0.5}"
PY_TITLE_HOOK="${SCRIPT_DIR}/hook.py"

usage() {
  cat <<EOF
用法:
  ./${SCRIPT_NAME} create [linux|win]
  ./${SCRIPT_NAME} [hook-json-file]
  ./${SCRIPT_NAME} -h|--help

说明:
  Codex hooks 生命周期通知入口。正常作为 hooks command 运行，从 stdin 读取 Codex hook payload。
  create 模式会按当前平台生成 hooks 配置，并写入 ~/.codex/hooks.json。
  默认读取脚本所在目录 .env；也可通过 FEISHU_ENV_FILE 或 FEISHU_BOT_ENV_FILE 指定配置文件。

动作:
  create              按当前系统生成 ~/.codex/hooks.json
  create linux        强制生成 Linux/macOS Bash hooks 配置
  create win          强制生成 Windows PowerShell hooks 配置
  hook-json-file      从指定 JSON 文件读取 hook payload，便于本地调试

常用环境变量:
  FEISHU_CODEX_HOOK_ENABLE_PUSH            true 时发送飞书通知，默认 false
  FEISHU_CODEX_HOOK_EVENTS                 事件白名单，空表示全部，例如 Stop,PostToolUse
  FEISHU_CODEX_HOOK_UPDATE_SESSION_TITLE   true 时在 Stop 阶段更新 Codex 会话标题

示例:
  ./${SCRIPT_NAME} create
  ./${SCRIPT_NAME} create linux
  FEISHU_CODEX_HOOK_ENABLE_PUSH=true ./${SCRIPT_NAME} ./payload.json

注意:
  不要把 webhook、app_secret、token 等敏感值写入 README、日志或提交记录。
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
  local sh_path="${SCRIPT_DIR}/feishu_codex_hook.sh"
  local ps1_path="${SCRIPT_DIR}/feishu_codex_hook.ps1"
  if [[ "${platform}" == "win" ]]; then
    printf 'powershell -NoProfile -ExecutionPolicy Bypass -File "%s"\n' "$(to_windows_path "${ps1_path}")"
    return 0
  fi
  printf 'bash %s\n' "${sh_path}"
}

write_hooks_json_file() {
  local output_path="$1"
  local command_text="$2"
  local output_dir
  output_dir="$(dirname "${output_path}")"
  mkdir -p "${output_dir}"
  FEISHU_CODEX_HOOK_COMMAND="${command_text}" python3 - "${output_path}" <<'PY'
import json
import os
import sys

output_path = sys.argv[1]
command_text = os.environ["FEISHU_CODEX_HOOK_COMMAND"]
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
    item = {
        "hooks": [
            {
                "type": "command",
                "command": command_text,
            }
        ]
    }
    if with_matcher:
        item["matcher"] = "*"
    hooks[event_name] = [item]

with open(output_path, "w", encoding="utf-8") as handle:
    json.dump({"hooks": hooks}, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
}

create_hooks_json_files() {
  local requested_platform="${1:-auto}"
  local platform command_text output_path
  platform="$(resolve_hooks_platform "${requested_platform}")" || return 1
  command_text="$(build_hook_command "${platform}")"
  output_path="${HOME}/.codex/hooks.json"

  # create 直接安装当前平台配置，避免脚本目录残留多个过期模板。
  write_hooks_json_file "${output_path}" "${command_text}"

  printf '已生成 %s hooks 配置:\n' "${platform}"
  printf '  %s\n' "${output_path}"
}

log_payload_line() {
  local payload_json="$1"
  local log_dir
  log_dir="$(dirname "${PAYLOAD_LOG_PATH}")"
  mkdir -p "${log_dir}"
  printf '%s\n' "${payload_json}" >>"${PAYLOAD_LOG_PATH}"
}

trim_payload_log_lines() {
  local keep_lines="${1:-50}"
  local tmp_file
  [[ -f "${PAYLOAD_LOG_PATH}" ]] || return 0
  tmp_file="${PAYLOAD_LOG_PATH}.tmp"
  tail -n "${keep_lines}" "${PAYLOAD_LOG_PATH}" >"${tmp_file}" || return 0
  mv "${tmp_file}" "${PAYLOAD_LOG_PATH}"
}

get_title_state() {
  local session_id="${1:-}"
  local turn_id="${2:-}"
  [[ -n "${session_id}" && -n "${turn_id}" && -f "${TITLE_STATE_PATH}" ]] || return 0
  FEISHU_CODEX_HOOK_STATE_PATH="${TITLE_STATE_PATH}" \
  FEISHU_CODEX_HOOK_SESSION_ID="${session_id}" \
  FEISHU_CODEX_HOOK_TURN_ID="${turn_id}" \
  python3 - <<'PY'
import json
import os

path = os.environ["FEISHU_CODEX_HOOK_STATE_PATH"]
session_id = os.environ["FEISHU_CODEX_HOOK_SESSION_ID"]
turn_id = os.environ["FEISHU_CODEX_HOOK_TURN_ID"]
key = f"{session_id}:{turn_id}"

try:
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
except Exception:
    data = {}

value = data.get(key, {})
title = value.get("title", "")
print(title if isinstance(title, str) else "")
PY
}

run_python_title_hook() {
  local raw_payload="${1:-}"
  [[ -n "${raw_payload}" && -f "${PY_TITLE_HOOK}" ]] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
	  FEISHU_CODEX_HOOK_TITLE_STATE_PATH="${TITLE_STATE_PATH}" \
	  FEISHU_CODEX_HOOK_UPDATE_SESSION_TITLE="${UPDATE_SESSION_TITLE}" \
	  FEISHU_CODEX_HOOK_CODEX_APP_SERVER_TIMEOUT="${CODEX_APP_SERVER_TIMEOUT}" \
	  FEISHU_CODEX_HOOK_CODEX_APP_SERVER_DRAIN_SECONDS="${CODEX_APP_SERVER_DRAIN_SECONDS}" \
	  python3 "${PY_TITLE_HOOK}" "${raw_payload}" >/dev/null 2>&1 || true
}

read_payload() {
  if [[ -n "${1:-}" ]]; then
    printf '%s' "$1"
    return 0
  fi
  cat
}

build_markdown_from_payload() {
  local raw="$1"
  FEISHU_CODEX_HOOK_PAYLOAD="${raw}" python3 - "$MAX_MESSAGE_CHARS" "$HOOK_FOOTER" "$HOOK_EVENTS" "$HOOK_INCLUDE_PAYLOAD" <<'PY'
import json
import os
import re
import sys

SUPPORTED_EVENTS = {
    "SessionStart",
    "SubagentStart",
    "PreToolUse",
    "PermissionRequest",
    "PostToolUse",
    "PreCompact",
    "PostCompact",
    "UserPromptSubmit",
    "SubagentStop",
    "Stop",
}

EVENT_ZH = {
    "SessionStart": "会话开始",
    "SubagentStart": "子代理开始",
    "PreToolUse": "工具调用前",
    "PermissionRequest": "权限请求",
    "PostToolUse": "工具调用后",
    "PreCompact": "压缩前",
    "PostCompact": "压缩后",
    "UserPromptSubmit": "用户提交提示",
    "SubagentStop": "子代理结束",
    "Stop": "回合结束",
}

limit = int(sys.argv[1])
footer = sys.argv[2]
allowed_events_raw = sys.argv[3]
include_payload = sys.argv[4].lower() in {"1", "true", "yes", "on"}
payload = json.loads(os.environ.get("FEISHU_CODEX_HOOK_PAYLOAD", ""))


def first_text(*names):
    for name in names:
        value = payload.get(name)
        if value is None:
            continue
        text = str(value)
        if text:
            return text
    return ""


def nested_text(obj, *names):
    if not isinstance(obj, dict):
        return ""
    for name in names:
        value = obj.get(name)
        if value is None:
            continue
        text = str(value)
        if text:
            return text
    return ""


def shorten(value, max_len=900):
    if value is None:
        return ""
    if not isinstance(value, str):
        value = json.dumps(value, ensure_ascii=False, sort_keys=True)
    value = value.strip()
    if len(value) > max_len:
        return value[:max_len] + "\n...(已截断)"
    return value


def code(value):
    return f"`{value or '-'}`"


def clean_title_summary(value, limit):
    if value is None:
        return ""
    if not isinstance(value, str):
        value = json.dumps(value, ensure_ascii=False, sort_keys=True)
    lines = []
    for line in value.replace("\r", "\n").split("\n"):
        line = line.strip()
        line = re.sub(r"^#{1,6}\s+", "", line)
        line = re.sub(r"^[-+*]\s+", "", line)
        line = re.sub(r"^\d+\.\s+", "", line)
        line = re.sub(r"^>\s+", "", line)
        if line:
            lines.append(line)
    value = " ".join(lines)
    value = re.sub(r"[`*#>\[\]\(\)~]+", " ", value)
    value = re.sub(r"\s+", " ", value).strip()
    if len(value) > limit:
        value = value[:limit].rstrip()
    return value


def strip_forwarded_title_prefix(value):
    if not isinstance(value, str):
        return value
    cleaned = value.strip()
    cleaned = re.sub(r"^\[[^\]]+\]\s+.+?\b\d{2}:\d{2}:\d{2}\s+", "", cleaned, count=1)
    cleaned = re.sub(r"^[，,。:：;；、\-\s]+", "", cleaned)
    return cleaned.strip()


def build_title_summary(event_name, tool_name_text, prompt_text, last_message_text):
    tool_input = payload.get("tool_input")
    command_text = ""
    if isinstance(tool_input, dict):
        for key in ("cmd", "command"):
            value = tool_input.get(key)
            if value:
                command_text = str(value)
                break

    if event_name in {"PreToolUse", "PostToolUse"}:
        return clean_title_summary(command_text or tool_name_text, 40)
    if event_name == "PermissionRequest":
        return clean_title_summary(tool_name_text, 32)
    if event_name == "UserPromptSubmit":
        return clean_title_summary(strip_forwarded_title_prefix(prompt_text), 40)
    if event_name == "Stop":
        return clean_title_summary(last_message_text, 24)
    if event_name in {"SubagentStart", "SubagentStop"}:
        return clean_title_summary(agent_type or tool_name_text, 32)
    return ""


event = first_text("hook_event_name", "hookEventName", "event_name", "eventName", "type")
if event not in SUPPORTED_EVENTS:
    print(json.dumps({"skip": True, "reason": f"unsupported_event:{event}"}, ensure_ascii=False))
    sys.exit(0)

allowed = {item.strip() for item in allowed_events_raw.split(",") if item.strip()}

cwd = first_text("cwd")
project = os.path.basename(os.path.normpath(cwd)) if cwd else ""
session_id = first_text("session_id", "sessionId")
turn_id = first_text("turn_id", "turnId")
model = first_text("model")
permission_mode = first_text("permission_mode", "permissionMode")
transcript_path = first_text("transcript_path", "transcriptPath")
tool_name = first_text("tool_name", "toolName")
tool_use_id = first_text("tool_use_id", "toolUseId", "call_id", "callId")
trigger = first_text("trigger")
source = first_text("source")
prompt = first_text("prompt")
last_assistant_message = first_text("last_assistant_message", "lastAssistantMessage")
stop_hook_active = first_text("stop_hook_active", "stopHookActive")
subagent = payload.get("subagent") if isinstance(payload.get("subagent"), dict) else {}
agent_id = first_text("agent_id", "agentId") or nested_text(subagent, "agent_id", "agentId")
agent_type = first_text("agent_type", "agentType") or nested_text(subagent, "agent_type", "agentType")
title_summary = build_title_summary(event, tool_name, prompt, last_assistant_message)

if allowed and event not in allowed:
    print(json.dumps({
        "skip": True,
        "reason": f"filtered_event:{event}",
        "event": event,
        "project": project,
        "title_summary": title_summary,
        "session_id": session_id,
        "turn_id": turn_id,
    }, ensure_ascii=False))
    sys.exit(0)

details = []
if source:
    details.append(f"- Source：{code(source)}")
if trigger:
    details.append(f"- Trigger：{code(trigger)}")
if tool_name:
    details.append(f"- Tool：{code(tool_name)}")
if tool_use_id:
    details.append(f"- Tool Use ID：{code(tool_use_id)}")
if stop_hook_active:
    details.append(f"- Stop Hook Active：{code(stop_hook_active)}")
if agent_id or agent_type:
    details.append(f"- Agent ID：{code(agent_id)}")
    details.append(f"- Agent Type：{code(agent_type)}")

message_blocks = []
if event == "UserPromptSubmit" and prompt:
    message_blocks.extend(["**用户提示**", "", shorten(prompt, min(limit, 1200))])
elif event == "Stop" and last_assistant_message:
    message_blocks.extend(["**最终回复**", "", shorten(last_assistant_message, limit)])

if include_payload:
    payload_excerpt = shorten(payload, min(limit, 1600))
    if payload_excerpt:
        message_blocks.extend(["", "---", "", "**Payload 摘要**", "", f"```json\n{payload_excerpt}\n```"])

markdown_parts = [
    f"**事件**：{event}（{EVENT_ZH.get(event, '-')}）",
    "",
    "**工作目录**",
    code(cwd),
    "",
    "**基础信息**",
    f"- Session：{code(session_id)}",
    f"- Turn：{code(turn_id)}",
    f"- Model：{code(model)}",
    f"- Permission：{code(permission_mode)}",
    f"- Transcript：{code(transcript_path)}",
]

if details:
    markdown_parts.extend(["", "**事件详情**", *details])

if message_blocks:
    markdown_parts.extend(["", "---", "", *message_blocks])

markdown_parts.extend(["", "---", "", footer])

print(json.dumps({
    "skip": False,
    "event": event,
    "project": project,
    "title_summary": title_summary,
    "session_id": session_id,
    "turn_id": turn_id,
    "markdown": "\n".join(markdown_parts),
}, ensure_ascii=False))
PY
}

extract_json_bool_field() {
  local body="$1"
  local field="$2"
  printf '%s' "${body}" | sed -nE 's/.*"'"${field}"'"[[:space:]]*:[[:space:]]*(true|false).*/\1/p' | head -n 1
}

extract_json_string_field() {
  local body="$1"
  local field="$2"
  FEISHU_CODEX_HOOK_JSON="${body}" python3 - "$field" <<'PY'
import json
import os
import sys

field = sys.argv[1]
data = json.loads(os.environ.get("FEISHU_CODEX_HOOK_JSON", ""))
value = data.get(field, "")
print(value if isinstance(value, str) else "")
PY
}

build_payload_log_entry() {
  local raw="$1"
  FEISHU_CODEX_HOOK_PAYLOAD="${raw}" python3 - <<'PY'
import json
import os
from datetime import datetime, timezone

payload = json.loads(os.environ.get("FEISHU_CODEX_HOOK_PAYLOAD", ""))

SENSITIVE_KEYWORDS = (
    "token",
    "secret",
    "password",
    "passwd",
    "authorization",
    "cookie",
    "session",
    "api_key",
    "apikey",
    "access_key",
    "private_key",
)


def is_sensitive_key(key: str) -> bool:
    normalized = key.lower().replace("-", "_")
    return any(keyword in normalized for keyword in SENSITIVE_KEYWORDS)


def redact(value):
    if isinstance(value, dict):
        return {
            key: ("***REDACTED***" if is_sensitive_key(key) else redact(child))
            for key, child in value.items()
        }
    if isinstance(value, list):
        return [redact(item) for item in value]
    if isinstance(value, str):
        lowered = value.lower()
        if lowered.startswith("bearer ") or "authorization:" in lowered or "cookie:" in lowered:
            return "***REDACTED***"
    return value


event = ""
for key in ("hook_event_name", "hookEventName", "event_name", "eventName", "type"):
    value = payload.get(key)
    if value:
        event = str(value)
        break

entry = {
    "logged_at": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
    "event": event,
    "cwd": str(payload.get("cwd", "")),
    "payload": redact(payload),
}
print(json.dumps(entry, ensure_ascii=False))
PY
}

main() {
  local raw parsed skip event markdown project send_title payload_log_entry title_summary session_id turn_id prompt_title
  raw="$(read_payload "${1:-}")"

  if [[ -z "${raw}" ]]; then
    exit 0
  fi
  if [[ ! -x "${PUSH_SCRIPT}" ]]; then
    exit 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    exit 0
  fi

  if ! parsed="$(build_markdown_from_payload "${raw}")"; then
    exit 0
  fi

  if payload_log_entry="$(build_payload_log_entry "${raw}")"; then
    log_payload_line "${payload_log_entry}"
  fi

  event="$(extract_json_string_field "${parsed}" "event")"
  project="$(extract_json_string_field "${parsed}" "project")"
  title_summary="$(extract_json_string_field "${parsed}" "title_summary")"
  session_id="$(extract_json_string_field "${parsed}" "session_id")"
  turn_id="$(extract_json_string_field "${parsed}" "turn_id")"
  if [[ -z "${event}" ]]; then
    exit 0
  fi
  if [[ "${event}" == "UserPromptSubmit" ]]; then
    run_python_title_hook "${raw}"
  fi
  skip="$(extract_json_bool_field "${parsed}" "skip")"
  if [[ "${skip}" == "true" ]]; then
    exit 0
  fi

  markdown="$(extract_json_string_field "${parsed}" "markdown")"
  if [[ -z "${markdown}" ]]; then
    exit 0
  fi
  prompt_title="$(get_title_state "${session_id}" "${turn_id}")"
  if [[ "${event}" == "Stop" ]]; then
    run_python_title_hook "${raw}"
    trim_payload_log_lines 50
  fi

  send_title="${prompt_title:-${title_summary:-${event}}}"
  if [[ -n "${project}" && "${send_title}" != "[${project}]"* ]]; then
    send_title="[${project}] ${send_title}"
  fi
  send_title="${send_title} $(date +%H:%M:%S)"

  if [[ "${HOOK_ENABLE_PUSH}" =~ ^(1|true|yes|on)$ ]]; then
    "${PUSH_SCRIPT}" app-markdown --title "${send_title}" --template "${HOOK_TEMPLATE}" --markdown "${markdown}" >/tmp/feishu_codex_hook.out 2>/tmp/feishu_codex_hook.err || true
  fi

  # Codex hooks 不应因通知失败阻断主流程，也不应向 stdout 输出内容注入模型上下文。
  exit 0
}

case "${1:-}" in
  -h|--help|help)
    usage
    exit 0
    ;;
esac

if [[ "${1:-}" == "create" ]]; then
  shift || true
  create_hooks_json_files "${1:-auto}"
  exit 0
fi

main "$@"

#!/usr/bin/env bash
set -euo pipefail

# Codex notify hook：仅处理 agent-turn-complete，并通过飞书应用机器人发送 Markdown 卡片。
# Codex 配置示例：
#   notify = ["bash", "/mnt/sync2/www/agents/shell/feishu_bot/feishu_bot_codex_notify.sh"]

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd -- "$(dirname "$0")" && pwd)"
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

LOG_PATH="${FEISHU_CODEX_NOTIFY_LOG_PATH:-${SCRIPT_DIR}/codex_notify.log}"
MAX_MESSAGE_CHARS="${FEISHU_CODEX_NOTIFY_MAX_CHARS:-3500}"
NOTIFY_TITLE="${FEISHU_CODEX_NOTIFY_TITLE:-Codex 任务完成}"
NOTIFY_STATUS="${FEISHU_CODEX_NOTIFY_STATUS:-已完成}"
NOTIFY_TEMPLATE="${FEISHU_CODEX_NOTIFY_TEMPLATE:-green}"
NOTIFY_FOOTER="${FEISHU_CODEX_NOTIFY_FOOTER:-由 Codex notify 自动发送}"

die() {
  printf '[%s] 错误: %s\n' "${SCRIPT_NAME}" "$*" >&2
  exit 1
}

log_line() {
  local message="$1"
  local log_dir
  log_dir="$(dirname "${LOG_PATH}")"
  mkdir -p "${log_dir}"
  printf '[%s] %s\n' "$(date -Iseconds)" "${message}" >>"${LOG_PATH}"
}

build_markdown_from_payload() {
  local raw="$1"
  FEISHU_CODEX_NOTIFY_PAYLOAD="${raw}" python3 - "$MAX_MESSAGE_CHARS" "$NOTIFY_STATUS" "$NOTIFY_FOOTER" <<'PY'
import json
import os
import sys

limit = int(sys.argv[1])
status = sys.argv[2]
footer = sys.argv[3]
payload = json.loads(os.environ.get("FEISHU_CODEX_NOTIFY_PAYLOAD", ""))

event_type = str(payload.get("type", ""))
if event_type != "agent-turn-complete":
    print(json.dumps({"skip": True}, ensure_ascii=False))
    sys.exit(0)

thread_id = str(payload.get("thread-id", ""))
turn_id = str(payload.get("turn-id", ""))
cwd = str(payload.get("cwd", ""))
project = os.path.basename(os.path.normpath(cwd)) if cwd else ""
last_message = str(payload.get("last-assistant-message", "")).strip()

if len(last_message) > limit:
    last_message = last_message[:limit] + "\n\n...(已截断)"

markdown = "\n".join([
    f"**状态**：{status}",
    "",
    "**工作目录**",
    f"`{cwd or '-'}`",
    "",
    "**会话信息**",
    f"- Thread：`{thread_id or '-'}`",
    f"- Turn：`{turn_id or '-'}`",
    "",
    "---",
    "",
    "**最终回复**",
    "",
    last_message or "_无最终回复内容_",
    "",
    "---",
    "",
    footer,
])

print(json.dumps({"skip": False, "markdown": markdown, "project": project}, ensure_ascii=False))
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
  FEISHU_CODEX_NOTIFY_JSON="${body}" python3 - "$field" <<'PY'
import json
import os
import sys

field = sys.argv[1]
data = json.loads(os.environ.get("FEISHU_CODEX_NOTIFY_JSON", ""))
value = data.get(field, "")
print(value if isinstance(value, str) else "")
PY
}

main() {
  local raw="${1:-}"
  [[ -n "${raw}" ]] || die "缺少 Codex notify payload"
  [[ -x "${PUSH_SCRIPT}" ]] || die "推送脚本不可执行: ${PUSH_SCRIPT}"
  command -v python3 >/dev/null 2>&1 || die "未找到 python3"

  local parsed skip markdown project send_title
  if ! parsed="$(build_markdown_from_payload "${raw}")"; then
    log_line "parse_error"
    exit 0
  fi

  skip="$(extract_json_bool_field "${parsed}" "skip")"
  if [[ "${skip}" == "true" ]]; then
    exit 0
  fi

  markdown="$(extract_json_string_field "${parsed}" "markdown")"
  if [[ -z "${markdown}" ]]; then
    log_line "empty_markdown"
    exit 0
  fi

  project="$(extract_json_string_field "${parsed}" "project")"
  send_title="${NOTIFY_TITLE}"
  if [[ -n "${project}" && "${send_title}" != "[${project}]"* ]]; then
    send_title="[${project}] ${send_title}"
  fi

  if "${PUSH_SCRIPT}" app-markdown --title "${send_title}" --template "${NOTIFY_TEMPLATE}" --markdown "${markdown}" >/tmp/feishu_codex_notify.out 2>/tmp/feishu_codex_notify.err; then
    log_line "sent"
  else
    log_line "send_error=$(tr '\n' ' ' </tmp/feishu_codex_notify.err | cut -c 1-500)"
  fi

  # notify hook 不应阻断 Codex 主流程。
  exit 0
}

main "$@"

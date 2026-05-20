#!/bin/bash

AI_LOCALBASE_BACKGROUND_SYNC_SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AI_LOCALBASE_BACKGROUND_SYNC_DEFAULT_ENV_FILE="$AI_LOCALBASE_BACKGROUND_SYNC_SKILL_DIR/.env"
AI_LOCALBASE_BACKGROUND_SYNC_STATE_DIR_NAME=".ai-localbase-background"

# 将任意文本安全转成 JSON 字符串内容，避免手拼请求体时被引号或换行破坏。
ai_localbase_background_sync_json_escape() {
  local value="${1-}"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  value=${value//$'\f'/\\f}
  value=${value//$'\b'/\\b}
  printf '%s' "$value"
}

# 从简单 JSON 响应里提取目标字符串字段。
ai_localbase_background_sync_extract_json_string_field() {
  local json="$1"
  local field="$2"
  local needle rest

  needle="\"$field\":\""
  json=${json//$'\n'/}
  json=${json//$'\r'/}
  rest="${json#*"$needle"}"
  if [ "$rest" = "$json" ]; then
    return 1
  fi
  printf '%s' "${rest%%\"*}"
}

ai_localbase_background_sync_fail() {
  echo "错误: $1" >&2
  exit 1
}

ai_localbase_background_sync_ensure_requirements() {
  if ! command -v curl >/dev/null 2>&1; then
    ai_localbase_background_sync_fail "未找到 curl，请先安装 curl"
  fi
}

ai_localbase_background_sync_resolve_env_file() {
  if [ -f "$AI_LOCALBASE_BACKGROUND_SYNC_DEFAULT_ENV_FILE" ]; then
    printf '%s\n' "$AI_LOCALBASE_BACKGROUND_SYNC_DEFAULT_ENV_FILE"
    return 0
  fi

  return 1
}

ai_localbase_background_sync_load_env() {
  local env_file
  env_file="$(ai_localbase_background_sync_resolve_env_file)" || ai_localbase_background_sync_fail \
    "未找到 .env。请先在 ai-localbase-background skill 当前目录中配置 .env"

  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a

  : "${MCP_API_BASE_URL:?错误: $env_file 缺少 MCP_API_BASE_URL}"
  : "${MCP_AUTH_TOKEN:?错误: $env_file 缺少 MCP_AUTH_TOKEN}"

  export MCP_API_BASE_URL
  export MCP_AUTH_HEADER="Authorization: Bearer $MCP_AUTH_TOKEN"
  export AI_LOCALBASE_BACKGROUND_SYNC_ENV_FILE="$env_file"
}

ai_localbase_background_sync_resolve_work_dir() {
  local input="${1:-$(pwd)}"

  if [ -d "$input" ]; then
    (cd "$input" && pwd -P)
  else
    ai_localbase_background_sync_fail "目录不存在: $input"
  fi
}

ai_localbase_background_sync_resolve_kb_name() {
  local dir="$1"
  basename "$dir"
}

ai_localbase_background_sync_runtime_root() {
  local work_dir="$1"
  printf '%s/docs/%s\n' "$work_dir" "$AI_LOCALBASE_BACKGROUND_SYNC_STATE_DIR_NAME"
}

ai_localbase_background_sync_ensure_runtime_dirs() {
  mkdir -p "$AI_LOCALBASE_BACKGROUND_SYNC_STATE_DIR"
  mkdir -p "$AI_LOCALBASE_BACKGROUND_SYNC_STATE_DIR/queue"
  mkdir -p "$AI_LOCALBASE_BACKGROUND_SYNC_STATE_DIR/jobs"
  mkdir -p "$AI_LOCALBASE_BACKGROUND_SYNC_STATE_DIR/results"

  if [ ! -f "$AI_LOCALBASE_BACKGROUND_SYNC_KB_CONFIG" ]; then
    printf '{}\n' > "$AI_LOCALBASE_BACKGROUND_SYNC_KB_CONFIG"
  fi
}

ai_localbase_background_sync_read_cached_kb_id() {
  local key="$1"
  local content needle rest

  content="$(tr -d '\r\n' < "$AI_LOCALBASE_BACKGROUND_SYNC_KB_CONFIG")"
  needle="\"$(ai_localbase_background_sync_json_escape "$key")\":\""
  rest="${content#*"$needle"}"
  if [ "$rest" = "$content" ]; then
    return 1
  fi
  printf '%s' "${rest%%\"*}"
}

ai_localbase_background_sync_write_cached_kb_id() {
  local key="$1"
  local id="$2"
  local content escaped_key escaped_value

  content="$(tr -d '\r\n' < "$AI_LOCALBASE_BACKGROUND_SYNC_KB_CONFIG")"
  escaped_key="$(ai_localbase_background_sync_json_escape "$key")"
  escaped_value="$(ai_localbase_background_sync_json_escape "$id")"

  if [ "$content" = "{}" ]; then
    printf '{"%s":"%s"}\n' "$escaped_key" "$escaped_value" > "$AI_LOCALBASE_BACKGROUND_SYNC_KB_CONFIG.tmp"
  else
    printf '%s,"%s":"%s"}\n' "${content%}}" "$escaped_key" "$escaped_value" > "$AI_LOCALBASE_BACKGROUND_SYNC_KB_CONFIG.tmp"
  fi
  mv "$AI_LOCALBASE_BACKGROUND_SYNC_KB_CONFIG.tmp" "$AI_LOCALBASE_BACKGROUND_SYNC_KB_CONFIG"
}

ai_localbase_background_sync_post_tool_call() {
  local tool_name="$1"
  local body="$2"

  curl -s "$MCP_API_BASE_URL/tools/$tool_name/call" \
    -H 'Content-Type: application/json' \
    -H "$MCP_AUTH_HEADER" \
    -d "$body"
}

ai_localbase_background_sync_prepare_context() {
  local work_dir_input="${1:-$(pwd)}"

  ai_localbase_background_sync_ensure_requirements
  ai_localbase_background_sync_load_env

  export AI_LOCALBASE_BACKGROUND_SYNC_WORK_DIR
  AI_LOCALBASE_BACKGROUND_SYNC_WORK_DIR="$(ai_localbase_background_sync_resolve_work_dir "$work_dir_input")"

  export AI_LOCALBASE_BACKGROUND_SYNC_KB_NAME
  AI_LOCALBASE_BACKGROUND_SYNC_KB_NAME="$(ai_localbase_background_sync_resolve_kb_name "$AI_LOCALBASE_BACKGROUND_SYNC_WORK_DIR")"

  export AI_LOCALBASE_BACKGROUND_SYNC_STATE_DIR
  AI_LOCALBASE_BACKGROUND_SYNC_STATE_DIR="$(ai_localbase_background_sync_runtime_root "$AI_LOCALBASE_BACKGROUND_SYNC_WORK_DIR")"

  export AI_LOCALBASE_BACKGROUND_SYNC_KB_CONFIG
  AI_LOCALBASE_BACKGROUND_SYNC_KB_CONFIG="$AI_LOCALBASE_BACKGROUND_SYNC_STATE_DIR/knowledge.json"

  ai_localbase_background_sync_ensure_runtime_dirs
}

ai_localbase_background_sync_ensure_kb_id() {
  AI_LOCALBASE_BACKGROUND_SYNC_KB_ID="$(ai_localbase_background_sync_read_cached_kb_id "$AI_LOCALBASE_BACKGROUND_SYNC_KB_NAME" || true)"

  if [ -z "${AI_LOCALBASE_BACKGROUND_SYNC_KB_ID:-}" ]; then
    AI_LOCALBASE_BACKGROUND_SYNC_KB_ID="$(ai_localbase_background_sync_read_cached_kb_id "$AI_LOCALBASE_BACKGROUND_SYNC_WORK_DIR" || true)"
    if [ -n "${AI_LOCALBASE_BACKGROUND_SYNC_KB_ID:-}" ]; then
      ai_localbase_background_sync_write_cached_kb_id \
        "$AI_LOCALBASE_BACKGROUND_SYNC_KB_NAME" \
        "$AI_LOCALBASE_BACKGROUND_SYNC_KB_ID"
    fi
  fi

  if [ -n "${AI_LOCALBASE_BACKGROUND_SYNC_KB_ID:-}" ]; then
    export AI_LOCALBASE_BACKGROUND_SYNC_KB_ID
    return 0
  fi

  local response
  response="$(ai_localbase_background_sync_post_tool_call "knowledge_base.create" "$(printf '{"arguments":{"name":"%s","description":"%s"}}' \
    "$(ai_localbase_background_sync_json_escape "$AI_LOCALBASE_BACKGROUND_SYNC_KB_NAME")" \
    "$(ai_localbase_background_sync_json_escape "目录: $AI_LOCALBASE_BACKGROUND_SYNC_WORK_DIR")")")"

  AI_LOCALBASE_BACKGROUND_SYNC_KB_ID="$(
    ai_localbase_background_sync_extract_json_string_field "$response" "knowledgeBaseId" || true
  )"
  if [ -z "${AI_LOCALBASE_BACKGROUND_SYNC_KB_ID:-}" ]; then
    ai_localbase_background_sync_fail "创建知识库失败: $response"
  fi

  ai_localbase_background_sync_write_cached_kb_id \
    "$AI_LOCALBASE_BACKGROUND_SYNC_KB_NAME" \
    "$AI_LOCALBASE_BACKGROUND_SYNC_KB_ID"

  export AI_LOCALBASE_BACKGROUND_SYNC_KB_ID
}

ai_localbase_background_sync_init() {
  local work_dir_input="${1:-$(pwd)}"
  ai_localbase_background_sync_prepare_context "$work_dir_input"
  ai_localbase_background_sync_ensure_kb_id

  printf '{"status":"ok","mode":"sync","workDir":"%s","knowledgeBaseName":"%s","knowledgeBaseId":"%s","stateDir":"%s","envFile":"%s"}\n' \
    "$(ai_localbase_background_sync_json_escape "$AI_LOCALBASE_BACKGROUND_SYNC_WORK_DIR")" \
    "$(ai_localbase_background_sync_json_escape "$AI_LOCALBASE_BACKGROUND_SYNC_KB_NAME")" \
    "$(ai_localbase_background_sync_json_escape "$AI_LOCALBASE_BACKGROUND_SYNC_KB_ID")" \
    "$(ai_localbase_background_sync_json_escape "$AI_LOCALBASE_BACKGROUND_SYNC_STATE_DIR")" \
    "$(ai_localbase_background_sync_json_escape "$AI_LOCALBASE_BACKGROUND_SYNC_ENV_FILE")"
}

ai_localbase_background_sync_upload() {
  local filename="${1:-example.md}"
  local content="${2:-# 示例文档

这是测试内容。}"
  local work_dir_input="${3:-$(pwd)}"
  local response

  ai_localbase_background_sync_prepare_context "$work_dir_input"
  ai_localbase_background_sync_ensure_kb_id

  response="$(ai_localbase_background_sync_post_tool_call "document.upload" "$(printf '{"arguments":{"knowledgeBaseId":"%s","filename":"%s","content":"%s"}}' \
    "$(ai_localbase_background_sync_json_escape "$AI_LOCALBASE_BACKGROUND_SYNC_KB_ID")" \
    "$(ai_localbase_background_sync_json_escape "$filename")" \
    "$(ai_localbase_background_sync_json_escape "$content")")")"
  printf '%s\n' "$response"
}

ai_localbase_background_sync_append() {
  local document_id="${1:-}"
  local content="${2:-}"
  local work_dir_input="${3:-$(pwd)}"
  local response

  if [ -z "$document_id" ] || [ -z "$content" ]; then
    ai_localbase_background_sync_fail "append 需要 [documentId] [内容] [目录]"
  fi

  ai_localbase_background_sync_prepare_context "$work_dir_input"
  ai_localbase_background_sync_ensure_kb_id

  response="$(ai_localbase_background_sync_post_tool_call "document.append" "$(printf '{"arguments":{"knowledgeBaseId":"%s","documentId":"%s","content":"%s"}}' \
    "$(ai_localbase_background_sync_json_escape "$AI_LOCALBASE_BACKGROUND_SYNC_KB_ID")" \
    "$(ai_localbase_background_sync_json_escape "$document_id")" \
    "$(ai_localbase_background_sync_json_escape "$content")")")"
  printf '%s\n' "$response"
}

ai_localbase_background_sync_update() {
  local document_id="${1:-}"
  local content="${2:-}"
  local work_dir_input="${3:-$(pwd)}"
  local response

  if [ -z "$document_id" ] || [ -z "$content" ]; then
    ai_localbase_background_sync_fail "update 需要 [documentId] [内容] [目录]"
  fi

  ai_localbase_background_sync_prepare_context "$work_dir_input"
  ai_localbase_background_sync_ensure_kb_id

  response="$(ai_localbase_background_sync_post_tool_call "document.update" "$(printf '{"arguments":{"knowledgeBaseId":"%s","documentId":"%s","content":"%s"}}' \
    "$(ai_localbase_background_sync_json_escape "$AI_LOCALBASE_BACKGROUND_SYNC_KB_ID")" \
    "$(ai_localbase_background_sync_json_escape "$document_id")" \
    "$(ai_localbase_background_sync_json_escape "$content")")")"
  printf '%s\n' "$response"
}

ai_localbase_background_sync_delete() {
  local document_id="${1:-}"
  local work_dir_input="${2:-$(pwd)}"
  local response

  if [ -z "$document_id" ]; then
    ai_localbase_background_sync_fail "delete 需要 [documentId] [目录]"
  fi

  ai_localbase_background_sync_prepare_context "$work_dir_input"
  ai_localbase_background_sync_ensure_kb_id

  response="$(ai_localbase_background_sync_post_tool_call "document.delete" "$(printf '{"arguments":{"knowledgeBaseId":"%s","documentId":"%s"}}' \
    "$(ai_localbase_background_sync_json_escape "$AI_LOCALBASE_BACKGROUND_SYNC_KB_ID")" \
    "$(ai_localbase_background_sync_json_escape "$document_id")")")"
  printf '%s\n' "$response"
}

ai_localbase_background_sync_parse_query_args() {
  if [ -d "${1:-}" ]; then
    AI_LOCALBASE_BACKGROUND_SYNC_WORK_DIR_ARG="$1"
    AI_LOCALBASE_BACKGROUND_SYNC_QUERY_ARG="${2:-示例}"
    AI_LOCALBASE_BACKGROUND_SYNC_TOP_K_ARG="${3:-3}"
  else
    AI_LOCALBASE_BACKGROUND_SYNC_QUERY_ARG="${1:-示例}"
    AI_LOCALBASE_BACKGROUND_SYNC_WORK_DIR_ARG="${2:-$(pwd)}"
    AI_LOCALBASE_BACKGROUND_SYNC_TOP_K_ARG="${3:-3}"
  fi

  if ! [[ "$AI_LOCALBASE_BACKGROUND_SYNC_TOP_K_ARG" =~ ^[0-9]+$ ]]; then
    ai_localbase_background_sync_fail "search 的 topK 必须是数字: $AI_LOCALBASE_BACKGROUND_SYNC_TOP_K_ARG"
  fi
}

ai_localbase_background_sync_parse_message_args() {
  if [ -d "${1:-}" ]; then
    AI_LOCALBASE_BACKGROUND_SYNC_WORK_DIR_ARG="$1"
    AI_LOCALBASE_BACKGROUND_SYNC_MESSAGE_ARG="${2:-这是什么内容？}"
  else
    AI_LOCALBASE_BACKGROUND_SYNC_MESSAGE_ARG="${1:-这是什么内容？}"
    AI_LOCALBASE_BACKGROUND_SYNC_WORK_DIR_ARG="${2:-$(pwd)}"
  fi
}

ai_localbase_background_sync_search() {
  local response

  ai_localbase_background_sync_parse_query_args "$@"
  ai_localbase_background_sync_prepare_context "$AI_LOCALBASE_BACKGROUND_SYNC_WORK_DIR_ARG"
  ai_localbase_background_sync_ensure_kb_id

  response="$(ai_localbase_background_sync_post_tool_call "knowledge_base.search" "$(printf '{"arguments":{"knowledgeBaseId":"%s","query":"%s","topK":%s}}' \
    "$(ai_localbase_background_sync_json_escape "$AI_LOCALBASE_BACKGROUND_SYNC_KB_ID")" \
    "$(ai_localbase_background_sync_json_escape "$AI_LOCALBASE_BACKGROUND_SYNC_QUERY_ARG")" \
    "$AI_LOCALBASE_BACKGROUND_SYNC_TOP_K_ARG")")"
  printf '%s\n' "$response"
}

ai_localbase_background_sync_chat() {
  local response

  ai_localbase_background_sync_parse_message_args "$@"
  ai_localbase_background_sync_prepare_context "$AI_LOCALBASE_BACKGROUND_SYNC_WORK_DIR_ARG"
  ai_localbase_background_sync_ensure_kb_id

  response="$(ai_localbase_background_sync_post_tool_call "chat.ask" "$(printf '{"arguments":{"knowledgeBaseId":"%s","message":"%s"}}' \
    "$(ai_localbase_background_sync_json_escape "$AI_LOCALBASE_BACKGROUND_SYNC_KB_ID")" \
    "$(ai_localbase_background_sync_json_escape "$AI_LOCALBASE_BACKGROUND_SYNC_MESSAGE_ARG")")")"
  printf '%s\n' "$response"
}

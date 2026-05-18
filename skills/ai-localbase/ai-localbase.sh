#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
KB_CONFIG="$SCRIPT_DIR/knowledge.json"

usage() {
  cat <<'EOF'
用法:
  ./ai-localbase.sh init [目录]
  ./ai-localbase.sh upload [文件名] [内容] [目录]
  ./ai-localbase.sh append [documentId] [内容] [目录]
  ./ai-localbase.sh update [documentId] [内容] [目录]
  ./ai-localbase.sh delete [documentId] [目录]
  ./ai-localbase.sh search [关键词] [目录]
  ./ai-localbase.sh chat [问题] [目录]

说明:
  - init: 初始化当前目录对应的知识库映射并输出摘要 JSON
  - upload: 上传文本内容到知识库
  - append: 向已有文档追加文本内容
  - update: 用新内容覆盖已有文档
  - delete: 删除已有文档
  - search: 在知识库中检索片段
  - chat: 基于知识库上下文发起问答
EOF
}

# 将任意文本安全转成 JSON 字符串内容，避免手拼请求体时被引号或换行破坏。
json_escape() {
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
extract_json_string_field() {
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

ensure_requirements() {
  if ! command -v curl >/dev/null 2>&1; then
    echo "错误: 未找到 curl，请先安装 curl"
    exit 1
  fi
}

load_env() {
  if [ ! -f "$ENV_FILE" ]; then
    echo "错误: .env 文件不存在，请复制 .env.example 并配置"
    exit 1
  fi

  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a

  : "${MCP_API_BASE_URL:?错误: .env 中缺少 MCP_API_BASE_URL}"
  : "${MCP_AUTH_TOKEN:?错误: .env 中缺少 MCP_AUTH_TOKEN}"

  export MCP_API_BASE_URL
  export MCP_AUTH_HEADER="Authorization: Bearer $MCP_AUTH_TOKEN"
}

resolve_work_dir() {
  local input="${1:-$(pwd)}"

  if [ -d "$input" ]; then
    (cd "$input" && pwd -P)
  else
    printf '%s\n' "$input"
  fi
}

resolve_kb_name() {
  local dir="$1"
  basename "$dir"
}

ensure_kb_config() {
  if [ ! -f "$KB_CONFIG" ]; then
    printf '{}\n' > "$KB_CONFIG"
  fi
}

read_cached_kb_id() {
  local dir="$1"
  local content needle rest

  content="$(tr -d '\r\n' < "$KB_CONFIG")"
  needle="\"$(json_escape "$dir")\":\""
  rest="${content#*"$needle"}"
  if [ "$rest" = "$content" ]; then
    return 1
  fi
  printf '%s' "${rest%%\"*}"
}

write_cached_kb_id() {
  local dir="$1"
  local id="$2"
  local content key value

  content="$(tr -d '\r\n' < "$KB_CONFIG")"
  key="$(json_escape "$dir")"
  value="$(json_escape "$id")"

  if [ "$content" = "{}" ]; then
    printf '{"%s":"%s"}\n' "$key" "$value" > "$KB_CONFIG.tmp"
  else
    printf '%s,"%s":"%s"}\n' "${content%}}" "$key" "$value" > "$KB_CONFIG.tmp"
  fi
  mv "$KB_CONFIG.tmp" "$KB_CONFIG"
}

post_tool_call() {
  local tool_name="$1"
  local body="$2"

  curl -s "$MCP_API_BASE_URL/tools/$tool_name/call" \
    -H 'Content-Type: application/json' \
    -H "$MCP_AUTH_HEADER" \
    -d "$body"
}

prepare_context() {
  local work_dir_input="${1:-$(pwd)}"

  ensure_requirements
  load_env
  ensure_kb_config

  export WORK_DIR
  WORK_DIR="$(resolve_work_dir "$work_dir_input")"
  export KB_NAME
  KB_NAME="$(resolve_kb_name "$WORK_DIR")"
}

ensure_kb_id() {
  KB_ID="$(read_cached_kb_id "$KB_NAME" || true)"

  if [ -z "${KB_ID:-}" ]; then
    KB_ID="$(read_cached_kb_id "$WORK_DIR" || true)"
    if [ -n "${KB_ID:-}" ]; then
      write_cached_kb_id "$KB_NAME" "$KB_ID"
    fi
  fi

  if [ -n "${KB_ID:-}" ]; then
    echo "使用已有知识库 ID: $KB_ID"
    export KB_ID
    return 0
  fi

  echo "目录 $WORK_DIR 未找到知识库，正在创建..."

  local response
  response="$(post_tool_call "knowledge_base.create" "$(printf '{"arguments":{"name":"%s","description":"%s"}}' \
    "$(json_escape "$KB_NAME")" "$(json_escape "目录: $WORK_DIR")")")"

  KB_ID="$(extract_json_string_field "$response" "knowledgeBaseId" || true)"
  if [ -z "${KB_ID:-}" ]; then
    echo "创建知识库失败: $response"
    exit 1
  fi

  write_cached_kb_id "$KB_NAME" "$KB_ID"
  echo "知识库创建成功: $KB_NAME (ID: $KB_ID)"
  export KB_ID
}

cmd_init() {
  local work_dir_input="${1:-$(pwd)}"
  prepare_context "$work_dir_input"
  ensure_kb_id
  printf '{"workDir":"%s","knowledgeBaseName":"%s","knowledgeBaseId":"%s"}\n' \
    "$(json_escape "$WORK_DIR")" "$(json_escape "$KB_NAME")" "$(json_escape "$KB_ID")"
}

cmd_upload() {
  local filename="${1:-example.md}"
  local content="${2:-# 示例文档

这是测试内容。}"
  local work_dir_input="${3:-$(pwd)}"
  local response

  prepare_context "$work_dir_input"
  ensure_kb_id

  echo "上传文档到知识库: $KB_ID"
  response="$(post_tool_call "document.upload" "$(printf '{"arguments":{"knowledgeBaseId":"%s","filename":"%s","content":"%s"}}' \
    "$(json_escape "$KB_ID")" "$(json_escape "$filename")" "$(json_escape "$content")")")"
  printf '%s\n' "$response"
}

cmd_append() {
  local document_id="${1:-}"
  local content="${2:-}"
  local work_dir_input="${3:-$(pwd)}"
  local response

  if [ -z "$document_id" ] || [ -z "$content" ]; then
    echo "错误: append 需要 [documentId] [内容] [目录]"
    usage
    exit 1
  fi

  prepare_context "$work_dir_input"
  ensure_kb_id

  echo "追加文档到知识库: $KB_ID (文档: $document_id)"
  response="$(post_tool_call "document.append" "$(printf '{"arguments":{"knowledgeBaseId":"%s","documentId":"%s","content":"%s"}}' \
    "$(json_escape "$KB_ID")" "$(json_escape "$document_id")" "$(json_escape "$content")")")"
  printf '%s\n' "$response"
}

cmd_update() {
  local document_id="${1:-}"
  local content="${2:-}"
  local work_dir_input="${3:-$(pwd)}"
  local response

  if [ -z "$document_id" ] || [ -z "$content" ]; then
    echo "错误: update 需要 [documentId] [内容] [目录]"
    usage
    exit 1
  fi

  prepare_context "$work_dir_input"
  ensure_kb_id

  echo "覆盖文档到知识库: $KB_ID (文档: $document_id)"
  response="$(post_tool_call "document.update" "$(printf '{"arguments":{"knowledgeBaseId":"%s","documentId":"%s","content":"%s"}}' \
    "$(json_escape "$KB_ID")" "$(json_escape "$document_id")" "$(json_escape "$content")")")"
  printf '%s\n' "$response"
}

cmd_delete() {
  local document_id="${1:-}"
  local work_dir_input="${2:-$(pwd)}"
  local response

  if [ -z "$document_id" ]; then
    echo "错误: delete 需要 [documentId] [目录]"
    usage
    exit 1
  fi

  prepare_context "$work_dir_input"
  ensure_kb_id

  echo "删除文档: $KB_ID (文档: $document_id)"
  response="$(post_tool_call "document.delete" "$(printf '{"arguments":{"knowledgeBaseId":"%s","documentId":"%s"}}' \
    "$(json_escape "$KB_ID")" "$(json_escape "$document_id")")")"
  printf '%s\n' "$response"
}

cmd_search() {
  local query="${1:-示例}"
  local work_dir_input="${2:-$(pwd)}"
  local response

  prepare_context "$work_dir_input"
  ensure_kb_id

  echo "检索: $query (知识库: $KB_ID)"
  response="$(post_tool_call "knowledge_base.search" "$(printf '{"arguments":{"knowledgeBaseId":"%s","query":"%s","topK":3}}' \
    "$(json_escape "$KB_ID")" "$(json_escape "$query")")")"
  printf '%s\n' "$response"
}

cmd_chat() {
  local message="${1:-这是什么内容？}"
  local work_dir_input="${2:-$(pwd)}"
  local response

  prepare_context "$work_dir_input"
  ensure_kb_id

  echo "问答: $message (知识库: $KB_ID)"
  response="$(post_tool_call "chat.ask" "$(printf '{"arguments":{"knowledgeBaseId":"%s","message":"%s"}}' \
    "$(json_escape "$KB_ID")" "$(json_escape "$message")")")"
  printf '%s\n' "$response"
}

main() {
  local action="${1:-help}"
  shift || true

  case "$action" in
    init)
      cmd_init "${1:-$(pwd)}"
      ;;
    upload)
      cmd_upload "${1:-example.md}" "${2:-# 示例文档

这是测试内容。}" "${3:-$(pwd)}"
      ;;
    append)
      cmd_append "${1:-}" "${2:-}" "${3:-$(pwd)}"
      ;;
    update)
      cmd_update "${1:-}" "${2:-}" "${3:-$(pwd)}"
      ;;
    delete)
      cmd_delete "${1:-}" "${2:-$(pwd)}"
      ;;
    search)
      cmd_search "${1:-示例}" "${2:-$(pwd)}"
      ;;
    chat)
      cmd_chat "${1:-这是什么内容？}" "${2:-$(pwd)}"
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      echo "错误: 不支持的动作 $action"
      usage
      exit 1
      ;;
  esac
}

main "$@"

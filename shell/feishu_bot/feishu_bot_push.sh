#!/usr/bin/env bash
set -euo pipefail

# 飞书机器人消息推送工具。
# 默认读取脚本所在目录下的 .env；若不存在则兼容读取脚本目录下的 feishu.env。
# 可通过 FEISHU_ENV_FILE 或 FEISHU_BOT_ENV_FILE 指定其他配置文件。
#
# 环境变量方式：
#   FEISHU_BOT_WEBHOOK='https://open.feishu.cn/open-apis/bot/v2/hook/****' \
#   FEISHU_BOT_SECRET='<签名密钥，可选>' \
#   ./shell/feishu_bot/feishu_bot_push.sh text --text '部署完成'
#
# 参数方式：
#   ./shell/feishu_bot/feishu_bot_push.sh text \
#     --webhook 'https://open.feishu.cn/open-apis/bot/v2/hook/****' \
#     --secret '<签名密钥，可选>' \
#     --text '部署完成'
#
# 应用机器人方式：
#   FEISHU_APP_ID='cli_xxx' FEISHU_APP_SECRET='xxx' \
#   ./shell/feishu_bot/feishu_bot_push.sh app-text --email 'user@example.com' --text '部署完成'

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd -- "$(dirname "$0")" && pwd)"
DEFAULT_ENV_FILE="${SCRIPT_DIR}/.env"
LEGACY_ENV_FILE="${SCRIPT_DIR}/feishu.env"
ENV_FILE="${FEISHU_ENV_FILE:-${FEISHU_BOT_ENV_FILE:-${DEFAULT_ENV_FILE}}}"

pre_scan_env_file() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --env-file)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--env-file 需要参数"
        ENV_FILE="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
}

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

  # 仅加载本地约定配置，避免把 webhook 与签名密钥写进命令历史。
  # shellcheck disable=SC1090
  . "${env_file}"

  for var_name in "${preserved_names[@]}"; do
    printf -v "${var_name}" '%s' "${preserved_values[${var_name}]}"
    export "${var_name}"
  done
}

die() {
  printf '[%s] 错误: %s\n' "${SCRIPT_NAME}" "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
用法:
  ./${SCRIPT_NAME} [text|post|markdown|card|raw|lookup-user|app-text|app-markdown] [选项]
  ./${SCRIPT_NAME} '直接发送的文本'

说明:
  调用飞书机器人推送消息。默认是自定义机器人 webhook；app-text 走应用机器人 OpenAPI。
  默认读取脚本所在目录下的 .env（${DEFAULT_ENV_FILE}），不存在时兼容读取 feishu.env（${LEGACY_ENV_FILE}）。
  webhook、签名密钥、app_secret 属于敏感配置，建议用环境变量或 .env 管理，不要提交到仓库。

动作:
  text                 发送普通文本消息，默认动作
  post                 发送富文本消息，使用 --title 和 --text
  markdown             发送简单 Markdown 卡片，使用 --title 和 --markdown/--text
  card                 发送卡片 JSON 文件，使用 --card-file
  raw                  发送完整请求体 JSON 文件，使用 --payload-file
  lookup-user          通过邮箱或手机号查询 open_id/user_id
  app-text             使用应用机器人发送文本消息
  app-markdown         使用应用机器人发送 Markdown 卡片

自定义机器人必填:
  --webhook <url>      飞书自定义机器人 webhook，也可用 FEISHU_BOT_WEBHOOK

应用机器人必填:
  --app-id <id>        飞书应用 app_id，也可用 FEISHU_APP_ID
  --app-secret <value> 飞书应用 app_secret，也可用 FEISHU_APP_SECRET
  --email <value>      接收者邮箱，也可用 FEISHU_EMAIL
  --mobile <value>     接收者手机号，也可用 FEISHU_MOBILE
  --open-id <value>    接收者 open_id，也可用 FEISHU_OPEN_ID
  --user-id <value>    接收者 user_id，也可用 FEISHU_USER_ID
  --chat-id <value>    接收群 chat_id，也可用 FEISHU_CHAT_ID

可选:
  --secret <value>     飞书签名密钥，也可用 FEISHU_BOT_SECRET
  --text <value>       文本内容，也可用 FEISHU_BOT_TEXT
  --title <value>      富文本或卡片标题，也可用 FEISHU_BOT_TITLE
  --markdown <value>   Markdown 卡片内容，也可用 FEISHU_BOT_MARKDOWN
  --template <value>   卡片颜色模板，默认 ${CARD_TEMPLATE}，也可用 FEISHU_CARD_TEMPLATE
  --card-file <path>   card 对象 JSON 文件，也可用 FEISHU_BOT_CARD_FILE
  --payload-file <path>完整请求体 JSON 文件，也可用 FEISHU_BOT_PAYLOAD_FILE
  --timeout <seconds>  curl 超时时间，默认 ${TIMEOUT}
  --env-file <path>    本地配置文件，默认 ${DEFAULT_ENV_FILE}
  --dry-run            只打印请求体，不发送
  -h, --help           显示帮助

示例:
  ./${SCRIPT_NAME} '部署完成'
  ./${SCRIPT_NAME} text --text '应用报警：接口失败'
  ./${SCRIPT_NAME} markdown --title '发布结果' --markdown '**状态**：成功'
  ./${SCRIPT_NAME} card --card-file ./card.json
  ./${SCRIPT_NAME} raw --payload-file ./payload.json
  ./${SCRIPT_NAME} lookup-user --app-id 'cli_xxx' --app-secret '***' --email 'user@example.com'
  ./${SCRIPT_NAME} app-text --app-id 'cli_xxx' --app-secret '***' --email 'user@example.com' --text '部署完成'
  ./${SCRIPT_NAME} app-markdown --title 'Codex 通知' --markdown '### 任务完成'
EOF
}

pre_scan_env_file "$@"
load_feishu_env_file "${ENV_FILE}"

ACTION="text"
WEBHOOK_URL="${FEISHU_BOT_WEBHOOK:-${FEISHU_WEBHOOK:-}}"
SIGN_SECRET="${FEISHU_BOT_SECRET:-${FEISHU_SECRET:-}}"
TEXT="${FEISHU_BOT_TEXT:-}"
TITLE="${FEISHU_BOT_TITLE:-飞书机器人通知}"
MARKDOWN="${FEISHU_BOT_MARKDOWN:-}"
CARD_TEMPLATE="${FEISHU_CARD_TEMPLATE:-blue}"
CARD_FILE="${FEISHU_BOT_CARD_FILE:-}"
PAYLOAD_FILE="${FEISHU_BOT_PAYLOAD_FILE:-}"
TIMEOUT="${FEISHU_BOT_TIMEOUT:-30}"
DRY_RUN="false"
APP_ID="${FEISHU_APP_ID:-}"
APP_SECRET="${FEISHU_APP_SECRET:-}"
EMAIL="${FEISHU_EMAIL:-}"
MOBILE="${FEISHU_MOBILE:-}"
OPEN_ID="${FEISHU_OPEN_ID:-}"
USER_ID="${FEISHU_USER_ID:-}"
CHAT_ID="${FEISHU_CHAT_ID:-}"
RECEIVE_ID_TYPE="${FEISHU_RECEIVE_ID_TYPE:-}"

json_escape() {
  local value="${1:-}"
  local escaped="" char i
  local length="${#value}"
  for ((i = 0; i < length; i++)); do
    char="${value:i:1}"
    case "${char}" in
      '"')
        escaped+='\"'
        ;;
      "\\")
        escaped+='\\'
        ;;
      $'\n')
        escaped+='\n'
        ;;
      $'\r')
        escaped+='\r'
        ;;
      $'\t')
        escaped+='\t'
        ;;
      $'\b')
        escaped+='\b'
        ;;
      $'\f')
        escaped+='\f'
        ;;
      *)
        escaped+="${char}"
        ;;
    esac
  done
  printf '%s' "${escaped}"
}

read_text_file() {
  local file_path="$1"
  [[ -r "${file_path}" ]] || die "文件不可读: ${file_path}"
  printf '%s' "$(<"${file_path}")"
}

parse_args() {
  if [[ $# -gt 0 && "$1" != -* ]]; then
    case "$1" in
      text|send)
        ACTION="text"
        shift
        ;;
      post|markdown|card|raw|lookup-user|app-text|app-markdown)
        ACTION="$1"
        shift
        ;;
      *)
        TEXT="$1"
        ACTION="text"
        shift
        ;;
    esac
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --webhook|--url)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--webhook 需要参数"
        WEBHOOK_URL="$2"
        shift 2
        ;;
      --secret|--sign-secret)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--secret 需要参数"
        SIGN_SECRET="$2"
        shift 2
        ;;
      --app-id)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--app-id 需要参数"
        APP_ID="$2"
        shift 2
        ;;
      --app-secret)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--app-secret 需要参数"
        APP_SECRET="$2"
        shift 2
        ;;
      --email)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--email 需要参数"
        EMAIL="$2"
        shift 2
        ;;
      --mobile)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--mobile 需要参数"
        MOBILE="$2"
        shift 2
        ;;
      --open-id)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--open-id 需要参数"
        OPEN_ID="$2"
        shift 2
        ;;
      --user-id)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--user-id 需要参数"
        USER_ID="$2"
        shift 2
        ;;
      --chat-id)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--chat-id 需要参数"
        CHAT_ID="$2"
        shift 2
        ;;
      --receive-id-type)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--receive-id-type 需要参数"
        RECEIVE_ID_TYPE="$2"
        shift 2
        ;;
      --text|-m|--message)
        [[ $# -ge 2 ]] || die "--text 需要参数"
        TEXT="$2"
        shift 2
        ;;
      --title)
        [[ $# -ge 2 ]] || die "--title 需要参数"
        TITLE="$2"
        shift 2
        ;;
      --markdown)
        [[ $# -ge 2 ]] || die "--markdown 需要参数"
        MARKDOWN="$2"
        shift 2
        ;;
      --template)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--template 需要参数"
        CARD_TEMPLATE="$2"
        shift 2
        ;;
      --card-file)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--card-file 需要参数"
        CARD_FILE="$2"
        shift 2
        ;;
      --payload-file)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--payload-file 需要参数"
        PAYLOAD_FILE="$2"
        shift 2
        ;;
      --timeout)
        [[ $# -ge 2 && "${2:-}" =~ ^[0-9]+$ ]] || die "--timeout 需要正整数"
        TIMEOUT="$2"
        shift 2
        ;;
      --env-file)
        shift 2
        ;;
      --dry-run)
        DRY_RUN="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "未知参数: $1"
        ;;
    esac
  done
}

validate_common() {
  if [[ "${DRY_RUN}" != "true" ]]; then
    command -v curl >/dev/null 2>&1 || die "未找到 curl"
  fi
  [[ -n "${WEBHOOK_URL}" ]] || die "缺少 webhook，请通过 --webhook 或 FEISHU_BOT_WEBHOOK 传入"
  [[ "${WEBHOOK_URL}" == https://open.feishu.cn/open-apis/bot/v2/hook/* ]] || die "webhook 格式不符合飞书自定义机器人地址"
}

validate_app_common() {
  if [[ "${DRY_RUN}" != "true" ]]; then
    command -v curl >/dev/null 2>&1 || die "未找到 curl"
  fi
  [[ -n "${APP_ID}" ]] || die "缺少 app_id，请通过 --app-id 或 FEISHU_APP_ID 传入"
  [[ -n "${APP_SECRET}" ]] || die "缺少 app_secret，请通过 --app-secret 或 FEISHU_APP_SECRET 传入"
}

validate_lookup_target() {
  [[ -n "${EMAIL}" || -n "${MOBILE}" ]] || die "lookup-user 需要 --email 或 --mobile"
}

validate_app_send_target() {
  local target_count=0
  [[ -n "${CHAT_ID}" ]] && ((target_count += 1))
  [[ -n "${OPEN_ID}" ]] && ((target_count += 1))
  [[ -n "${USER_ID}" ]] && ((target_count += 1))
  [[ -n "${EMAIL}" ]] && ((target_count += 1))
  [[ -n "${MOBILE}" ]] && ((target_count += 1))
  ((target_count == 1)) || die "${ACTION} 需要且只能指定一种接收者: --chat-id/--open-id/--user-id/--email/--mobile"
  if [[ "${ACTION}" == "app-markdown" ]]; then
    [[ -n "${MARKDOWN}" || -n "${TEXT}" ]] || die "app-markdown 需要 --markdown 或 --text"
  else
    [[ -n "${TEXT}" ]] || die "app-text 需要 --text"
  fi
}

build_text_payload() {
  [[ -n "${TEXT}" ]] || die "text 动作需要 --text 或直接传入文本"
  printf '{"msg_type":"text","content":{"text":"%s"}}' "$(json_escape "${TEXT}")"
}

build_post_payload() {
  [[ -n "${TEXT}" ]] || die "post 动作需要 --text"
  printf '{"msg_type":"post","content":{"post":{"zh_cn":{"title":"%s","content":[[{"tag":"text","text":"%s"}]]}}}}' \
    "$(json_escape "${TITLE}")" \
    "$(json_escape "${TEXT}")"
}

build_markdown_payload() {
  local content="${MARKDOWN:-${TEXT}}"
  [[ -n "${content}" ]] || die "markdown 动作需要 --markdown 或 --text"
  printf '{"msg_type":"interactive","card":{"schema":"2.0","config":{"update_multi":true},"body":{"direction":"vertical","padding":"12px 12px 12px 12px","elements":[{"tag":"markdown","content":"%s","text_align":"left","text_size":"normal_v2"}]},"header":{"title":{"tag":"plain_text","content":"%s"},"template":"%s","padding":"12px 12px 12px 12px"}}}' \
    "$(json_escape "${content}")" \
    "$(json_escape "${TITLE}")" \
    "$(json_escape "${CARD_TEMPLATE}")"
}

build_card_payload() {
  [[ -n "${CARD_FILE}" ]] || die "card 动作需要 --card-file"
  local card_json
  card_json="$(read_text_file "${CARD_FILE}")"
  [[ -n "${card_json//[[:space:]]/}" ]] || die "card 文件为空"
  printf '{"msg_type":"interactive","card":%s}' "${card_json}"
}

build_raw_payload() {
  [[ -n "${PAYLOAD_FILE}" ]] || die "raw 动作需要 --payload-file"
  local payload_json
  payload_json="$(read_text_file "${PAYLOAD_FILE}")"
  [[ -n "${payload_json//[[:space:]]/}" ]] || die "payload 文件为空"
  printf '%s' "${payload_json}"
}

build_payload() {
  case "${ACTION}" in
    text)
      build_text_payload
      ;;
    post)
      build_post_payload
      ;;
    markdown)
      build_markdown_payload
      ;;
    card)
      build_card_payload
      ;;
    raw)
      build_raw_payload
      ;;
    *)
      die "不支持的动作: ${ACTION}"
      ;;
  esac
}

generate_sign() {
  local timestamp="$1"
  local secret="$2"
  local string_to_sign="${timestamp}"$'\n'"${secret}"
  command -v openssl >/dev/null 2>&1 || die "使用签名密钥需要安装 openssl"
  printf '' | openssl dgst -sha256 -hmac "${string_to_sign}" -binary | openssl base64 -A
}

add_signature() {
  local payload="$1"
  [[ -n "${SIGN_SECRET}" ]] || {
    printf '%s' "${payload}"
    return 0
  }

  local timestamp sign trimmed
  timestamp="$(date +%s)"
  sign="$(generate_sign "${timestamp}" "${SIGN_SECRET}")"
  trimmed="${payload#"${payload%%[![:space:]]*}"}"
  [[ "${trimmed}" == \{* ]] || die "请求体必须是 JSON object 才能追加签名"
  printf '{"timestamp":"%s","sign":"%s",%s' \
    "${timestamp}" \
    "$(json_escape "${sign}")" \
    "${trimmed#\{}"
}

validate_payload_size() {
  local payload="$1"
  local bytes
  bytes="$(printf '%s' "${payload}" | wc -c | tr -d '[:space:]')"
  [[ "${bytes}" =~ ^[0-9]+$ ]] || die "无法计算请求体大小"
  ((bytes <= 20480)) || die "请求体超过飞书 20KB 限制: ${bytes} bytes"
}

extract_json_number_field() {
  local body="$1"
  local field="$2"
  printf '%s' "${body}" | sed -nE 's/.*"'"${field}"'"[[:space:]]*:[[:space:]]*(-?[0-9]+).*/\1/p' | head -n 1
}

extract_json_string_field() {
  local body="$1"
  local field="$2"
  printf '%s' "${body}" | sed -nE 's/.*"'"${field}"'"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' | head -n 1
}

extract_first_user_id_field() {
  local body="$1"
  local field="$2"
  printf '%s' "${body}" | tr '\n' ' ' | sed -nE 's/.*"user_list"[[:space:]]*:[[:space:]]*\[[^]]*"'"${field}"'"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' | head -n 1
}

build_app_content_string() {
  printf '{"text":"%s"}' "$(json_escape "${TEXT}")"
}

build_app_markdown_content_string() {
  local content="${MARKDOWN:-${TEXT}}"
  [[ -n "${content}" ]] || die "app-markdown 需要 --markdown 或 --text"
  printf '{"schema":"2.0","config":{"update_multi":true},"body":{"direction":"vertical","padding":"12px 12px 12px 12px","elements":[{"tag":"markdown","content":"%s","text_align":"left","text_size":"normal_v2"}]},"header":{"title":{"tag":"plain_text","content":"%s"},"template":"%s","padding":"12px 12px 12px 12px"}}' \
    "$(json_escape "${content}")" \
    "$(json_escape "${TITLE}")" \
    "$(json_escape "${CARD_TEMPLATE}")"
}

request_json() {
  local url="$1"
  local payload="$2"
  shift 2
  local tmp_body http_status body code msg
  tmp_body="$(mktemp)"

  if ! http_status="$(
    curl -sS \
      -m "${TIMEOUT}" \
      -X POST \
      -H 'Content-Type: application/json' \
      "$@" \
      --data-binary "${payload}" \
      -o "${tmp_body}" \
      -w '%{http_code}' \
      "${url}"
  )"; then
    rm -f "${tmp_body}"
    die "curl 请求失败"
  fi

  body="$(<"${tmp_body}")"
  rm -f "${tmp_body}"
  [[ "${http_status}" =~ ^2[0-9][0-9]$ ]] || die "HTTP ${http_status}: ${body}"

  code="$(extract_json_number_field "${body}" "code")"
  if [[ -n "${code}" && "${code}" != "0" ]]; then
    msg="$(extract_json_string_field "${body}" "msg")"
    [[ -n "${msg}" ]] || msg="${body}"
    die "飞书返回错误 code=${code}: ${msg}"
  fi

  printf '%s' "${body}"
}

get_tenant_access_token() {
  local payload body token
  payload="$(printf '{"app_id":"%s","app_secret":"%s"}' "$(json_escape "${APP_ID}")" "$(json_escape "${APP_SECRET}")")"
  body="$(request_json 'https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal' "${payload}")"
  token="$(extract_json_string_field "${body}" "tenant_access_token")"
  [[ -n "${token}" ]] || die "飞书未返回 tenant_access_token"
  printf '%s' "${token}"
}

lookup_user_id() {
  local token="$1"
  local id_type="${2:-open_id}"
  local payload body open_id user_id

  case "${id_type}" in
    open_id|user_id|union_id)
      ;;
    *)
      die "不支持的 user_id_type: ${id_type}"
      ;;
  esac

  if [[ -n "${EMAIL}" ]]; then
    payload="$(printf '{"emails":["%s"]}' "$(json_escape "${EMAIL}")")"
  else
    payload="$(printf '{"mobiles":["%s"]}' "$(json_escape "${MOBILE}")")"
  fi

  body="$(request_json "https://open.feishu.cn/open-apis/contact/v3/users/batch_get_id?user_id_type=${id_type}" "${payload}" -H "Authorization: Bearer ${token}")"
  open_id="$(extract_first_user_id_field "${body}" "open_id")"
  user_id="$(extract_first_user_id_field "${body}" "user_id")"

  if [[ "${id_type}" == "user_id" ]]; then
    [[ -n "${user_id}" ]] || die "未查到 user_id，请确认通讯录权限、邮箱/手机号和用户状态"
    printf '%s' "${user_id}"
    return 0
  fi

  [[ -n "${open_id}" ]] || die "未查到 open_id，请确认通讯录权限、邮箱/手机号和用户状态"
  printf '%s' "${open_id}"
}

run_lookup_user() {
  validate_app_common
  validate_lookup_target

  local token id_type resolved_id
  id_type="${RECEIVE_ID_TYPE:-open_id}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    printf '{"action":"lookup-user","user_id_type":"%s"}\n' "$(json_escape "${id_type}")"
    return 0
  fi

  token="$(get_tenant_access_token)"
  resolved_id="$(lookup_user_id "${token}" "${id_type}")"
  printf '{"%s":"%s"}\n' "${id_type}" "$(json_escape "${resolved_id}")"
}

resolve_receive_target() {
  local token="$1"
  local resolved_id
  if [[ -n "${CHAT_ID}" ]]; then
    printf 'chat_id\t%s' "${CHAT_ID}"
  elif [[ -n "${OPEN_ID}" ]]; then
    printf 'open_id\t%s' "${OPEN_ID}"
  elif [[ -n "${USER_ID}" ]]; then
    printf 'user_id\t%s' "${USER_ID}"
  elif [[ -n "${EMAIL}" ]]; then
    resolved_id="$(lookup_user_id "${token}" "open_id")" || return 1
    printf 'open_id\t%s' "${resolved_id}"
  elif [[ -n "${MOBILE}" ]]; then
    resolved_id="$(lookup_user_id "${token}" "open_id")" || return 1
    printf 'open_id\t%s' "${resolved_id}"
  else
    die "缺少接收者"
  fi
}

run_app_text() {
  validate_app_common
  validate_app_send_target

  local token target receive_id_type receive_id content payload body
  if [[ "${DRY_RUN}" == "true" ]]; then
    content="$(build_app_content_string)"
    printf '{"receive_id":"<resolved>","msg_type":"text","content":"%s"}\n' "$(json_escape "${content}")"
    return 0
  fi

  token="$(get_tenant_access_token)"
  target="$(resolve_receive_target "${token}")" || die "解析接收者失败"
  receive_id_type="${target%%$'\t'*}"
  receive_id="${target#*$'\t'}"
  content="$(build_app_content_string)"
  payload="$(printf '{"receive_id":"%s","msg_type":"text","content":"%s"}' \
    "$(json_escape "${receive_id}")" \
    "$(json_escape "${content}")")"

  body="$(request_json "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=${receive_id_type}" "${payload}" -H "Authorization: Bearer ${token}")"
  printf '%s\n' "${body}"
}

run_app_markdown() {
  validate_app_common
  validate_app_send_target

  local token target receive_id_type receive_id content payload body
  if [[ "${DRY_RUN}" == "true" ]]; then
    content="$(build_app_markdown_content_string)"
    printf '{"receive_id":"<resolved>","msg_type":"interactive","content":"%s"}\n' "$(json_escape "${content}")"
    return 0
  fi

  token="$(get_tenant_access_token)"
  target="$(resolve_receive_target "${token}")" || die "解析接收者失败"
  receive_id_type="${target%%$'\t'*}"
  receive_id="${target#*$'\t'}"
  content="$(build_app_markdown_content_string)"
  payload="$(printf '{"receive_id":"%s","msg_type":"interactive","content":"%s"}' \
    "$(json_escape "${receive_id}")" \
    "$(json_escape "${content}")")"

  body="$(request_json "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=${receive_id_type}" "${payload}" -H "Authorization: Bearer ${token}")"
  printf '%s\n' "${body}"
}

send_payload() {
  local payload="$1"
  local tmp_body http_status body code msg
  tmp_body="$(mktemp)"

  if ! http_status="$(
    curl -sS \
      -m "${TIMEOUT}" \
      -X POST \
      -H 'Content-Type: application/json' \
      --data-binary "${payload}" \
      -o "${tmp_body}" \
      -w '%{http_code}' \
      "${WEBHOOK_URL}"
  )"; then
    rm -f "${tmp_body}"
    die "curl 请求失败"
  fi

  body="$(<"${tmp_body}")"
  rm -f "${tmp_body}"
  [[ "${http_status}" =~ ^2[0-9][0-9]$ ]] || die "HTTP ${http_status}: ${body}"

  code="$(extract_json_number_field "${body}" "code")"
  if [[ -n "${code}" && "${code}" != "0" ]]; then
    msg="$(extract_json_string_field "${body}" "msg")"
    [[ -n "${msg}" ]] || msg="${body}"
    die "飞书返回错误 code=${code}: ${msg}"
  fi

  printf '%s\n' "${body}"
}

main() {
  parse_args "$@"

  case "${ACTION}" in
    lookup-user)
      run_lookup_user
      return 0
      ;;
    app-text)
      run_app_text
      return 0
      ;;
    app-markdown)
      run_app_markdown
      return 0
      ;;
  esac

  validate_common

  local payload
  payload="$(build_payload)"
  payload="$(add_signature "${payload}")"
  validate_payload_size "${payload}"

  if [[ "${DRY_RUN}" == "true" ]]; then
    printf '%s\n' "${payload}"
    return 0
  fi

  send_payload "${payload}"
}

main "$@"

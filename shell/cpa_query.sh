#!/usr/bin/env bash
set -euo pipefail

# 调用方式：
#   CPA_BASE_URL='http://<管理服务地址>:<端口>' \
#   CPA_MANAGEMENT_TOKEN='<remote-management token>' \
#   ./cpa_query.sh
#
# 等价参数方式：
#   ./cpa_query.sh \
#     --base-url 'http://<管理服务地址>:<端口>' \
#     --management-token '<remote-management token>'
#
# 设置账号优先级：
#   ./cpa_query.sh priority \
#     --base-url 'http://<管理服务地址>:<端口>' \
#     --management-token '<remote-management token>' \
#     --name '3块钱.json' \
#     --priority 8
#
# 设置账号优先级（等价别名）：
#   ./cpa_query.sh set-priority \
#     --base-url 'http://<管理服务地址>:<端口>' \
#     --management-token '<remote-management token>' \
#     --name '3块钱.json' \
#     --priority 8
#
# 设置账号优先级（省略 action，检测到 --name/--priority 后自动切到 priority）：
#   ./cpa_query.sh \
#     --base-url 'http://<管理服务地址>:<端口>' \
#     --management-token '<remote-management token>' \
#     --name '3块钱.json' \
#     --priority 8
#
# 更新字段（显式 fields）：
#   ./cpa_query.sh fields \
#     --base-url 'http://<管理服务地址>:<端口>' \
#     --management-token '<remote-management token>' \
#     --field-name '3块钱.json' \
#     --field-priority 8
#
# 更新字段（省略 action，检测到 --field-* 后自动切到 fields）：
#   ./cpa_query.sh \
#     --base-url 'http://<管理服务地址>:<端口>' \
#     --management-token '<remote-management token>' \
#     --field-name '3块钱.json' \
#     --field-priority 8
#
# 自动处理订阅临近账号的优先级：
#   ./cpa_query.sh auto-priority \
#     --base-url 'http://<管理服务地址>:<端口>' \
#     --management-token '<remote-management token>'
#
# 默认查询账号额度和管理端当天用量后写入提示词快照 cp_query.json：
#   ./cpa_query.sh \
#     --base-url 'http://<管理服务地址>:<端口>' \
#     --management-token '<remote-management token>'
#
# 读取本地 cp_query.json 生成图片提示词：
#   ./cpa_query.sh --prompt
#
# 自动查询账号额度和管理端当天用量并输出图片提示词（先生成 cp_query.json，再读取它生成 prompt）：
#   ./cpa_query.sh \
#     --base-url 'http://<管理服务地址>:<端口>' \
#     --management-token '<remote-management token>' && \
#   ./cpa_query.sh --prompt
#
# 读取指定提示词快照文件：
#   ./cpa_query.sh --prompt --prompt-file '/path/to/cp_query.json'
#
# 列出已禁用账号：
#   ./cpa_query.sh disabled-list \
#     --base-url 'http://<管理服务地址>:<端口>' \
#     --management-token '<remote-management token>'
#
# 删除 auth-file 账号：
#   ./cpa_query.sh delete-auth \
#     --base-url 'http://<管理服务地址>:<端口>' \
#     --management-token '<remote-management token>' \
#     --name '3块钱.json'
#
# 查询管理端当天用量汇总，并同步更新 cp_query.json：
#   ./cpa_query.sh management-usage \
#     --base-url 'http://<管理服务地址>:<端口>' \
#     --management-token '<remote-management token>'
#   # 也可用 --usage-base-url 覆盖。
#
# api-call 目标固定为 ChatGPT usage 地址。
# 可选：追加 `usage` 只输出用量查询；追加 `auth-files` 只输出 auth-files 原始响应；
#      追加 `management-usage` / `server-usage` 查询管理端 `/usage` 汇总；
#      追加 `disabled-list` / `disabled` 只列出 auth-files 中 disabled=true 的账号；
#      追加 `delete-auth` / `delete-auth-file` 删除指定 auth-file 账号；
#      追加 `priority` / `set-priority` 设置单个账号优先级；
#      追加 `fields` 更新单个 auth-file 的字段（当前支持 priority，保留兼容）；
#      追加 `auto-priority` 自动调整 priority。
#      优先级说明：1=正常账号；8=free；9=即将过期或已过期；11=日抛。
#      规则：plan_type=free 的账号固定调整到优先级 8；plan_type 以本次 api-call 为准；
#           非 free 账号只要订阅剩余 3 天内或已过期未满 10 天，统一调整到优先级 9；
#           已过期达到 10 天及以上时，不调整当前优先级；
#           api-call 返回 401 时禁用账号；free 周额度用完时自动禁用，到周刷新时间后自动启用。

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd -- "$(dirname "$0")" && pwd)"
CURRENT_DIR="${PWD:-$(pwd)}"
DEFAULT_ENV_FILE="${CURRENT_DIR}/cpa.env"
ENV_FILE="${CPA_ENV_FILE:-${DEFAULT_ENV_FILE}}"
CACHE_DIR="${CPA_CACHE_DIR:-${SCRIPT_DIR}/.cache}"
CACHE_TTL="${CPA_CACHE_TTL:-300}"

load_cpa_env_file() {
  local env_file="${1:-}"
  local -a preserved_names=()
  local -A preserved_values=()
  local var_name
  [[ -n "${env_file}" ]] || return 0
  [[ -f "${env_file}" ]] || return 0

  while IFS= read -r var_name; do
    [[ -n "${var_name}" ]] || continue
    preserved_names+=("${var_name}")
    preserved_values["${var_name}"]="${!var_name}"
  done < <(compgen -A variable CPA_ || true)

  # 仅加载当前工作区内约定路径的本地配置文件，用于减少重复传参。
  # shellcheck disable=SC1090
  . "${env_file}"

  for var_name in "${preserved_names[@]}"; do
    printf -v "${var_name}" '%s' "${preserved_values[${var_name}]}"
    export "${var_name}"
  done
}

load_cpa_env_file "${ENV_FILE}"

BASE_URL="${CPA_BASE_URL:-}"
USAGE_BASE_URL="${CPA_USAGE_BASE_URL:-}"
USAGE_PORT="${CPA_USAGE_PORT:-18317}"
MANAGEMENT_TOKEN="${CPA_MANAGEMENT_TOKEN:-}"
TARGET_URL="https://chatgpt.com/backend-api/wham/usage"
TARGET_METHOD="${CPA_TARGET_METHOD:-GET}"
TARGET_AUTH_HEADER="${CPA_TARGET_AUTH_HEADER:-Bearer \$TOKEN\$}"
CHATGPT_ACCOUNT_ID="${CPA_CHATGPT_ACCOUNT_ID:-}"
FIELD_NAME="${CPA_FIELD_NAME:-}"
FIELD_PRIORITY="${CPA_FIELD_PRIORITY:-}"
PROMPT_FILE="${CPA_PROMPT_FILE:-${SCRIPT_DIR}/../cp_query.json}"
STATE_FILE="${CPA_STATE_FILE:-${PROMPT_FILE}}"
STATE_FILE_EXPLICIT="false"
LEGACY_STATE_FILE="${SCRIPT_DIR}/../cpa_query.json"
TIMEOUT="${CPA_TIMEOUT:-30}"
USAGE_TIMEOUT="${CPA_USAGE_TIMEOUT:-120}"
INCLUDE_MANAGEMENT_USAGE="${CPA_INCLUDE_MANAGEMENT_USAGE:-false}"
MAX_PARALLEL_JOBS="${CPA_MAX_PARALLEL_JOBS:-5}"
INSECURE="true"
ACTION="all"
ACTION_EXPLICIT="false"
PRIORITY_ACTION_REQUESTED="false"

BROWSER_USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36"
TARGET_USER_AGENT="${CPA_TARGET_USER_AGENT:-codex_cli_rs/0.76.0 (Debian 13.0.0; x86_64) WindowsTerminal}"
declare -a CURL_ARGS=()
declare -a AUTH_NAMES=()
declare -a AUTH_NOTES=()
declare -a AUTH_PRIORITIES=()
declare -a AUTH_INDEXES=()
declare -a AUTH_ACCOUNT_IDS=()
declare -a AUTH_PLAN_TYPES=()
declare -a AUTH_SUBSCRIPTION_STARTS=()
declare -a AUTH_SUBSCRIPTION_UNTILS=()
declare -a AUTH_DISABLED_FLAGS=()
declare -a RESULT_ROWS=()
declare -a SUMMARY_5H_ITEMS=()
declare -a SUMMARY_WEEK_ITEMS=()
declare -a SUMMARY_EXPIRY_ITEMS=()
declare -a SUMMARY_FREE_ITEMS=()
declare -a SUMMARY_ERROR_NAMES=()
declare -a SUMMARY_PLAN_CHANGE_ITEMS=()
declare -a AUTO_PRIORITY_LINES=()
SUMMARY_TOTAL=0
SUMMARY_OK=0
SUMMARY_ERROR=0
SUMMARY_SUM_5H=0
SUMMARY_SUM_WEEK=0
SUMMARY_ITEM_ORDER=0
AUTO_PRIORITY_MANAGED=0
AUTO_PRIORITY_RESTORED=0
AUTO_PRIORITY_UNCHANGED=0

usage() {
  cat <<EOF
用法:
  ./${SCRIPT_NAME} [all|auth-files|usage|management-usage|server-usage|disabled-list|disabled|delete-auth|delete-auth-file|priority|set-priority|fields|auto-priority] [选项]

说明:
  查询 cliproxyapi remote management 接口。
  默认会先读取当前运行目录下的 cpa.env（${DEFAULT_ENV_FILE}）；如需覆盖路径，可设置 CPA_ENV_FILE。
  默认执行 all：先查询 auth-files，再按 name/authIndex 逐个查询 ChatGPT usage 并执行自动禁用，
               然后对未禁用账号自动处理 priority，最后写入 ${PROMPT_FILE}。
  默认查询不会输出看板图片提示词，而是把本次结果写入 ${PROMPT_FILE}。
  management-usage / server-usage：查询 GET /v0/management/usage，输出当天接口与模型汇总，并同步更新 ${PROMPT_FILE}。
  默认 all/usage 不采集 management usage 快照，避免大响应拖慢账号额度查询；需要时加 --with-management-usage。
  disabled-list / disabled：只读取 auth-files 并列出 disabled=true 的账号，不触发 usage 查询或状态更新。
  delete-auth / delete-auth-file：调用 DELETE /v0/management/auth-files 删除 --name 指定的账号。
  priority / set-priority：设置指定账号的 priority。
  fields：调用 PATCH /v0/management/auth-files/fields 更新单个账号字段。
  优先级说明：1=正常账号；8=free；9=即将过期或已过期；11=日抛。
  auto-priority：plan_type=free 的账号固定调到 8；plan_type 以本次 api-call 为准；
                 非 free 账号只要订阅剩余 3 天内或已过期未满 10 天，统一调到 9；
                 已过期达到 10 天及以上时，不调整当前优先级；
                 当前 priority 已经 >= 8 的账号跳过自动调整。
                 api-call 返回 401 时禁用账号；free 周额度用完时自动禁用，到周刷新时间后自动启用。
                 若同一账号上次 api-call plan_type=plus、本次为 free，会输出套餐提醒。
  --prompt：不发起查询，直接读取 ${PROMPT_FILE} 并生成看板图片提示词。
  若未显式指定动作，但传入了 --field-name/--field-priority，则会自动切到 fields。

必填:
  --base-url <url>                 管理接口地址，也可用 CPA_BASE_URL
  --management-token <token>       remote-management Bearer token，也可用 CPA_MANAGEMENT_TOKEN

选项:
  --target-method <method>         api-call 目标方法，默认 ${TARGET_METHOD}
  --target-auth-header <value>     目标请求 Authorization，默认保留 Bearer \$TOKEN\$ 占位
  --account-id <id>                Chatgpt-Account-Id，也可用 CPA_CHATGPT_ACCOUNT_ID
  --usage-base-url <url>           management-usage 专用地址，也可用 CPA_USAGE_BASE_URL
  --usage-port <port>              management-usage 自动派生端口，默认 ${USAGE_PORT}
  --usage-timeout <seconds>        management-usage 专用超时时间，默认 ${USAGE_TIMEOUT}
  --with-management-usage          all/usage 写快照时附带采集 /v0/management/usage，也可用 CPA_INCLUDE_MANAGEMENT_USAGE=true
  --name <name>                    priority/delete-auth 动作必填，目标账号名
  --priority <int>                 priority 动作必填，目标优先级
  --field-name <name>              fields 动作必填，目标账号名，也可用 CPA_FIELD_NAME
  --field-priority <int>           fields 动作必填，目标优先级，也可用 CPA_FIELD_PRIORITY
  --state-file <path>              auto-priority 状态数据路径，默认复用 ${PROMPT_FILE}
  --prompt                         读取本地提示词快照并输出看板图片提示词
  --prompt-file <path>             提示词快照文件路径，默认 ${PROMPT_FILE}
  --timeout <seconds>              curl 超时时间，默认 ${TIMEOUT}
  --no-insecure                    不向 curl 传递 --insecure
  -h, --help                       显示帮助

示例:
  CPA_BASE_URL='http://127.0.0.1:3318' CPA_MANAGEMENT_TOKEN='***' ./${SCRIPT_NAME}
  ./${SCRIPT_NAME} usage --base-url 'http://127.0.0.1:3318' --management-token '***'
  ./${SCRIPT_NAME} management-usage --base-url 'http://127.0.0.1:3318' --management-token '***'
  ./${SCRIPT_NAME} disabled-list --base-url 'http://127.0.0.1:3318' --management-token '***'
  ./${SCRIPT_NAME} delete-auth --base-url 'http://127.0.0.1:3318' --management-token '***' --name '3块钱.json'
  ./${SCRIPT_NAME} priority --base-url 'http://127.0.0.1:3318' --management-token '***' --name '3块钱.json' --priority 8
  ./${SCRIPT_NAME} fields --base-url 'http://127.0.0.1:3318' --management-token '***' --field-name '3块钱.json' --field-priority 8
  ./${SCRIPT_NAME} auto-priority --base-url 'http://127.0.0.1:3318' --management-token '***'
  ./${SCRIPT_NAME} --prompt
EOF
}

die() {
  printf '[%s] 错误: %s\n' "${SCRIPT_NAME}" "$*" >&2
  exit 1
}

log() {
  printf '[%s] %s\n' "${SCRIPT_NAME}" "$*" >&2
}

get_cache_key() {
  local action="$1"
  printf '%s_%s' "${action}" "$(printf '%s' "${BASE_URL}${MANAGEMENT_TOKEN}" | md5sum | cut -d' ' -f1)"
}

is_cache_valid() {
  local cache_file="$1"
  [[ -f "${cache_file}" ]] || return 1
  local age=$(($(date +%s) - $(stat -c %Y "${cache_file}" 2>/dev/null || stat -f %m "${cache_file}" 2>/dev/null || echo 0)))
  ((age < CACHE_TTL))
}

get_cached_or_fetch() {
  local cache_key="$1"
  local fetch_func="$2"
  local cache_file="${CACHE_DIR}/${cache_key}"

  if is_cache_valid "${cache_file}"; then
    cat "${cache_file}"
    return 0
  fi

  local result
  result="$("${fetch_func}")"
  mkdir -p "${CACHE_DIR}"
  printf '%s' "${result}" > "${cache_file}"
  printf '%s' "${result}"
}

truncate_text() {
  local value="${1:-}"
  local max_length="${2:-20}"

  if (( ${#value} <= max_length )); then
    printf '%s' "${value}"
  else
    printf '%s...' "${value:0:max_length}"
  fi
}

compact_error_reason() {
  local reason="${1:-未知错误}"
  local prefix=""
  local message=""

  reason="${reason//$'\r'/ }"
  reason="${reason//$'\n'/ }"

  if [[ "${reason}" =~ ^(HTTP[[:space:]][0-9]+:[[:space:]]+)(.*)$ ]]; then
    prefix="${BASH_REMATCH[1]}"
    message="${BASH_REMATCH[2]}"
    printf '%s%s' "${prefix}" "$(truncate_text "${message}" 20)"
    return 0
  fi

  printf '%s' "$(truncate_text "${reason}" 20)"
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "${value}"
}

parse_args() {
  if [[ $# -gt 0 && "$1" != -* ]]; then
    ACTION="$1"
    ACTION_EXPLICIT="true"
    shift
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base-url)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--base-url 需要参数"
        BASE_URL="${2%/}"
        shift 2
        ;;
      --management-token)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--management-token 需要参数"
        MANAGEMENT_TOKEN="$2"
        shift 2
        ;;
      --target-method)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--target-method 需要参数"
        TARGET_METHOD="$2"
        shift 2
        ;;
      --target-auth-header)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--target-auth-header 需要参数"
        TARGET_AUTH_HEADER="$2"
        shift 2
        ;;
      --account-id)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--account-id 需要参数"
        CHATGPT_ACCOUNT_ID="$2"
        shift 2
        ;;
      --usage-base-url)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--usage-base-url 需要参数"
        USAGE_BASE_URL="${2%/}"
        shift 2
        ;;
      --usage-port)
        [[ $# -ge 2 && "${2:-}" =~ ^[0-9]+$ ]] || die "--usage-port 需要整数端口"
        USAGE_PORT="$2"
        shift 2
        ;;
      --usage-timeout)
        [[ $# -ge 2 && "${2:-}" =~ ^[0-9]+$ ]] || die "--usage-timeout 需要整数秒数"
        USAGE_TIMEOUT="$2"
        shift 2
        ;;
      --with-management-usage)
        INCLUDE_MANAGEMENT_USAGE="true"
        shift
        ;;
      --name)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--name 需要参数"
        FIELD_NAME="$2"
        PRIORITY_ACTION_REQUESTED="true"
        shift 2
        ;;
      --priority)
        [[ $# -ge 2 && "${2:-}" =~ ^-?[0-9]+$ ]] || die "--priority 需要整数"
        FIELD_PRIORITY="$2"
        PRIORITY_ACTION_REQUESTED="true"
        shift 2
        ;;
      --field-name)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--field-name 需要参数"
        FIELD_NAME="$2"
        shift 2
        ;;
      --field-priority)
        [[ $# -ge 2 && "${2:-}" =~ ^-?[0-9]+$ ]] || die "--field-priority 需要整数"
        FIELD_PRIORITY="$2"
        shift 2
        ;;
      --state-file)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--state-file 需要参数"
        STATE_FILE="$2"
        STATE_FILE_EXPLICIT="true"
        shift 2
        ;;
      --prompt)
        ACTION="prompt"
        ACTION_EXPLICIT="true"
        shift
        ;;
      --prompt-file)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--prompt-file 需要参数"
        PROMPT_FILE="$2"
        if [[ "${STATE_FILE_EXPLICIT}" != "true" ]]; then
          STATE_FILE="${PROMPT_FILE}"
        fi
        shift 2
        ;;
      --timeout)
        [[ $# -ge 2 && "${2:-}" =~ ^[0-9]+$ ]] || die "--timeout 需要整数秒数"
        TIMEOUT="$2"
        shift 2
        ;;
      --no-insecure)
        INSECURE="false"
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

  if [[ "${ACTION_EXPLICIT}" == "false" && "${PRIORITY_ACTION_REQUESTED}" == "true" ]]; then
    ACTION="priority"
  elif [[ "${ACTION_EXPLICIT}" == "false" ]] && [[ -n "${FIELD_NAME}" || -n "${FIELD_PRIORITY}" ]]; then
    ACTION="fields"
  fi
}

ensure_requirements() {
  case "${ACTION}" in
    all|auth-files|usage|management-usage|server-usage|disabled-list|disabled|delete-auth|delete-auth-file|priority|set-priority|fields|auto-priority|prompt)
      ;;
    *)
      die "未知动作: ${ACTION}，请使用 all/auth-files/usage/management-usage/server-usage/disabled-list/disabled/delete-auth/delete-auth-file/priority/set-priority/fields/auto-priority 或 --prompt"
      ;;
  esac

  if [[ "${ACTION}" == "prompt" ]]; then
    command -v jq >/dev/null 2>&1 || die "--prompt 需要 jq 来解析 ${PROMPT_FILE}"
    [[ -f "${PROMPT_FILE}" ]] || die "提示词快照不存在: ${PROMPT_FILE}"
    return 0
  fi

  command -v curl >/dev/null 2>&1 || die "未找到 curl"
  [[ -n "${BASE_URL}" ]] || die "缺少管理接口地址，请通过 --base-url 或 CPA_BASE_URL 传入"
  [[ -n "${MANAGEMENT_TOKEN}" ]] || die "缺少管理 Token，请通过 --management-token 或 CPA_MANAGEMENT_TOKEN 传入"

  if [[ "${ACTION}" == "all" || "${ACTION}" == "usage" || "${ACTION}" == "management-usage" || "${ACTION}" == "server-usage" || "${ACTION}" == "disabled-list" || "${ACTION}" == "disabled" || "${ACTION}" == "auto-priority" ]]; then
    command -v jq >/dev/null 2>&1 || die "${ACTION} 需要 jq 来解析 JSON 响应"
  fi

  if [[ "${ACTION}" == "fields" || "${ACTION}" == "priority" || "${ACTION}" == "set-priority" ]]; then
    [[ -n "${FIELD_NAME}" ]] || die "${ACTION} 动作缺少账号名，请传入 --name 或 --field-name"
    [[ "${FIELD_PRIORITY}" =~ ^-?[0-9]+$ ]] || die "${ACTION} 动作缺少合法优先级，请传入 --priority 或 --field-priority"
  fi

  if [[ "${ACTION}" == "delete-auth" || "${ACTION}" == "delete-auth-file" ]]; then
    [[ -n "${FIELD_NAME}" ]] || die "${ACTION} 动作缺少账号名，请传入 --name"
  fi
}

build_curl_common_args() {
  local referer_base_url="${1:-${BASE_URL}}"
  local request_timeout="${2:-${TIMEOUT}}"
  CURL_ARGS=(
    --silent
    --show-error
    --location
    --connect-timeout "${TIMEOUT}"
    --max-time "${request_timeout}"
    -H "Accept: application/json, text/plain, */*"
    -H "Accept-Language: zh-CN,zh;q=0.9,en;q=0.8,ja;q=0.7"
    -H "Authorization: Bearer ${MANAGEMENT_TOKEN}"
    -H "Referer: ${referer_base_url}/management.html"
    -H "User-Agent: ${BROWSER_USER_AGENT}"
  )

  if [[ "${INSECURE}" == "true" ]]; then
    CURL_ARGS+=(--insecure)
  fi
}

derive_usage_base_url() {
  local source_url="${1%/}"

  if [[ -n "${USAGE_BASE_URL}" ]]; then
    printf '%s' "${USAGE_BASE_URL%/}"
    return 0
  fi

  if [[ "${source_url}" =~ ^(https?://[^/:]+):[0-9]+$ ]]; then
    printf '%s:%s' "${BASH_REMATCH[1]}" "${USAGE_PORT}"
    return 0
  fi

  if [[ "${source_url}" =~ ^(https?://[^/]+)(/.*)?$ ]]; then
    printf '%s:%s' "${BASH_REMATCH[1]}" "${USAGE_PORT}"
    return 0
  fi

  printf '%s' "${source_url}"
}

fetch_auth_files() {
  build_curl_common_args
  curl "${CURL_ARGS[@]}" "${BASE_URL}/v0/management/auth-files"
}

fetch_auth_files_cached() {
  local cache_key
  cache_key="$(get_cache_key "auth_files")"
  get_cached_or_fetch "${cache_key}" fetch_auth_files
}

fetch_management_usage() {
  local usage_base_url
  usage_base_url="$(derive_usage_base_url "${BASE_URL}")"
  build_curl_common_args "${usage_base_url}" "${USAGE_TIMEOUT}"
  curl "${CURL_ARGS[@]}" "${usage_base_url}/v0/management/usage"
}

is_supported_management_usage_response() {
  local response="$1"

  printf '%s' "${response}" | jq -e '
    type == "object"
    and (
      (.apis | type) == "object"
      or (.total_requests? != null)
    )
  ' >/dev/null 2>&1
}

build_auth_fields_payload() {
  local field_name="$1"
  local field_priority="$2"
  printf '{"name":"%s","priority":%s}' \
    "$(json_escape "${field_name}")" \
    "${field_priority}"
}

build_auth_status_payload() {
  local field_name="$1"
  local disabled="$2"
  printf '{"name":"%s","disabled":%s}' \
    "$(json_escape "${field_name}")" \
    "${disabled}"
}

build_auth_delete_payload() {
  local field_name="$1"
  printf '{"names":["%s"]}' "$(json_escape "${field_name}")"
}

patch_auth_fields() {
  local field_name="$1"
  local field_priority="$2"
  local payload
  build_curl_common_args
  payload="$(build_auth_fields_payload "${field_name}" "${field_priority}")"

  curl "${CURL_ARGS[@]}" \
    -X PATCH \
    -H "Content-Type: application/json" \
    -H "Origin: ${BASE_URL}" \
    --data-raw "${payload}" \
    "${BASE_URL}/v0/management/auth-files/fields"
}

patch_auth_status() {
  local field_name="$1"
  local disabled="$2"
  local payload
  build_curl_common_args
  payload="$(build_auth_status_payload "${field_name}" "${disabled}")"

  curl "${CURL_ARGS[@]}" \
    -X PATCH \
    -H "Content-Type: application/json" \
    -H "Origin: ${BASE_URL}" \
    --data-raw "${payload}" \
    "${BASE_URL}/v0/management/auth-files/status"
}

delete_auth_file() {
  local field_name="$1"
  local payload
  build_curl_common_args
  payload="$(build_auth_delete_payload "${field_name}")"

  curl "${CURL_ARGS[@]}" \
    -X DELETE \
    -H "Content-Type: application/json" \
    -H "Origin: ${BASE_URL}" \
    --data-raw "${payload}" \
    "${BASE_URL}/v0/management/auth-files"
}

disable_auth_entry_if_needed() {
  local field_name="$1"
  local index="$2"
  local reason="${3:-异常}"
  local disabled_flag="${AUTH_DISABLED_FLAGS[index]:-"false"}"

  if [[ "${disabled_flag}" == "true" ]]; then
    return 0
  fi

  log "自动禁用账号: ${field_name}（${reason}）"
  patch_auth_status "${field_name}" "true" >/dev/null
  AUTH_DISABLED_FLAGS[index]="true"
}

enable_auth_entry_if_needed() {
  local field_name="$1"
  local index="$2"
  local reason="${3:-恢复}"
  local disabled_flag="${AUTH_DISABLED_FLAGS[index]:-"false"}"

  if [[ "${disabled_flag}" != "true" ]]; then
    return 0
  fi

  log "自动启用账号: ${field_name}（${reason}）"
  patch_auth_status "${field_name}" "false" >/dev/null
  AUTH_DISABLED_FLAGS[index]="false"
}

query_auth_files() {
  log "查询 auth-files"
  fetch_auth_files
  printf '\n'
}

update_auth_fields() {
  log "更新 auth-fields: ${FIELD_NAME} -> priority ${FIELD_PRIORITY}"
  patch_auth_fields "${FIELD_NAME}" "${FIELD_PRIORITY}"
  printf '\n'
}

set_auth_priority() {
  log "设置账号优先级: ${FIELD_NAME} -> ${FIELD_PRIORITY}"
  patch_auth_fields "${FIELD_NAME}" "${FIELD_PRIORITY}"
  printf '\n'
}

delete_auth_file_action() {
  log "删除 auth-file: ${FIELD_NAME}"
  delete_auth_file "${FIELD_NAME}"
  printf '\n'
}

current_timestamp_utc() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

current_timestamp_local() {
  date '+%Y-%m-%dT%H:%M:%S%z' | sed -E 's/([+-][0-9]{2})([0-9]{2})$/\1:\2/'
}

normalize_iso_timezone() {
  local value="$1"
  printf '%s' "${value}" | sed -E 's/([+-][0-9]{2}):([0-9]{2})$/\1\2/'
}

parse_datetime_to_epoch() {
  local value="$1"
  local normalized_value

  if [[ -z "${value}" || "${value}" == "-" ]]; then
    return 1
  fi

  if date -d "${value}" '+%s' >/dev/null 2>&1; then
    date -d "${value}" '+%s'
    return 0
  fi

  normalized_value="$(normalize_iso_timezone "${value}")"
  if date -j -f '%Y-%m-%dT%H:%M:%S%z' "${normalized_value}" '+%s' >/dev/null 2>&1; then
    date -j -f '%Y-%m-%dT%H:%M:%S%z' "${normalized_value}" '+%s'
    return 0
  fi

  return 1
}

ensure_state_file() {
  local merged_state_json

  # 状态数据已并入 cp_query.json 的 state 节点：托管 priority、free 周额度定时启用、套餐变化提醒都统一落这里。
  merged_state_json="$(
    if [[ -f "${LEGACY_STATE_FILE}" ]] && jq -e '
      type == "object"
      and (.managed_priorities? == null or (.managed_priorities | type) == "object")
      and (.free_weekly_disabled? == null or (.free_weekly_disabled | type) == "object")
      and (.plan_types? == null or (.plan_types | type) == "object")
    ' "${LEGACY_STATE_FILE}" >/dev/null 2>&1; then
      jq -c '{
        managed_priorities: (.managed_priorities // {}),
        free_weekly_disabled: (.free_weekly_disabled // {}),
        plan_types: (.plan_types // {})
      }' "${LEGACY_STATE_FILE}"
    else
      printf '%s' '{"managed_priorities":{},"free_weekly_disabled":{},"plan_types":{}}'
    fi
  )"

  if [[ ! -f "${STATE_FILE}" ]]; then
    mkdir -p "$(dirname "${STATE_FILE}")"
    jq -n --argjson merged_state "${merged_state_json}" '{state: $merged_state}' > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "${STATE_FILE}" || {
      rm -f "${STATE_FILE}.tmp"
      die "初始化状态数据失败: ${STATE_FILE}"
    }
    return 0
  fi

  jq -e 'type == "object"' "${STATE_FILE}" >/dev/null 2>&1 || die "状态文件 ${STATE_FILE} 不是合法的 cp_query.json 结构"

  if ! jq -e '
    (.state? == null or (.state | type) == "object")
    and (.state.managed_priorities? == null or (.state.managed_priorities | type) == "object")
    and (.state.free_weekly_disabled? == null or (.state.free_weekly_disabled | type) == "object")
    and (.state.plan_types? == null or (.state.plan_types | type) == "object")
  ' "${STATE_FILE}" >/dev/null 2>&1; then
    die "状态文件 ${STATE_FILE} 不是合法的 cp_query.json 结构"
  fi

  jq \
    --argjson merged_state "${merged_state_json}" \
    '.state //= $merged_state
    | .state.managed_priorities //= ($merged_state.managed_priorities // {})
    | .state.free_weekly_disabled //= ($merged_state.free_weekly_disabled // {})
    | .state.plan_types //= ($merged_state.plan_types // {})' \
    "${STATE_FILE}" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "${STATE_FILE}" || {
      rm -f "${STATE_FILE}.tmp"
      die "升级状态数据失败: ${STATE_FILE}"
    }
}

state_get_original_priority() {
  local name="$1"
  jq -r --arg name "${name}" '.state.managed_priorities[$name].original_priority // empty' "${STATE_FILE}"
}

state_set_managed_priority() {
  local name="$1"
  local original_priority="$2"
  local last_applied_priority="$3"
  local subscription_until="$4"

  jq \
    --arg name "${name}" \
    --argjson original_priority "${original_priority}" \
    --argjson last_applied_priority "${last_applied_priority}" \
    --arg subscription_until "${subscription_until}" \
    --arg updated_at "$(current_timestamp_utc)" \
    '.state.managed_priorities[$name] = {
      original_priority: $original_priority,
      last_applied_priority: $last_applied_priority,
      subscription_until: $subscription_until,
      updated_at: $updated_at
    }' \
    "${STATE_FILE}" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "${STATE_FILE}" || {
      rm -f "${STATE_FILE}.tmp"
      die "写入状态文件失败: ${STATE_FILE}"
    }
}

state_remove_managed_priority() {
  local name="$1"

  jq --arg name "${name}" 'del(.state.managed_priorities[$name])' "${STATE_FILE}" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "${STATE_FILE}" || {
    rm -f "${STATE_FILE}.tmp"
    die "清理状态文件失败: ${STATE_FILE}"
  }
}

state_get_free_weekly_restore_epoch() {
  local name="$1"
  jq -r --arg name "${name}" '.state.free_weekly_disabled[$name].restore_epoch // empty' "${STATE_FILE}"
}

state_set_free_weekly_disabled() {
  local name="$1"
  local restore_epoch="$2"
  local restore_at="$3"
  local reason="$4"

  jq \
    --arg name "${name}" \
    --argjson restore_epoch "${restore_epoch}" \
    --arg restore_at "${restore_at}" \
    --arg reason "${reason}" \
    --arg disabled_at "$(current_timestamp_utc)" \
    '.state.free_weekly_disabled[$name] = {
      restore_epoch: $restore_epoch,
      restore_at: $restore_at,
      reason: $reason,
      disabled_at: $disabled_at
    }' \
    "${STATE_FILE}" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "${STATE_FILE}" || {
      rm -f "${STATE_FILE}.tmp"
      die "写入 free 周额度禁用状态失败: ${STATE_FILE}"
    }
}

state_remove_free_weekly_disabled() {
  local name="$1"

  jq --arg name "${name}" 'del(.state.free_weekly_disabled[$name])' "${STATE_FILE}" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "${STATE_FILE}" || {
    rm -f "${STATE_FILE}.tmp"
    die "清理 free 周额度禁用状态失败: ${STATE_FILE}"
  }
}

state_get_plan_type() {
  local name="$1"
  jq -r --arg name "${name}" '.state.plan_types[$name].plan_type // empty' "${STATE_FILE}"
}

prompt_snapshot_get_plan_type() {
  local name="$1"

  [[ -f "${PROMPT_FILE}" ]] || return 0
  jq -r --arg name "${name}" '
    (
      .auth[]?
      | select(.name == $name)
      | .plan_type
    ) // (
      .result_rows[]?
      | select(.name == $name)
      | .plan_info
    ) // empty
  ' "${PROMPT_FILE}" 2>/dev/null | head -n 1
}

get_previous_plan_type() {
  local name="$1"
  local previous_plan_type

  previous_plan_type="$(prompt_snapshot_get_plan_type "${name}")"
  if [[ -n "${previous_plan_type}" && "${previous_plan_type}" != "-" ]]; then
    printf '%s' "${previous_plan_type}"
    return 0
  fi

  state_get_plan_type "${name}"
}

state_set_plan_type() {
  local name="$1"
  local plan_type="$2"

  [[ -n "${plan_type}" && "${plan_type}" != "-" ]] || return 0

  jq \
    --arg name "${name}" \
    --arg plan_type "${plan_type}" \
    --arg updated_at "$(current_timestamp_utc)" \
    '.state.plan_types[$name] = {
      plan_type: $plan_type,
      updated_at: $updated_at
    }' \
    "${STATE_FILE}" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "${STATE_FILE}" || {
      rm -f "${STATE_FILE}.tmp"
      die "写入套餐状态失败: ${STATE_FILE}"
    }
}

compute_auto_priority() {
  local subscription_until_epoch="$1"
  local now_epoch="$2"
  local remaining_seconds

  [[ -n "${subscription_until_epoch}" ]] || return 0

  remaining_seconds=$((subscription_until_epoch - now_epoch))
  # 非 free 账号只保留两种自动档位：正常账号 priority 1；临期或过期 10 天内账号 priority 9。
  if (( remaining_seconds >= 259200 || remaining_seconds <= -864000 )); then
    return 0
  else
    printf '9'
  fi
}

format_remaining_duration() {
  local remaining_seconds="$1"
  local abs_seconds days hours

  abs_seconds="${remaining_seconds}"
  if (( abs_seconds < 0 )); then
    abs_seconds=$(( -abs_seconds ))
  fi

  days=$((abs_seconds / 86400))
  hours=$(((abs_seconds % 86400) / 3600))

  if (( remaining_seconds < 0 )); then
    printf '已过期 %s天%s小时' "${days}" "${hours}"
  else
    printf '%s天%s小时' "${days}" "${hours}"
  fi
}

format_precise_duration() {
  local remaining_seconds="$1"
  local abs_seconds days hours minutes seconds

  abs_seconds="${remaining_seconds}"
  if (( abs_seconds < 0 )); then
    abs_seconds=$(( -abs_seconds ))
  fi

  days=$((abs_seconds / 86400))
  hours=$(((abs_seconds % 86400) / 3600))
  minutes=$(((abs_seconds % 3600) / 60))
  seconds=$((abs_seconds % 60))

  if (( remaining_seconds < 0 )); then
    printf '已过期%s天%02d时%02d分%02d秒' "${days}" "${hours}" "${minutes}" "${seconds}"
  else
    printf '剩余%s天%02d时%02d分%02d秒' "${days}" "${hours}" "${minutes}" "${seconds}"
  fi
}

reset_auto_priority_report() {
  AUTO_PRIORITY_LINES=()
  AUTO_PRIORITY_MANAGED=0
  AUTO_PRIORITY_RESTORED=0
  AUTO_PRIORITY_UNCHANGED=0
}

record_auto_priority_line() {
  AUTO_PRIORITY_LINES+=("$1")
}

print_auto_priority_report() {
  local line

  printf '\n'
  printf '## 优先级调整\n'
  printf -- '- 概要：调整 %s；恢复 %s；未变更 %s\n' \
    "${AUTO_PRIORITY_MANAGED}" \
    "${AUTO_PRIORITY_RESTORED}" \
    "${AUTO_PRIORITY_UNCHANGED}"

  if [[ "${#AUTO_PRIORITY_LINES[@]}" -eq 0 ]]; then
    printf -- '- 明细：无\n'
  else
    printf '\n'
    printf '### 调整明细\n'
    for line in "${AUTO_PRIORITY_LINES[@]}"; do
      printf -- '- %s\n' "${line}"
    done
  fi
}

print_auto_priority_rules() {
  printf '优先级处理规则：\n'
  printf '1. 优先级定义：1=正常账号；8=free；9=即将过期或已过期；11=日抛。\n'
  printf '2. free 账号固定调整到优先级 8，不使用订阅时间做恢复判断。\n'
  printf '3. 若上次快照为非 free、本次 api-call 变为 free，立即按 free 逻辑调到 8。\n'
  printf '4. 当前 priority 已经 >= 8 的账号跳过自动调整；priority 11 的日抛账号保持人工控制。\n'
  printf '5. 非 free 账号只保留 priority 1 和 9：剩余 3 天内或已过期未满 10 天时统一调整到 9；已过期达到 10 天及以上时保持当前优先级。\n'
  printf '6. free 账号只看周额度；周额度用完时自动禁用，到周刷新时间后自动启用。\n'
  printf '7. 已记录的 free 周额度禁用账号，到期后会自动启用。\n'
  printf '\n'
}

restore_free_weekly_disabled_entries_for_current_entries() {
  local total="${#AUTH_INDEXES[@]}"
  local index=0
  local now_epoch
  local name plan_type disabled_flag restore_epoch

  now_epoch="$(date '+%s')"

  while [[ "${index}" -lt "${total}" ]]; do
    name="${AUTH_NAMES[index]:-"(未命名)"}"
    plan_type="${AUTH_PLAN_TYPES[index]:-"-"}"
    disabled_flag="${AUTH_DISABLED_FLAGS[index]:-"false"}"
    restore_epoch="$(state_get_free_weekly_restore_epoch "${name}")"

    if [[ -z "${restore_epoch}" ]]; then
      index=$((index + 1))
      continue
    fi

    if [[ "${plan_type}" != "free" ]]; then
      # 套餐已经不是 free 时，旧的 free 周额度禁用记录不再适用。
      state_remove_free_weekly_disabled "${name}"
      index=$((index + 1))
      continue
    fi

    if [[ ! "${restore_epoch}" =~ ^[0-9]+$ ]]; then
      log "free 周额度禁用状态异常，跳过自动启用: ${name}"
      index=$((index + 1))
      continue
    fi

    if (( now_epoch >= restore_epoch )); then
      enable_auth_entry_if_needed "${name}" "${index}" "free 周额度刷新"
      state_remove_free_weekly_disabled "${name}"
    elif [[ "${disabled_flag}" != "true" ]]; then
      # 账号已被人工启用时清理托管记录，避免后续误恢复。
      state_remove_free_weekly_disabled "${name}"
    fi

    index=$((index + 1))
  done
}

auto_manage_priorities_for_current_entries() {
  local total
  local index=0
  local now_epoch
  local name priority plan_type disabled_flag subscription_until original_priority target_priority subscription_until_epoch

  ensure_state_file
  reset_auto_priority_report
  print_auto_priority_rules
  total="${#AUTH_INDEXES[@]}"
  now_epoch="$(date '+%s')"

  [[ "${total}" -gt 0 ]] || die "没有可处理的 auth-files"
  restore_free_weekly_disabled_entries_for_current_entries

  while [[ "${index}" -lt "${total}" ]]; do
    name="${AUTH_NAMES[index]:-"(未命名)"}"
    priority="${AUTH_PRIORITIES[index]:-"-"}"
    plan_type="${AUTH_PLAN_TYPES[index]:-"-"}"
    disabled_flag="${AUTH_DISABLED_FLAGS[index]:-"false"}"
    subscription_until="${AUTH_SUBSCRIPTION_UNTILS[index]:-"-"}"
    original_priority="$(state_get_original_priority "${name}")"
    subscription_until_epoch=""
    target_priority=""

    if [[ "${disabled_flag}" == "true" ]]; then
      # 禁用账号不再参与 priority 调整，避免刚被禁用的账号继续被调度提权。
      AUTO_PRIORITY_UNCHANGED=$((AUTO_PRIORITY_UNCHANGED + 1))
      index=$((index + 1))
      continue
    fi

    if [[ "${priority}" =~ ^-?[0-9]+$ ]] && (( priority >= 8 )); then
      # 账号当前已经处在高优先级区间时，不再做自动提权或恢复处理。
      AUTO_PRIORITY_UNCHANGED=$((AUTO_PRIORITY_UNCHANGED + 1))
      index=$((index + 1))
      continue
    fi

    if [[ "${plan_type}" == "free" ]]; then
      if [[ -n "${original_priority}" ]]; then
        # free 没有订阅恢复语义；清理旧版本留下的 priority 托管记录。
        state_remove_managed_priority "${name}"
      fi
      if [[ "${priority}" == "8" ]]; then
        AUTO_PRIORITY_UNCHANGED=$((AUTO_PRIORITY_UNCHANGED + 1))
        index=$((index + 1))
        continue
      fi
      [[ "${priority}" =~ ^-?[0-9]+$ ]] || die "账号 ${name} 的当前 priority 非法: ${priority}"
      log "free 账号调整优先级: ${name} ${priority} -> 8"
      patch_auth_fields "${name}" "8" >/dev/null
      record_auto_priority_line "free调整: ${name} | ${priority} -> 8"
      AUTH_PRIORITIES[index]="8"
      AUTO_PRIORITY_MANAGED=$((AUTO_PRIORITY_MANAGED + 1))
      index=$((index + 1))
      continue
    fi

    if subscription_until_epoch="$(parse_datetime_to_epoch "${subscription_until}")"; then
      target_priority="$(compute_auto_priority "${subscription_until_epoch}" "${now_epoch}")"
    fi

    if [[ -n "${target_priority}" ]]; then
      if [[ "${priority}" != "${target_priority}" ]]; then
        log "临期或过期非 free 账号提权: ${name} ${priority} -> ${target_priority}"
        patch_auth_fields "${name}" "${target_priority}" >/dev/null
        AUTH_PRIORITIES[index]="${target_priority}"
        AUTO_PRIORITY_MANAGED=$((AUTO_PRIORITY_MANAGED + 1))
        record_auto_priority_line "临期/过期提权: ${name} | ${priority} -> ${target_priority} | plan_type ${plan_type} | 到期 $(format_subscription_time "${subscription_until}")"
      else
        AUTO_PRIORITY_UNCHANGED=$((AUTO_PRIORITY_UNCHANGED + 1))
      fi
      if [[ -n "${original_priority}" ]]; then
        state_remove_managed_priority "${name}"
      fi
      index=$((index + 1))
      continue
    fi

    if [[ -n "${original_priority}" ]]; then
      state_remove_managed_priority "${name}"
    fi
    AUTO_PRIORITY_UNCHANGED=$((AUTO_PRIORITY_UNCHANGED + 1))

    index=$((index + 1))
  done
}

auto_manage_priorities() {
  local auth_files_response

  log "从 auth-files 自动处理 priority"
  auth_files_response="$(fetch_auth_files_cached)"
  resolve_auth_entries_from_auth_files "${auth_files_response}"
  auto_manage_priorities_for_current_entries
  sort_auth_entries_by_priority
  print_auto_priority_report
}

extract_auth_entries() {
  local response="$1"

  printf '%s' "${response}" | jq -r '
    [.. | objects | select(.auth_index? // .authIndex?)]
    | unique_by(.auth_index? // .authIndex?)
    | .[]
    | [
        (.name? // .label? // .email? // .id? // "(未命名)"),
        (.note? // "-"),
        ((.priority? // "-") | tostring),
        ((.auth_index? // .authIndex?) | tostring),
        (.id_token?.chatgpt_account_id? // "-"),
        (.id_token?.plan_type? // "-"),
        (.id_token?.chatgpt_subscription_active_start? // "-"),
        (.id_token?.chatgpt_subscription_active_until? // "-"),
        ((.disabled? // false) | tostring)
      ]
    | @tsv
  '
}

resolve_auth_entries_from_auth_files() {
  local response="$1"
  local name note priority auth_index account_id plan_type subscription_start subscription_until disabled
  AUTH_NAMES=()
  AUTH_NOTES=()
  AUTH_PRIORITIES=()
  AUTH_INDEXES=()
  AUTH_ACCOUNT_IDS=()
  AUTH_PLAN_TYPES=()
  AUTH_SUBSCRIPTION_STARTS=()
  AUTH_SUBSCRIPTION_UNTILS=()
  AUTH_DISABLED_FLAGS=()

  while IFS=$'\t' read -r name note priority auth_index account_id plan_type subscription_start subscription_until disabled || [[ -n "${name}${note}${priority}${auth_index}${account_id}${plan_type}${subscription_start}${subscription_until}${disabled}" ]]; do
    [[ -z "${auth_index}" ]] && continue
    AUTH_NAMES+=("${name:-"(未命名)"}")
    AUTH_NOTES+=("${note:-"-"}")
    AUTH_PRIORITIES+=("${priority:-"-"}")
    AUTH_INDEXES+=("${auth_index}")
    AUTH_ACCOUNT_IDS+=("${account_id:-"-"}")
    AUTH_PLAN_TYPES+=("${plan_type:-"-"}")
    AUTH_SUBSCRIPTION_STARTS+=("${subscription_start:-"-"}")
    AUTH_SUBSCRIPTION_UNTILS+=("${subscription_until:-"-"}")
    AUTH_DISABLED_FLAGS+=("${disabled:-"false"}")
  done < <(extract_auth_entries "${response}")

  [[ "${#AUTH_INDEXES[@]}" -gt 0 ]] || die "无法从 auth-files 响应中提取 authIndex"
  sort_auth_entries_by_priority
}

sort_auth_entries_by_priority() {
  local count="${#AUTH_INDEXES[@]}"
  local index=0
  local name note priority auth_index account_id plan_type subscription_start subscription_until disabled sort_priority

  [[ "${count}" -le 1 ]] && return 0
  command -v sort >/dev/null 2>&1 || return 0

  local sorted_output=""
  sorted_output="$(
    while [[ "${index}" -lt "${count}" ]]; do
      name="${AUTH_NAMES[index]:-"(未命名)"}"
      note="${AUTH_NOTES[index]:-"-"}"
      priority="${AUTH_PRIORITIES[index]:-"-"}"
      auth_index="${AUTH_INDEXES[index]}"
      account_id="${AUTH_ACCOUNT_IDS[index]:-"-"}"
      plan_type="${AUTH_PLAN_TYPES[index]:-"-"}"
      subscription_start="${AUTH_SUBSCRIPTION_STARTS[index]:-"-"}"
      subscription_until="${AUTH_SUBSCRIPTION_UNTILS[index]:-"-"}"
      disabled="${AUTH_DISABLED_FLAGS[index]:-"false"}"
      if [[ "${priority}" =~ ^-?[0-9]+$ ]]; then
        sort_priority="${priority}"
      else
        sort_priority="-1"
      fi
      printf '%s\t%06d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${sort_priority}" \
        "${index}" \
        "${name}" \
        "${note}" \
        "${priority}" \
        "${auth_index}" \
        "${account_id}" \
        "${plan_type}" \
        "${subscription_start}" \
        "${subscription_until}" \
        "${disabled}"
      index=$((index + 1))
    done | sort -t $'\t' -k1,1nr -k2,2n
  )"

  AUTH_NAMES=()
  AUTH_NOTES=()
  AUTH_PRIORITIES=()
  AUTH_INDEXES=()
  AUTH_ACCOUNT_IDS=()
  AUTH_PLAN_TYPES=()
  AUTH_SUBSCRIPTION_STARTS=()
  AUTH_SUBSCRIPTION_UNTILS=()
  AUTH_DISABLED_FLAGS=()

  while IFS=$'\t' read -r _sort_priority _order name note priority auth_index account_id plan_type subscription_start subscription_until disabled || [[ -n "${_sort_priority}${_order}${name}${note}${priority}${auth_index}${account_id}${plan_type}${subscription_start}${subscription_until}${disabled}" ]]; do
    [[ -z "${auth_index}" ]] && continue
    AUTH_NAMES+=("${name}")
    AUTH_NOTES+=("${note}")
    AUTH_PRIORITIES+=("${priority}")
    AUTH_INDEXES+=("${auth_index}")
    AUTH_ACCOUNT_IDS+=("${account_id:-"-"}")
    AUTH_PLAN_TYPES+=("${plan_type:-"-"}")
    AUTH_SUBSCRIPTION_STARTS+=("${subscription_start:-"-"}")
    AUTH_SUBSCRIPTION_UNTILS+=("${subscription_until:-"-"}")
    AUTH_DISABLED_FLAGS+=("${disabled:-"false"}")
  done <<< "${sorted_output}"
}

build_usage_payload() {
  local auth_index="$1"
  local plan_type="${2:-}"
  local header_json
  local body_field=""
  header_json="\"Authorization\":\"$(json_escape "${TARGET_AUTH_HEADER}")\","
  header_json+="\"Content-Type\":\"application/json\","
  header_json+="\"User-Agent\":\"$(json_escape "${TARGET_USER_AGENT}")\""

  # ChatGPT 多账号环境才需要该请求头；未传入时不发送，避免固化个人账号 ID。
  if [[ -n "${CHATGPT_ACCOUNT_ID}" ]]; then
    header_json+=",\"Chatgpt-Account-Id\":\"$(json_escape "${CHATGPT_ACCOUNT_ID}")\""
  fi

  if [[ -n "${plan_type}" && "${plan_type}" != "-" ]]; then
    body_field=",\"body\":\"$(json_escape "$(printf '{"plan_type":"%s"}' "$(json_escape "${plan_type}")")")\""
  fi

  printf '{"authIndex":"%s","method":"%s","url":"%s","header":{%s}%s}' \
    "$(json_escape "${auth_index}")" \
    "$(json_escape "${TARGET_METHOD}")" \
    "$(json_escape "${TARGET_URL}")" \
    "${header_json}" \
    "${body_field}"
}

fetch_usage_response() {
  local auth_index="$1"
  local plan_type="${2:-}"
  local payload
  build_curl_common_args
  payload="$(build_usage_payload "${auth_index}" "${plan_type}")"

  curl "${CURL_ARGS[@]}" \
    -H "Content-Type: application/json" \
    -H "Origin: ${BASE_URL}" \
    --data-raw "${payload}" \
    "${BASE_URL}/v0/management/api-call"
}

fetch_usage_parallel() {
  local index="$1"
  local auth_index="$2"
  local plan_type="$3"
  local output_file="$4"

  local response
  mkdir -p "$(dirname "${output_file}")"
  if response="$(fetch_usage_response "${auth_index}" "${plan_type}" 2>&1)"; then
    printf '%s\t%s\n' "${index}" "${response}" > "${output_file}"
  else
    printf '%s\tERROR\t%s\n' "${index}" "${response}" > "${output_file}"
  fi
}

format_percent() {
  local value="$1"
  if [[ "${value}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    printf '%s%%' "${value}"
  else
    printf '%s' "${value:-N/A}"
  fi
}

format_md_cell() {
  local value="${1:-"-"}"
  value="${value//$'\r'/ }"
  value="${value//$'\n'/ }"
  value="${value//|/\\|}"
  printf '%s' "${value:-"-"}"
}

format_reset_time() {
  local epoch="$1"

  if [[ ! "${epoch}" =~ ^[0-9]+$ ]]; then
    printf 'N/A'
    return 0
  fi

  if date -d "@${epoch}" '+%m-%d %H:%M:%S' >/dev/null 2>&1; then
    date -d "@${epoch}" '+%m-%d %H:%M:%S'
  elif date -r "${epoch}" '+%m-%d %H:%M:%S' >/dev/null 2>&1; then
    date -r "${epoch}" '+%m-%d %H:%M:%S'
  else
    printf '%s' "${epoch}"
  fi
}

format_subscription_time() {
  local value="$1"

  if [[ -z "${value}" || "${value}" == "-" ]]; then
    printf '-'
    return 0
  fi

  if date -d "${value}" '+%m-%d %H:%M:%S' >/dev/null 2>&1; then
    date -d "${value}" '+%m-%d %H:%M:%S'
  elif date -j -f '%Y-%m-%dT%H:%M:%S%z' "${value}" '+%m-%d %H:%M:%S' >/dev/null 2>&1; then
    date -j -f '%Y-%m-%dT%H:%M:%S%z' "${value}" '+%m-%d %H:%M:%S'
  else
    printf '%s' "${value}"
  fi
}

is_expired_plus_plan() {
  local plan_type="$1"
  local subscription_until="$2"
  local subscription_until_epoch
  local now_epoch

  [[ "${plan_type}" == "plus" ]] || return 1
  subscription_until_epoch="$(parse_datetime_to_epoch "${subscription_until}")" || return 1
  now_epoch="$(date '+%s')"
  (( subscription_until_epoch <= now_epoch ))
}

is_api_call_401_error() {
  local reason="$1"

  [[ "${reason}" =~ ^HTTP[[:space:]]401: ]]
}

extract_usage_limits() {
  local response="$1"

  printf '%s' "${response}" | jq -r '
    def body_json:
      if (.body | type) == "string" then
        (try (.body | fromjson) catch null)
      else
        (.body // .)
      end;

    (.status_code // 200) as $status
    | (body_json) as $body
    | if ($status == 401) then
        ["ERROR", ("HTTP " + ($status | tostring) + ": " + (($body.detail // $body.error // $body.message // .body // "api-call failed") | tostring))] | @tsv
      elif ($body == null) then
        ["N/A", "N/A", "N/A", "N/A", "-"] | @tsv
      else
        (($body.plan_type // "-") | tostring) as $plan_type
        | ($body.rate_limit // {}) as $rate_limit
        | ($rate_limit.primary_window // {}) as $primary
        | ($rate_limit.secondary_window // {}) as $secondary
        | [
          (if $plan_type == "free" then
            "N/A"
          elif ($primary.used_percent | type) == "number" then
            (100 - $primary.used_percent)
          else
            "N/A"
          end),
          (if $plan_type == "free" then
            "N/A"
          else
            ($primary.reset_at // "N/A")
          end),
          (if $plan_type == "free" and ($primary.used_percent | type) == "number" then
            (100 - $primary.used_percent)
          elif ($secondary.used_percent | type) == "number" then
            (100 - $secondary.used_percent)
          else
            "N/A"
          end),
          (if $plan_type == "free" then
            ($primary.reset_at // "N/A")
          else
            ($secondary.reset_at // "N/A")
          end),
          $plan_type
        ] | @tsv
      end
  '
}

print_usage_header() {
  printf 'name\tnote\t优先级\t5小时/周剩余\t5小时刷新时间\t周刷新时间\t状态/异常\n'
}

render_usage_table() {
  local row
  local name note priority plan_info subscription_info limits five_hour_reset week_reset status
  local status_display

  printf '| 账号 | 5h/week | 状态 | 备注 | 优先级 | 套餐 | 订阅 | 刷新 |\n'
  printf '| --- | --- | --- | --- | --- | --- | --- | --- |\n'
  for row in "${RESULT_ROWS[@]}"; do
    IFS=$'\t' read -r name note priority plan_info subscription_info limits five_hour_reset week_reset status <<< "${row}"
    [[ "${status}" == "OK" ]] || continue
    status_display="${status}"
    status_display="ok"
    printf '| %s | %s | %s | %s | %s | %s | %s | %s / %s |\n' \
      "$(format_md_cell "${name}")" \
      "$(format_md_cell "${limits}")" \
      "$(format_md_cell "${status_display}")" \
      "$(format_md_cell "${note}")" \
      "$(format_md_cell "${priority}")" \
      "$(format_md_cell "${plan_info}")" \
      "$(format_md_cell "${subscription_info}")" \
      "$(format_md_cell "${five_hour_reset}")" \
      "$(format_md_cell "${week_reset}")"
  done
}

render_management_usage() {
  local response="$1"
  local usage_date
  local start_epoch
  local end_epoch

  usage_date="$(date '+%Y-%m-%d')"
  start_epoch="$(date -d 'today 00:00:00' '+%s')"
  end_epoch="$(date -d 'tomorrow 00:00:00' '+%s')"

  printf '%s' "${response}" | jq -r \
    --arg usage_date "${usage_date}" \
    --argjson start_epoch "${start_epoch}" \
    --argjson end_epoch "${end_epoch}" '
    def sum_tokens($items): ($items | map(.tokens.total_tokens // 0) | add // 0);
    def fail_count($items): ($items | map(select(.failed == true)) | length);
    def ok_count($items): ($items | length) - fail_count($items);
    def pct($part; $total):
      if ($total | tonumber) == 0 then "0%"
      else (((($part | tonumber) * 10000 / ($total | tonumber)) | floor) / 100 | tostring) + "%"
      end;
    def token_m($tokens):
      (((($tokens // 0) | tonumber) / 10000 | floor) / 100 | tostring) + "M";
    def direct_ok:
      (.ok // .success_count // ((.total_requests // 0) - (.failure_count // .fail // 0)));
    def direct_fail:
      (.fail // .failure_count // 0);
    def direct_success_rate:
      (.success_rate // pct(direct_ok; (.total_requests // 0)));
    def direct_tokens_m:
      (.total_tokens_m // token_m(.total_tokens // 0));
    def as_item_array($items):
      if ($items | type) == "array" then $items
      elif ($items | type) == "object" then
        $items | to_entries | map(.value + {name: (.value.name // .key)})
      else []
      end;
    def detail_lines($items; $key; $extra_key; $extra_label):
      as_item_array($items) as $normalized_items
      | if ($normalized_items | length) == 0 then ["- 无"]
      else
        ($normalized_items
        | sort_by(-((.tokens_m // "0M") | sub("M$"; "") | tonumber), (.[$key] // .name // ""))
        | map(
            "- " + ((.[$key] // .name // "-") | tostring)
            + ": 请求 " + ((.requests // 0) | tostring)
            + "，成功/失败 " + ((.ok // 0) | tostring) + "/" + ((.fail // 0) | tostring)
            + "，tokens " + (.tokens_m // token_m(.tokens // .total_tokens // 0))
            + (if .[$extra_key] != null then "，" + $extra_label + (.[$extra_key] | tostring) else "" end)
          ))
      end;
    def timestamp_epoch:
      (.timestamp // "" | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601?);
    def summary_name:
      ((.auth_file_snapshot // .account_snapshot // .auth_label_snapshot // .source // "(未知账号)") | tostring)
      | sub("\\.json$"; "")
      | split("@")[0]
      | sub("^codex-"; "")
      | sub("^code-"; "");

    . as $root
    | [
        ($root.apis // {})
        | to_entries[]
        | .key as $api
        | (.value.models // {})
        | to_entries[]
        | .key as $model
        | (.value.details[]? + {api: $api, model: $model})
        | (timestamp_epoch) as $ts
        | select($ts != null and $ts >= $start_epoch and $ts < $end_epoch)
      ] as $details
    | if ($details | length) > 0 then
        ($details | length) as $total
        | ok_count($details) as $ok
        | fail_count($details) as $fail
        | sum_tokens($details) as $tokens
        | [
            ("管理端当天用量：" + $usage_date),
            "",
            ("总请求: " + ($total | tostring)),
            ("成功/失败: " + ($ok | tostring) + "/" + ($fail | tostring)),
            ("成功率: " + pct($ok; $total)),
            ("总 tokens: " + token_m($tokens)),
            "",
            "账号汇总:"
          ],
          (
            $details
            | group_by(summary_name)
            | map(. as $items | {account: ($items[0] | summary_name), requests: ($items | length), ok: ok_count($items), fail: fail_count($items), tokens: sum_tokens($items), models: ($items | map(.model) | unique | length)})
            | sort_by(-.tokens, .account)
            | .[]
            | "- " + .account + ": 请求 " + (.requests | tostring) + "，成功/失败 " + (.ok | tostring) + "/" + (.fail | tostring) + "，tokens " + token_m(.tokens) + "，使用模型数 " + (.models | tostring)
          ),
          "",
          "模型汇总:",
          (
            $details
            | group_by(.model)
            | map(. as $items | {model: $items[0].model, requests: ($items | length), ok: ok_count($items), fail: fail_count($items), tokens: sum_tokens($items), accounts: ($items | map(summary_name) | unique | length)})
            | sort_by(-.tokens, .model)
            | .[]
            | "- " + .model + ": 请求 " + (.requests | tostring) + "，成功/失败 " + (.ok | tostring) + "/" + (.fail | tostring) + "，tokens " + token_m(.tokens) + "，使用账号数 " + (.accounts | tostring)
          ),
          "",
          "接口汇总:",
          (
            $details
            | group_by(.api)
            | map(. as $items | {api: $items[0].api, requests: ($items | length), ok: ok_count($items), fail: fail_count($items), tokens: sum_tokens($items), models: ($items | map(.model) | unique | length)})
            | sort_by(-.tokens, .api)
            | .[]
            | "- " + .api + ": 请求 " + (.requests | tostring) + "，成功/失败 " + (.ok | tostring) + "/" + (.fail | tostring) + "，tokens " + token_m(.tokens) + "，使用模型数 " + (.models | tostring)
          )
      else
        [
          ("管理端当天用量：" + ($root.date // $usage_date)),
          "",
          ("总请求: " + (($root.total_requests // 0) | tostring)),
          ("成功/失败: " + ($root | direct_ok | tostring) + "/" + ($root | direct_fail | tostring)),
          ("成功率: " + ($root | direct_success_rate)),
          ("总 tokens: " + ($root | direct_tokens_m)),
          "",
          "账号汇总:"
        ],
        detail_lines($root.accounts; "account"; "model_count"; "使用模型数 "),
        "",
        "模型汇总:",
        detail_lines($root.models; "model"; "account_count"; "使用账号数 "),
        "",
        "接口汇总:",
        detail_lines($root.apis; "api"; "model_count"; "使用模型数 ")
      end
    | if type == "array" then .[] else . end
  '
}

build_management_usage_snapshot_json() {
  local response="$1"
  local usage_date
  local start_epoch
  local end_epoch

  usage_date="$(date '+%Y-%m-%d')"
  start_epoch="$(date -d 'today 00:00:00' '+%s')"
  end_epoch="$(date -d 'tomorrow 00:00:00' '+%s')"

  printf '%s' "${response}" | jq -c \
    --arg usage_date "${usage_date}" \
    --argjson start_epoch "${start_epoch}" \
    --argjson end_epoch "${end_epoch}" '
    def sum_tokens($items): ($items | map(.tokens.total_tokens // 0) | add // 0);
    def fail_count($items): ($items | map(select(.failed == true)) | length);
    def ok_count($items): ($items | length) - fail_count($items);
    def pct($part; $total):
      if ($total | tonumber) == 0 then "0%"
      else (((($part | tonumber) * 10000 / ($total | tonumber)) | floor) / 100 | tostring) + "%"
      end;
    def token_m($tokens):
      (((($tokens // 0) | tonumber) / 10000 | floor) / 100 | tostring) + "M";
    def direct_ok:
      (.ok // .success_count // ((.total_requests // 0) - (.failure_count // .fail // 0)));
    def direct_fail:
      (.fail // .failure_count // 0);
    def direct_success_rate:
      (.success_rate // pct(direct_ok; (.total_requests // 0)));
    def direct_tokens_m:
      (.total_tokens_m // token_m(.total_tokens // 0));
    def as_item_array($items):
      if ($items | type) == "array" then $items
      elif ($items | type) == "object" then
        $items | to_entries | map(.value + {name: (.value.name // .key)})
      else []
      end;
    def normalize_items($items; $name_key; $extra_key):
      as_item_array($items)
      | map({
          name: ((.name // .[$name_key] // "-") | tostring),
          requests: (.requests // 0),
          ok: (.ok // .success_count // 0),
          fail: (.fail // .failure_count // 0),
          tokens_m: (.tokens_m // token_m(.tokens // .total_tokens // 0)),
          ($extra_key): (.[$extra_key] // null)
        });
    def timestamp_epoch:
      (.timestamp // "" | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601?);
    def summary_name:
      ((.auth_file_snapshot // .account_snapshot // .auth_label_snapshot // .source // "(未知账号)") | tostring)
      | sub("\\.json$"; "")
      | split("@")[0]
      | sub("^codex-"; "")
      | sub("^code-"; "");

    . as $root
    | [
        ($root.apis // {})
        | to_entries[]
        | .key as $api
        | (.value.models // {})
        | to_entries[]
        | .key as $model
        | (.value.details[]? + {api: $api, model: $model})
        | (timestamp_epoch) as $ts
        | select($ts != null and $ts >= $start_epoch and $ts < $end_epoch)
      ] as $details
    | if ($details | length) > 0 then
        ($details | length) as $total
        | ok_count($details) as $ok
        | fail_count($details) as $fail
        | sum_tokens($details) as $tokens
        | {
            available: true,
            date: $usage_date,
            total_requests: $total,
            ok: $ok,
            fail: $fail,
            success_rate: pct($ok; $total),
            total_tokens_m: token_m($tokens),
            accounts: (
              $details
              | group_by(summary_name)
              | map(. as $items | {name: ($items[0] | summary_name), requests: ($items | length), ok: ok_count($items), fail: fail_count($items), tokens_m: token_m(sum_tokens($items)), model_count: ($items | map(.model) | unique | length)})
              | sort_by(-(.tokens_m | sub("M$"; "") | tonumber), .name)
            ),
            models: (
              $details
              | group_by(.model)
              | map(. as $items | {name: $items[0].model, requests: ($items | length), ok: ok_count($items), fail: fail_count($items), tokens_m: token_m(sum_tokens($items)), account_count: ($items | map(summary_name) | unique | length)})
              | sort_by(-(.tokens_m | sub("M$"; "") | tonumber), .name)
            ),
            apis: (
              $details
              | group_by(.api)
              | map(. as $items | {name: $items[0].api, requests: ($items | length), ok: ok_count($items), fail: fail_count($items), tokens_m: token_m(sum_tokens($items)), model_count: ($items | map(.model) | unique | length)})
              | sort_by(-(.tokens_m | sub("M$"; "") | tonumber), .name)
            )
          }
      else
        {
          available: true,
          date: ($root.date // $usage_date),
          total_requests: ($root.total_requests // 0),
          ok: ($root | direct_ok),
          fail: ($root | direct_fail),
          success_rate: ($root | direct_success_rate),
          total_tokens_m: ($root | direct_tokens_m),
          accounts: (normalize_items($root.accounts; "account"; "model_count") | sort_by(-(.tokens_m | sub("M$"; "") | tonumber), .name)),
          models: (normalize_items($root.models; "model"; "account_count") | sort_by(-(.tokens_m | sub("M$"; "") | tonumber), .name)),
          apis: (normalize_items($root.apis; "api"; "model_count") | sort_by(-(.tokens_m | sub("M$"; "") | tonumber), .name))
        }
      end
  '
}

collect_management_usage_snapshot_json() {
  local response
  local curl_error_file
  local curl_error

  curl_error_file="$(mktemp)"
  if ! response="$(fetch_management_usage 2>"${curl_error_file}")"; then
    curl_error="$(<"${curl_error_file}")"
    rm -f "${curl_error_file}"
    if ! is_supported_management_usage_response "${response}"; then
      log "management usage 快照跳过: $(compact_error_reason "${curl_error:-${response}}")；如响应较大可提高 --usage-timeout"
      printf 'null'
      return 0
    fi
    log "management usage 快照收到可解析响应，忽略 curl 非零退出: $(compact_error_reason "${curl_error}")"
  else
    rm -f "${curl_error_file}"
  fi

  if ! is_supported_management_usage_response "${response}"; then
    log "management usage 快照跳过: 响应不是预期 JSON 对象"
    printf 'null'
    return 0
  fi

  build_management_usage_snapshot_json "${response}" || {
    log "management usage 快照跳过: 解析失败"
    printf 'null'
  }
}

save_management_usage_snapshot() {
  local response="$1"
  local management_usage_json
  local state_json

  ensure_state_file
  management_usage_json="$(build_management_usage_snapshot_json "${response}")" || {
    die "management usage 快照解析失败"
  }
  state_json="$(jq -c '.state // {managed_priorities:{},free_weekly_disabled:{},plan_types:{}}' "${STATE_FILE}")"

  mkdir -p "$(dirname "${PROMPT_FILE}")"
  if [[ -s "${PROMPT_FILE}" ]] && jq -e 'type == "object"' "${PROMPT_FILE}" >/dev/null 2>&1; then
    # 单独查询 usage 时只更新 usage 节点，保留已有额度快照内容。
    jq --argjson management_usage "${management_usage_json}" \
      --argjson state "${state_json}" \
      '.management_usage = $management_usage | .state = $state' \
      "${PROMPT_FILE}" > "${PROMPT_FILE}.tmp" && mv "${PROMPT_FILE}.tmp" "${PROMPT_FILE}" || {
        rm -f "${PROMPT_FILE}.tmp"
        die "更新提示词快照 usage 失败: ${PROMPT_FILE}"
      }
  else
    jq -n \
      --arg generated_at "$(current_timestamp_local)" \
      --argjson management_usage "${management_usage_json}" \
      --argjson state "${state_json}" \
      '{
        generated_at: $generated_at,
        auth: [],
        management_usage: $management_usage,
        summary: {
          total: "0",
          ok: "0",
          error: "0",
          sum_5h: "0",
          sum_week: "0",
          five_hour_items: [],
          week_items: [],
          expiry_items: [],
          free_items: [],
          plan_change_items: [],
          error_items: []
        },
        result_rows: [],
        state: $state
      }' > "${PROMPT_FILE}.tmp" && mv "${PROMPT_FILE}.tmp" "${PROMPT_FILE}" || {
        rm -f "${PROMPT_FILE}.tmp"
        die "写入提示词快照 usage 失败: ${PROMPT_FILE}"
      }
  fi
  log "已更新提示词快照 usage: ${PROMPT_FILE}"
}

render_disabled_list() {
  local total="${#AUTH_NAMES[@]}"
  local index=0
  local name note priority auth_index account_id plan_type subscription_start subscription_until disabled
  local plan_info subscription_info
  local -a disabled_rows=()

  while [[ "${index}" -lt "${total}" ]]; do
    disabled="${AUTH_DISABLED_FLAGS[index]:-"false"}"
    if [[ "${disabled}" == "true" ]]; then
      name="${AUTH_NAMES[index]:-"(未命名)"}"
      note="${AUTH_NOTES[index]:-"-"}"
      priority="${AUTH_PRIORITIES[index]:-"-"}"
      auth_index="${AUTH_INDEXES[index]:-"-"}"
      account_id="${AUTH_ACCOUNT_IDS[index]:-"-"}"
      plan_type="${AUTH_PLAN_TYPES[index]:-"-"}"
      subscription_start="${AUTH_SUBSCRIPTION_STARTS[index]:-"-"}"
      subscription_until="${AUTH_SUBSCRIPTION_UNTILS[index]:-"-"}"
      plan_info="${plan_type}"
      subscription_info="$(format_subscription_time "${subscription_start}") -> $(format_subscription_time "${subscription_until}")"
      disabled_rows+=("${name}"$'\t'"${note}"$'\t'"${priority}"$'\t'"${auth_index}"$'\t'"${plan_info}"$'\t'"${subscription_info}")
    fi
    index=$((index + 1))
  done

  printf '## 禁用列表（%s）\n' "${#disabled_rows[@]}"
  if [[ "${#disabled_rows[@]}" -eq 0 ]]; then
    return 0
  fi

  printf '\n'
  printf '| 账号 | 状态 | 备注 | 优先级 | 套餐 | 订阅 | authIndex |\n'
  printf '| --- | --- | --- | --- | --- | --- | --- |\n'
  for row in "${disabled_rows[@]}"; do
    IFS=$'\t' read -r name note priority auth_index plan_info subscription_info <<< "${row}"
    printf '| %s | disabled=true | %s | %s | %s | %s | %s |\n' \
      "$(format_md_cell "${name}")" \
      "$(format_md_cell "${note}")" \
      "$(format_md_cell "${priority}")" \
      "$(format_md_cell "${plan_info}")" \
      "$(format_md_cell "${subscription_info}")" \
      "$(format_md_cell "${auth_index}")"
  done
}

number_less_than() {
  local left="$1"
  local right="$2"
  awk -v left="${left}" -v right="${right}" 'BEGIN { exit !(left + 0 < right + 0) }'
}

number_greater_than_zero() {
  local value="$1"
  awk -v value="${value}" 'BEGIN { exit !(value + 0 > 0) }'
}

number_add() {
  local left="$1"
  local right="$2"
  awk -v left="${left}" -v right="${right}" 'BEGIN { printf "%g", left + right }'
}

format_summary_name() {
  local name="$1"
  local display_name="$name"

  if [[ "${display_name}" == *"@"* ]]; then
    display_name="${display_name%.json}"
    display_name="${display_name%%@*}"
    if [[ "${display_name}" == codex-* ]]; then
      display_name="${display_name#codex-}"
    elif [[ "${display_name}" == code-* ]]; then
      display_name="${display_name#code-}"
    fi
  fi

  printf '%s' "${display_name}"
}

record_error_summary() {
  local name="$1"
  local reason="${2:-}"

  reason="$(compact_error_reason "${reason}")"

  SUMMARY_ERROR_NAMES+=("${name}"$'\t'"${reason}")
}

build_error_summary_line() {
  local details=""
  local item name reason short_name

  if [[ "${#SUMMARY_ERROR_NAMES[@]}" -eq 0 ]]; then
    printf '异常：-\n'
    return 0
  fi

  for item in "${SUMMARY_ERROR_NAMES[@]}"; do
    IFS=$'\t' read -r name reason <<< "${item}"
    reason="$(compact_error_reason "${reason}")"
    short_name="$(format_summary_name "${name}")"
    if [[ -n "${details}" ]]; then
      details+="，"
    fi
    details+="${short_name}"
    if [[ -n "${reason}" ]]; then
      details+="（${reason}）"
    fi
  done

  printf '异常：%s\n' "${details}"
}

record_plan_change_summary() {
  local name="$1"
  local previous_plan="$2"
  local current_plan="$3"

  SUMMARY_PLAN_CHANGE_ITEMS+=("${name}"$'\t'"${previous_plan}"$'\t'"${current_plan}")
}

build_plan_change_summary_line() {
  local details=""
  local item name previous_plan current_plan short_name

  if [[ "${#SUMMARY_PLAN_CHANGE_ITEMS[@]}" -eq 0 ]]; then
    printf '套餐提醒：-\n'
    return 0
  fi

  for item in "${SUMMARY_PLAN_CHANGE_ITEMS[@]}"; do
    IFS=$'\t' read -r name previous_plan current_plan <<< "${item}"
    short_name="$(format_summary_name "${name}")"
    if [[ -n "${details}" ]]; then
      details+="，"
    fi
    details+="${short_name}（${previous_plan} -> ${current_plan}）"
  done

  printf '套餐提醒：%s\n' "${details}"
}

build_summary_metric_line() {
  local label="$1"
  local -n items_ref="$2"
  local details=""
  local count=0
  local value order name short_name

  if [[ "${#items_ref[@]}" -eq 0 ]]; then
    printf '%s：0\n' "${label}"
    return 0
  fi

  while IFS=$'\t' read -r value order name || [[ -n "${value}${order}${name}" ]]; do
    [[ -n "${name}" ]] || continue
    short_name="$(format_summary_name "${name}")"
    if [[ -n "${details}" ]]; then
      details+="，"
    fi
    details+="${short_name} $(format_percent "${value}")"
    count=$((count + 1))
  done < <(printf '%s\n' "${items_ref[@]}")

  printf '%s：%s' "${label}" "${count}"
  if [[ -n "${details}" ]]; then
    printf '（%s）' "${details}"
  fi
  printf '\n'
}

build_quota_detail_table() {
  local -A five_hour_by_name=()
  local -A week_by_name=()
  local -a ordered_names=()
  local value order name short_name

  while IFS=$'\t' read -r value order name || [[ -n "${value}${order}${name}" ]]; do
    [[ -n "${name}" ]] || continue
    five_hour_by_name["${name}"]="$(format_percent "${value}")"
  done < <(printf '%s\n' "${SUMMARY_5H_ITEMS[@]}" | sort -t $'\t' -k2,2n)

  while IFS=$'\t' read -r value order name || [[ -n "${value}${order}${name}" ]]; do
    [[ -n "${name}" ]] || continue
    week_by_name["${name}"]="$(format_percent "${value}")"
  done < <(printf '%s\n' "${SUMMARY_WEEK_ITEMS[@]}" | sort -t $'\t' -k2,2n)

  while IFS=$'\t' read -r order name || [[ -n "${order}${name}" ]]; do
    [[ -n "${name}" ]] || continue
    ordered_names+=("${name}")
  done < <(
    {
      printf '%s\n' "${SUMMARY_5H_ITEMS[@]}" | awk -F '\t' 'NF >= 3 { print $2 "\t" $3 }'
      printf '%s\n' "${SUMMARY_WEEK_ITEMS[@]}" | awk -F '\t' 'NF >= 3 { print $2 "\t" $3 }'
    } | sort -t $'\t' -k1,1n | awk -F '\t' '!seen[$2]++ { print $1 "\t" $2 }'
  )

  if [[ "${#ordered_names[@]}" -eq 0 ]]; then
    printf -- '- 无额度明细\n'
    return 0
  fi

  printf '| 账号 | 5h剩余 | 周剩余 |\n'
  printf '| --- | --- | --- |\n'
  for name in "${ordered_names[@]}"; do
    short_name="$(format_summary_name "${name}")"
    printf '| %s | %s | %s |\n' \
      "$(format_md_cell "${short_name}")" \
      "$(format_md_cell "${five_hour_by_name[${name}]:-"-"}")" \
      "$(format_md_cell "${week_by_name[${name}]:-"-"}")"
  done
}

build_free_summary_line() {
  local details=""
  local count=0
  local order name short_name

  if [[ "${#SUMMARY_FREE_ITEMS[@]}" -eq 0 ]]; then
    printf 'free账号：0\n'
    return 0
  fi

  while IFS=$'\t' read -r order name || [[ -n "${order}${name}" ]]; do
    [[ -n "${name}" ]] || continue
    short_name="$(format_summary_name "${name}")"
    if [[ -n "${details}" ]]; then
      details+="，"
    fi
    details+="${short_name}"
    count=$((count + 1))
  done < <(printf '%s\n' "${SUMMARY_FREE_ITEMS[@]}" | sort -t $'\t' -k1,1n)

  printf 'free账号：%s' "${count}"
  if [[ -n "${details}" ]]; then
    printf '（%s）' "${details}"
  fi
  printf '\n'
}

build_disabled_summary_line() {
  local count=0
  local total="${#AUTH_NAMES[@]}"
  local index=0
  local disabled

  while [[ "${index}" -lt "${total}" ]]; do
    disabled="${AUTH_DISABLED_FLAGS[index]:-"false"}"
    if [[ "${disabled}" == "true" ]]; then
      count=$((count + 1))
    fi
    index=$((index + 1))
  done

  printf '已禁用：%s' "${count}"
  printf '\n'
}

record_expiry_summary() {
  local name="$1"
  local subscription_until="$2"
  local order="$3"
  local subscription_until_epoch
  local remaining_seconds

  subscription_until_epoch="$(parse_datetime_to_epoch "${subscription_until}")" || return 0
  remaining_seconds=$((subscription_until_epoch - $(date '+%s')))
  SUMMARY_EXPIRY_ITEMS+=("${remaining_seconds}"$'\t'"${order}"$'\t'"${name}")
}

build_expiry_summary_line() {
  local details=""
  local count=0
  local remaining_seconds order name short_name

  if [[ "${#SUMMARY_EXPIRY_ITEMS[@]}" -eq 0 ]]; then
    printf '过期提醒：0\n'
    return 0
  fi

  while IFS=$'\t' read -r remaining_seconds order name || [[ -n "${remaining_seconds}${order}${name}" ]]; do
    [[ -n "${name}" ]] || continue
    short_name="$(format_summary_name "${name}")"
    if [[ -n "${details}" ]]; then
      details+="，"
    fi
    details+="${short_name} $(format_precise_duration "${remaining_seconds}")"
    count=$((count + 1))
  done < <(printf '%s\n' "${SUMMARY_EXPIRY_ITEMS[@]}" | sort -t $'\t' -k1,1n -k2,2n)

  printf '过期提醒：%s' "${count}"
  if [[ -n "${details}" ]]; then
    printf '（%s）' "${details}"
  fi
  printf '\n'
}

build_expiring_soon_summary_line() {
  local threshold_days="${1:-7}"
  local threshold_seconds=$((threshold_days * 86400))
  local details=""
  local count=0
  local remaining_seconds order name short_name

  while IFS=$'\t' read -r remaining_seconds order name || [[ -n "${remaining_seconds}${order}${name}" ]]; do
    [[ "${remaining_seconds}" =~ ^-?[0-9]+$ ]] || continue
    if (( remaining_seconds <= 0 || remaining_seconds > threshold_seconds )); then
      continue
    fi
    short_name="$(format_summary_name "${name}")"
    if [[ -n "${details}" ]]; then
      details+="，"
    fi
    details+="${short_name} $(format_precise_duration "${remaining_seconds}")"
    count=$((count + 1))
  done < <(printf '%s\n' "${SUMMARY_EXPIRY_ITEMS[@]}" | sort -t $'\t' -k1,1n -k2,2n)

  printf '%s天内到期：%s' "${threshold_days}" "${count}"
  if [[ -n "${details}" ]]; then
    printf '（%s）' "${details}"
  fi
  printf '\n'
}

count_disabled_summary_items() {
  local count=0
  local total="${#AUTH_NAMES[@]}"
  local index=0
  local disabled

  while [[ "${index}" -lt "${total}" ]]; do
    disabled="${AUTH_DISABLED_FLAGS[index]:-"false"}"
    if [[ "${disabled}" == "true" ]]; then
      count=$((count + 1))
    fi
    index=$((index + 1))
  done

  printf '%s' "${count}"
}

count_expiring_soon_summary_items() {
  local threshold_days="${1:-7}"
  local threshold_seconds=$((threshold_days * 86400))
  local count=0
  local remaining_seconds order name

  while IFS=$'\t' read -r remaining_seconds order name || [[ -n "${remaining_seconds}${order}${name}" ]]; do
    [[ "${remaining_seconds}" =~ ^-?[0-9]+$ ]] || continue
    if (( remaining_seconds > 0 && remaining_seconds <= threshold_seconds )); then
      count=$((count + 1))
    fi
  done < <(printf '%s\n' "${SUMMARY_EXPIRY_ITEMS[@]}")

  printf '%s' "${count}"
}

print_overview_summary_block() {
  local five_hour_total="$1"
  local week_total="$2"
  local free_count="${#SUMMARY_FREE_ITEMS[@]}"
  local disabled_count
  local error_count="${#SUMMARY_ERROR_NAMES[@]}"
  local expiring_soon_count

  disabled_count="$(count_disabled_summary_items)"
  expiring_soon_count="$(count_expiring_soon_summary_items 7)"

  printf '概要\n'
  printf -- '- 基础：%s个 | OK %s | ERR %s\n' \
    "${SUMMARY_TOTAL}" \
    "${SUMMARY_OK}" \
    "${SUMMARY_ERROR}"
  printf -- '- 额度：5h总剩余 %s | 周总剩余 %s\n' \
    "${five_hour_total}" \
    "${week_total}"
  printf -- '- 风险：free %s | 已禁用 %s | 异常 %s | 7天内到期 %s\n' \
    "${free_count}" \
    "${disabled_count}" \
    "${error_count}" \
    "${expiring_soon_count}"
}

format_subscription_status() {
  local subscription_until="$1"
  local subscription_until_epoch
  local remaining_seconds
  local abs_seconds days hours minutes seconds

  subscription_until_epoch="$(parse_datetime_to_epoch "${subscription_until}")" || {
    printf '-'
    return 0
  }
  remaining_seconds=$((subscription_until_epoch - $(date '+%s')))
  if (( remaining_seconds < 0 )); then
    printf '已过期'
    return 0
  fi

  days=$((remaining_seconds / 86400))
  if (( days >= 1 )); then
    printf '剩余%s天' "${days}"
    return 0
  fi

  abs_seconds="${remaining_seconds}"
  hours=$((abs_seconds / 3600))
  minutes=$(((abs_seconds % 3600) / 60))
  seconds=$((abs_seconds % 60))
  printf '剩余%02d时%02d分%02d秒' "${hours}" "${minutes}" "${seconds}"
}

build_refresh_focus_line() {
  local label="$1"
  local reset_kind="$2"
  local row details="" items=""
  local order=0
  local name note priority plan_info subscription_info limits five_hour_reset week_reset status reset_value

  for row in "${RESULT_ROWS[@]}"; do
    IFS=$'\t' read -r name note priority plan_info subscription_info limits five_hour_reset week_reset status <<< "${row}"
    if [[ "${reset_kind}" == "5h" ]]; then
      reset_value="${five_hour_reset}"
    else
      reset_value="${week_reset}"
    fi
    [[ -n "${reset_value}" && "${reset_value}" != "-" && "${reset_value}" != "N/A" ]] || continue
    items+="${reset_value}"$'\t'"$(printf '%06d' "${order}")"$'\t'"${name}"$'\n'
    order=$((order + 1))
  done

  while IFS=$'\t' read -r reset_value _order name || [[ -n "${reset_value}${_order}${name}" ]]; do
    [[ -n "${name}" ]] || continue
    if [[ -n "${details}" ]]; then
      details+="，"
    fi
    details+="${name} ${reset_value}"
  done < <(printf '%s' "${items}" | sort -t $'\t' -k1,1 -k2,2n)

  printf '%s：%s\n' "${label}" "${details:-"-"}"
}

build_account_info_lines() {
  local total="${#AUTH_INDEXES[@]}"
  local index=0
  local name note plan_type subscription_start subscription_until subscription_info subscription_status disabled

  while [[ "${index}" -lt "${total}" ]]; do
    name="${AUTH_NAMES[index]:-"(未命名)"}"
    note="${AUTH_NOTES[index]:-"-"}"
    plan_type="${AUTH_PLAN_TYPES[index]:-"-"}"
    subscription_start="${AUTH_SUBSCRIPTION_STARTS[index]:-"-"}"
    subscription_until="${AUTH_SUBSCRIPTION_UNTILS[index]:-"-"}"
    disabled="${AUTH_DISABLED_FLAGS[index]:-"false"}"
    if [[ "${disabled}" == "true" ]]; then
      index=$((index + 1))
      continue
    fi
    subscription_info="$(format_subscription_time "${subscription_start}") -> $(format_subscription_time "${subscription_until}")"
    subscription_status="$(format_subscription_status "${subscription_until}")"
    printf '%s；套餐 %s；订阅 %s；订阅状态 %s；备注 %s\n' \
      "${name}" \
      "${plan_type}" \
      "${subscription_info}" \
      "${subscription_status}" \
      "${note}"
    index=$((index + 1))
  done
}

build_expiry_focus_line() {
  local details=""
  local remaining_seconds order name short_name subscription_until display_until

  if [[ "${#SUMMARY_EXPIRY_ITEMS[@]}" -eq 0 ]]; then
    printf '订阅到期重点：-\n'
    return 0
  fi

  while IFS=$'\t' read -r remaining_seconds order name || [[ -n "${remaining_seconds}${order}${name}" ]]; do
    [[ -n "${name}" ]] || continue
    subscription_until="${AUTH_SUBSCRIPTION_UNTILS[10#${order}]:-"-"}"
    display_until="$(format_subscription_time "${subscription_until}")"
    short_name="${name}"
    if [[ -n "${details}" ]]; then
      details+="，"
    fi
    details+="${short_name} ${display_until}（$(format_precise_duration "${remaining_seconds}")）"
  done < <(printf '%s\n' "${SUMMARY_EXPIRY_ITEMS[@]}" | sort -t $'\t' -k1,1n -k2,2n)

  printf '订阅到期重点：%s\n' "${details}"
}

save_prompt_snapshot() {
  local auth_json result_rows_json summary_5h_json summary_week_json summary_expiry_json summary_free_json plan_change_json error_json management_usage_json state_json

  ensure_state_file
  state_json="$(jq -c '.state // {managed_priorities:{},free_weekly_disabled:{},plan_types:{}}' "${STATE_FILE}")"

  auth_json="$(
    local count="${#AUTH_NAMES[@]}"
    local index=0
    local name note priority auth_index account_id plan_type subscription_start subscription_until disabled
    while [[ "${index}" -lt "${count}" ]]; do
      name="${AUTH_NAMES[index]:-"(未命名)"}"
      note="${AUTH_NOTES[index]:-"-"}"
      priority="${AUTH_PRIORITIES[index]:-"-"}"
      auth_index="${AUTH_INDEXES[index]:-"-"}"
      account_id="${AUTH_ACCOUNT_IDS[index]:-"-"}"
      plan_type="${AUTH_PLAN_TYPES[index]:-"-"}"
      subscription_start="${AUTH_SUBSCRIPTION_STARTS[index]:-"-"}"
      subscription_until="${AUTH_SUBSCRIPTION_UNTILS[index]:-"-"}"
      disabled="${AUTH_DISABLED_FLAGS[index]:-"false"}"
      if [[ "${disabled}" == "true" ]]; then
        index=$((index + 1))
        continue
      fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${name}" \
        "${note}" \
        "${priority}" \
        "${auth_index}" \
        "${account_id}" \
        "${plan_type}" \
        "${subscription_start}" \
        "${subscription_until}" \
        "${disabled}"
      index=$((index + 1))
    done | jq -Rsc '
      split("\n")
      | map(select(length > 0) | split("\t"))
      | map({
          name: .[0],
          note: .[1],
          priority: .[2],
          auth_index: .[3],
          account_id: .[4],
          plan_type: .[5],
          subscription_start: .[6],
          subscription_until: .[7],
          disabled: .[8]
        })
    '
  )"

  result_rows_json="$(
    printf '%s\n' "${RESULT_ROWS[@]}" | jq -Rsc '
      split("\n")
      | map(select(length > 0) | split("\t"))
      | map({
          name: .[0],
          note: .[1],
          priority: .[2],
          plan_info: .[3],
          subscription_info: .[4],
          limits: .[5],
          five_hour_reset: .[6],
          week_reset: .[7],
          status: .[8]
        })
    '
  )"

  summary_5h_json="$(
    printf '%s\n' "${SUMMARY_5H_ITEMS[@]}" | jq -Rsc '
      split("\n")
      | map(select(length > 0) | split("\t"))
      | map({value: .[0], order: .[1], name: .[2]})
    '
  )"

  summary_week_json="$(
    printf '%s\n' "${SUMMARY_WEEK_ITEMS[@]}" | jq -Rsc '
      split("\n")
      | map(select(length > 0) | split("\t"))
      | map({value: .[0], order: .[1], name: .[2]})
    '
  )"

  summary_expiry_json="$(
    printf '%s\n' "${SUMMARY_EXPIRY_ITEMS[@]}" | jq -Rsc '
      split("\n")
      | map(select(length > 0) | split("\t"))
      | map({remaining_seconds: .[0], order: .[1], name: .[2]})
    '
  )"

  summary_free_json="$(
    printf '%s\n' "${SUMMARY_FREE_ITEMS[@]}" | jq -Rsc '
      split("\n")
      | map(select(length > 0) | split("\t"))
      | map({order: .[0], name: .[1]})
    '
  )"

  plan_change_json="$(
    printf '%s\n' "${SUMMARY_PLAN_CHANGE_ITEMS[@]}" | jq -Rsc '
      split("\n")
      | map(select(length > 0) | split("\t"))
      | map({name: .[0], previous_plan: .[1], current_plan: .[2]})
    '
  )"

  error_json="$(
    printf '%s\n' "${SUMMARY_ERROR_NAMES[@]}" | jq -Rsc '
      split("\n")
      | map(select(length > 0) | split("\t"))
      | map({name: .[0], reason: (.[1] // "")})
    '
  )"

  if [[ "${INCLUDE_MANAGEMENT_USAGE}" == "true" ]]; then
    # management usage 属于辅助快照，采集失败时写 null，不阻断额度查询结果落盘。
    log "查询 management usage 快照"
    management_usage_json="$(collect_management_usage_snapshot_json)"
  else
    # 默认不抓管理端当天总用量，避免 /v0/management/usage 大响应拖慢账号额度查询。
    management_usage_json="null"
  fi

  mkdir -p "$(dirname "${PROMPT_FILE}")"
  jq -n \
    --arg generated_at "$(current_timestamp_local)" \
    --arg summary_total "${SUMMARY_TOTAL}" \
    --arg summary_ok "${SUMMARY_OK}" \
    --arg summary_error "${SUMMARY_ERROR}" \
    --arg summary_sum_5h "${SUMMARY_SUM_5H}" \
    --arg summary_sum_week "${SUMMARY_SUM_WEEK}" \
    --argjson auth "${auth_json}" \
    --argjson result_rows "${result_rows_json}" \
    --argjson summary_5h_items "${summary_5h_json}" \
    --argjson summary_week_items "${summary_week_json}" \
    --argjson summary_expiry_items "${summary_expiry_json}" \
    --argjson summary_free_items "${summary_free_json}" \
    --argjson summary_plan_change_items "${plan_change_json}" \
    --argjson summary_error_items "${error_json}" \
    --argjson management_usage "${management_usage_json}" \
    --argjson state "${state_json}" \
    '{
      generated_at: $generated_at,
      auth: $auth,
      management_usage: $management_usage,
      summary: {
        total: $summary_total,
        ok: $summary_ok,
        error: $summary_error,
        sum_5h: $summary_sum_5h,
        sum_week: $summary_sum_week,
        five_hour_items: $summary_5h_items,
        week_items: $summary_week_items,
        expiry_items: $summary_expiry_items,
        free_items: $summary_free_items,
        plan_change_items: $summary_plan_change_items,
        error_items: $summary_error_items
      },
      result_rows: $result_rows,
      state: $state
    }' > "${PROMPT_FILE}.tmp" && mv "${PROMPT_FILE}.tmp" "${PROMPT_FILE}" || {
      rm -f "${PROMPT_FILE}.tmp"
      die "写入提示词快照失败: ${PROMPT_FILE}"
    }
}

load_prompt_snapshot() {
  AUTH_NAMES=()
  AUTH_NOTES=()
  AUTH_PRIORITIES=()
  AUTH_INDEXES=()
  AUTH_ACCOUNT_IDS=()
  AUTH_PLAN_TYPES=()
  AUTH_SUBSCRIPTION_STARTS=()
  AUTH_SUBSCRIPTION_UNTILS=()
  AUTH_DISABLED_FLAGS=()
  RESULT_ROWS=()
  SUMMARY_5H_ITEMS=()
  SUMMARY_WEEK_ITEMS=()
  SUMMARY_EXPIRY_ITEMS=()
  SUMMARY_FREE_ITEMS=()
  SUMMARY_PLAN_CHANGE_ITEMS=()
  SUMMARY_ERROR_NAMES=()

  while IFS=$'\t' read -r name note priority auth_index account_id plan_type subscription_start subscription_until disabled || [[ -n "${name}${note}${priority}${auth_index}${account_id}${plan_type}${subscription_start}${subscription_until}${disabled}" ]]; do
    [[ -n "${name}" ]] || continue
    AUTH_NAMES+=("${name}")
    AUTH_NOTES+=("${note:-"-"}")
    AUTH_PRIORITIES+=("${priority:-"-"}")
    AUTH_INDEXES+=("${auth_index:-"-"}")
    AUTH_ACCOUNT_IDS+=("${account_id:-"-"}")
    AUTH_PLAN_TYPES+=("${plan_type:-"-"}")
    AUTH_SUBSCRIPTION_STARTS+=("${subscription_start:-"-"}")
    AUTH_SUBSCRIPTION_UNTILS+=("${subscription_until:-"-"}")
    AUTH_DISABLED_FLAGS+=("${disabled:-"false"}")
  done < <(
    jq -r '.auth[]? | [
      (.name // "(未命名)"),
      (.note // "-"),
      (.priority // "-"),
      (.auth_index // "-"),
      (.account_id // "-"),
      (.plan_type // "-"),
      (.subscription_start // "-"),
      (.subscription_until // "-"),
      (.disabled // "false")
    ] | @tsv' "${PROMPT_FILE}"
  )

  while IFS=$'\t' read -r value order name || [[ -n "${value}${order}${name}" ]]; do
    [[ -n "${name}" ]] || continue
    SUMMARY_5H_ITEMS+=("${value}"$'\t'"${order}"$'\t'"${name}")
  done < <(jq -r '.summary.five_hour_items[]? | [(.value // ""), (.order // ""), (.name // "")] | @tsv' "${PROMPT_FILE}")

  while IFS=$'\t' read -r value order name || [[ -n "${value}${order}${name}" ]]; do
    [[ -n "${name}" ]] || continue
    SUMMARY_WEEK_ITEMS+=("${value}"$'\t'"${order}"$'\t'"${name}")
  done < <(jq -r '.summary.week_items[]? | [(.value // ""), (.order // ""), (.name // "")] | @tsv' "${PROMPT_FILE}")

  while IFS=$'\t' read -r remaining_seconds order name || [[ -n "${remaining_seconds}${order}${name}" ]]; do
    [[ -n "${name}" ]] || continue
    SUMMARY_EXPIRY_ITEMS+=("${remaining_seconds}"$'\t'"${order}"$'\t'"${name}")
  done < <(jq -r '.summary.expiry_items[]? | [(.remaining_seconds // ""), (.order // ""), (.name // "")] | @tsv' "${PROMPT_FILE}")

  while IFS=$'\t' read -r order name || [[ -n "${order}${name}" ]]; do
    [[ -n "${name}" ]] || continue
    SUMMARY_FREE_ITEMS+=("${order}"$'\t'"${name}")
  done < <(jq -r '.summary.free_items[]? | [(.order // ""), (.name // "")] | @tsv' "${PROMPT_FILE}")

  while IFS=$'\t' read -r name previous_plan current_plan || [[ -n "${name}${previous_plan}${current_plan}" ]]; do
    [[ -n "${name}" ]] || continue
    SUMMARY_PLAN_CHANGE_ITEMS+=("${name}"$'\t'"${previous_plan}"$'\t'"${current_plan}")
  done < <(jq -r '.summary.plan_change_items[]? | [(.name // ""), (.previous_plan // ""), (.current_plan // "")] | @tsv' "${PROMPT_FILE}")

  while IFS=$'\t' read -r name reason || [[ -n "${name}${reason}" ]]; do
    [[ -n "${name}" ]] || continue
    SUMMARY_ERROR_NAMES+=("${name}"$'\t'"$(compact_error_reason "${reason}")")
  done < <(jq -r '.summary.error_items[]? | [(.name // ""), (.reason // "")] | @tsv' "${PROMPT_FILE}")

  while IFS=$'\t' read -r name note priority plan_info subscription_info limits five_hour_reset week_reset status || [[ -n "${name}${note}${priority}${plan_info}${subscription_info}${limits}${five_hour_reset}${week_reset}${status}" ]]; do
    [[ -n "${name}" ]] || continue
    RESULT_ROWS+=("${name}"$'\t'"${note}"$'\t'"${priority}"$'\t'"${plan_info}"$'\t'"${subscription_info}"$'\t'"${limits}"$'\t'"${five_hour_reset}"$'\t'"${week_reset}"$'\t'"${status}")
  done < <(
    jq -r '.result_rows[]? | [
      (.name // "(未命名)"),
      (.note // "-"),
      (.priority // "-"),
      (.plan_info // "-"),
      (.subscription_info // "-"),
      (.limits // "-"),
      (.five_hour_reset // "-"),
      (.week_reset // "-"),
      (.status // "-")
    ] | @tsv' "${PROMPT_FILE}"
  )

  SUMMARY_TOTAL="$(jq -r '.summary.total // "0"' "${PROMPT_FILE}")"
  SUMMARY_OK="$(jq -r '.summary.ok // "0"' "${PROMPT_FILE}")"
  SUMMARY_ERROR="$(jq -r '.summary.error // "0"' "${PROMPT_FILE}")"
  SUMMARY_SUM_5H="$(jq -r '.summary.sum_5h // "0"' "${PROMPT_FILE}")"
  SUMMARY_SUM_WEEK="$(jq -r '.summary.sum_week // "0"' "${PROMPT_FILE}")"
  SUMMARY_ITEM_ORDER=0
}

build_management_usage_prompt_lines() {
  [[ -f "${PROMPT_FILE}" ]] || return 0

  jq -r '
    def brief_items($items; $extra_key; $extra_label):
      ($items // [])
      | .[:8]
      | map(
          .name + " " + (.tokens_m // "0M") + "/" + ((.requests // 0) | tostring) + "次"
          + (if .[$extra_key] != null then "（" + $extra_label + ((.[$extra_key] // 0) | tostring) + "）" else "" end)
        )
      | join("，")
      | if length > 0 then . else "无" end;

    .management_usage as $usage
    | select($usage != null and ($usage.available // false) == true)
    | [
        ("- 日期：" + ($usage.date // "-")),
        ("- 总请求：" + (($usage.total_requests // 0) | tostring)
          + "，成功/失败：" + (($usage.ok // 0) | tostring) + "/" + (($usage.fail // 0) | tostring)
          + "，成功率：" + ($usage.success_rate // "0%")
          + "，总 tokens：" + ($usage.total_tokens_m // "0M")),
        ("- 账号汇总：" + (brief_items($usage.accounts; "model_count"; "模型数 "))),
        ("- 模型汇总：" + (brief_items($usage.models; "account_count"; "账号数 "))),
        ("- 接口汇总：" + (brief_items($usage.apis; "model_count"; "模型数 ")))
      ]
    | .[]
  ' "${PROMPT_FILE}"
}

print_dashboard_image_prompt() {
  local five_hour_total="N/A"
  local week_total="N/A"
  local enabled_total="${#AUTH_NAMES[@]}"
  local free_count="${#SUMMARY_FREE_ITEMS[@]}"
  local error_count="${#SUMMARY_ERROR_NAMES[@]}"
  local expiring_soon_count
  local management_usage_lines
  local line

  if [[ "${#SUMMARY_5H_ITEMS[@]}" -gt 0 ]]; then
    five_hour_total="$(format_percent "${SUMMARY_SUM_5H}")"
  fi
  if [[ "${#SUMMARY_WEEK_ITEMS[@]}" -gt 0 ]]; then
    week_total="$(format_percent "${SUMMARY_SUM_WEEK}")"
  fi
  expiring_soon_count="$(count_expiring_soon_summary_items 7)"

  printf '\n'
  printf '# 看板图片提示词\n'
  printf '\n'
  cat <<'EOF'
## 任务
生成一张中文企业运营看板图片，标题为“账号额度监控摘要”。

## 视觉风格
- 类型：SaaS BI dashboard / 企业后台 / 运营周报 / 经营分析看板。
- 气质：干净、专业、可信、信息密度高，适合业务汇报。
- 配色：蓝白商务风或稳重深蓝商务风；低风险/高剩余用蓝绿系，预警/低剩余用橙红系。
- 避免：赛博朋克、强烈霓虹、海报式夸张光效、装饰性过强的背景。

## 版式要求
- 顶部：标题和概要指标卡片。
- 中部：额度明细为核心表格，5h剩余和周剩余必须并列展示。
- 辅助区：展示提醒、刷新重点、账号补充信息。
- 当天用量：仅在下方“当天用量”有数据时展示；如果标记为未采集，不要编造。
- 刷新时间：不要单独做大模块，必须归属于额度或刷新重点区域。

## 数据规则
- 只使用下方实时数据，不要改写数字，不要添加不存在的项目。
- 5h剩余和周剩余中的 0% 账号必须展示，不能因为数值为 0 而省略。
- 账号名右侧用 tag/标签样式展示套餐；订阅与备注放在账号名称下方。
- 订阅到期颜色：小于等于 7 天用红色；大于 7 天且小于等于 15 天用黄色；其余普通样式。
- 不要显示编造的日期、年份、时钟、时间戳；右上角、标题栏、页眉禁止出现 current time、last updated 等时间文案。

## 实时数据

EOF
  printf '### 概要\n'
  printf '| 分类 | 指标 |\n'
  printf '| --- | --- |\n'
  printf '| 基础 | 共 %s 个；OK %s；ERR %s |\n' "${enabled_total}" "${SUMMARY_OK}" "${SUMMARY_ERROR}"
  printf '| 额度 | 5h总剩余 %s；周总剩余 %s |\n' "${five_hour_total}" "${week_total}"
  printf '| 风险 | free %s；异常 %s；7天内到期 %s |\n' \
    "${free_count}" \
    "${error_count}" \
    "${expiring_soon_count}"
  printf '\n### 额度明细\n'
  build_quota_detail_table
  printf '\n### 提醒\n'
  printf -- '- '
  build_free_summary_line
  printf -- '- '
  build_expiring_soon_summary_line 7
  printf -- '- '
  build_plan_change_summary_line
  printf -- '- '
  build_error_summary_line
  printf '\n### 当天用量\n'
  management_usage_lines="$(build_management_usage_prompt_lines)"
  if [[ -n "${management_usage_lines}" ]]; then
    printf '%s\n' "${management_usage_lines}"
  else
    printf -- '- 未采集\n'
  fi
  printf '\n### 刷新重点\n'
  printf -- '- '
  build_refresh_focus_line '5h刷新重点' '5h'
  printf -- '- '
  build_refresh_focus_line '周刷新重点' 'week'
  printf '\n### 账号补充信息\n'
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    printf -- '- %s\n' "${line}"
  done < <(build_account_info_lines)
  printf '\n### 订阅到期重点\n'
  printf -- '- '
  build_expiry_focus_line
  cat <<'EOF'

## 输出特征
operations dashboard, business analytics board, enterprise SaaS admin UI, Chinese infographic, clean layout, highly readable.
EOF
}

record_success_summary() {
  local name="$1"
  local five_hour="$2"
  local week="$3"
  local include_remaining="${4:-true}"
  local entry_order=""
  local week_positive="false"

  SUMMARY_OK=$((SUMMARY_OK + 1))
  printf -v entry_order '%06d' "${SUMMARY_ITEM_ORDER}"
  SUMMARY_ITEM_ORDER=$((SUMMARY_ITEM_ORDER + 1))

  [[ "${include_remaining}" == "true" ]] || return 0

  if [[ "${week}" =~ ^[0-9]+([.][0-9]+)?$ ]] && number_greater_than_zero "${week}"; then
    week_positive="true"
  fi

  if [[ "${five_hour}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    SUMMARY_5H_ITEMS+=("${five_hour}"$'\t'"${entry_order}"$'\t'"${name}")
    # 周剩余为 0 时，该账号的 5 小时额度实际不可用，不计入 5 小时总量。
    if [[ ! "${week}" =~ ^[0-9]+([.][0-9]+)?$ ]] || [[ "${week_positive}" == "true" ]]; then
      SUMMARY_SUM_5H="$(number_add "${SUMMARY_SUM_5H}" "${five_hour}")"
    fi
  fi

  if [[ "${week}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    SUMMARY_WEEK_ITEMS+=("${week}"$'\t'"${entry_order}"$'\t'"${name}")
    SUMMARY_SUM_WEEK="$(number_add "${SUMMARY_SUM_WEEK}" "${week}")"
  fi
}

print_usage_summary() {
  local five_hour_total="N/A"
  local week_total="N/A"
  local free_count="${#SUMMARY_FREE_ITEMS[@]}"
  local disabled_count
  local error_count="${#SUMMARY_ERROR_NAMES[@]}"
  local expiring_soon_count

  if [[ "${#SUMMARY_5H_ITEMS[@]}" -gt 0 ]]; then
    five_hour_total="$(format_percent "${SUMMARY_SUM_5H}")"
  fi
  if [[ "${#SUMMARY_WEEK_ITEMS[@]}" -gt 0 ]]; then
    week_total="$(format_percent "${SUMMARY_SUM_WEEK}")"
  fi
  disabled_count="$(count_disabled_summary_items)"
  expiring_soon_count="$(count_expiring_soon_summary_items 7)"

  printf '## 概要\n'
  printf '| 分类 | 指标 |\n'
  printf '| --- | --- |\n'
  printf '| 基础 | 共 %s 个；OK %s；ERR %s |\n' "${SUMMARY_TOTAL}" "${SUMMARY_OK}" "${SUMMARY_ERROR}"
  printf '| 额度 | 5h总剩余 %s；周总剩余 %s |\n' "${five_hour_total}" "${week_total}"
  printf '| 风险 | free %s；已禁用 %s；异常 %s；7天内到期 %s |\n' \
    "${free_count}" \
    "${disabled_count}" \
    "${error_count}" \
    "${expiring_soon_count}"

  printf '\n## 额度摘要\n'
  printf -- '- '
  build_summary_metric_line '5h剩余' SUMMARY_5H_ITEMS
  printf -- '- '
  build_summary_metric_line '周剩余' SUMMARY_WEEK_ITEMS

  printf '\n## 提醒\n'
  printf -- '- '
  build_free_summary_line
  printf -- '- '
  build_disabled_summary_line
  printf -- '- '
  build_expiring_soon_summary_line 7
  printf -- '- '
  build_plan_change_summary_line
  printf -- '- '
  build_error_summary_line
  printf '\n'
}

refresh_result_row_priorities_from_auth_entries() {
  local row
  local -a refreshed_rows=()
  local name note priority plan_info subscription_info limits five_hour_reset week_reset status
  local auth_index

  for row in "${RESULT_ROWS[@]}"; do
    IFS=$'\t' read -r name note priority plan_info subscription_info limits five_hour_reset week_reset status <<< "${row}"
    auth_index=0
    while [[ "${auth_index}" -lt "${#AUTH_NAMES[@]}" ]]; do
      if [[ "${AUTH_NAMES[auth_index]:-}" == "${name}" ]]; then
        priority="${AUTH_PRIORITIES[auth_index]:-"${priority}"}"
        break
      fi
      auth_index=$((auth_index + 1))
    done
    refreshed_rows+=("${name}"$'\t'"${note}"$'\t'"${priority}"$'\t'"${plan_info}"$'\t'"${subscription_info}"$'\t'"${limits}"$'\t'"${five_hour_reset}"$'\t'"${week_reset}"$'\t'"${status}")
  done

  RESULT_ROWS=("${refreshed_rows[@]}")
}

render_and_save_usage_results() {
  render_usage_table
  printf '\n'
  print_usage_summary
  save_prompt_snapshot
}

disable_free_weekly_quota_if_needed() {
  local name="$1"
  local index="$2"
  local week_remaining="$3"
  local week_reset_epoch="$4"
  local now_epoch
  local restore_at

  [[ "${week_remaining}" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
  if number_greater_than_zero "${week_remaining}"; then
    return 1
  fi

  if [[ ! "${week_reset_epoch}" =~ ^[0-9]+$ ]]; then
    log "free 账号周额度已用尽但缺少周刷新时间，跳过自动禁用: ${name}"
    return 1
  fi

  now_epoch="$(date '+%s')"
  if (( week_reset_epoch <= now_epoch )); then
    log "free 账号周额度已用尽但周刷新时间已过，跳过自动禁用: ${name}"
    state_remove_free_weekly_disabled "${name}"
    return 1
  fi

  restore_at="$(format_reset_time "${week_reset_epoch}")"
  log "free 账号周额度用尽，自动禁用到周刷新: ${name}（恢复 ${restore_at}）"
  disable_auth_entry_if_needed "${name}" "${index}" "free 周额度用尽"
  state_set_free_weekly_disabled "${name}" "${week_reset_epoch}" "${restore_at}" "free 周额度用尽"
  return 0
}

query_usage_for_auth_entries() {
  local finalize="${1:-true}"
  local total="${#AUTH_INDEXES[@]}"
  local index=0
  local current_index=0
  local name note priority account_id plan_type disabled_flag subscription_start subscription_until
  local plan_info subscription_info auth_index response parsed
  local first second third fourth fifth error_reason raw_error_reason previous_plan_type
  local five_hour_reset week_reset status
  local temp_dir job_count=0

  RESULT_ROWS=()
  SUMMARY_TOTAL="${total}"
  SUMMARY_OK=0
  SUMMARY_ERROR=0
  SUMMARY_SUM_5H=0
  SUMMARY_SUM_WEEK=0
  SUMMARY_5H_ITEMS=()
  SUMMARY_WEEK_ITEMS=()
  SUMMARY_EXPIRY_ITEMS=()
  SUMMARY_FREE_ITEMS=()
  SUMMARY_ERROR_NAMES=()
  SUMMARY_PLAN_CHANGE_ITEMS=()
  SUMMARY_ITEM_ORDER=0

  [[ "${total}" -gt 0 ]] || die "没有可查询的 authIndex，请检查 auth-files 响应"
  ensure_state_file
  restore_free_weekly_disabled_entries_for_current_entries

  # 创建临时目录用于并行查询
  temp_dir="$(mktemp -d)"

  # 并行查询
  for auth_index in "${AUTH_INDEXES[@]}"; do
    current_index="${index}"
    name="${AUTH_NAMES[current_index]:-"(未命名)"}"
    plan_type="${AUTH_PLAN_TYPES[current_index]:-"-"}"
    disabled_flag="${AUTH_DISABLED_FLAGS[current_index]:-"false"}"
    subscription_until="${AUTH_SUBSCRIPTION_UNTILS[current_index]:-"-"}"

    record_expiry_summary "${name}" "${subscription_until}" "${current_index}"

    if [[ "${disabled_flag}" == "true" ]]; then
      log "跳过 usage ($((index + 1))/${total}): ${name}（disabled=true）"
      index=$((index + 1))
      continue
    fi

    log "查询 usage ($((index + 1))/${total}): ${name}"
    fetch_usage_parallel "${current_index}" "${auth_index}" "${plan_type}" "${temp_dir}/${current_index}.out" &
    job_count=$((job_count + 1))

    if ((job_count >= MAX_PARALLEL_JOBS)); then
      wait -n
      job_count=$((job_count - 1))
    fi

    index=$((index + 1))
  done
  wait

  # 处理结果
  for current_index in "${!AUTH_INDEXES[@]}"; do
    [[ -f "${temp_dir}/${current_index}.out" ]] || continue

    name="${AUTH_NAMES[current_index]:-"(未命名)"}"
    note="${AUTH_NOTES[current_index]:-"-"}"
    priority="${AUTH_PRIORITIES[current_index]:-"-"}"
    plan_type="${AUTH_PLAN_TYPES[current_index]:-"-"}"
    disabled_flag="${AUTH_DISABLED_FLAGS[current_index]:-"false"}"
    subscription_start="${AUTH_SUBSCRIPTION_STARTS[current_index]:-"-"}"
    subscription_until="${AUTH_SUBSCRIPTION_UNTILS[current_index]:-"-"}"
    plan_info="${plan_type}"
    subscription_info="$(format_subscription_time "${subscription_start}") -> $(format_subscription_time "${subscription_until}")"

    IFS=$'\t' read -r _idx response < "${temp_dir}/${current_index}.out"

    if [[ "${response}" == "ERROR"* ]]; then
      IFS=$'\t' read -r _idx _err error_reason < "${temp_dir}/${current_index}.out"
      error_reason="$(compact_error_reason "${error_reason}")"
      SUMMARY_ERROR=$((SUMMARY_ERROR + 1))
      RESULT_ROWS+=("${name}"$'\t'"${note}"$'\t'"${priority}"$'\t'"${plan_info}"$'\t'"${subscription_info}"$'\t-\t-\t-\t'"异常: ${error_reason}")
      continue
    fi

    if ! parsed="$(extract_usage_limits "${response}" 2>&1)"; then
      error_reason="$(compact_error_reason "${parsed}")"
      SUMMARY_ERROR=$((SUMMARY_ERROR + 1))
      RESULT_ROWS+=("${name}"$'\t'"${note}"$'\t'"${priority}"$'\t'"${plan_info}"$'\t'"${subscription_info}"$'\t-\t-\t-\t'"异常: ${error_reason}")
      continue
    fi

    IFS=$'\t' read -r first second third fourth fifth <<< "${parsed}"
    if [[ "${first}" == "ERROR" ]]; then
      raw_error_reason="${second:-未知错误}"
      error_reason="$(compact_error_reason "${raw_error_reason}")"
      SUMMARY_ERROR=$((SUMMARY_ERROR + 1))
      record_error_summary "${name}" "${error_reason}"
      if is_api_call_401_error "${raw_error_reason}"; then
        disable_auth_entry_if_needed "${name}" "${current_index}" "${error_reason}"
        disabled_flag="true"
      fi
      RESULT_ROWS+=("${name}"$'\t'"${note}"$'\t'"${priority}"$'\t'"${plan_info}"$'\t'"${subscription_info}"$'\t-\t-\t-\t'"异常: ${error_reason}")
      continue
    fi

    if [[ -n "${fifth}" && "${fifth}" != "-" ]]; then
      plan_type="${fifth}"
      AUTH_PLAN_TYPES[current_index]="${fifth}"
      previous_plan_type="$(get_previous_plan_type "${name}")"
      if [[ -n "${previous_plan_type}" && "${previous_plan_type}" != "free" && "${plan_type}" == "free" ]]; then
        record_plan_change_summary "${name}" "${previous_plan_type}" "${plan_type}"
      fi
      state_set_plan_type "${name}" "${plan_type}"
    fi
    if [[ "${plan_type}" == "free" ]]; then
      SUMMARY_FREE_ITEMS+=("$(printf '%06d' "${current_index}")"$'\t'"${name}")
    fi
    plan_info="${plan_type}"
    five_hour_reset="$(format_reset_time "${second}")"
    week_reset="$(format_reset_time "${fourth}")"
    status="OK"
    if [[ "${plan_type}" == "free" ]] && disable_free_weekly_quota_if_needed "${name}" "${current_index}" "${third}" "${fourth}"; then
      disabled_flag="true"
      status="已禁用: free周额度用尽，恢复 ${week_reset}"
      SUMMARY_ERROR=$((SUMMARY_ERROR + 1))
      record_error_summary "${name}" "首次禁用: free周额度用尽，恢复 ${week_reset}"
    fi
    if [[ "${disabled_flag}" == "true" ]]; then
      :
    elif is_expired_plus_plan "${plan_type}" "${subscription_until}"; then
      record_success_summary "${name}" "${first}" "${third}" "false"
    else
      record_success_summary "${name}" "${first}" "${third}"
    fi
    RESULT_ROWS+=("${name}"$'\t'"${note}"$'\t'"${priority}"$'\t'"${plan_info}"$'\t'"${subscription_info}"$'\t'"$(format_percent "${first}")/$(format_percent "${third}")"$'\t'"${five_hour_reset}"$'\t'"${week_reset}"$'\t'"${status}")
  done

  rm -rf "${temp_dir}"

  if [[ "${finalize}" == "true" ]]; then
    render_and_save_usage_results
  fi
}

run_all_action() {
  local auth_files_response

  log "查询 auth-files"
  auth_files_response="$(fetch_auth_files_cached)"
  resolve_auth_entries_from_auth_files "${auth_files_response}"
  query_usage_for_auth_entries "false"
  log "自动处理 priority"
  auto_manage_priorities_for_current_entries
  sort_auth_entries_by_priority
  refresh_result_row_priorities_from_auth_entries
  render_and_save_usage_results
  print_auto_priority_report
}

run_usage_action() {
  local auth_files_response

  print_auto_priority_rules
  log "从 auth-files 自动提取全部 name/authIndex"
  auth_files_response="$(fetch_auth_files_cached)"
  resolve_auth_entries_from_auth_files "${auth_files_response}"
  query_usage_for_auth_entries
}

run_management_usage_action() {
  local response
  local curl_error_file
  local curl_error

  log "查询 management usage"
  curl_error_file="$(mktemp)"
  if ! response="$(fetch_management_usage 2>"${curl_error_file}")"; then
    curl_error="$(<"${curl_error_file}")"
    rm -f "${curl_error_file}"
    if ! is_supported_management_usage_response "${response}"; then
      die "management usage 请求失败: $(compact_error_reason "${curl_error:-${response}}")；当前 usage 超时 ${USAGE_TIMEOUT}s，可加 --usage-timeout 180"
    fi
    log "management usage 收到可解析响应，忽略 curl 非零退出: $(compact_error_reason "${curl_error}")"
  else
    rm -f "${curl_error_file}"
  fi
  if ! is_supported_management_usage_response "${response}"; then
    die "management usage 响应不是预期 JSON 对象，请检查 --base-url 是否指向支持 /v0/management/usage 的服务"
  fi
  render_management_usage "${response}"
  save_management_usage_snapshot "${response}"
}

run_disabled_list_action() {
  local auth_files_response

  log "从 auth-files 提取 disabled=true 账号"
  auth_files_response="$(fetch_auth_files_cached)"
  resolve_auth_entries_from_auth_files "${auth_files_response}"
  render_disabled_list
}

main() {
  parse_args "$@"
  BASE_URL="${BASE_URL%/}"
  ensure_requirements

  if [[ "${ACTION}" == "all" ]]; then
    run_all_action
    return 0
  fi

  if [[ "${ACTION}" == "auth-files" ]]; then
    query_auth_files
    return 0
  fi

  if [[ "${ACTION}" == "usage" ]]; then
    run_usage_action
    return 0
  fi

  if [[ "${ACTION}" == "management-usage" || "${ACTION}" == "server-usage" ]]; then
    run_management_usage_action
    return 0
  fi

  if [[ "${ACTION}" == "disabled-list" || "${ACTION}" == "disabled" ]]; then
    run_disabled_list_action
    return 0
  fi

  if [[ "${ACTION}" == "delete-auth" || "${ACTION}" == "delete-auth-file" ]]; then
    delete_auth_file_action
    return 0
  fi

  if [[ "${ACTION}" == "priority" || "${ACTION}" == "set-priority" ]]; then
    set_auth_priority
    return 0
  fi

  if [[ "${ACTION}" == "fields" ]]; then
    update_auth_fields
    return 0
  fi

  if [[ "${ACTION}" == "auto-priority" ]]; then
    auto_manage_priorities
    return 0
  fi

  if [[ "${ACTION}" == "prompt" ]]; then
    load_prompt_snapshot
    print_dashboard_image_prompt
    return 0
  fi

  die "未知动作: ${ACTION}"
}

main "$@"

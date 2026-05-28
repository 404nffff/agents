#!/usr/bin/env bash
set -euo pipefail

# Sub2API 管理端账号工具。
# 默认读取脚本同目录的 .env，只使用 x-api-key 鉴权，不携带 Bearer Token 或 Cookie。
#
# 动作与接口：
#   all          -> 默认动作，依次执行 accounts + keys
#   accounts     -> GET    /api/v1/admin/accounts
#   usage        -> GET    /api/v1/admin/accounts/<id>/usage
#   keys         -> GET    /api/v1/admin/users/1/api-keys
#                   GET    /api/v1/admin/usage?api_key_id=<id>&start_date=<today>&end_date=<today>
#   schedulable  -> POST   /api/v1/admin/accounts/<id>/schedulable
#   disable      -> POST   /api/v1/admin/accounts/<id>/schedulable   {"schedulable":false}
#   enable       -> POST   /api/v1/admin/accounts/<id>/schedulable   {"schedulable":true}
#   delete       -> DELETE /api/v1/admin/accounts/<id>
#   priority     -> POST   /api/v1/admin/accounts/bulk-update
#   bulk-update  -> POST   /api/v1/admin/accounts/bulk-update
#
# 常用用法：
#   cp shell/sub2api/.env.example shell/sub2api/.env
#   ./shell/sub2api/query.sh
#   ./shell/sub2api/query.sh accounts
#   ./shell/sub2api/query.sh keys
#   ./shell/sub2api/query.sh usage --account-id 15
#   ./shell/sub2api/query.sh disable --account-id 16
#   ./shell/sub2api/query.sh enable --account-id 16
#   ./shell/sub2api/query.sh delete --account-id 14
#   ./shell/sub2api/query.sh priority --account-id 16 --priority 1
#
# 默认只有列表动作会落盘 JSON：
#   shell/sub2api/accounts.json
#   shell/sub2api/keys.json
# 所有动作都只打印 Markdown，不生成 report.md；
# 非列表动作仅在显式传 --output 时才保存 JSON。

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd -- "$(dirname "$0")" && pwd)"
DEFAULT_ENV_FILE="${SCRIPT_DIR}/.env"
ENV_FILE="${SUB2API_ENV_FILE:-${DEFAULT_ENV_FILE}}"

load_sub2api_env_file() {
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
  done < <(compgen -A variable SUB2API_ || true)

  # 只加载本工具约定的本地配置文件，避免命令行反复传入敏感值。
  # shellcheck disable=SC1090
  . "${env_file}"

  for var_name in "${preserved_names[@]}"; do
    printf -v "${var_name}" '%s' "${preserved_values[${var_name}]}"
    export "${var_name}"
  done
}

load_sub2api_env_file "${ENV_FILE}"

ACTION="all"
BASE_URL="${SUB2API_BASE_URL:-}"
API_KEY="${SUB2API_API_KEY:-}"
OUTPUT_FILE="${SUB2API_OUTPUT_FILE:-}"
ACCOUNT_ID="${SUB2API_ACCOUNT_ID:-}"
ACCOUNT_IDS="${SUB2API_ACCOUNT_IDS:-}"
SCHEDULABLE_VALUE="${SUB2API_SCHEDULABLE:-}"
PRIORITY_VALUE="${SUB2API_PRIORITY:-}"
TIMEZONE="Etc/GMT-8"
TIMEOUT="30"
BROWSER_USER_AGENT="${SUB2API_USER_AGENT:-Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36}"
DEFAULT_ACCOUNTS_PAGE_SIZE=10
DEFAULT_KEYS_PAGE_SIZE=20
DEFAULT_KEY_USAGE_PAGE_SIZE=20
PARALLELISM="${SUB2API_PARALLELISM:-6}"
GENERATED_AT="$(date -Iseconds)"
TODAY_DATE="$(date +%F)"

usage() {
  cat <<EOF
用法:
  ./${SCRIPT_NAME} [all|accounts|keys|usage|schedulable|disable|enable|delete|priority|bulk-update|raw] [选项]

  说明:
  查询或更新 Sub2API 管理端账号状态：
  - GET /api/v1/admin/accounts
  - GET /api/v1/admin/accounts/<id>/usage
  - GET /api/v1/admin/users/1/api-keys
  - GET /api/v1/admin/usage?api_key_id=<id>
  - POST /api/v1/admin/accounts/<id>/schedulable
  - POST /api/v1/admin/accounts/bulk-update
  - DELETE /api/v1/admin/accounts/<id>
  默认读取 ${DEFAULT_ENV_FILE}；如需覆盖路径，可设置 SUB2API_ENV_FILE。
  默认动作是 all，会先输出账号汇总，再输出令牌汇总。
  默认会在终端打印 Markdown 结果，不生成 report.md。
  只有 accounts/keys 列表默认写 accounts.json/keys.json；
  其他动作仅在显式传 --output 时保存 JSON。
  accounts 会固定按每页 ${DEFAULT_ACCOUNTS_PAGE_SIZE} 条自动翻页拉完账号列表，再按每个账号 id 调用 usage 并合并成集合。
  keys 会固定按每页 ${DEFAULT_KEYS_PAGE_SIZE} 条自动翻页拉完令牌列表，再按每个令牌 id 查询当天 admin usage 并合并账号、模型、IP、tokens。
  终端默认输出 Markdown 报告内容；raw 动作保留原始 accounts 接口响应。

选项:
  --base-url <url>          Sub2API 地址，也可用 SUB2API_BASE_URL
  --api-key <key>           x-api-key，也可用 SUB2API_API_KEY
  --output <path>           保存响应 JSON；未指定时按动作自动命名
  --account-id <id>         usage 动作的账号 id，也可用 SUB2API_ACCOUNT_ID
  --account-ids <csv>       bulk-update/priority 的账号 id 列表，例如 16,17
  --schedulable <bool>      schedulable 动作设置 true/false，也可用 SUB2API_SCHEDULABLE
  --priority <int>          priority/bulk-update 动作设置优先级，也可用 SUB2API_PRIORITY
  SUB2API_PARALLELISM       accounts/keys 内部 usage 并发数，默认 ${PARALLELISM}
  -h, --help                显示帮助

示例:
  SUB2API_BASE_URL='http://127.0.0.1:3335' SUB2API_API_KEY='***' ./${SCRIPT_NAME}
  ./${SCRIPT_NAME} accounts --base-url 'http://127.0.0.1:3335' --api-key '***'
  ./${SCRIPT_NAME} keys --base-url 'http://127.0.0.1:3335' --api-key '***'
  ./${SCRIPT_NAME} usage --base-url 'http://127.0.0.1:3335' --api-key '***' --account-id '15'
  ./${SCRIPT_NAME} schedulable --account-id '16' --schedulable false
  ./${SCRIPT_NAME} disable --account-id '16'
  ./${SCRIPT_NAME} enable --account-id '16'
  ./${SCRIPT_NAME} delete --account-id '14'
  ./${SCRIPT_NAME} priority --account-id '16' --priority 1
  ./${SCRIPT_NAME} bulk-update --account-ids '16,17' --priority 1
EOF
}

die() {
  printf '[%s] 错误: %s\n' "${SCRIPT_NAME}" "$*" >&2
  exit 1
}

log() {
  printf '[%s] %s\n' "${SCRIPT_NAME}" "$*" >&2
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"
}

wait_for_parallel_slot() {
  local limit="$1"
  local running
  while true; do
    running="$(jobs -pr | wc -l | tr -d ' ')"
    [[ "${running}" -lt "${limit}" ]] && break
    wait -n || true
  done
}

wait_for_parallel_jobs() {
  while [[ "$(jobs -pr | wc -l | tr -d ' ')" -gt 0 ]]; do
    wait -n || true
  done
}

format_remaining_quota() {
  local value="${1:-}"
  if [[ -z "${value}" || "${value}" == "null" || "${value}" == "-" ]]; then
    printf '-'
    return 0
  fi

  if jq -nr --arg value "${value}" '$value | tonumber' >/dev/null 2>&1; then
    jq -nr --arg value "${value}" '100 - ($value | tonumber)'
  else
    printf '%s' "${value}"
  fi
}

format_tokens_m() {
  local value="${1:-}"
  if [[ -z "${value}" || "${value}" == "null" || "${value}" == "-" ]]; then
    printf '0.00M'
    return 0
  fi

  if jq -nr --arg value "${value}" '$value | tonumber' >/dev/null 2>&1; then
    awk -v value="${value}" 'BEGIN { printf "%.2fM", value / 1000000 }'
  else
    printf '%s' "${value}"
  fi
}

normalize_iso_datetime() {
  local value="${1:-}"
  if [[ "${value}" =~ ^(.+)([+-][0-9]{2}):([0-9]{2})$ ]]; then
    printf '%s%s%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
    return 0
  fi
  printf '%s' "${value}"
}

format_display_time() {
  local value="${1:-}"
  local normalized_value

  if [[ -z "${value}" || "${value}" == "null" || "${value}" == "-" ]]; then
    printf '-'
    return 0
  fi

  if [[ "${value}" =~ ^[0-9]+$ ]]; then
    if date -d "@${value}" '+%m-%d %H:%M:%S' >/dev/null 2>&1; then
      date -d "@${value}" '+%m-%d %H:%M:%S'
      return 0
    fi
    if date -r "${value}" '+%m-%d %H:%M:%S' >/dev/null 2>&1; then
      date -r "${value}" '+%m-%d %H:%M:%S'
      return 0
    fi
  fi

  if date -d "${value}" '+%m-%d %H:%M:%S' >/dev/null 2>&1; then
    date -d "${value}" '+%m-%d %H:%M:%S'
    return 0
  fi

  normalized_value="$(normalize_iso_datetime "${value}")"
  if date -j -f '%Y-%m-%dT%H:%M:%S%z' "${normalized_value}" '+%m-%d %H:%M:%S' >/dev/null 2>&1; then
    date -j -f '%Y-%m-%dT%H:%M:%S%z' "${normalized_value}" '+%m-%d %H:%M:%S'
    return 0
  fi

  printf '%s' "${value}"
}

url_encode() {
  local value="${1:-}"
  local i char encoded=""
  local length="${#value}"
  for ((i = 0; i < length; i++)); do
    char="${value:i:1}"
    case "${char}" in
      [a-zA-Z0-9.~_-])
        encoded+="${char}"
        ;;
      *)
        printf -v encoded '%s%%%02X' "${encoded}" "'${char}"
        ;;
    esac
  done
  printf '%s' "${encoded}"
}

api_base_url() {
  local raw="${BASE_URL%/}"
  raw="${raw%/api/v1}"
  raw="${raw%/api}"
  printf '%s' "${raw}"
}

append_query_param() {
  local name="$1"
  local value="$2"
  local sep="&"
  if [[ -z "${QUERY_STRING}" ]]; then
    sep=""
  fi
  QUERY_STRING+="${sep}${name}=$(url_encode "${value}")"
}

parse_args() {
  if [[ $# -gt 0 && "$1" != -* ]]; then
    ACTION="$1"
    shift
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base-url)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--base-url 需要参数"
        BASE_URL="${2%/}"
        shift 2
        ;;
      --api-key|--key)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--api-key 需要参数"
        API_KEY="$2"
        shift 2
        ;;
      --output)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--output 需要参数"
        OUTPUT_FILE="$2"
        shift 2
        ;;
      --account-id|--id)
        [[ $# -ge 2 && "${2:-}" =~ ^[0-9]+$ ]] || die "--account-id 需要整数"
        ACCOUNT_ID="$2"
        shift 2
        ;;
      --account-ids)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--account-ids 需要参数"
        ACCOUNT_IDS="$2"
        shift 2
        ;;
      --schedulable)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--schedulable 需要参数"
        SCHEDULABLE_VALUE="$2"
        shift 2
        ;;
      --priority)
        [[ $# -ge 2 && "${2:-}" =~ ^-?[0-9]+$ ]] || die "--priority 需要整数"
        PRIORITY_VALUE="$2"
        shift 2
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

normalize_schedulable_value() {
  local value="${1:-}"
  case "${value,,}" in
    true|1|yes|y|on)
      printf 'true'
      ;;
    false|0|no|n|off)
      printf 'false'
      ;;
    *)
      return 1
      ;;
  esac
}

normalize_account_ids_csv() {
  local value="${1:-}"
  local sanitized
  sanitized="$(printf '%s' "${value}" | tr -d '[:space:]')"
  [[ -n "${sanitized}" ]] || return 1
  [[ "${sanitized}" =~ ^[0-9]+(,[0-9]+)*$ ]] || return 1
  printf '%s' "${sanitized}"
}

validate_config() {
  case "${ACTION}" in
    all|accounts|keys|usage|schedulable|disable|enable|delete|priority|bulk-update|raw) ;;
    *) die "未知动作: ${ACTION}" ;;
  esac
  [[ -n "${BASE_URL}" ]] || die "缺少 SUB2API_BASE_URL 或 --base-url"
  [[ -n "${API_KEY}" ]] || die "缺少 SUB2API_API_KEY 或 --api-key"
  [[ "${TIMEOUT}" =~ ^[0-9]+$ ]] || die "TIMEOUT 需要整数"
  [[ "${PARALLELISM}" =~ ^[0-9]+$ && "${PARALLELISM}" -gt 0 ]] || die "SUB2API_PARALLELISM 需要正整数"
  if [[ "${ACTION}" == "usage" || "${ACTION}" == "schedulable" || "${ACTION}" == "disable" || "${ACTION}" == "enable" || "${ACTION}" == "delete" ]]; then
    [[ -n "${ACCOUNT_ID}" ]] || die "该动作需要 SUB2API_ACCOUNT_ID 或 --account-id"
    [[ "${ACCOUNT_ID}" =~ ^[0-9]+$ ]] || die "ACCOUNT_ID 需要整数"
  fi
  if [[ "${ACTION}" == "priority" ]]; then
    ACTION="bulk-update"
  fi
  if [[ "${ACTION}" == "bulk-update" ]]; then
    if [[ -z "${ACCOUNT_IDS}" ]]; then
      [[ -n "${ACCOUNT_ID}" ]] || die "bulk-update 动作需要 --account-id 或 --account-ids"
      ACCOUNT_IDS="${ACCOUNT_ID}"
    fi
    ACCOUNT_IDS="$(normalize_account_ids_csv "${ACCOUNT_IDS}")" || die "ACCOUNT_IDS 需要逗号分隔整数，例如 16,17"
    [[ -n "${PRIORITY_VALUE}" && "${PRIORITY_VALUE}" =~ ^-?[0-9]+$ ]] || die "bulk-update 动作需要 --priority 整数"
  fi
  if [[ "${ACTION}" == "disable" ]]; then
    SCHEDULABLE_VALUE="false"
  fi
  if [[ "${ACTION}" == "enable" ]]; then
    SCHEDULABLE_VALUE="true"
  fi
  if [[ "${ACTION}" == "schedulable" || "${ACTION}" == "disable" || "${ACTION}" == "enable" ]]; then
    SCHEDULABLE_VALUE="$(normalize_schedulable_value "${SCHEDULABLE_VALUE}")" || die "SCHEDULABLE 需要 true/false"
  fi
  if [[ "${ACTION}" != "raw" ]]; then
    need_cmd jq
  fi
}

build_accounts_url() {
  local page="$1"
  QUERY_STRING=""
  append_query_param "page" "${page}"
  append_query_param "page_size" "${DEFAULT_ACCOUNTS_PAGE_SIZE}"
  append_query_param "platform" ""
  append_query_param "type" ""
  append_query_param "status" ""
  append_query_param "privacy_mode" ""
  append_query_param "group" ""
  append_query_param "search" ""
  append_query_param "sort_by" "schedulable"
  append_query_param "sort_order" "desc"
  append_query_param "lite" "1"
  append_query_param "timezone" "${TIMEZONE}"
  printf '%s/api/v1/admin/accounts?%s' "$(api_base_url)" "${QUERY_STRING}"
}

build_keys_url() {
  QUERY_STRING=""
  append_query_param "timezone" "${TIMEZONE}"
  printf '%s/api/v1/admin/users/1/api-keys?%s' "$(api_base_url)" "${QUERY_STRING}"
}

build_usage_url() {
  QUERY_STRING=""
  append_query_param "timezone" "${TIMEZONE}"
  printf '%s/api/v1/admin/accounts/%s/usage?%s' "$(api_base_url)" "${ACCOUNT_ID}" "${QUERY_STRING}"
}

build_key_usage_url_for_id() {
  local api_key_id="$1"
  local page="$2"
  QUERY_STRING=""
  append_query_param "page" "${page}"
  append_query_param "page_size" "${DEFAULT_KEY_USAGE_PAGE_SIZE}"
  append_query_param "exact_total" "false"
  append_query_param "start_date" "${TODAY_DATE}"
  append_query_param "end_date" "${TODAY_DATE}"
  append_query_param "api_key_id" "${api_key_id}"
  append_query_param "sort_by" "created_at"
  append_query_param "sort_order" "desc"
  append_query_param "timezone" "${TIMEZONE}"
  printf '%s/api/v1/admin/usage?%s' "$(api_base_url)" "${QUERY_STRING}"
}

build_schedulable_url() {
  printf '%s/api/v1/admin/accounts/%s/schedulable' "$(api_base_url)" "${ACCOUNT_ID}"
}

build_delete_url() {
  printf '%s/api/v1/admin/accounts/%s' "$(api_base_url)" "${ACCOUNT_ID}"
}

build_bulk_update_url() {
  printf '%s/api/v1/admin/accounts/bulk-update' "$(api_base_url)"
}

resolved_output_file() {
  if [[ -n "${OUTPUT_FILE}" ]]; then
    printf '%s' "${OUTPUT_FILE}"
    return 0
  fi
  if [[ "${ACTION}" == "keys" ]]; then
    printf '%s/keys.json' "${SCRIPT_DIR}"
    return 0
  fi
  printf '%s/accounts.json' "${SCRIPT_DIR}"
}

resolved_report_file() {
  local output_file="$1"
  if [[ "${output_file}" == *.json ]]; then
    printf '%s-report.md' "${output_file%.json}"
    return 0
  fi
  printf '%s.md' "${output_file}"
}

build_usage_url_for_id() {
  local account_id="$1"
  QUERY_STRING=""
  append_query_param "timezone" "${TIMEZONE}"
  printf '%s/api/v1/admin/accounts/%s/usage?%s' "$(api_base_url)" "${account_id}" "${QUERY_STRING}"
}

normalize_usage_file() {
  local body_file="$1"
  local output_file="$2"
  local account_id="$3"
  jq --arg account_id "${account_id}" --arg generated_at "${GENERATED_AT}" '
    {
      code: (.code // 0),
      message: (.message // .msg // "success"),
      generated_at: $generated_at,
      data: {
        account_id: ($account_id | tonumber),
        updated_at: (.data.updated_at // .updated_at // null),
        five_hour: {
          utilization: (.data.five_hour.utilization // .five_hour.utilization // null),
          resets_at: (.data.five_hour.resets_at // .five_hour.resets_at // null),
          remaining_seconds: (.data.five_hour.remaining_seconds // .five_hour.remaining_seconds // null),
          window_stats: (.data.five_hour.window_stats // .five_hour.window_stats // null)
        },
        seven_day: {
          utilization: (.data.seven_day.utilization // .seven_day.utilization // null),
          resets_at: (.data.seven_day.resets_at // .seven_day.resets_at // null),
          remaining_seconds: (.data.seven_day.remaining_seconds // .seven_day.remaining_seconds // null),
          window_stats: (.data.seven_day.window_stats // .seven_day.window_stats // null)
        }
      }
    }
  ' "${body_file}" > "${output_file}"
}

normalize_schedulable_file() {
  local body_file="$1"
  local output_file="$2"
  local account_id="$3"
  local desired_schedulable="$4"
  jq --arg account_id "${account_id}" --arg desired_schedulable "${desired_schedulable}" --arg generated_at "${GENERATED_AT}" '
    {
      code: (.code // 0),
      message: (.message // .msg // "success"),
      generated_at: $generated_at,
      data: {
        account_id: ($account_id | tonumber),
        requested_schedulable: ($desired_schedulable == "true"),
        current_schedulable: (
          if (.data | type) == "object" and (.data | has("schedulable")) then .data.schedulable
          elif has("schedulable") then .schedulable
          else null
          end
        ),
        name: (.data.name // .name // null),
        platform: (.data.platform // .platform // null),
        type: (.data.type // .type // null),
        status: (.data.status // .status // null),
        error_message: (.data.error_message // .error_message // null),
        credentials_disabled: (
          if (.data | type) == "object"
            and (.data.credentials | type) == "object"
            and (.data.credentials | has("disabled")) then .data.credentials.disabled
          elif (.credentials | type) == "object" and (.credentials | has("disabled")) then .credentials.disabled
          else null
          end
        ),
        priority: (.data.priority // .priority // null),
        updated_at: (.data.updated_at // .updated_at // null),
        rate_limited_at: (.data.rate_limited_at // .rate_limited_at // null),
        rate_limit_reset_at: (.data.rate_limit_reset_at // .rate_limit_reset_at // null),
        overload_until: (.data.overload_until // .overload_until // null),
        temp_unschedulable_until: (.data.temp_unschedulable_until // .temp_unschedulable_until // null),
        temp_unschedulable_reason: (.data.temp_unschedulable_reason // .temp_unschedulable_reason // null),
        session_window_start: (.data.session_window_start // .session_window_start // null),
        session_window_end: (.data.session_window_end // .session_window_end // null),
        session_window_status: (.data.session_window_status // .session_window_status // null)
      }
    }
  ' "${body_file}" > "${output_file}"
}

normalize_delete_file() {
  local body_file="$1"
  local output_file="$2"
  local account_id="$3"
  jq --arg account_id "${account_id}" --arg generated_at "${GENERATED_AT}" '
    {
      code: (.code // 0),
      message: (.message // .msg // "success"),
      generated_at: $generated_at,
      data: {
        account_id: ($account_id | tonumber),
        deleted: true,
        id: (.data.id // .id // null),
        name: (.data.name // .name // null),
        status: (.data.status // .status // null),
        error_message: (.data.error_message // .error_message // null),
        updated_at: (.data.updated_at // .updated_at // null)
      }
    }
  ' "${body_file}" > "${output_file}"
}

normalize_bulk_update_file() {
  local body_file="$1"
  local output_file="$2"
  local account_ids_csv="$3"
  local priority_value="$4"
  jq --arg account_ids_csv "${account_ids_csv}" --arg priority_value "${priority_value}" --arg generated_at "${GENERATED_AT}" '
    {
      code: (.code // 0),
      message: (.message // .msg // "success"),
      generated_at: $generated_at,
      data: {
        account_ids: ($account_ids_csv | split(",") | map(tonumber)),
        requested_priority: ($priority_value | tonumber),
        updated_count: (
          if (.data | type) == "array" then (.data | length)
          elif (.data.items | type) == "array" then (.data.items | length)
          else null
          end
        ),
        raw: (.data // null)
      }
    }
  ' "${body_file}" > "${output_file}"
}

build_account_item() {
  local account_json="$1"
  local usage_file="$2"
  local error_message="${3:-}"
  if [[ -n "${usage_file}" && -f "${usage_file}" ]]; then
    jq -cn \
      --argjson account "${account_json}" \
      --slurpfile usage "${usage_file}" '
      {
        id: $account.id,
        name: $account.name,
        platform: $account.platform,
        type: $account.type,
        status: $account.status,
        schedulable: $account.schedulable,
        priority: $account.priority,
        rate_multiplier: $account.rate_multiplier,
        notes: $account.notes,
        error_message: $account.error_message,
        last_used_at: $account.last_used_at,
        group_ids: ($account.group_ids // []),
        group_names: (($account.groups // []) | map(.name)),
        credentials: {
          email: $account.credentials.email,
          disabled: $account.credentials.disabled,
          plan_type: $account.credentials.plan_type,
          priority: $account.credentials.priority,
          type: $account.credentials.type,
          expires_at: $account.credentials.expires_at,
          expired: $account.credentials.expired,
          last_refresh: $account.credentials.last_refresh,
          account_id: $account.credentials.account_id,
          chatgpt_user_id: $account.credentials.chatgpt_user_id
        },
        usage: ($usage[0].data // null),
        usage_error: null,
        account_updated_at: $account.updated_at
      }
    '
    return 0
  fi

  jq -cn \
    --argjson account "${account_json}" \
    --arg usage_error "${error_message}" '
    {
      id: $account.id,
      name: $account.name,
      platform: $account.platform,
      type: $account.type,
      status: $account.status,
      schedulable: $account.schedulable,
      priority: $account.priority,
      rate_multiplier: $account.rate_multiplier,
      notes: $account.notes,
      error_message: $account.error_message,
      last_used_at: $account.last_used_at,
      group_ids: ($account.group_ids // []),
      group_names: (($account.groups // []) | map(.name)),
      credentials: {
        email: $account.credentials.email,
        disabled: $account.credentials.disabled,
        plan_type: $account.credentials.plan_type,
        priority: $account.credentials.priority,
        type: $account.credentials.type,
        expires_at: $account.credentials.expires_at,
        expired: $account.credentials.expired,
        last_refresh: $account.credentials.last_refresh,
        account_id: $account.credentials.account_id,
        chatgpt_user_id: $account.credentials.chatgpt_user_id
      },
      usage: null,
      usage_error: $usage_error,
      account_updated_at: $account.updated_at
    }
  '
}

fetch_all_key_usage() {
  local api_key_id="$1"
  local output_file="$2"
  local tmp_dir combined_items_file page page_file current_page_items_file pages has_more max_pages page_count
  local -a page_item_files=()
  tmp_dir="$(mktemp -d)"
  combined_items_file="${tmp_dir}/usage-items.json"
  page=1
  max_pages=100
  page_file="${tmp_dir}/usage-page-1.json"
  current_page_items_file="${tmp_dir}/usage-page-1-items.json"
  request_json "$(build_key_usage_url_for_id "${api_key_id}" 1)" "${page_file}" "key_usage_internal"
  jq -c '{
    pages: (.data.pages // .pages // null),
    total: (.data.total // .total // null),
    has_more: (.data.has_more // .has_more // false),
    items: (.data.items // .data.usages // .data.list // .items // .usages // [])
  }' "${page_file}" > "${current_page_items_file}"
  page_item_files+=("${current_page_items_file}")

  pages="$(jq -r '.pages // empty' "${current_page_items_file}")"
  has_more="$(jq -r '.has_more // false' "${current_page_items_file}")"
  page_count=1

  if [[ -n "${pages}" && "${pages}" =~ ^[0-9]+$ && "${pages}" -gt 1 ]]; then
    page=2
    while [[ "${page}" -le "${pages}" ]]; do
      page_file="${tmp_dir}/usage-page-${page}.json"
      current_page_items_file="${tmp_dir}/usage-page-${page}-items.json"
      page_item_files+=("${current_page_items_file}")
      (
        if request_json "$(build_key_usage_url_for_id "${api_key_id}" "${page}")" "${page_file}" "key_usage_internal"; then
          jq -c '{
            pages: (.data.pages // .pages // null),
            total: (.data.total // .total // null),
            has_more: (.data.has_more // .has_more // false),
            items: (.data.items // .data.usages // .data.list // .items // .usages // [])
          }' "${page_file}" > "${current_page_items_file}"
        else
          printf '{"pages":null,"total":null,"has_more":false,"items":[]}\n' > "${current_page_items_file}"
        fi
      ) &
      wait_for_parallel_slot "${PARALLELISM}"
      page=$((page + 1))
    done
    wait_for_parallel_jobs
    page_count="${pages}"
  elif [[ "${has_more}" == "true" ]]; then
    page=2
    while [[ "${page}" -le "${max_pages}" ]]; do
      page_file="${tmp_dir}/usage-page-${page}.json"
      current_page_items_file="${tmp_dir}/usage-page-${page}-items.json"
      request_json "$(build_key_usage_url_for_id "${api_key_id}" "${page}")" "${page_file}" "key_usage_internal"
      jq -c '{
        pages: (.data.pages // .pages // null),
        total: (.data.total // .total // null),
        has_more: (.data.has_more // .has_more // false),
        items: (.data.items // .data.usages // .data.list // .items // .usages // [])
      }' "${page_file}" > "${current_page_items_file}"
      page_item_files+=("${current_page_items_file}")
      page_count="${page}"
      has_more="$(jq -r '.has_more // false' "${current_page_items_file}")"
      [[ "${has_more}" == "true" ]] || break
      page=$((page + 1))
    done
  fi

  jq -s --argjson page_count "${page_count}" '
    {
      pages: (.[0].pages // null),
      total: (.[0].total // null),
      pages_fetched: $page_count,
      items: (map(.items // []) | add // [])
    }
  ' "${page_item_files[@]}" > "${combined_items_file}"

  cp "${combined_items_file}" "${output_file}"
  rm -rf "${tmp_dir}"
}

build_key_item() {
  local key_json="$1"
  local usage_file="$2"
  local usage_error="${3:-}"
  if [[ -n "${usage_file}" && -f "${usage_file}" ]]; then
    jq -cn \
      --argjson key "${key_json}" \
      --arg today_date "${TODAY_DATE}" \
      --slurpfile usage "${usage_file}" '
      def mask_secret($value):
        if $value == null then null
        else ($value | tostring) as $s
        | if ($s | length) <= 12 then $s
          else "\($s[0:6])...\($s[-4:])"
          end
        end;
      def usage_items:
        ($usage[0].items // []) | map({
          account_name: (.account.name // .account_name // .accountName // .account.email // .account_id // null),
          input_tokens: (.input_tokens // .prompt_tokens // .usage.input_tokens // .usage.prompt_tokens // 0),
          output_tokens: (.output_tokens // .completion_tokens // .usage.output_tokens // .usage.completion_tokens // 0),
          model: (.model // .model_name // .request_model // null),
          ip_address: (.ip_address // .ip // .client_ip // .remote_addr // null),
          created_at: (.created_at // null)
        });
      usage_items as $items |
      {
        id: $key.id,
        name: ($key.name // $key.label // $key.title // null),
        key_preview: mask_secret($key.key // $key.token // $key.value // $key.prefix // $key.key_preview // $key.preview // null),
        status: ($key.status // (if $key.disabled == true then "disabled" elif $key.enabled == false then "disabled" else "active" end)),
        enabled: ($key.enabled // (if $key.disabled == true then false else null end)),
        created_at: ($key.created_at // null),
        updated_at: ($key.updated_at // null),
        expires_at: ($key.expires_at // null),
        last_used_at: ($key.last_used_at // null),
        usage_error: null,
        usage: {
          date: $today_date,
          request_count: ($items | length),
          input_tokens: ([$items[].input_tokens | numbers] | add // 0),
          output_tokens: ([$items[].output_tokens | numbers] | add // 0),
          account_names: ([$items[].account_name | select(. != null and . != "")] | unique),
          models: ([$items[].model | select(. != null and . != "")] | unique),
          ip_addresses: ([$items[].ip_address | select(. != null and . != "")] | unique),
          records: $items
        }
      }
    '
    return 0
  fi

  jq -cn \
    --argjson key "${key_json}" \
    --arg usage_error "${usage_error}" \
    --arg today_date "${TODAY_DATE}" '
    def mask_secret($value):
      if $value == null then null
      else ($value | tostring) as $s
      | if ($s | length) <= 12 then $s
        else "\($s[0:6])...\($s[-4:])"
        end
      end;
    {
      id: $key.id,
      name: ($key.name // $key.label // $key.title // null),
      key_preview: mask_secret($key.key // $key.token // $key.value // $key.prefix // $key.key_preview // $key.preview // null),
      status: ($key.status // (if $key.disabled == true then "disabled" elif $key.enabled == false then "disabled" else "active" end)),
      enabled: ($key.enabled // (if $key.disabled == true then false else null end)),
      created_at: ($key.created_at // null),
      updated_at: ($key.updated_at // null),
      expires_at: ($key.expires_at // null),
      last_used_at: ($key.last_used_at // null),
      usage_error: $usage_error,
      usage: {
        date: $today_date,
        request_count: 0,
        input_tokens: 0,
        output_tokens: 0,
        account_names: [],
        models: [],
        ip_addresses: [],
        records: []
      }
    }
  '
}

render_usage_markdown() {
  local json_file="$1"
  local report_file="$2"
  local updated_at five_remaining five_reset week_remaining week_reset
  updated_at="$(jq -r '.data.updated_at // "-"' "${json_file}")"
  five_remaining="$(jq -r '.data.five_hour.utilization // "-"' "${json_file}")"
  five_reset="$(jq -r '.data.five_hour.resets_at // "-"' "${json_file}")"
  week_remaining="$(jq -r '.data.seven_day.utilization // "-"' "${json_file}")"
  week_reset="$(jq -r '.data.seven_day.resets_at // "-"' "${json_file}")"

  jq -r --arg updated_at "$(format_display_time "${updated_at}")" \
    --arg five_remaining "$(format_remaining_quota "${five_remaining}")" \
    --arg five_reset "$(format_display_time "${five_reset}")" \
    --arg week_remaining "$(format_remaining_quota "${week_remaining}")" \
    --arg week_reset "$(format_display_time "${week_reset}")" '
    [
      "# Sub2API 单账号 Usage",
      "",
      "| 字段 | 值 |",
      "| --- | --- |",
      "| 生成时间 | \(.generated_at // "-") |",
      "| 账号 ID | \(.data.account_id // "-") |",
      "| 更新时间 | \($updated_at) |",
      "| 5h 剩余额度 | \($five_remaining) |",
      "| 5h 重置时间 | \($five_reset) |",
      "| 周剩余额度 | \($week_remaining) |",
      "| 周重置时间 | \($week_reset) |"
    ] | .[]
  ' "${json_file}" > "${report_file}"
}

render_schedulable_markdown() {
  local json_file="$1"
  local report_file="$2"
  local updated_at rate_limited_at rate_limit_reset_at overload_until temp_unschedulable_until session_window_start session_window_end
  updated_at="$(jq -r '.data.updated_at // "-"' "${json_file}")"
  rate_limited_at="$(jq -r '.data.rate_limited_at // "-"' "${json_file}")"
  rate_limit_reset_at="$(jq -r '.data.rate_limit_reset_at // "-"' "${json_file}")"
  overload_until="$(jq -r '.data.overload_until // "-"' "${json_file}")"
  temp_unschedulable_until="$(jq -r '.data.temp_unschedulable_until // "-"' "${json_file}")"
  session_window_start="$(jq -r '.data.session_window_start // "-"' "${json_file}")"
  session_window_end="$(jq -r '.data.session_window_end // "-"' "${json_file}")"

  jq -r \
    --arg updated_at "$(format_display_time "${updated_at}")" \
    --arg rate_limited_at "$(format_display_time "${rate_limited_at}")" \
    --arg rate_limit_reset_at "$(format_display_time "${rate_limit_reset_at}")" \
    --arg overload_until "$(format_display_time "${overload_until}")" \
    --arg temp_unschedulable_until "$(format_display_time "${temp_unschedulable_until}")" \
    --arg session_window_start "$(format_display_time "${session_window_start}")" \
    --arg session_window_end "$(format_display_time "${session_window_end}")" '
    [
      "# Sub2API 账号调度状态更新",
      "",
      "| 字段 | 值 |",
      "| --- | --- |",
      "| 生成时间 | \(.generated_at // "-") |",
      "| 账号 ID | \(.data.account_id // "-") |",
      "| 账号 | \(.data.name // "-") |",
      "| 请求调度状态 | \(if .data.requested_schedulable == null then "-" else (.data.requested_schedulable | tostring) end) |",
      "| 当前调度状态 | \(if .data.current_schedulable == null then "-" else (.data.current_schedulable | tostring) end) |",
      "| 账号状态 | \(.data.status // "-") |",
      "| 凭证禁用 | \(if .data.credentials_disabled == null then "-" else (.data.credentials_disabled | tostring) end) |",
      "| 优先级 | \(.data.priority // "-") |",
      "| 错误信息 | \(.data.error_message // "-") |",
      "| 更新时间 | \($updated_at) |",
      "| 限流开始 | \($rate_limited_at) |",
      "| 限流恢复 | \($rate_limit_reset_at) |",
      "| 过载截止 | \($overload_until) |",
      "| 临时不可调度截止 | \($temp_unschedulable_until) |",
      "| 临时不可调度原因 | \(if ((.data.temp_unschedulable_reason // "") | length) == 0 then "-" else .data.temp_unschedulable_reason end) |",
      "| 会话窗口开始 | \($session_window_start) |",
      "| 会话窗口结束 | \($session_window_end) |",
      "| 会话窗口状态 | \(if ((.data.session_window_status // "") | length) == 0 then "-" else .data.session_window_status end) |"
    ] | .[]
  ' "${json_file}" > "${report_file}"
}

render_delete_markdown() {
  local json_file="$1"
  local report_file="$2"
  local updated_at
  updated_at="$(jq -r '.data.updated_at // "-"' "${json_file}")"

  jq -r --arg updated_at "$(format_display_time "${updated_at}")" '
    [
      "# Sub2API 账号删除结果",
      "",
      "| 字段 | 值 |",
      "| --- | --- |",
      "| 生成时间 | \(.generated_at // "-") |",
      "| 账号 ID | \(.data.account_id // "-") |",
      "| 删除结果 | \(.data.deleted // "-") |",
      "| 账号 | \(.data.name // "-") |",
      "| 状态 | \(.data.status // "-") |",
      "| 错误信息 | \(.data.error_message // "-") |",
      "| 更新时间 | \($updated_at) |"
    ] | .[]
  ' "${json_file}" > "${report_file}"
}

render_bulk_update_markdown() {
  local json_file="$1"
  local report_file="$2"
  jq -r '
    [
      "# Sub2API 批量优先级更新结果",
      "",
      "| 字段 | 值 |",
      "| --- | --- |",
      "| 生成时间 | \(.generated_at // "-") |",
      "| 账号 ID 列表 | \((.data.account_ids // []) | join(", ")) |",
      "| 请求优先级 | \(.data.requested_priority // "-") |",
      "| 更新数量 | \(.data.updated_count // "-") |",
      "| 返回消息 | \(.message // "-") |"
    ] | .[]
  ' "${json_file}" > "${report_file}"
}

render_keys_markdown() {
  local json_file="$1"
  local report_file="$2"
  local input_tokens output_tokens
  input_tokens="$(jq -r '.data.summary.input_tokens // 0' "${json_file}")"
  output_tokens="$(jq -r '.data.summary.output_tokens // 0' "${json_file}")"
  {
    jq -r \
      --arg input_tokens_m "$(format_tokens_m "${input_tokens}")" \
      --arg output_tokens_m "$(format_tokens_m "${output_tokens}")" '
      [
        "# Sub2API 令牌汇总",
        "",
        "| 指标 | 值 |",
        "| --- | ---: |",
        "| 生成时间 | \(.generated_at // "-") |",
        "| 日期 | \(.data.date // "-") |",
        "| 页数 | \(.data.pages // "-") |",
        "| 每页条数 | \(.data.page_size // "-") |",
        "| 令牌总数 | \(.data.total // "-") |",
        "| 今日请求数 | \(.data.summary.request_count // 0) |",
        "| 输入 tokens | \(.data.summary.input_tokens // 0)（\($input_tokens_m)） |",
        "| 输出 tokens | \(.data.summary.output_tokens // 0)（\($output_tokens_m)） |",
        ""
      ] | .[]
    ' "${json_file}"

    printf '## 令牌列表\n\n'
    printf '| ID | 名称 | 令牌 | 状态 | 创建时间 | 最近使用时间 | 今日请求 | 账号 | 模型 | IP | 输入tokens(M) | 输出tokens(M) |\n'
    printf '| --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | ---: | ---: |\n'
    if [[ "$(jq -r '.data.items | length' "${json_file}")" -eq 0 ]]; then
      printf '| - | - | - | - | - | - | - | - | - | - | - | - |\n'
    else
      jq -r '
        .data.items[] |
        [
          (.id | tostring),
          (.name // "-"),
          (.key_preview // "-"),
          (.status // "-"),
          (.created_at // "-"),
          (.last_used_at // "-"),
          (.usage.request_count // 0 | tostring),
          ((.usage.account_names // []) | if length == 0 then "-" else join(", ") end),
          ((.usage.models // []) | if length == 0 then "-" else join(", ") end),
          ((.usage.ip_addresses // []) | if length == 0 then "-" else join(", ") end),
          (.usage.input_tokens // 0 | tostring),
          (.usage.output_tokens // 0 | tostring)
        ] | @tsv
      ' "${json_file}" | while IFS=$'\t' read -r id name key_preview status created_at last_used_at request_count accounts models ips input output; do
        printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
          "${id}" \
          "${name}" \
          "${key_preview}" \
          "${status}" \
          "$(format_display_time "${created_at}")" \
          "$(format_display_time "${last_used_at}")" \
          "${request_count}" \
          "${accounts:-"-"}" \
          "${models:-"-"}" \
          "${ips:-"-"}" \
          "$(format_tokens_m "${input}")" \
          "$(format_tokens_m "${output}")"
      done
    fi
  } > "${report_file}"
}

render_accounts_markdown() {
  local json_file="$1"
  local report_file="$2"
  local normal_count abnormal_count normal_five_tokens normal_week_tokens abnormal_five_tokens abnormal_week_tokens
  normal_count="$(jq -r '.data.summary["正常账号数"] // 0' "${json_file}")"
  abnormal_count="$(jq -r '.data.summary["异常账号数"] // 0' "${json_file}")"
  normal_five_tokens="$(jq -r '.data.summary["正常账号汇总"]["5h_tokens_sum"] // 0' "${json_file}")"
  normal_week_tokens="$(jq -r '.data.summary["正常账号汇总"]["周_tokens_sum"] // 0' "${json_file}")"
  abnormal_five_tokens="$(jq -r '.data.summary["异常账号汇总"]["5h_tokens_sum"] // 0' "${json_file}")"
  abnormal_week_tokens="$(jq -r '.data.summary["异常账号汇总"]["周_tokens_sum"] // 0' "${json_file}")"
  {
    jq -r '
      [
        "# Sub2API 账号汇总",
        "",
        "| 指标 | 值 |",
        "| --- | ---: |",
        "| 生成时间 | \(.generated_at // "-") |",
        "| 页数 | \(.data.pages // "-") |",
        "| 每页条数 | \(.data.page_size // "-") |",
        "| 账号总数 | \(.data.total // "-") |",
        "| 正常账号 | \(.data.summary["正常账号数"] // 0) |",
        "| 异常账号 | \(.data.summary["异常账号数"] // 0) |",
        "| 5h 限额汇总 | \(.data.summary["5h限额汇总"].remaining_sum // 0) |",
        "| 周限额汇总 | \(.data.summary["周限额汇总"].remaining_sum // 0) |",
        ""
      ] | .[]
    ' "${json_file}"

    printf '## 正常账号（%s个 | 5h tokens %s | 周 tokens %s）\n\n' \
      "${normal_count}" \
      "$(format_tokens_m "${normal_five_tokens}")" \
      "$(format_tokens_m "${normal_week_tokens}")"
    printf '| ID | 账号 | 套餐 | 优先级 | 过期时间 | 最近使用时间 | 5h限额 | 周限额 | 5h消耗 | 周消耗 | 5h刷新时间 | 周刷新时间 |\n'
    printf '| --- | --- | --- | ---: | --- | --- | ---: | ---: | ---: | ---: | --- | --- |\n'
    if [[ "$(jq -r '.data.summary["正常账号"] | length' "${json_file}")" -eq 0 ]]; then
      printf '| - | - | - | - | - | - | - | - | - | - | - | - |\n'
    else
      jq -r '
        def priority_key:
          ((.["优先级"] // 999999) | tonumber? // 999999);
        def last_used_key:
          if (.["最近使用时间"] == null or .["最近使用时间"] == "-") then "" else (.["最近使用时间"] | tostring) end;
        .data.summary["正常账号"]
        | sort_by([priority_key, last_used_key])
        | group_by(priority_key)
        | map(reverse)
        | add // []
        | .[] |
        [
          (.id | tostring),
          .name,
          (.["套餐"] // "-"),
          (.["优先级"] // "-"),
          (.["过期时间"] // "-"),
          (.["最近使用时间"] // "-"),
          (.["5h限额"].utilization | tostring),
          (.["周限额"].utilization | tostring),
          (.["5h限额"].tokens | tostring),
          (.["周限额"].tokens | tostring),
          (.["5h限额"].resets_at // "-"),
          (.["周限额"].resets_at // "-")
        ] | @tsv
      ' "${json_file}" | while IFS=$'\t' read -r id name plan priority expires_at last_used_at five week five_tokens week_tokens five_reset week_reset; do
        printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
          "${id}" \
          "${name}" \
          "${plan}" \
          "${priority}" \
          "$(format_display_time "${expires_at}")" \
          "$(format_display_time "${last_used_at}")" \
          "$(format_remaining_quota "${five}")" \
          "$(format_remaining_quota "${week}")" \
          "$(format_tokens_m "${five_tokens}")" \
          "$(format_tokens_m "${week_tokens}")" \
          "$(format_display_time "${five_reset}")" \
          "$(format_display_time "${week_reset}")"
      done
    fi

    printf '\n## 异常账号（%s个 | 5h tokens %s | 周 tokens %s）\n\n' \
      "${abnormal_count}" \
      "$(format_tokens_m "${abnormal_five_tokens}")" \
      "$(format_tokens_m "${abnormal_week_tokens}")"
    printf '| ID | 账号 | 套餐 | 优先级 | 过期时间 | 最近使用时间 | 账号状态 | 调度状态 | 5h限额 | 周限额 | 5h消耗 | 周消耗 | 异常原因 |\n'
    printf '| --- | --- | --- | ---: | --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- |\n'
    if [[ "$(jq -r '.data.summary["异常账号"] | length' "${json_file}")" -eq 0 ]]; then
      printf '| - | - | - | - | - | - | - | - | - | - | - | - | - |\n'
    else
      jq -r '
        .data.summary["异常账号"][] |
        [
          (.id | tostring),
          .name,
          (.["套餐"] // "-"),
          (.["优先级"] // "-"),
          (.["过期时间"] // "-"),
          (.["最近使用时间"] // "-"),
          (.["账号状态"] // "-"),
          (.["调度状态"] // "-"),
          (.["5h限额"].utilization | tostring),
          (.["周限额"].utilization | tostring),
          (.["5h限额"].tokens | tostring),
          (.["周限额"].tokens | tostring),
          ((.["异常原因"] // []) | join("; "))
        ] | @tsv
      ' "${json_file}" | while IFS=$'\t' read -r id name plan priority expires_at last_used_at status sched five week five_tokens week_tokens reason; do
        printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
          "${id}" \
          "${name}" \
          "${plan}" \
          "${priority}" \
          "$(format_display_time "${expires_at}")" \
          "$(format_display_time "${last_used_at}")" \
          "${status}" \
          "${sched}" \
          "$(format_remaining_quota "${five}")" \
          "$(format_remaining_quota "${week}")" \
          "$(format_tokens_m "${five_tokens}")" \
          "$(format_tokens_m "${week_tokens}")" \
          "${reason}"
      done
    fi
  } > "${report_file}"
}

normalize_accounts_with_usage() {
  local accounts_items_file="$1"
  local output_file="$2"
  local total pages tmp_dir items_file item_ids_file id account_json usage_raw usage_normalized failed_count item_file status_file
  tmp_dir="$(mktemp -d)"
  items_file="${tmp_dir}/items.ndjson"
  item_ids_file="${tmp_dir}/account_ids.txt"
  failed_count=0
  : > "${items_file}"
  trap 'rm -rf "${tmp_dir}"' RETURN

  total="$(jq -r '.total // 0' "${accounts_items_file}")"
  pages="$(jq -r '.pages // 0' "${accounts_items_file}")"
  jq -r '.items[]?.id' "${accounts_items_file}" > "${item_ids_file}"

  while IFS= read -r id; do
    [[ -n "${id}" ]] || continue
    account_json="$(jq -c --argjson account_id "${id}" '.items[] | select(.id == $account_id)' "${accounts_items_file}")"
    usage_raw="${tmp_dir}/usage-${id}-raw.json"
    usage_normalized="${tmp_dir}/usage-${id}.json"
    item_file="${tmp_dir}/item-${id}.json"
    status_file="${tmp_dir}/status-${id}"
    (
      if request_json "$(build_usage_url_for_id "${id}")" "${usage_raw}" "usage_internal" "${id}" \
        && normalize_usage_file "${usage_raw}" "${usage_normalized}" "${id}"; then
        build_account_item "${account_json}" "${usage_normalized}" > "${item_file}"
        printf '0\n' > "${status_file}"
      else
        build_account_item "${account_json}" "" "usage_request_failed" > "${item_file}"
        printf '1\n' > "${status_file}"
      fi
    ) &
    wait_for_parallel_slot "${PARALLELISM}"
  done < "${item_ids_file}"
  wait_for_parallel_jobs

  while IFS= read -r id; do
    [[ -n "${id}" ]] || continue
    item_file="${tmp_dir}/item-${id}.json"
    status_file="${tmp_dir}/status-${id}"
    [[ -f "${item_file}" ]] && cat "${item_file}" >> "${items_file}"
    if [[ "$(cat "${status_file}" 2>/dev/null || printf '1')" != "0" ]]; then
      failed_count=$((failed_count + 1))
    fi
  done < "${item_ids_file}"

  jq -s \
    --argjson total "${total}" \
    --argjson pages "${pages}" \
    --argjson page_size "${DEFAULT_ACCOUNTS_PAGE_SIZE}" \
    --argjson usage_failed "${failed_count}" \
    --arg generated_at "${GENERATED_AT}" '
    def raw_usage_5h:
      .usage.five_hour.utilization // null;
    def raw_usage_7d:
      .usage.seven_day.utilization // null;
    def raw_5h_tokens:
      .usage.five_hour.window_stats.tokens // null;
    def raw_7d_tokens:
      .usage.seven_day.window_stats.tokens // null;
    def remaining_quota($value):
      if $value == null then null else 100 - $value end;
    def usable_5h_remaining:
      if raw_usage_5h == null then null
      elif raw_usage_7d == null then remaining_quota(raw_usage_5h)
      elif remaining_quota(raw_usage_7d) > 0 then remaining_quota(raw_usage_5h)
      else null
      end;
    def abnormal_reason_candidates:
      [
        if .usage_error != null then "usage 拉取失败: \(.usage_error)" else empty end,
        if ((.error_message // "") != "") then "error_message: \(.error_message)" else empty end,
        if ((.status // "") != "active") then "status=\(.status // "unknown")" else empty end,
        if (.usage.five_hour.resets_at // null) == null then "five_hour.resets_at=null" else empty end,
        if (.usage.seven_day.resets_at // null) == null then "seven_day.resets_at=null" else empty end,
        if .credentials.disabled == true then "credentials.disabled=true" else empty end
      ];
    def abnormal_reasons:
      (abnormal_reason_candidates) as $reasons
      | if ($reasons | length) == 1 and ($reasons[0] == "credentials.disabled=true") then [] else $reasons end;
    def summary_item:
      {
        id,
        name,
        "平台": .platform,
        "类型": .type,
        "账号状态": .status,
        "调度状态": (if .schedulable == true then "可调度" else "不可调度" end),
        "套餐": (.credentials.plan_type // null),
        "优先级": (.priority // .credentials.priority // null),
        "过期时间": (.credentials.expires_at // null),
        "最近使用时间": (.last_used_at // null),
        "限额状态": .summary_status,
        "异常原因": .summary_reasons,
        "5h限额": {
          utilization: raw_usage_5h,
          remaining: remaining_quota(raw_usage_5h),
          resets_at: (.usage.five_hour.resets_at // null),
          tokens: raw_5h_tokens
        },
        "周限额": {
          utilization: raw_usage_7d,
          remaining: remaining_quota(raw_usage_7d),
          resets_at: (.usage.seven_day.resets_at // null),
          tokens: raw_7d_tokens
        },
        usage_updated_at: (.usage.updated_at // null)
      };
    (map(. + {
      summary_reasons: abnormal_reasons,
      summary_status: (if (abnormal_reasons | length) > 0 then "异常" else "正常" end)
    })) as $items |
    {
      code: 0,
      message: "success",
      generated_at: $generated_at,
      data: {
        pages: $pages,
        page_size: $page_size,
        count: ($items | length),
        total: $total,
        usage_failed: $usage_failed,
        summary: (
          ([$items[] | select(.summary_status == "正常")]) as $normal_items |
          ([$items[] | select(.summary_status == "异常")]) as $abnormal_items |
          {
          "5h限额汇总": {
            account_count: ($normal_items | length),
            known_count: ([$normal_items[] | select(raw_usage_5h != null)] | length),
            utilization_sum: ([$normal_items[] | raw_usage_5h | numbers] | add // 0),
            remaining_sum: ([$normal_items[] | usable_5h_remaining | numbers] | add // 0)
          },
          "周限额汇总": {
            account_count: ($normal_items | length),
            known_count: ([$normal_items[] | select(raw_usage_7d != null)] | length),
            utilization_sum: ([$normal_items[] | raw_usage_7d | numbers] | add // 0),
            remaining_sum: ([$normal_items[] | remaining_quota(raw_usage_7d) | numbers] | add // 0)
          },
          "正常账号数": ($normal_items | length),
          "异常账号数": ($abnormal_items | length),
          "正常账号汇总": {
            account_count: ($normal_items | length),
            "5h_tokens_sum": ([$normal_items[] | raw_5h_tokens | numbers] | add // 0),
            "周_tokens_sum": ([$normal_items[] | raw_7d_tokens | numbers] | add // 0)
          },
          "异常账号汇总": {
            account_count: ($abnormal_items | length),
            "5h_tokens_sum": ([$abnormal_items[] | raw_5h_tokens | numbers] | add // 0),
            "周_tokens_sum": ([$abnormal_items[] | raw_7d_tokens | numbers] | add // 0)
          },
          "账号限额列表": ($items | map(summary_item)),
          "正常账号": ($normal_items | map(summary_item)),
          "异常账号": ($abnormal_items | map(summary_item))
        }),
        items: $items
      }
    }
  ' "${items_file}" > "${output_file}"

  rm -rf "${tmp_dir}"
  trap - RETURN
}

normalize_keys_with_usage() {
  local keys_items_file="$1"
  local output_file="$2"
  local total pages tmp_dir items_file item_ids_file id key_json usage_items failed_count item_file status_file
  tmp_dir="$(mktemp -d)"
  items_file="${tmp_dir}/keys.ndjson"
  item_ids_file="${tmp_dir}/key_ids.txt"
  failed_count=0
  : > "${items_file}"
  trap 'rm -rf "${tmp_dir}"' RETURN

  total="$(jq -r '.total // 0' "${keys_items_file}")"
  pages="$(jq -r '.pages // 0' "${keys_items_file}")"
  jq -r '.items[]?.id // empty' "${keys_items_file}" > "${item_ids_file}"

  while IFS= read -r id; do
    [[ -n "${id}" ]] || continue
    key_json="$(jq -c --argjson key_id "${id}" '.items[] | select(.id == $key_id)' "${keys_items_file}")"
    usage_items="${tmp_dir}/key-${id}-usage.json"
    item_file="${tmp_dir}/key-${id}.json"
    status_file="${tmp_dir}/key-status-${id}"
    (
      if fetch_all_key_usage "${id}" "${usage_items}"; then
        build_key_item "${key_json}" "${usage_items}" > "${item_file}"
        printf '0\n' > "${status_file}"
      else
        build_key_item "${key_json}" "" "usage_request_failed" > "${item_file}"
        printf '1\n' > "${status_file}"
      fi
    ) &
    wait_for_parallel_slot "${PARALLELISM}"
  done < "${item_ids_file}"
  wait_for_parallel_jobs

  while IFS= read -r id; do
    [[ -n "${id}" ]] || continue
    item_file="${tmp_dir}/key-${id}.json"
    status_file="${tmp_dir}/key-status-${id}"
    [[ -f "${item_file}" ]] && cat "${item_file}" >> "${items_file}"
    if [[ "$(cat "${status_file}" 2>/dev/null || printf '1')" != "0" ]]; then
      failed_count=$((failed_count + 1))
    fi
  done < "${item_ids_file}"

  jq -s \
    --argjson total "${total}" \
    --argjson pages "${pages}" \
    --argjson page_size "${DEFAULT_KEYS_PAGE_SIZE}" \
    --argjson usage_failed "${failed_count}" \
    --arg generated_at "${GENERATED_AT}" \
    --arg today_date "${TODAY_DATE}" '
    {
      code: 0,
      message: "success",
      generated_at: $generated_at,
      data: {
        date: $today_date,
        pages: $pages,
        page_size: $page_size,
        count: (length),
        total: $total,
        usage_failed: $usage_failed,
        summary: {
          request_count: ([.[].usage.request_count | numbers] | add // 0),
          input_tokens: ([.[].usage.input_tokens | numbers] | add // 0),
          output_tokens: ([.[].usage.output_tokens | numbers] | add // 0)
        },
        items: .
      }
    }
  ' "${items_file}" > "${output_file}"

  rm -rf "${tmp_dir}"
  trap - RETURN
}

fetch_all_keys() {
  local output_file="$1"
  local tmp_dir pages total first_page_file combined_items_file page current_page_items_file page_file
  tmp_dir="$(mktemp -d)"
  first_page_file="${tmp_dir}/keys-page-1.json"
  combined_items_file="${tmp_dir}/keys-items.json"
  trap 'rm -rf "${tmp_dir}"' RETURN

  request_json "$(build_keys_url 1)" "${first_page_file}" "keys_internal"
  pages="$(jq -r '.data.pages // .pages // 1' "${first_page_file}")"
  total="$(jq -r '.data.total // .total // 0' "${first_page_file}")"
  jq -c '{
    total: (.data.total // .total // 0),
    pages: (.data.pages // .pages // 1),
    items: (.data.items // .data.keys // .data.list // .items // .keys // [])
  }' "${first_page_file}" > "${combined_items_file}"

  page=2
  while [[ "${page}" -le "${pages}" ]]; do
    page_file="${tmp_dir}/keys-page-${page}.json"
    current_page_items_file="${tmp_dir}/keys-page-${page}-items.json"
    request_json "$(build_keys_url "${page}")" "${page_file}" "keys_internal"
    jq -c '{items: (.data.items // .data.keys // .data.list // .items // .keys // [])}' "${page_file}" > "${current_page_items_file}"
    jq -s '
      {
        total: (.[0].total // 0),
        pages: (.[0].pages // 1),
        items: ((.[0].items // []) + (.[1].items // []))
      }
    ' "${combined_items_file}" "${current_page_items_file}" > "${combined_items_file}.tmp"
    mv "${combined_items_file}.tmp" "${combined_items_file}"
    page=$((page + 1))
  done

  jq --argjson total "${total}" --argjson pages "${pages}" '
    .total = $total | .pages = $pages
  ' "${combined_items_file}" > "${combined_items_file}.final"
  mv "${combined_items_file}.final" "${combined_items_file}"
  normalize_keys_with_usage "${combined_items_file}" "${output_file}"
  rm -rf "${tmp_dir}"
  trap - RETURN
}

fetch_all_accounts() {
  local output_file="$1"
  local tmp_dir pages total first_page_file combined_items_file page_file page current_page_items_file
  tmp_dir="$(mktemp -d)"
  first_page_file="${tmp_dir}/page-1.json"
  combined_items_file="${tmp_dir}/accounts-items.json"
  trap 'rm -rf "${tmp_dir}"' RETURN

  request_json "$(build_accounts_url 1)" "${first_page_file}" "accounts_internal"
  pages="$(jq -r '.data.pages // .pages // 1' "${first_page_file}")"
  total="$(jq -r '.data.total // .total // 0' "${first_page_file}")"
  jq -c '{
    total: (.data.total // .total // 0),
    pages: (.data.pages // .pages // 1),
    items: (.data.items // .data.accounts // .data.list // .items // .accounts // [])
  }' "${first_page_file}" > "${combined_items_file}"

  page=2
  while [[ "${page}" -le "${pages}" ]]; do
    page_file="${tmp_dir}/page-${page}.json"
    current_page_items_file="${tmp_dir}/page-${page}-items.json"
    request_json "$(build_accounts_url "${page}")" "${page_file}" "accounts_internal"
    jq -c '{items: (.data.items // .data.accounts // .data.list // .items // .accounts // [])}' "${page_file}" > "${current_page_items_file}"
    jq -s '
      {
        total: (.[0].total // 0),
        pages: (.[0].pages // 1),
        items: ((.[0].items // []) + (.[1].items // []))
      }
    ' "${combined_items_file}" "${current_page_items_file}" > "${combined_items_file}.tmp"
    mv "${combined_items_file}.tmp" "${combined_items_file}"
    page=$((page + 1))
  done

  jq --argjson total "${total}" --argjson pages "${pages}" '
    .total = $total | .pages = $pages
  ' "${combined_items_file}" > "${combined_items_file}.final"
  mv "${combined_items_file}.final" "${combined_items_file}"
  normalize_accounts_with_usage "${combined_items_file}" "${output_file}"
  rm -rf "${tmp_dir}"
  trap - RETURN
}

build_referer_url() {
  local action_name="${1:-${ACTION}}"
  local account_id="${2:-${ACCOUNT_ID}}"
  if [[ "${action_name}" == "usage" || "${action_name}" == "usage_internal" ]]; then
    printf '%s/admin/accounts/%s/usage' "$(api_base_url)" "${account_id}"
    return 0
  fi
  if [[ "${action_name}" == "keys" || "${action_name}" == "keys_internal" ]]; then
    printf '%s/keys' "$(api_base_url)"
    return 0
  fi
  if [[ "${action_name}" == "key_usage_internal" ]]; then
    printf '%s/admin/usage' "$(api_base_url)"
    return 0
  fi
  printf '%s/admin/accounts' "$(api_base_url)"
}

request_json() {
  local url="$1"
  local output_file="$2"
  local request_kind="${3:-${ACTION}}"
  local request_account_id="${4:-${ACCOUNT_ID}}"
  local tmp_headers tmp_body http_status content_type etag bytes
  tmp_headers="$(mktemp)"
  tmp_body="$(mktemp)"

  local -a curl_args=(
    -sS
    --max-time "${TIMEOUT}"
    -D "${tmp_headers}"
    -o "${tmp_body}"
    "${url}"
    -H "Accept: application/json, text/plain, */*"
    -H "Accept-Language: zh"
    -H "x-api-key: ${API_KEY}"
    -H "Referer: $(build_referer_url "${request_kind}" "${request_account_id}")"
    -H "User-Agent: ${BROWSER_USER_AGENT}"
  )
  curl_args+=(--insecure)

  need_cmd curl
  if ! curl "${curl_args[@]}"; then
    rm -f "${tmp_headers}" "${tmp_body}"
    return 1
  fi

  http_status="$(awk 'toupper($0) ~ /^HTTP\// {code=$2} END {print code}' "${tmp_headers}")"
  content_type="$(awk 'BEGIN{IGNORECASE=1} /^content-type:/ {sub(/^[^:]+:[[:space:]]*/, ""); print; exit}' "${tmp_headers}" | tr -d '\r')"
  etag="$(awk 'BEGIN{IGNORECASE=1} /^etag:/ {sub(/^[^:]+:[[:space:]]*/, ""); print; exit}' "${tmp_headers}" | tr -d '\r')"
  bytes="$(wc -c < "${tmp_body}" | tr -d ' ')"

  if [[ "${http_status}" == "304" ]]; then
    printf 'HTTP_STATUS=304\nmessage=not_modified\netag=%s\n' "${etag:-}"
    rm -f "${tmp_headers}" "${tmp_body}"
    return 0
  fi

  if [[ -z "${http_status}" || ! "${http_status}" =~ ^2 ]]; then
    printf '[%s] HTTP_STATUS=%s CONTENT_TYPE=%s BODY_BYTES=%s\n' "${SCRIPT_NAME}" "${http_status:-unknown}" "${content_type:-unknown}" "${bytes}" >&2
    if [[ "${bytes}" -gt 0 ]]; then
      head -c 800 "${tmp_body}" >&2
      printf '\n' >&2
    fi
    rm -f "${tmp_headers}" "${tmp_body}"
    return 1
  fi

  mkdir -p "$(dirname "${output_file}")"
  cp "${tmp_body}" "${output_file}"

  if [[ "${request_kind}" == "usage_internal" ]]; then
    rm -f "${tmp_headers}" "${tmp_body}"
    return 0
  fi
  if [[ "${request_kind}" == "accounts_internal" || "${request_kind}" == "keys_internal" || "${request_kind}" == "key_usage_internal" ]]; then
    rm -f "${tmp_headers}" "${tmp_body}"
    return 0
  fi

  if [[ "${ACTION}" == "raw" ]]; then
    cat "${tmp_body}"
    rm -f "${tmp_headers}" "${tmp_body}"
    return 0
  fi

  if [[ "${ACTION}" == "usage" ]]; then
    normalize_usage_file "${tmp_body}" "${output_file}" "${ACCOUNT_ID}"
  fi
  rm -f "${tmp_headers}" "${tmp_body}"
}

request_json_with_body() {
  local url="$1"
  local output_file="$2"
  local body_json="$3"
  local request_kind="${4:-${ACTION}}"
  local request_account_id="${5:-${ACCOUNT_ID}}"
  local tmp_headers tmp_body http_status content_type bytes
  tmp_headers="$(mktemp)"
  tmp_body="$(mktemp)"

  local -a curl_args=(
    -sS
    --max-time "${TIMEOUT}"
    -D "${tmp_headers}"
    -o "${tmp_body}"
    "${url}"
    -H "Accept: application/json, text/plain, */*"
    -H "Accept-Language: zh"
    -H "x-api-key: ${API_KEY}"
    -H "Content-Type: application/json"
    -H "Referer: $(build_referer_url "${request_kind}" "${request_account_id}")"
    -H "User-Agent: ${BROWSER_USER_AGENT}"
    --data-raw "${body_json}"
  )
  curl_args+=(--insecure)

  need_cmd curl
  if ! curl "${curl_args[@]}"; then
    rm -f "${tmp_headers}" "${tmp_body}"
    return 1
  fi

  http_status="$(awk 'toupper($0) ~ /^HTTP\// {code=$2} END {print code}' "${tmp_headers}")"
  content_type="$(awk 'BEGIN{IGNORECASE=1} /^content-type:/ {sub(/^[^:]+:[[:space:]]*/, ""); print; exit}' "${tmp_headers}" | tr -d '\r')"
  bytes="$(wc -c < "${tmp_body}" | tr -d ' ')"

  if [[ -z "${http_status}" || ! "${http_status}" =~ ^2 ]]; then
    printf '[%s] HTTP_STATUS=%s CONTENT_TYPE=%s BODY_BYTES=%s\n' "${SCRIPT_NAME}" "${http_status:-unknown}" "${content_type:-unknown}" "${bytes}" >&2
    if [[ "${bytes}" -gt 0 ]]; then
      head -c 800 "${tmp_body}" >&2
      printf '\n' >&2
    fi
    rm -f "${tmp_headers}" "${tmp_body}"
    return 1
  fi

  mkdir -p "$(dirname "${output_file}")"
  cp "${tmp_body}" "${output_file}"

  if [[ "${ACTION}" == "schedulable" || "${ACTION}" == "disable" || "${ACTION}" == "enable" ]]; then
    normalize_schedulable_file "${tmp_body}" "${output_file}" "${ACCOUNT_ID}" "${SCHEDULABLE_VALUE}"
  elif [[ "${ACTION}" == "bulk-update" ]]; then
    normalize_bulk_update_file "${tmp_body}" "${output_file}" "${ACCOUNT_IDS}" "${PRIORITY_VALUE}"
  fi

  rm -f "${tmp_headers}" "${tmp_body}"
}

request_json_with_method() {
  local url="$1"
  local output_file="$2"
  local method="$3"
  local request_kind="${4:-${ACTION}}"
  local request_account_id="${5:-${ACCOUNT_ID}}"
  local tmp_headers tmp_body http_status content_type bytes
  tmp_headers="$(mktemp)"
  tmp_body="$(mktemp)"

  local -a curl_args=(
    -sS
    --max-time "${TIMEOUT}"
    -X "${method}"
    -D "${tmp_headers}"
    -o "${tmp_body}"
    "${url}"
    -H "Accept: application/json, text/plain, */*"
    -H "Accept-Language: zh"
    -H "x-api-key: ${API_KEY}"
    -H "Referer: $(build_referer_url "${request_kind}" "${request_account_id}")"
    -H "User-Agent: ${BROWSER_USER_AGENT}"
  )
  curl_args+=(--insecure)

  need_cmd curl
  if ! curl "${curl_args[@]}"; then
    rm -f "${tmp_headers}" "${tmp_body}"
    return 1
  fi

  http_status="$(awk 'toupper($0) ~ /^HTTP\// {code=$2} END {print code}' "${tmp_headers}")"
  content_type="$(awk 'BEGIN{IGNORECASE=1} /^content-type:/ {sub(/^[^:]+:[[:space:]]*/, ""); print; exit}' "${tmp_headers}" | tr -d '\r')"
  bytes="$(wc -c < "${tmp_body}" | tr -d ' ')"

  if [[ -z "${http_status}" || ! "${http_status}" =~ ^2 ]]; then
    printf '[%s] HTTP_STATUS=%s CONTENT_TYPE=%s BODY_BYTES=%s\n' "${SCRIPT_NAME}" "${http_status:-unknown}" "${content_type:-unknown}" "${bytes}" >&2
    if [[ "${bytes}" -gt 0 ]]; then
      head -c 800 "${tmp_body}" >&2
      printf '\n' >&2
    fi
    rm -f "${tmp_headers}" "${tmp_body}"
    return 1
  fi

  mkdir -p "$(dirname "${output_file}")"
  cp "${tmp_body}" "${output_file}"

  if [[ "${ACTION}" == "delete" ]]; then
    normalize_delete_file "${tmp_body}" "${output_file}" "${ACCOUNT_ID}"
  fi

  rm -f "${tmp_headers}" "${tmp_body}"
}

main() {
  local request_url output_file report_file request_body temp_dir accounts_output_file keys_output_file
  parse_args "$@"
  validate_config
  output_file="$(resolved_output_file)"
  if [[ -z "${OUTPUT_FILE}" && "${ACTION}" != "all" && "${ACTION}" != "accounts" && "${ACTION}" != "keys" && "${ACTION}" != "raw" ]]; then
    temp_dir="$(mktemp -d)"
    output_file="${temp_dir}/response.json"
    trap 'rm -rf "${temp_dir}"' RETURN
  fi
  if [[ -n "${temp_dir:-}" ]]; then
    report_file="${temp_dir}/report.md"
  else
    report_file="${SCRIPT_DIR}/.tmp-report.md"
  fi
  if [[ "${ACTION}" == "all" ]]; then
    accounts_output_file="${SCRIPT_DIR}/accounts.json"
    keys_output_file="${SCRIPT_DIR}/keys.json"

    fetch_all_accounts "${accounts_output_file}"
    render_accounts_markdown "${accounts_output_file}" "${report_file}"
    cat "${report_file}"
    rm -f "${report_file}"

    printf '\n'
    fetch_all_keys "${keys_output_file}"
    render_keys_markdown "${keys_output_file}" "${report_file}"
    cat "${report_file}"
    rm -f "${report_file}"
    return 0
  fi
  if [[ "${ACTION}" == "accounts" ]]; then
    fetch_all_accounts "${output_file}"
    render_accounts_markdown "${output_file}" "${report_file}"
    cat "${report_file}"
    rm -f "${report_file}"
    return 0
  fi
  if [[ "${ACTION}" == "keys" ]]; then
    fetch_all_keys "${output_file}"
    render_keys_markdown "${output_file}" "${report_file}"
    cat "${report_file}"
    rm -f "${report_file}"
    return 0
  fi
  case "${ACTION}" in
    usage)
      request_url="$(build_usage_url)"
      ;;
    schedulable|disable|enable)
      request_url="$(build_schedulable_url)"
      request_body="{\"schedulable\":${SCHEDULABLE_VALUE}}"
      ;;
    delete)
      request_url="$(build_delete_url)"
      ;;
    bulk-update)
      request_url="$(build_bulk_update_url)"
      request_body="$(jq -cn --arg account_ids_csv "${ACCOUNT_IDS}" --arg priority_value "${PRIORITY_VALUE}" '{account_ids: ($account_ids_csv | split(",") | map(tonumber)), priority: ($priority_value | tonumber)}')"
      ;;
    *)
      request_url="$(build_accounts_url 1)"
      ;;
  esac
  if [[ "${ACTION}" == "schedulable" || "${ACTION}" == "disable" || "${ACTION}" == "enable" ]]; then
    request_json_with_body "${request_url}" "${output_file}" "${request_body}"
    render_schedulable_markdown "${output_file}" "${report_file}"
    cat "${report_file}"
    if [[ -n "${temp_dir:-}" ]]; then
      rm -rf "${temp_dir}"
      trap - RETURN
    fi
    return 0
  fi
  if [[ "${ACTION}" == "bulk-update" ]]; then
    request_json_with_body "${request_url}" "${output_file}" "${request_body}"
    render_bulk_update_markdown "${output_file}" "${report_file}"
    cat "${report_file}"
    rm -f "${report_file}"
    if [[ -n "${temp_dir:-}" ]]; then
      rm -rf "${temp_dir}"
      trap - RETURN
    fi
    return 0
  fi
  if [[ "${ACTION}" == "delete" ]]; then
    request_json_with_method "${request_url}" "${output_file}" "DELETE"
    render_delete_markdown "${output_file}" "${report_file}"
    cat "${report_file}"
    rm -f "${report_file}"
    if [[ -n "${temp_dir:-}" ]]; then
      rm -rf "${temp_dir}"
      trap - RETURN
    fi
    return 0
  fi
  request_json "${request_url}" "${output_file}"
  if [[ "${ACTION}" == "usage" ]]; then
    render_usage_markdown "${output_file}" "${report_file}"
    cat "${report_file}"
    rm -f "${report_file}"
    if [[ -n "${temp_dir:-}" ]]; then
      rm -rf "${temp_dir}"
      trap - RETURN
    fi
  fi
}

main "$@"

#!/usr/bin/env bash
set -euo pipefail

# 调用方式：
#   CPA_BASE_URL='http://<管理服务地址>:<端口>' \
#   CPA_MANAGEMENT_TOKEN='<remote-management token>' \
#   ./shell/cpa_query.sh
#
# 等价参数方式：
#   ./shell/cpa_query.sh \
#     --base-url 'http://<管理服务地址>:<端口>' \
#     --management-token '<remote-management token>'
#
# api-call 目标固定为 ChatGPT usage 地址。
# 可选：追加 `usage` 只输出用量查询；追加 `auth-files` 只输出 auth-files 原始响应。

SCRIPT_NAME="$(basename "$0")"

BASE_URL="${CPA_BASE_URL:-}"
MANAGEMENT_TOKEN="${CPA_MANAGEMENT_TOKEN:-}"
TARGET_URL="https://chatgpt.com/backend-api/wham/usage"
TARGET_METHOD="${CPA_TARGET_METHOD:-GET}"
TARGET_AUTH_HEADER="${CPA_TARGET_AUTH_HEADER:-Bearer \$TOKEN\$}"
CHATGPT_ACCOUNT_ID="${CPA_CHATGPT_ACCOUNT_ID:-}"
TIMEOUT="${CPA_TIMEOUT:-30}"
INSECURE="true"
ACTION="all"

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
declare -a RESULT_ROWS=()
declare -a SUMMARY_5H_ITEMS=()
declare -a SUMMARY_WEEK_ITEMS=()
declare -a SUMMARY_ERROR_NAMES=()
SUMMARY_TOTAL=0
SUMMARY_OK=0
SUMMARY_ERROR=0
SUMMARY_SUM_5H=0
SUMMARY_SUM_WEEK=0
SUMMARY_ITEM_ORDER=0

usage() {
  cat <<EOF
用法:
  ./${SCRIPT_NAME} [all|auth-files|usage] [选项]

说明:
  查询 cliproxyapi remote management 接口。
  默认执行 all：先查询 auth-files，再按 name/authIndex 逐个查询 ChatGPT usage。

必填:
  --base-url <url>                 管理接口地址，也可用 CPA_BASE_URL
  --management-token <token>       remote-management Bearer token，也可用 CPA_MANAGEMENT_TOKEN

选项:
  --target-method <method>         api-call 目标方法，默认 ${TARGET_METHOD}
  --target-auth-header <value>     目标请求 Authorization，默认保留 Bearer \$TOKEN\$ 占位
  --account-id <id>                Chatgpt-Account-Id，也可用 CPA_CHATGPT_ACCOUNT_ID
  --timeout <seconds>              curl 超时时间，默认 ${TIMEOUT}
  --no-insecure                    不向 curl 传递 --insecure
  -h, --help                       显示帮助

示例:
  CPA_BASE_URL='http://127.0.0.1:3318' CPA_MANAGEMENT_TOKEN='***' ./${SCRIPT_NAME}
  ./${SCRIPT_NAME} usage --base-url 'http://127.0.0.1:3318' --management-token '***'
EOF
}

die() {
  printf '[%s] 错误: %s\n' "${SCRIPT_NAME}" "$*" >&2
  exit 1
}

log() {
  printf '[%s] %s\n' "${SCRIPT_NAME}" "$*" >&2
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
}

ensure_requirements() {
  command -v curl >/dev/null 2>&1 || die "未找到 curl"
  [[ -n "${BASE_URL}" ]] || die "缺少管理接口地址，请通过 --base-url 或 CPA_BASE_URL 传入"
  [[ -n "${MANAGEMENT_TOKEN}" ]] || die "缺少管理 Token，请通过 --management-token 或 CPA_MANAGEMENT_TOKEN 传入"
  case "${ACTION}" in
    all|auth-files|usage)
      ;;
    *)
      die "未知动作: ${ACTION}，请使用 all/auth-files/usage"
      ;;
  esac

  if [[ "${ACTION}" == "all" || "${ACTION}" == "usage" ]]; then
    command -v jq >/dev/null 2>&1 || die "usage/all 需要 jq 来解析 auth-files 和 api-call 响应"
  fi
}

build_curl_common_args() {
  CURL_ARGS=(
    --silent
    --show-error
    --location
    --connect-timeout "${TIMEOUT}"
    --max-time "${TIMEOUT}"
    -H "Accept: application/json, text/plain, */*"
    -H "Accept-Language: zh-CN,zh;q=0.9,en;q=0.8,ja;q=0.7"
    -H "Authorization: Bearer ${MANAGEMENT_TOKEN}"
    -H "Referer: ${BASE_URL}/management.html"
    -H "User-Agent: ${BROWSER_USER_AGENT}"
  )

  if [[ "${INSECURE}" == "true" ]]; then
    CURL_ARGS+=(--insecure)
  fi
}

fetch_auth_files() {
  build_curl_common_args
  curl "${CURL_ARGS[@]}" "${BASE_URL}/v0/management/auth-files"
}

query_auth_files() {
  log "查询 auth-files"
  fetch_auth_files
  printf '\n'
}

extract_auth_entries() {
  local response="$1"

  printf '%s' "${response}" | jq -r '
    .. | objects
    | ((.auth_index? // .authIndex? // "") | tostring) as $auth_index
    | select($auth_index != "")
    | [
        (.name? // .label? // .email? // .id? // "(未命名)"),
        (.note? // "-"),
        ((.priority? // "-") | tostring),
        $auth_index,
        (.id_token?.chatgpt_account_id? // "-"),
        (.id_token?.plan_type? // "-"),
        (.id_token?.chatgpt_subscription_active_start? // "-"),
        (.id_token?.chatgpt_subscription_active_until? // "-")
      ]
    | @tsv
  ' | awk -F '\t' 'NF >= 4 && !seen[$4]++'
}

resolve_auth_entries_from_auth_files() {
  local response="$1"
  local name note priority auth_index account_id plan_type subscription_start subscription_until
  AUTH_NAMES=()
  AUTH_NOTES=()
  AUTH_PRIORITIES=()
  AUTH_INDEXES=()
  AUTH_ACCOUNT_IDS=()
  AUTH_PLAN_TYPES=()
  AUTH_SUBSCRIPTION_STARTS=()
  AUTH_SUBSCRIPTION_UNTILS=()

  while IFS=$'\t' read -r name note priority auth_index account_id plan_type subscription_start subscription_until || [[ -n "${name}${note}${priority}${auth_index}${account_id}${plan_type}${subscription_start}${subscription_until}" ]]; do
    [[ -z "${auth_index}" ]] && continue
    AUTH_NAMES+=("${name:-"(未命名)"}")
    AUTH_NOTES+=("${note:-"-"}")
    AUTH_PRIORITIES+=("${priority:-"-"}")
    AUTH_INDEXES+=("${auth_index}")
    AUTH_ACCOUNT_IDS+=("${account_id:-"-"}")
    AUTH_PLAN_TYPES+=("${plan_type:-"-"}")
    AUTH_SUBSCRIPTION_STARTS+=("${subscription_start:-"-"}")
    AUTH_SUBSCRIPTION_UNTILS+=("${subscription_until:-"-"}")
  done < <(extract_auth_entries "${response}")

  [[ "${#AUTH_INDEXES[@]}" -gt 0 ]] || die "无法从 auth-files 响应中提取 authIndex"
  sort_auth_entries_by_priority
}

sort_auth_entries_by_priority() {
  local count="${#AUTH_INDEXES[@]}"
  local index=0
  local name note priority auth_index account_id plan_type subscription_start subscription_until sort_priority

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
      if [[ "${priority}" =~ ^-?[0-9]+$ ]]; then
        sort_priority="${priority}"
      else
        sort_priority="-1"
      fi
      printf '%s\t%06d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${sort_priority}" \
        "${index}" \
        "${name}" \
        "${note}" \
        "${priority}" \
        "${auth_index}" \
        "${account_id}" \
        "${plan_type}" \
        "${subscription_start}" \
        "${subscription_until}"
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

  while IFS=$'\t' read -r _sort_priority _order name note priority auth_index account_id plan_type subscription_start subscription_until || [[ -n "${_sort_priority}${_order}${name}${note}${priority}${auth_index}${account_id}${plan_type}${subscription_start}${subscription_until}" ]]; do
    [[ -z "${auth_index}" ]] && continue
    AUTH_NAMES+=("${name}")
    AUTH_NOTES+=("${note}")
    AUTH_PRIORITIES+=("${priority}")
    AUTH_INDEXES+=("${auth_index}")
    AUTH_ACCOUNT_IDS+=("${account_id:-"-"}")
    AUTH_PLAN_TYPES+=("${plan_type:-"-"}")
    AUTH_SUBSCRIPTION_STARTS+=("${subscription_start:-"-"}")
    AUTH_SUBSCRIPTION_UNTILS+=("${subscription_until:-"-"}")
  done <<< "${sorted_output}"
}

build_usage_payload() {
  local auth_index="$1"
  local header_json
  header_json="\"Authorization\":\"$(json_escape "${TARGET_AUTH_HEADER}")\","
  header_json+="\"Content-Type\":\"application/json\","
  header_json+="\"User-Agent\":\"$(json_escape "${TARGET_USER_AGENT}")\""

  # ChatGPT 多账号环境才需要该请求头；未传入时不发送，避免固化个人账号 ID。
  if [[ -n "${CHATGPT_ACCOUNT_ID}" ]]; then
    header_json+=",\"Chatgpt-Account-Id\":\"$(json_escape "${CHATGPT_ACCOUNT_ID}")\""
  fi

  printf '{"authIndex":"%s","method":"%s","url":"%s","header":{%s}}' \
    "$(json_escape "${auth_index}")" \
    "$(json_escape "${TARGET_METHOD}")" \
    "$(json_escape "${TARGET_URL}")" \
    "${header_json}"
}

fetch_usage_response() {
  local auth_index="$1"
  local payload
  build_curl_common_args
  payload="$(build_usage_payload "${auth_index}")"

  curl "${CURL_ARGS[@]}" \
    -H "Content-Type: application/json" \
    -H "Origin: ${BASE_URL}" \
    --data-raw "${payload}" \
    "${BASE_URL}/v0/management/api-call"
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

extract_usage_limits() {
  local response="$1"

  printf '%s' "${response}" | jq -r '
    def body_json:
      if (.body | type) == "string" then
        (.body | fromjson?)
      else
        (.body // .)
      end;

    (.status_code // 200) as $status
    | (body_json) as $body
    | if ($status != 200) then
        ["ERROR", ("HTTP " + ($status | tostring) + ": " + (($body.detail // $body.error // $body.message // .body // "api-call failed") | tostring))] | @tsv
      elif ($body == null) then
        ["ERROR", "api-call body 不是合法 JSON"] | @tsv
      elif ($body.rate_limit? == null) then
        ["ERROR", "api-call body 缺少 rate_limit"] | @tsv
      else
        [
          (if ($body.rate_limit.primary_window.used_percent | type) == "number" then
            (100 - $body.rate_limit.primary_window.used_percent)
          else
            "N/A"
          end),
          ($body.rate_limit.primary_window.reset_at // "N/A"),
          (if ($body.rate_limit.secondary_window.used_percent | type) == "number" then
            (100 - $body.rate_limit.secondary_window.used_percent)
          else
            "N/A"
          end),
          ($body.rate_limit.secondary_window.reset_at // "N/A")
        ] | @tsv
      end
  '
}

print_usage_header() {
  printf 'name\tnote\t优先级\t5小时/周剩余\t5小时刷新时间\t周刷新时间\t状态/异常\n'
}

render_usage_table() {
  local row
  local row_number=0
  local total_rows="${#RESULT_ROWS[@]}"
  local name note priority plan_info subscription_info limits five_hour_reset week_reset status
  local status_display

  for row in "${RESULT_ROWS[@]}"; do
    row_number=$((row_number + 1))
    IFS=$'\t' read -r name note priority plan_info subscription_info limits five_hour_reset week_reset status <<< "${row}"
    status_display="${status}"
    if [[ "${status}" == "OK" ]]; then
      status_display="ok"
    fi
    printf '%s. %s\n' "${row_number}" "${name}"
    printf '   5h/week：%s\n' "${limits}"
    printf '   状态：%s\n' "${status_display}"
    printf '   备注: %s\n' "${note}"
    printf '   优先级: %s\n' "${priority}"
    printf '   套餐: %s\n' "${plan_info}"
    printf '   订阅: %s\n' "${subscription_info}"
    printf '   刷新: %s / %s\n' "${five_hour_reset}" "${week_reset}"
    if [[ "${row_number}" -lt "${total_rows}" ]]; then
      printf '\n'
    fi
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

build_error_summary_line() {
  local details=""
  local name short_name

  if [[ "${#SUMMARY_ERROR_NAMES[@]}" -eq 0 ]]; then
    printf '异常：-\n'
    return 0
  fi

  for name in "${SUMMARY_ERROR_NAMES[@]}"; do
    short_name="$(format_summary_name "${name}")"
    if [[ -n "${details}" ]]; then
      details+="，"
    fi
    details+="${short_name}"
  done

  printf '异常：%s\n' "${details}"
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

record_success_summary() {
  local name="$1"
  local five_hour="$2"
  local week="$3"
  local entry_order=""
  local five_hour_positive="false"
  local week_positive="false"

  SUMMARY_OK=$((SUMMARY_OK + 1))
  printf -v entry_order '%06d' "${SUMMARY_ITEM_ORDER}"
  SUMMARY_ITEM_ORDER=$((SUMMARY_ITEM_ORDER + 1))

  if [[ "${week}" =~ ^[0-9]+([.][0-9]+)?$ ]] && number_greater_than_zero "${week}"; then
    week_positive="true"
  fi

  if [[ "${five_hour}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    if number_greater_than_zero "${five_hour}"; then
      five_hour_positive="true"
    fi
    if [[ "${five_hour_positive}" == "true" && "${week_positive}" == "true" ]]; then
      SUMMARY_5H_ITEMS+=("${five_hour}"$'\t'"${entry_order}"$'\t'"${name}")
    fi
    # 周剩余为 0 时，该账号的 5 小时额度实际不可用，不计入 5 小时总量。
    if [[ ! "${week}" =~ ^[0-9]+([.][0-9]+)?$ ]] || [[ "${week_positive}" == "true" ]]; then
      SUMMARY_SUM_5H="$(number_add "${SUMMARY_SUM_5H}" "${five_hour}")"
    fi
  fi

  if [[ "${week}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    if [[ "${week_positive}" == "true" ]]; then
      SUMMARY_WEEK_ITEMS+=("${week}"$'\t'"${entry_order}"$'\t'"${name}")
    fi
    SUMMARY_SUM_WEEK="$(number_add "${SUMMARY_SUM_WEEK}" "${week}")"
  fi
}

print_usage_summary() {
  local five_hour_total="N/A"
  local week_total="N/A"

  if [[ "${#SUMMARY_5H_ITEMS[@]}" -gt 0 ]]; then
    five_hour_total="$(format_percent "${SUMMARY_SUM_5H}")"
  fi
  if [[ "${#SUMMARY_WEEK_ITEMS[@]}" -gt 0 ]]; then
    week_total="$(format_percent "${SUMMARY_SUM_WEEK}")"
  fi

  printf '概要: %s个 。OK %s / ERR %s 。总 %s/%s\n\n' \
    "${SUMMARY_TOTAL}" \
    "${SUMMARY_OK}" \
    "${SUMMARY_ERROR}" \
    "${five_hour_total}" \
    "${week_total}"
  build_summary_metric_line '5h剩余' SUMMARY_5H_ITEMS
  printf '\n'
  build_summary_metric_line '周剩余' SUMMARY_WEEK_ITEMS
  printf '\n'
  build_error_summary_line
}

query_usage_for_auth_entries() {
  local total="${#AUTH_INDEXES[@]}"
  local index=0
  local name
  local note
  local priority
  local account_id
  local plan_type
  local subscription_start
  local subscription_until
  local plan_info
  local subscription_info
  local auth_index
  local response
  local parsed
  local first
  local second
  local third
  local fourth
  local five_hour_reset
  local week_reset
  RESULT_ROWS=()
  SUMMARY_TOTAL="${total}"
  SUMMARY_OK=0
  SUMMARY_ERROR=0
  SUMMARY_SUM_5H=0
  SUMMARY_SUM_WEEK=0
  SUMMARY_5H_ITEMS=()
  SUMMARY_WEEK_ITEMS=()
  SUMMARY_ERROR_NAMES=()
  SUMMARY_ITEM_ORDER=0

  [[ "${total}" -gt 0 ]] || die "没有可查询的 authIndex，请检查 auth-files 响应"

  for auth_index in "${AUTH_INDEXES[@]}"; do
    name="${AUTH_NAMES[index]:-"(未命名)"}"
    note="${AUTH_NOTES[index]:-"-"}"
    priority="${AUTH_PRIORITIES[index]:-"-"}"
    account_id="${AUTH_ACCOUNT_IDS[index]:-"-"}"
    plan_type="${AUTH_PLAN_TYPES[index]:-"-"}"
    subscription_start="${AUTH_SUBSCRIPTION_STARTS[index]:-"-"}"
    subscription_until="${AUTH_SUBSCRIPTION_UNTILS[index]:-"-"}"
    plan_info="${plan_type} | 账号ID: ${account_id}"
    subscription_info="$(format_subscription_time "${subscription_start}") -> $(format_subscription_time "${subscription_until}")"
    index=$((index + 1))
    log "查询 usage (${index}/${total}): ${name}"

    if ! response="$(fetch_usage_response "${auth_index}" 2>&1)"; then
      SUMMARY_ERROR=$((SUMMARY_ERROR + 1))
      SUMMARY_ERROR_NAMES+=("${name}")
      RESULT_ROWS+=("${name}"$'\t'"${note}"$'\t'"${priority}"$'\t'"${plan_info}"$'\t'"${subscription_info}"$'\t-\t-\t-\t'"异常: ${response//$'\n'/ }")
      continue
    fi

    if ! parsed="$(extract_usage_limits "${response}" 2>&1)"; then
      SUMMARY_ERROR=$((SUMMARY_ERROR + 1))
      SUMMARY_ERROR_NAMES+=("${name}")
      RESULT_ROWS+=("${name}"$'\t'"${note}"$'\t'"${priority}"$'\t'"${plan_info}"$'\t'"${subscription_info}"$'\t-\t-\t-\t'"异常: ${parsed//$'\n'/ }")
      continue
    fi

    IFS=$'\t' read -r first second third fourth <<< "${parsed}"
    if [[ "${first}" == "ERROR" ]]; then
      SUMMARY_ERROR=$((SUMMARY_ERROR + 1))
      SUMMARY_ERROR_NAMES+=("${name}")
      RESULT_ROWS+=("${name}"$'\t'"${note}"$'\t'"${priority}"$'\t'"${plan_info}"$'\t'"${subscription_info}"$'\t-\t-\t-\t'"异常: ${second:-未知错误}")
      continue
    fi

    five_hour_reset="$(format_reset_time "${second}")"
    week_reset="$(format_reset_time "${fourth}")"
    record_success_summary "${name}" "${first}" "${third}"
    RESULT_ROWS+=("${name}"$'\t'"${note}"$'\t'"${priority}"$'\t'"${plan_info}"$'\t'"${subscription_info}"$'\t'"$(format_percent "${first}")/$(format_percent "${third}")"$'\t'"${five_hour_reset}"$'\t'"${week_reset}"$'\tOK')
  done

  render_usage_table
  printf '\n'
  print_usage_summary
}

main() {
  parse_args "$@"
  BASE_URL="${BASE_URL%/}"
  ensure_requirements

  case "${ACTION}" in
    all)
      local auth_files_response
      log "查询 auth-files"
      auth_files_response="$(fetch_auth_files)"
      resolve_auth_entries_from_auth_files "${auth_files_response}"
      query_usage_for_auth_entries
      ;;
    auth-files)
      query_auth_files
      ;;
    usage)
      local auth_files_response
      log "从 auth-files 自动提取全部 name/authIndex"
      auth_files_response="$(fetch_auth_files)"
      resolve_auth_entries_from_auth_files "${auth_files_response}"
      query_usage_for_auth_entries
      ;;
  esac
}

main "$@"

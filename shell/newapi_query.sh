#!/usr/bin/env bash
set -euo pipefail

# NewAPI 面板查询工具。
# 默认查询当天全量日志：轮询 GET /api/log/ 翻页，并把合并结果写入 shell/log.json。
#
# 环境变量方式：
#   NEWAPI_BASE_URL='http://<newapi地址>:<端口>/v1' \
#   NEWAPI_KEY='<newapi key>' \
#   ./newapi_query.sh
#
# 参数方式：
#   ./newapi_query.sh log \
#     --base-url 'http://<newapi地址>:<端口>/v1' \
#     --api-key '<newapi key>'
#
# 如面板日志接口要求浏览器会话，可额外传 cookie：
#   NEWAPI_COOKIE='<浏览器 cookie>' ./newapi_query.sh log --base-url 'http://<newapi地址>:<端口>/v1' --api-key '<newapi key>'

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd -- "$(dirname "$0")" && pwd)"

ACTION="log"
BASE_URL="${NEWAPI_BASE_URL:-}"
API_KEY="${NEWAPI_KEY:-}"
COOKIE="${NEWAPI_COOKIE:-}"
NEWAPI_USER="${NEWAPI_USER:-1}"
OUTPUT_FILE="${NEWAPI_OUTPUT_FILE:-${SCRIPT_DIR}/log.json}"
PAGE="${NEWAPI_PAGE:-1}"
PAGE_SIZE="${NEWAPI_PAGE_SIZE:-100}"
LOG_TYPE="${NEWAPI_LOG_TYPE:-0}"
USERNAME="${NEWAPI_USERNAME:-}"
TOKEN_NAME="${NEWAPI_TOKEN_NAME:-}"
MODEL_NAME="${NEWAPI_MODEL_NAME:-}"
CHANNEL="${NEWAPI_CHANNEL:-}"
GROUP="${NEWAPI_GROUP:-}"
REQUEST_ID="${NEWAPI_REQUEST_ID:-}"
START_TIMESTAMP="${NEWAPI_START_TIMESTAMP:-}"
END_TIMESTAMP="${NEWAPI_END_TIMESTAMP:-}"
TIMEOUT="${NEWAPI_TIMEOUT:-60}"
INSECURE="true"
BROWSER_USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36"

usage() {
  cat <<EOF
用法:
  ./${SCRIPT_NAME} [log] [选项]

说明:
  查询 NewAPI 面板日志接口 GET /api/log/，自动翻页拉取全量结果，默认保存到 ${OUTPUT_FILE}。
  --base-url 可传站点根地址或 /v1 地址；如果传入 /v1，脚本会自动退回站点根地址拼接 /api/log/。
  默认时间范围为本地当天 00:00:00 到当前时间。
  汇总金额按历史前端逻辑 quota / 500000 计算。

选项:
  --base-url <url>          NewAPI 地址，也可用 NEWAPI_BASE_URL
  --api-key <key>           NewAPI key，也可用 NEWAPI_KEY
  --cookie <cookie>         面板会话 cookie，也可用 NEWAPI_COOKIE
  --new-api-user <id>       New-API-User 请求头，默认 ${NEWAPI_USER}
  --output <path>           输出文件，默认 ${OUTPUT_FILE}
  --page <int>              页码，默认 ${PAGE}
  --page-size <int>         每页数量，默认 ${PAGE_SIZE}
  --type <int>              日志类型，默认 ${LOG_TYPE}
  --username <value>        username 查询条件
  --token-name <value>      token_name 查询条件
  --model-name <value>      model_name 查询条件
  --channel <value>         channel 查询条件
  --group <value>           group 查询条件
  --request-id <value>      request_id 查询条件
  --start-timestamp <unix>  开始时间戳，默认当天 00:00:00
  --end-timestamp <unix>    结束时间戳，默认当前时间
  --timeout <seconds>       curl 最大耗时，默认 ${TIMEOUT}
  --no-insecure             不向 curl 传递 --insecure
  -h, --help                显示帮助

示例:
  NEWAPI_BASE_URL='http://127.0.0.1:3333/v1' NEWAPI_KEY='***' ./${SCRIPT_NAME}
  ./${SCRIPT_NAME} log --base-url 'http://127.0.0.1:3333/v1' --api-key '***' --output '${SCRIPT_DIR}/log.json'
EOF
}

die() {
  printf '[%s] 错误: %s\n' "${SCRIPT_NAME}" "$*" >&2
  exit 1
}

log() {
  printf '[%s] %s\n' "${SCRIPT_NAME}" "$*" >&2
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

site_base_url() {
  local raw="${BASE_URL%/}"
  raw="${raw%/v1}"
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
      --cookie)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--cookie 需要参数"
        COOKIE="$2"
        shift 2
        ;;
      --new-api-user)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--new-api-user 需要参数"
        NEWAPI_USER="$2"
        shift 2
        ;;
      --output)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--output 需要参数"
        OUTPUT_FILE="$2"
        shift 2
        ;;
      --page)
        [[ $# -ge 2 && "${2:-}" =~ ^[0-9]+$ ]] || die "--page 需要整数"
        PAGE="$2"
        shift 2
        ;;
      --page-size)
        [[ $# -ge 2 && "${2:-}" =~ ^[0-9]+$ ]] || die "--page-size 需要整数"
        PAGE_SIZE="$2"
        shift 2
        ;;
      --type)
        [[ $# -ge 2 && "${2:-}" =~ ^[0-9]+$ ]] || die "--type 需要整数"
        LOG_TYPE="$2"
        shift 2
        ;;
      --username)
        [[ $# -ge 2 ]] || die "--username 需要参数"
        USERNAME="$2"
        shift 2
        ;;
      --token-name)
        [[ $# -ge 2 ]] || die "--token-name 需要参数"
        TOKEN_NAME="$2"
        shift 2
        ;;
      --model-name)
        [[ $# -ge 2 ]] || die "--model-name 需要参数"
        MODEL_NAME="$2"
        shift 2
        ;;
      --channel)
        [[ $# -ge 2 ]] || die "--channel 需要参数"
        CHANNEL="$2"
        shift 2
        ;;
      --group)
        [[ $# -ge 2 ]] || die "--group 需要参数"
        GROUP="$2"
        shift 2
        ;;
      --request-id)
        [[ $# -ge 2 ]] || die "--request-id 需要参数"
        REQUEST_ID="$2"
        shift 2
        ;;
      --start-timestamp)
        [[ $# -ge 2 && "${2:-}" =~ ^[0-9]+$ ]] || die "--start-timestamp 需要 unix 秒级时间戳"
        START_TIMESTAMP="$2"
        shift 2
        ;;
      --end-timestamp)
        [[ $# -ge 2 && "${2:-}" =~ ^[0-9]+$ ]] || die "--end-timestamp 需要 unix 秒级时间戳"
        END_TIMESTAMP="$2"
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
  [[ "${ACTION}" == "log" ]] || die "未知动作: ${ACTION}，当前仅支持 log"
  command -v curl >/dev/null 2>&1 || die "未找到 curl"
  command -v jq >/dev/null 2>&1 || die "未找到 jq，无法合并分页并生成汇总"
  [[ -n "${BASE_URL}" ]] || die "缺少 NewAPI 地址，请通过 --base-url 或 NEWAPI_BASE_URL 传入"
  [[ -n "${API_KEY}" || -n "${COOKIE}" ]] || die "缺少认证信息，请传入 --api-key/NEWAPI_KEY，或 --cookie/NEWAPI_COOKIE"
  if [[ -z "${START_TIMESTAMP}" ]]; then
    START_TIMESTAMP="$(date -d 'today 00:00:00' '+%s')"
  fi
  if [[ -z "${END_TIMESTAMP}" ]]; then
    END_TIMESTAMP="$(date '+%s')"
  fi
}

build_log_url() {
  local page="$1"
  local base
  base="$(site_base_url)"
  QUERY_STRING=""
  append_query_param "p" "${page}"
  append_query_param "page_size" "${PAGE_SIZE}"
  append_query_param "type" "${LOG_TYPE}"
  append_query_param "username" "${USERNAME}"
  append_query_param "token_name" "${TOKEN_NAME}"
  append_query_param "model_name" "${MODEL_NAME}"
  append_query_param "start_timestamp" "${START_TIMESTAMP}"
  append_query_param "end_timestamp" "${END_TIMESTAMP}"
  append_query_param "channel" "${CHANNEL}"
  append_query_param "group" "${GROUP}"
  append_query_param "request_id" "${REQUEST_ID}"
  printf '%s/api/log/?%s' "${base}" "${QUERY_STRING}"
}

fetch_log_page() {
  local page="$1"
  local base
  local url
  local -a curl_args
  base="$(site_base_url)"
  url="$(build_log_url "${page}")"
  curl_args=(
    --silent
    --show-error
    --location
    --connect-timeout 15
    --max-time "${TIMEOUT}"
    -H "Accept: application/json, text/plain, */*"
    -H "Accept-Language: zh-CN,zh;q=0.9,en;q=0.8,ja;q=0.7"
    -H "Cache-Control: no-store"
    -H "New-API-User: ${NEWAPI_USER}"
    -H "Referer: ${base}/console/log"
    -H "User-Agent: ${BROWSER_USER_AGENT}"
  )
  if [[ -n "${API_KEY}" ]]; then
    curl_args+=(
      -H "Authorization: Bearer ${API_KEY}"
      -H "New-API-Key: ${API_KEY}"
    )
  fi
  if [[ -n "${COOKIE}" ]]; then
    curl_args+=(-b "${COOKIE}")
  fi
  if [[ "${INSECURE}" == "true" ]]; then
    curl_args+=(--insecure)
  fi
  curl "${curl_args[@]}" "${url}"
}

build_summary_json() {
  local page_dir="$1"

  jq -s -c \
    --arg generated_at "$(date '+%Y-%m-%d %H:%M:%S %z')" \
    --argjson start_timestamp "${START_TIMESTAMP}" \
    --argjson end_timestamp "${END_TIMESTAMP}" \
    --argjson page_size "${PAGE_SIZE}" \
    --argjson first_page "${PAGE}" '
    def n: tonumber? // 0;
    def amount($quota): (($quota | n) / 500000);
    def money($quota): (amount($quota) * 100000 | round / 100000);
    def item_account: ((.username // .user_id // "(未知账号)") | tostring);
    def item_model: ((.model_name // "(未知模型)") | tostring);
    def item_token: ((.token_name // "") | tostring);
    def sum_quota($items): ($items | map(.quota | n) | add // 0);
    def sum_prompt($items): ($items | map(.prompt_tokens | n) | add // 0);
    def sum_completion($items): ($items | map(.completion_tokens | n) | add // 0);
    def row_common($items):
      {
        requests: ($items | length),
        amount: money(sum_quota($items)),
        prompt_tokens: sum_prompt($items),
        completion_tokens: sum_completion($items),
        total_tokens: (sum_prompt($items) + sum_completion($items))
      };

    . as $pages
    | ($pages[0].data.total // 0 | n) as $total
    | [ $pages[] | .data.items[]? ] as $items
    | sum_quota($items) as $total_quota
    | {
        success: true,
        message: "",
        generated_at: $generated_at,
        query: {
          start_timestamp: $start_timestamp,
          end_timestamp: $end_timestamp,
          page_size: $page_size,
          first_page: $first_page,
          pages: ($pages | length)
        },
        data: {
          total: $total,
          fetched: ($items | length),
          items: $items
        },
        summary: {
          quota_unit: 500000,
          total_requests: ($items | length),
          total_amount: money($total_quota),
          total_prompt_tokens: sum_prompt($items),
          total_completion_tokens: sum_completion($items),
          total_tokens: (sum_prompt($items) + sum_completion($items)),
          accounts: (
            $items
            | group_by(item_account)
            | map(
                . as $group
                | row_common($group)
                  + {
                      username: ($group[0] | item_account),
                      token_names: ($group | map(item_token) | map(select(length > 0)) | unique),
                      models: ($group | map(item_model) | unique)
                    }
              )
            | sort_by(-.amount, .username)
          ),
          token_names: (
            $items
            | group_by(item_token)
            | map(
                . as $group
                | row_common($group)
                  + {
                      token_name: ($group[0] | item_token),
                      account_count: ($group | map(item_account) | unique | length),
                      models: ($group | map(item_model) | unique)
                    }
              )
            | sort_by(-.amount, .token_name)
          ),
          models: (
            $items
            | group_by(item_model)
            | map(
                . as $group
                | row_common($group)
                  + {
                      model_name: ($group[0] | item_model),
                      account_count: ($group | map(item_account) | unique | length)
                    }
              )
            | sort_by(-.amount, .model_name)
          )
        }
      }
  ' "${page_dir}"/*.json
}

render_summary() {
  local file="$1"

  jq -r '
    def token_m($tokens):
      (((($tokens // 0) | tonumber) / 10000 | floor) / 100 | tostring) + "M";
    [
      "NewAPI 当前日志汇总",
      ("总请求: " + (.summary.total_requests | tostring)),
      ("总金额: " + (.summary.total_amount | tostring) + "（quota/500000）"),
      ("总 tokens: " + token_m(.summary.total_tokens)),
      "",
      "账号汇总:",
      (
        .summary.accounts[]
        | "- " + .username + ": 请求 " + (.requests | tostring)
          + "，金额 " + (.amount | tostring)
          + "，tokens " + token_m(.total_tokens)
          + "，模型 " + ((.models // []) | join(", "))
      ),
      "",
      "Token 名称汇总:",
      (
        .summary.token_names[]
        | "- " + (if .token_name == "" then "(空)" else .token_name end) + ": 请求 " + (.requests | tostring)
          + "，金额 " + (.amount | tostring)
          + "，tokens " + token_m(.total_tokens)
          + "，模型 " + ((.models // []) | join(", "))
      ),
      "",
      "模型汇总:",
      (
        .summary.models[]
        | "- " + .model_name + ": 请求 " + (.requests | tostring)
          + "，金额 " + (.amount | tostring)
          + "，tokens " + token_m(.total_tokens)
          + "，账号数 " + (.account_count | tostring)
      )
    ] | .[]
  ' "${file}"
}

run_log_action() {
  local response total total_pages page
  local page_dir
  local tmp_file

  page_dir="$(mktemp -d)"

  log "查询 NewAPI 日志第 ${PAGE} 页"
  if ! response="$(fetch_log_page "${PAGE}" 2>&1)"; then
    die "NewAPI 日志请求失败: ${response//$'\n'/ }"
  fi
  if ! printf '%s' "${response}" | jq -e '.success == true and (.data.items | type == "array")' >/dev/null 2>&1; then
    die "NewAPI 日志响应不是预期 JSON: $(printf '%s' "${response}" | head -c 120)"
  fi
  printf '%s' "${response}" > "${page_dir}/page-${PAGE}.json"

  total="$(printf '%s' "${response}" | jq -r '.data.total // 0')"
  total_pages=$(( (total + PAGE_SIZE - 1) / PAGE_SIZE ))
  if (( total_pages < PAGE )); then
    total_pages="${PAGE}"
  fi

  page=$((PAGE + 1))
  while (( page <= total_pages )); do
    log "查询 NewAPI 日志第 ${page}/${total_pages} 页"
    if ! response="$(fetch_log_page "${page}" 2>&1)"; then
      die "NewAPI 日志第 ${page} 页请求失败: ${response//$'\n'/ }"
    fi
    if ! printf '%s' "${response}" | jq -e '.success == true and (.data.items | type == "array")' >/dev/null 2>&1; then
      die "NewAPI 日志第 ${page} 页响应不是预期 JSON"
    fi
    printf '%s' "${response}" > "${page_dir}/page-${page}.json"
    page=$((page + 1))
  done

  mkdir -p "$(dirname "${OUTPUT_FILE}")"
  tmp_file="$(mktemp "${OUTPUT_FILE}.XXXXXX")"
  build_summary_json "${page_dir}" > "${tmp_file}"
  mv "${tmp_file}" "${OUTPUT_FILE}"
  log "已写入合并响应和汇总: ${OUTPUT_FILE}"
  render_summary "${OUTPUT_FILE}"
  rm -rf "${page_dir}"
}

main() {
  parse_args "$@"
  BASE_URL="${BASE_URL%/}"
  ensure_requirements

  if [[ "${ACTION}" == "log" ]]; then
    run_log_action
    return 0
  fi

  die "未知动作: ${ACTION}"
}

main "$@"

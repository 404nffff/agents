#!/usr/bin/env bash
set -euo pipefail

# CLIProxyAPI 管理端 OAuth 登录辅助脚本。
# 仅覆盖“发起登录并拿到浏览器 URL”和“按 state 轮询状态”两类动作。
#
# 环境变量方式：
#   CPA_BASE_URL='http://<管理服务地址>:<端口>' \
#   CPA_MANAGEMENT_TOKEN='<remote-management token>' \
#   ./cpa_auth.sh codex-auth-url
#
# 参数方式：
#   ./cpa_auth.sh anthropic-auth-url \
#     --base-url 'http://<管理服务地址>:<端口>' \
#     --management-token '<remote-management token>'
#
# Web UI 回调模式（Anthropic / Codex / Gemini CLI / Antigravity 支持）：
#   ./cpa_auth.sh codex-auth-url \
#     --base-url 'http://<管理服务地址>:<端口>' \
#     --management-token '<remote-management token>' \
#     --is-webui
#
# Gemini CLI 指定 project_id：
#   ./cpa_auth.sh gemini-cli-auth-url \
#     --base-url 'http://<管理服务地址>:<端口>' \
#     --management-token '<remote-management token>' \
#     --project-id 'my-gcp-project'
#
# 轮询授权状态：
#   ./cpa_auth.sh get-auth-status \
#     --base-url 'http://<管理服务地址>:<端口>' \
#     --management-token '<remote-management token>' \
#     --state 'codex-1716206400'
#
# 说明：
#   - 返回结果直接透传管理端 JSON，便于配合 jq 或其他脚本处理。
#   - Anthropic 与 Claude 在这里视为同一提供商，动作别名为 claude-auth-url。

SCRIPT_NAME="$(basename "$0")"
CURRENT_DIR="${PWD:-$(pwd)}"
DEFAULT_ENV_FILE="${CURRENT_DIR}/cpa.env"
ENV_FILE="${CPA_ENV_FILE:-${DEFAULT_ENV_FILE}}"

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
MANAGEMENT_TOKEN="${CPA_MANAGEMENT_TOKEN:-}"
AUTH_STATE="${CPA_AUTH_STATE:-}"
PROJECT_ID="${CPA_PROJECT_ID:-}"
IS_WEBUI="${CPA_AUTH_IS_WEBUI:-false}"
TIMEOUT="${CPA_AUTH_TIMEOUT:-${CPA_TIMEOUT:-30}}"
INSECURE="true"
ACTION=""

BROWSER_USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36"
declare -a CURL_ARGS=()
QUERY_STRING=""

usage() {
  cat <<EOF
用法:
  ./${SCRIPT_NAME} <anthropic-auth-url|claude-auth-url|codex-auth-url|gemini-cli-auth-url|gemini-auth-url|antigravity-auth-url|get-auth-status|auth-status> [选项]

说明:
  查询 CLIProxyAPI 管理端 OAuth 登录辅助接口。
  默认会先读取当前运行目录下的 cpa.env（${DEFAULT_ENV_FILE}）；如需覆盖路径，可设置 CPA_ENV_FILE。
  登录类动作会返回 { "status": "ok", "url": "...", "state": "..." }，
  状态查询会返回 { "status": "wait" | "ok" | "error", ... }。

必填:
  --base-url <url>                 管理接口地址，也可用 CPA_BASE_URL
  --management-token <token>       remote-management Bearer token，也可用 CPA_MANAGEMENT_TOKEN

动作:
  anthropic-auth-url               开始 Anthropic / Claude 登录
  claude-auth-url                  anthropic-auth-url 的等价别名
  codex-auth-url                   开始 Codex 登录
  gemini-cli-auth-url              开始 Gemini CLI 登录
  gemini-auth-url                  gemini-cli-auth-url 的等价别名
  antigravity-auth-url             开始 Antigravity 登录
  get-auth-status                  按 state 轮询登录结果
  auth-status                      get-auth-status 的等价别名

选项:
  --state <value>                  get-auth-status/auth-status 必填，也可用 CPA_AUTH_STATE
  --project-id <id>                gemini-cli-auth-url 可选，也可用 CPA_PROJECT_ID
  --is-webui                       为支持的登录动作追加 ?is_webui=true，也可用 CPA_AUTH_IS_WEBUI=true
  --no-webui                       显式关闭 is_webui
  --timeout <seconds>              curl 超时时间，默认 ${TIMEOUT}
  --no-insecure                    不向 curl 传递 --insecure
  -h, --help                       显示帮助

示例:
  ./${SCRIPT_NAME} codex-auth-url --base-url 'http://127.0.0.1:3318' --management-token '***'
  ./${SCRIPT_NAME} codex-auth-url --base-url 'http://127.0.0.1:3318' --management-token '***' --is-webui
  ./${SCRIPT_NAME} gemini-cli-auth-url --base-url 'http://127.0.0.1:3318' --management-token '***' --project-id 'my-gcp-project'
  ./${SCRIPT_NAME} get-auth-status --base-url 'http://127.0.0.1:3318' --management-token '***' --state 'codex-1716206400'
EOF
}

die() {
  printf '[%s] 错误: %s\n' "${SCRIPT_NAME}" "$*" >&2
  exit 1
}

log() {
  printf '[%s] %s\n' "${SCRIPT_NAME}" "$*" >&2
}

normalize_bool() {
  local value="${1:-}"
  case "${value,,}" in
    1|true|yes|y|on)
      printf 'true'
      ;;
    0|false|no|n|off|'')
      printf 'false'
      ;;
    *)
      die "布尔值非法: ${value}"
      ;;
  esac
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
      --management-token)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--management-token 需要参数"
        MANAGEMENT_TOKEN="$2"
        shift 2
        ;;
      --state)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--state 需要参数"
        AUTH_STATE="$2"
        shift 2
        ;;
      --project-id)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--project-id 需要参数"
        PROJECT_ID="$2"
        shift 2
        ;;
      --is-webui)
        IS_WEBUI="true"
        shift
        ;;
      --no-webui)
        IS_WEBUI="false"
        shift
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
  [[ -n "${ACTION}" ]] || {
    usage
    exit 1
  }

  case "${ACTION}" in
    anthropic-auth-url|claude-auth-url|codex-auth-url|gemini-cli-auth-url|gemini-auth-url|antigravity-auth-url|get-auth-status|auth-status)
      ;;
    *)
      die "未知动作: ${ACTION}"
      ;;
  esac

  command -v curl >/dev/null 2>&1 || die "未找到 curl"
  [[ -n "${BASE_URL}" ]] || die "缺少管理接口地址，请通过 --base-url 或 CPA_BASE_URL 传入"
  [[ -n "${MANAGEMENT_TOKEN}" ]] || die "缺少管理 Token，请通过 --management-token 或 CPA_MANAGEMENT_TOKEN 传入"

  IS_WEBUI="$(normalize_bool "${IS_WEBUI}")"

  if [[ "${ACTION}" == "get-auth-status" || "${ACTION}" == "auth-status" ]]; then
    [[ -n "${AUTH_STATE}" ]] || die "${ACTION} 动作缺少 state，请传入 --state 或 CPA_AUTH_STATE"
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

build_action_url() {
  local path=""

  QUERY_STRING=""
  case "${ACTION}" in
    anthropic-auth-url|claude-auth-url)
      path="/v0/management/anthropic-auth-url"
      ;;
    codex-auth-url)
      path="/v0/management/codex-auth-url"
      ;;
    gemini-cli-auth-url|gemini-auth-url)
      path="/v0/management/gemini-cli-auth-url"
      if [[ -n "${PROJECT_ID}" ]]; then
        append_query_param "project_id" "${PROJECT_ID}"
      fi
      ;;
    antigravity-auth-url)
      path="/v0/management/antigravity-auth-url"
      ;;
    get-auth-status|auth-status)
      path="/v0/management/get-auth-status"
      append_query_param "state" "${AUTH_STATE}"
      ;;
  esac

  if [[ "${ACTION}" != "get-auth-status" && "${ACTION}" != "auth-status" && "${IS_WEBUI}" == "true" ]]; then
    append_query_param "is_webui" "true"
  fi

  if [[ -n "${QUERY_STRING}" ]]; then
    printf '%s%s?%s' "${BASE_URL}" "${path}" "${QUERY_STRING}"
  else
    printf '%s%s' "${BASE_URL}" "${path}"
  fi
}

describe_action() {
  case "${ACTION}" in
    anthropic-auth-url|claude-auth-url)
      printf '发起 Anthropic/Claude 登录'
      ;;
    codex-auth-url)
      printf '发起 Codex 登录'
      ;;
    gemini-cli-auth-url|gemini-auth-url)
      printf '发起 Gemini CLI 登录'
      ;;
    antigravity-auth-url)
      printf '发起 Antigravity 登录'
      ;;
    get-auth-status|auth-status)
      printf '查询授权状态'
      ;;
  esac
}

run_action() {
  local url
  build_curl_common_args
  url="$(build_action_url)"
  log "$(describe_action): ${url}"
  curl "${CURL_ARGS[@]}" "${url}"
  printf '\n'
}

main() {
  parse_args "$@"
  BASE_URL="${BASE_URL%/}"
  ensure_requirements
  run_action
}

main "$@"

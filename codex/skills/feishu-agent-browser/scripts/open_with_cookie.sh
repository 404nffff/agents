#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 统一飞书导入 Cookie、打开页面和保存状态的默认路径。
SESSION_NAME="${FEISHU_AGENT_BROWSER_SESSION:-feishu_cookie}"
STATE_FILE="${FEISHU_AGENT_BROWSER_STATE_FILE:-$SKILL_DIR/feishu-agent-browser-state.json}"
RUNTIME_DIR="${FEISHU_AGENT_BROWSER_RUNTIME_DIR:-/tmp/agent-browser-runtime}"
TARGET_URL="${1:-${FEISHU_AGENT_BROWSER_URL:-https://feishu.cn/}}"
COOKIE_DOMAIN="${FEISHU_AGENT_BROWSER_COOKIE_DOMAIN:-.feishu.cn}"
COOKIE_STRING="${FEISHU_AGENT_BROWSER_COOKIE:-}"

check_agent_browser_prerequisites() {
  # 运行前先确认 agent-browser 命令可用；缺失时尝试自动安装。
  if ! command -v agent-browser >/dev/null 2>&1; then
    if ! command -v npm >/dev/null 2>&1; then
      printf 'missing required command: npm\n' >&2
      printf 'please install npm first, then retry.\n' >&2
      exit 1
    fi

    printf 'agent-browser not found, installing via npm i -g agent-browser ...\n' >&2
    npm i -g agent-browser
  fi

  if ! command -v agent-browser >/dev/null 2>&1; then
    printf 'missing required command: agent-browser\n' >&2
    printf 'please install agent-browser first, then retry.\n' >&2
    exit 1
  fi
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

if [[ -z "$COOKIE_STRING" ]]; then
  COOKIE_STRING="$(cat)"
fi

check_agent_browser_prerequisites

COOKIE_STRING="$(trim "$COOKIE_STRING")"
if [[ -z "$COOKIE_STRING" ]]; then
  printf 'missing cookie input\n' >&2
  exit 1
fi

mkdir -p "$RUNTIME_DIR"
mkdir -p "$(dirname "$STATE_FILE")"

# 先打开目标域名，确保后续 Cookie 注入有有效上下文。
XDG_RUNTIME_DIR="$RUNTIME_DIR" \
agent-browser --session "$SESSION_NAME" open "$TARGET_URL"

XDG_RUNTIME_DIR="$RUNTIME_DIR" \
agent-browser --session "$SESSION_NAME" wait --load networkidle

# 这些 Cookie 通常以 HttpOnly 方式工作，直接按约定补齐属性。
HTTP_ONLY_COOKIES=(
  "session"
  "session_list"
  "sl_session"
  "passport_app_access_token"
  "_csrf_token"
  "lgw_csrf_token"
  "swp_csrf_token"
  "QXV0aHpDb250ZXh0"
)

IFS=';' read -r -a COOKIE_PAIRS <<<"$COOKIE_STRING"
for raw_pair in "${COOKIE_PAIRS[@]}"; do
  pair="$(trim "$raw_pair")"
  [[ -z "$pair" ]] && continue

  if [[ "$pair" == *"="* ]]; then
    name="${pair%%=*}"
    value="${pair#*=}"
  else
    name="$pair"
    value=""
  fi

  name="$(trim "$name")"
  [[ -z "$name" ]] && continue

  cookie_cmd=(
    agent-browser
    --session "$SESSION_NAME"
    cookies set "$name" "$value"
    --domain "$COOKIE_DOMAIN"
    --path /
    --secure
  )

  for http_only_name in "${HTTP_ONLY_COOKIES[@]}"; do
    if [[ "$name" == "$http_only_name" ]]; then
      cookie_cmd+=(--httpOnly)
      break
    fi
  done

  XDG_RUNTIME_DIR="$RUNTIME_DIR" "${cookie_cmd[@]}"
done

# Cookie 写完后重新访问页面，再把登录态保存为默认状态文件。
XDG_RUNTIME_DIR="$RUNTIME_DIR" \
agent-browser --session "$SESSION_NAME" open "$TARGET_URL"

XDG_RUNTIME_DIR="$RUNTIME_DIR" \
agent-browser --session "$SESSION_NAME" wait --load networkidle

XDG_RUNTIME_DIR="$RUNTIME_DIR" \
agent-browser --session "$SESSION_NAME" state save "$STATE_FILE"

TITLE="$(
  XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  agent-browser --session "$SESSION_NAME" get title
)"
URL="$(
  XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  agent-browser --session "$SESSION_NAME" get url
)"

printf 'feishu state saved: %s\n' "$STATE_FILE"
printf 'title: %s\n' "$TITLE"
printf 'url: %s\n' "$URL"

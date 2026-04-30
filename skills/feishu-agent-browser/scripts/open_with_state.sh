#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 约定统一的会话名、状态文件和运行时目录，减少重复命令。
SESSION_NAME="${FEISHU_AGENT_BROWSER_SESSION:-feishu_cookie}"
STATE_FILE="${FEISHU_AGENT_BROWSER_STATE_FILE:-$SKILL_DIR/feishu-agent-browser-state.json}"
RUNTIME_DIR="${FEISHU_AGENT_BROWSER_RUNTIME_DIR:-/tmp/agent-browser-runtime}"
TARGET_URL="${1:-${FEISHU_AGENT_BROWSER_URL:-https://feishu.cn/}}"

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

check_agent_browser_prerequisites

if [[ ! -f "$STATE_FILE" ]]; then
  printf 'missing state file: %s\n' "$STATE_FILE" >&2
  exit 1
fi

mkdir -p "$RUNTIME_DIR"

XDG_RUNTIME_DIR="$RUNTIME_DIR" \
agent-browser --session "$SESSION_NAME" state load "$STATE_FILE"

XDG_RUNTIME_DIR="$RUNTIME_DIR" \
agent-browser --session "$SESSION_NAME" open "$TARGET_URL"

XDG_RUNTIME_DIR="$RUNTIME_DIR" \
agent-browser --session "$SESSION_NAME" wait --load networkidle

TITLE="$(
  XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  agent-browser --session "$SESSION_NAME" get title
)"
URL="$(
  XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  agent-browser --session "$SESSION_NAME" get url
)"

printf 'title: %s\n' "$TITLE"
printf 'url: %s\n' "$URL"

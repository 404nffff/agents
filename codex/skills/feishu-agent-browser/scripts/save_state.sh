#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 统一飞书浏览会话与状态文件路径，避免每次手动输入。
SESSION_NAME="${FEISHU_AGENT_BROWSER_SESSION:-feishu_cookie}"
STATE_FILE="${FEISHU_AGENT_BROWSER_STATE_FILE:-$SKILL_DIR/feishu-agent-browser-state.json}"
RUNTIME_DIR="${FEISHU_AGENT_BROWSER_RUNTIME_DIR:-/tmp/agent-browser-runtime}"

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

mkdir -p "$RUNTIME_DIR"
mkdir -p "$(dirname "$STATE_FILE")"

XDG_RUNTIME_DIR="$RUNTIME_DIR" \
agent-browser --session "$SESSION_NAME" state save "$STATE_FILE"

printf 'feishu state saved: %s\n' "$STATE_FILE"

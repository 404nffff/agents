#!/usr/bin/env python3
"""飞书通知插件。

插件只接收通用 hook context，并复用既有 `shell/feishu_bot/feishu_bot_push.sh`
发送 Markdown 卡片。未开启推送时只维护标题状态，不发网络请求。
"""

from __future__ import annotations

import json
import os
import shlex
import subprocess
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


PLUGIN_DIR = Path(__file__).resolve().parent
SCRIPT_DIR = PLUGIN_DIR.parent.parent
FEISHU_DIR = SCRIPT_DIR.parent / "feishu_bot"
PUSH_SCRIPT = FEISHU_DIR / "feishu_bot_push.sh"
DEFAULT_ENV_FILE = PLUGIN_DIR / ".env"

EVENT_ZH = {
    "SessionStart": "会话开始",
    "SubagentStart": "子代理开始",
    "PreToolUse": "工具调用前",
    "PermissionRequest": "权限请求",
    "PostToolUse": "工具调用后",
    "PreCompact": "压缩前",
    "PostCompact": "压缩后",
    "UserPromptSubmit": "用户提交提示",
    "SubagentStop": "子代理结束",
    "Stop": "回合结束",
}

SENSITIVE_KEYWORDS = (
    "token",
    "secret",
    "password",
    "passwd",
    "authorization",
    "cookie",
    "session",
    "api_key",
    "apikey",
    "access_key",
    "private_key",
)


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


def enabled(value: str) -> bool:
    return value.lower() in {"1", "true", "yes", "on"}


def first_text(payload: dict[str, Any], *names: str) -> str:
    for name in names:
        value = payload.get(name)
        if value is not None and str(value):
            return str(value)
    return ""


def nested_text(obj: Any, *names: str) -> str:
    if not isinstance(obj, dict):
        return ""
    for name in names:
        value = obj.get(name)
        if value is not None and str(value):
            return str(value)
    return ""


def redact(value: Any) -> Any:
    if isinstance(value, dict):
        result = {}
        for key, child in value.items():
            key_text = str(key)
            normalized = key_text.lower().replace("-", "_")
            result[key_text] = "***REDACTED***" if any(item in normalized for item in SENSITIVE_KEYWORDS) else redact(child)
        return result
    if isinstance(value, list):
        return [redact(item) for item in value]
    if isinstance(value, str):
        lowered = value.lower()
        if lowered.startswith("bearer ") or "authorization:" in lowered or "cookie:" in lowered:
            return "***REDACTED***"
    return value


def load_plugin_env() -> None:
    """读取插件本地配置；外部环境变量优先，避免覆盖调用者传入值。"""
    env_file = Path(env("FEISHU_CODEX_HOOK_ENV_FILE", str(DEFAULT_ENV_FILE)) or str(DEFAULT_ENV_FILE))
    if not env_file.exists():
        return
    for raw_line in env_file.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if not key or key in os.environ:
            continue
        try:
            parsed = shlex.split(value, comments=False, posix=True)
            value = parsed[0] if parsed else ""
        except ValueError:
            value = value.strip().strip("'\"")
        os.environ[key] = value


def send_markdown(title: str, markdown: str) -> None:
    template = env("FEISHU_CODEX_HOOK_TEMPLATE", env("FEISHU_CODEX_NOTIFY_TEMPLATE", "blue"))
    if PUSH_SCRIPT.exists() and os.name != "nt":
        try:
            result = subprocess.run(
                [str(PUSH_SCRIPT), "app-markdown", "--title", title, "--template", template, "--markdown", markdown],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            if result.returncode == 0:
                return
        except Exception:
            pass
    send_markdown_with_api(title, markdown, template)


def shorten(value: Any, max_len: int = 900) -> str:
    if value is None:
        return ""
    if not isinstance(value, str):
        value = json.dumps(value, ensure_ascii=False, sort_keys=True)
    value = value.strip()
    if len(value) > max_len:
        return value[:max_len] + "\n...(已截断)"
    return value


def code(value: str) -> str:
    return f"`{value or '-'}`"


def build_markdown(context: dict[str, Any]) -> str:
    payload = context.get("payload")
    payload = payload if isinstance(payload, dict) else {}
    event = str(context.get("event", ""))
    try:
        max_chars = int(env("FEISHU_CODEX_HOOK_MAX_CHARS", "3000") or "3000")
    except ValueError:
        max_chars = 3000
    footer = env("FEISHU_CODEX_HOOK_FOOTER", "由 Codex hooks 自动发送")
    include_payload = enabled(env("FEISHU_CODEX_HOOK_INCLUDE_PAYLOAD", "false"))

    cwd = first_text(payload, "cwd")
    session_id = first_text(payload, "session_id", "sessionId")
    turn_id = first_text(payload, "turn_id", "turnId")
    model = first_text(payload, "model")
    permission_mode = first_text(payload, "permission_mode", "permissionMode")
    transcript_path = first_text(payload, "transcript_path", "transcriptPath")
    tool_name = first_text(payload, "tool_name", "toolName")
    tool_use_id = first_text(payload, "tool_use_id", "toolUseId", "call_id", "callId")
    trigger = first_text(payload, "trigger")
    source = first_text(payload, "source")
    prompt = first_text(payload, "prompt")
    last_assistant_message = first_text(payload, "last_assistant_message", "lastAssistantMessage")
    stop_hook_active = first_text(payload, "stop_hook_active", "stopHookActive")
    subagent = payload.get("subagent") if isinstance(payload.get("subagent"), dict) else {}
    agent_id = first_text(payload, "agent_id", "agentId") or nested_text(subagent, "agent_id", "agentId")
    agent_type = first_text(payload, "agent_type", "agentType") or nested_text(subagent, "agent_type", "agentType")

    details = []
    if source:
        details.append(f"- Source：{code(source)}")
    if trigger:
        details.append(f"- Trigger：{code(trigger)}")
    if tool_name:
        details.append(f"- Tool：{code(tool_name)}")
    if tool_use_id:
        details.append(f"- Tool Use ID：{code(tool_use_id)}")
    if stop_hook_active:
        details.append(f"- Stop Hook Active：{code(stop_hook_active)}")
    if agent_id or agent_type:
        details.append(f"- Agent ID：{code(agent_id)}")
        details.append(f"- Agent Type：{code(agent_type)}")

    message_blocks = []
    if event == "UserPromptSubmit" and prompt:
        message_blocks.extend(["**用户提示**", "", shorten(prompt, min(max_chars, 1200))])
    elif event == "Stop" and last_assistant_message:
        message_blocks.extend(["**最终回复**", "", shorten(last_assistant_message, max_chars)])

    if include_payload:
        payload_excerpt = shorten(redact(payload), min(max_chars, 1600))
        if payload_excerpt:
            message_blocks.extend(["", "---", "", "**Payload 摘要**", "", f"```json\n{payload_excerpt}\n```"])

    parts = [
        f"**事件**：{event}（{EVENT_ZH.get(event, '-')}）",
        "",
        "**工作目录**",
        code(cwd),
        "",
        "**基础信息**",
        f"- Session：{code(session_id)}",
        f"- Turn：{code(turn_id)}",
        f"- Model：{code(model)}",
        f"- Permission：{code(permission_mode)}",
        f"- Transcript：{code(transcript_path)}",
    ]

    if details:
        parts.extend(["", "**事件详情**", *details])
    if message_blocks:
        parts.extend(["", "---", "", *message_blocks])
    parts.extend(["", "---", "", footer])
    return "\n".join(parts)


def post_json(uri: str, body: dict[str, Any], headers: dict[str, str] | None = None) -> dict[str, Any]:
    try:
        timeout = int(env("FEISHU_BOT_TIMEOUT", "30") or "30")
    except ValueError:
        timeout = 30
    data = json.dumps(body, ensure_ascii=False).encode("utf-8")
    request_headers = {"Content-Type": "application/json; charset=utf-8"}
    request_headers.update(headers or {})
    request = urllib.request.Request(uri, data=data, headers=request_headers, method="POST")
    with urllib.request.urlopen(request, timeout=timeout) as response:
        loaded = json.loads(response.read().decode("utf-8"))
    if loaded.get("code") not in (None, 0):
        raise RuntimeError(f"飞书返回错误 code={loaded.get('code')}: {loaded.get('msg')}")
    return loaded


def tenant_access_token() -> str:
    app_id = env("FEISHU_APP_ID")
    app_secret = env("FEISHU_APP_SECRET")
    if not app_id or not app_secret:
        return ""
    response = post_json(
        "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal",
        {"app_id": app_id, "app_secret": app_secret},
    )
    return str(response.get("tenant_access_token", ""))


def receive_target(token: str) -> dict[str, str]:
    candidates = [
        ("chat_id", env("FEISHU_CHAT_ID")),
        ("open_id", env("FEISHU_OPEN_ID")),
        ("user_id", env("FEISHU_USER_ID")),
        ("email", env("FEISHU_EMAIL")),
        ("mobile", env("FEISHU_MOBILE")),
    ]
    configured = [(target_type, value) for target_type, value in candidates if value]
    if len(configured) != 1:
        return {}
    target_type, value = configured[0]
    if target_type in {"chat_id", "open_id", "user_id"}:
        return {"type": target_type, "value": value}

    body = {"emails": [value]} if target_type == "email" else {"mobiles": [value]}
    response = post_json(
        "https://open.feishu.cn/open-apis/contact/v3/users/batch_get_id?user_id_type=open_id",
        body,
        {"Authorization": f"Bearer {token}"},
    )
    users = response.get("data", {}).get("user_list", [])
    open_id = str(users[0].get("open_id", "")) if users else ""
    return {"type": "open_id", "value": open_id} if open_id else {}


def send_markdown_with_api(title: str, markdown: str, template: str) -> None:
    token = tenant_access_token()
    if not token:
        return
    target = receive_target(token)
    if not target:
        return
    card = {
        "schema": "2.0",
        "config": {"update_multi": True},
        "body": {
            "direction": "vertical",
            "padding": "12px 12px 12px 12px",
            "elements": [{"tag": "markdown", "content": markdown, "text_align": "left", "text_size": "normal_v2"}],
        },
        "header": {
            "title": {"tag": "plain_text", "content": title},
            "template": template,
            "padding": "12px 12px 12px 12px",
        },
    }
    query = urllib.parse.urlencode({"receive_id_type": target["type"]})
    post_json(
        f"https://open.feishu.cn/open-apis/im/v1/messages?{query}",
        {"receive_id": target["value"], "msg_type": "interactive", "content": json.dumps(card, ensure_ascii=False)},
        {"Authorization": f"Bearer {token}"},
    )


def build_send_title(context: dict[str, Any]) -> str:
    title = str(context.get("title_summary", "")) or str(context.get("event", ""))
    project = str(context.get("project", ""))
    if project and not title.startswith(f"[{project}]"):
        title = f"[{project}] {title}"
    return title


def handle(context: dict[str, Any]) -> None:
    load_plugin_env()
    if not enabled(env("FEISHU_CODEX_HOOK_ENABLE_PUSH", "false")):
        return

    send_markdown(build_send_title(context), build_markdown(context))

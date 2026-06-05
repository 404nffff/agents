#!/usr/bin/env python3
"""Codex hooks 通用入口。

入口职责保持很薄：读取 payload、归一事件、写脱敏日志、按事件调用插件。
具体动作由插件完成，例如 `plugins/feishu/hook.py` 负责飞书通知。
"""

from __future__ import annotations

import importlib
import json
import os
import re
import shlex
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_ENV_FILE = SCRIPT_DIR / ".env"
DEFAULT_LOG_PATH = SCRIPT_DIR / "codex_hook_payload.log"
DEFAULT_ERROR_LOG_PATH = SCRIPT_DIR / "codex_hook_error.log"
DEFAULT_TITLE_STATE_PATH = SCRIPT_DIR / "codex_hook_title_state.json"

SUPPORTED_EVENTS = {
    "SessionStart",
    "SubagentStart",
    "PreToolUse",
    "PermissionRequest",
    "PostToolUse",
    "PreCompact",
    "PostCompact",
    "UserPromptSubmit",
    "SubagentStop",
    "Stop",
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


def clean_title_summary(value: Any, limit: int = 40) -> str:
    if value is None:
        return ""
    if not isinstance(value, str):
        value = json.dumps(value, ensure_ascii=False, sort_keys=True)
    lines = []
    for line in value.replace("\r", "\n").split("\n"):
        line = line.strip()
        line = re.sub(r"^#{1,6}\s+", "", line)
        line = re.sub(r"^[-+*]\s+", "", line)
        line = re.sub(r"^\d+\.\s+", "", line)
        line = re.sub(r"^>\s+", "", line)
        if line:
            lines.append(line)
    text = " ".join(lines)
    text = re.sub(r"[`*#>\[\]\(\)~]+", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text[:limit].rstrip() if len(text) > limit else text


def strip_forwarded_title_prefix(value: str) -> str:
    text = value.strip()
    text = re.sub(r"^\[[^\]]+\]\s+.+?\b\d{2}:\d{2}:\d{2}\s+", "", text, count=1)
    text = re.sub(r"^[，,。:：;；、\-\s]+", "", text)
    return text.strip()


def title_from_prompt(prompt: str) -> str:
    return clean_title_summary(strip_forwarded_title_prefix(prompt), 40)


def title_state_path() -> Path:
    return Path(env("CODEX_HOOK_TITLE_STATE_PATH", str(DEFAULT_TITLE_STATE_PATH)) or str(DEFAULT_TITLE_STATE_PATH))


def read_title_state() -> dict[str, Any]:
    path = title_state_path()
    if not path.exists():
        return {}
    try:
        loaded = json.loads(path.read_text(encoding="utf-8"))
        return loaded if isinstance(loaded, dict) else {}
    except Exception:
        return {}


def write_title_state(data: dict[str, Any]) -> None:
    path = title_state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def state_key(session_id: str, turn_id: str) -> str:
    return f"{session_id}:{turn_id}"


def set_title_state(session_id: str, turn_id: str, title: str) -> None:
    if not session_id or not turn_id or not title:
        return
    data = read_title_state()
    # Codex 可能在前一轮 Stop 前收到下一轮 UserPromptSubmit；保留多个 turn，避免提前删掉待完成标题。
    data[state_key(session_id, turn_id)] = {"session_id": session_id, "turn_id": turn_id, "title": title}
    write_title_state(dict(list(data.items())[-50:]))


def get_title_state(session_id: str, turn_id: str) -> str:
    if not session_id or not turn_id:
        return ""
    value = read_title_state().get(state_key(session_id, turn_id), {})
    title = value.get("title", "") if isinstance(value, dict) else ""
    return title if isinstance(title, str) else ""


def clear_title_state(session_id: str, turn_id: str) -> None:
    if not session_id or not turn_id:
        return
    data = read_title_state()
    if data.pop(state_key(session_id, turn_id), None) is not None:
        write_title_state(data)


def hook_event_name(payload: dict[str, Any]) -> str:
    return first_text(payload, "hook_event_name", "hookEventName", "event_name", "eventName", "type")


def project_name(cwd: str) -> str:
    if not cwd:
        return ""
    normalized = os.path.normpath(cwd)
    return os.path.basename(normalized)


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


def build_payload_log_entry(payload: dict[str, Any]) -> str:
    entry = {
        "logged_at": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        "event": hook_event_name(payload),
        "cwd": first_text(payload, "cwd"),
        "payload": redact(payload),
    }
    return json.dumps(entry, ensure_ascii=False)


def build_title_summary(payload: dict[str, Any], event: str) -> str:
    session_id = first_text(payload, "session_id", "sessionId")
    turn_id = first_text(payload, "turn_id", "turnId")
    tool_name = first_text(payload, "tool_name", "toolName")
    tool_input = payload.get("tool_input")
    command_text = ""
    if isinstance(tool_input, dict):
        command_text = first_text(tool_input, "cmd", "command")

    prompt = first_text(payload, "prompt")
    last_message = first_text(payload, "last_assistant_message", "lastAssistantMessage")
    subagent = payload.get("subagent") if isinstance(payload.get("subagent"), dict) else {}
    agent_type = first_text(payload, "agent_type", "agentType") or nested_text(subagent, "agent_type", "agentType")

    if event in {"PreToolUse", "PostToolUse"}:
        return clean_title_summary(command_text or tool_name, 40)
    if event == "PermissionRequest":
        return clean_title_summary(tool_name, 32)
    if event == "UserPromptSubmit":
        title = title_from_prompt(prompt)
        set_title_state(session_id, turn_id, title)
        return title
    if event == "Stop":
        return get_title_state(session_id, turn_id) or clean_title_summary(last_message, 24)
    if event in {"SubagentStart", "SubagentStop"}:
        return clean_title_summary(agent_type or tool_name, 32)
    return ""


def build_context(raw: str, payload: dict[str, Any]) -> dict[str, Any]:
    event = hook_event_name(payload)
    cwd = first_text(payload, "cwd")
    session_id = first_text(payload, "session_id", "sessionId")
    turn_id = first_text(payload, "turn_id", "turnId")
    title_summary = build_title_summary(payload, event)
    return {
        "raw": raw,
        "payload": payload,
        "event": event,
        "project": project_name(cwd),
        "session_id": session_id,
        "turn_id": turn_id,
        "title_summary": title_summary,
    }


def load_env_file() -> None:
    env_file = Path(env("CODEX_HOOK_ENV_FILE", str(DEFAULT_ENV_FILE)) or str(DEFAULT_ENV_FILE))
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


def read_payload() -> str:
    if len(sys.argv) > 1 and sys.argv[1]:
        candidate = Path(sys.argv[1])
        if candidate.is_file():
            return candidate.read_text(encoding="utf-8")
        return sys.argv[1]
    return sys.stdin.read()


def write_payload_log(payload: dict[str, Any]) -> None:
    if not enabled(env("CODEX_HOOK_LOG_PAYLOAD", "true")):
        return
    log_path = Path(env("CODEX_HOOK_PAYLOAD_LOG_PATH", str(DEFAULT_LOG_PATH)) or str(DEFAULT_LOG_PATH))
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("a", encoding="utf-8") as handle:
        handle.write(build_payload_log_entry(payload) + "\n")


def write_error_log(event: str, plugin: str, error: Exception) -> None:
    if not enabled(env("CODEX_HOOK_LOG_ERRORS", "true")):
        return
    log_path = Path(env("CODEX_HOOK_ERROR_LOG_PATH", str(DEFAULT_ERROR_LOG_PATH)) or str(DEFAULT_ERROR_LOG_PATH))
    log_path.parent.mkdir(parents=True, exist_ok=True)
    entry = {
        "logged_at": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        "event": event,
        "plugin": plugin,
        # 错误日志只记录异常类型和简短文本，避免把 payload 或环境变量写入磁盘。
        "error_type": type(error).__name__,
        "error": clean_title_summary(str(error), 160),
    }
    with log_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry, ensure_ascii=False) + "\n")


def trim_payload_log() -> None:
    log_path = Path(env("CODEX_HOOK_PAYLOAD_LOG_PATH", str(DEFAULT_LOG_PATH)) or str(DEFAULT_LOG_PATH))
    if not log_path.exists():
        return
    try:
        keep_lines = int(env("CODEX_HOOK_PAYLOAD_LOG_KEEP_LINES", "50"))
    except ValueError:
        keep_lines = 50
    lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
    log_path.write_text("\n".join(lines[-keep_lines:]) + ("\n" if lines else ""), encoding="utf-8")


def trim_error_log() -> None:
    log_path = Path(env("CODEX_HOOK_ERROR_LOG_PATH", str(DEFAULT_ERROR_LOG_PATH)) or str(DEFAULT_ERROR_LOG_PATH))
    if not log_path.exists():
        return
    try:
        keep_lines = int(env("CODEX_HOOK_ERROR_LOG_KEEP_LINES", "50"))
    except ValueError:
        keep_lines = 50
    lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
    log_path.write_text("\n".join(lines[-keep_lines:]) + ("\n" if lines else ""), encoding="utf-8")


def event_plugins(event: str) -> list[str]:
    """按 `事件:插件1,插件2;事件2:插件3` 解析当前事件插件列表。"""
    raw = env("CODEX_HOOK_EVENTS", "")
    result: list[str] = []
    for item in raw.split(";"):
        item = item.strip()
        if not item or ":" not in item:
            continue
        event_name, plugin_text = item.split(":", 1)
        if event_name.strip() not in {event, "*"}:
            continue
        for plugin_name in plugin_text.split(","):
            plugin_name = plugin_name.strip()
            if plugin_name and re.fullmatch(r"[A-Za-z0-9_-]+", plugin_name):
                result.append(plugin_name.replace("-", "_"))
    return result


def dispatch_plugins(context: dict[str, Any], names: list[str]) -> None:
    for name in names:
        try:
            module = importlib.import_module(f"plugins.{name}.hook")
            module.handle(context)
        except Exception as error:
            # Hook 动作不能污染 stdout，也不能阻断 Codex 主流程；错误写入脱敏日志便于本地排查。
            write_error_log(str(context.get("event", "")), name, error)
            continue


def main() -> int:
    load_env_file()
    raw = read_payload()
    if not raw.strip():
        return 0
    try:
        payload = json.loads(raw)
    except Exception:
        return 0
    if not isinstance(payload, dict):
        return 0

    event = hook_event_name(payload)
    if event not in SUPPORTED_EVENTS:
        return 0
    context = build_context(raw, payload)
    names = event_plugins(event)
    if not names:
        return 0

    write_payload_log(payload)
    dispatch_plugins(context, names)
    if event == "Stop":
        clear_title_state(context.get("session_id", ""), context.get("turn_id", ""))
        trim_payload_log()
        trim_error_log()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

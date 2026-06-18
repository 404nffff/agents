#!/usr/bin/env python3
"""Codex hook 计时器插件。

在 `UserPromptSubmit` 记录发送时间，在 `Stop` 记录结束时间并计算本轮耗时。
状态文件只保留最近一次记录，避免长期累积本地运行痕迹。
"""

from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


PLUGIN_DIR = Path(__file__).resolve().parent
SCRIPT_DIR = PLUGIN_DIR.parent.parent
DEFAULT_STATE_PATH = SCRIPT_DIR / "codex_hook_timer_state.json"
DEFAULT_KEEP_ENTRIES = 50


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


def state_path() -> Path:
    return Path(env("CODEX_HOOK_TIMER_STATE_PATH", str(DEFAULT_STATE_PATH)) or str(DEFAULT_STATE_PATH))


def now_time() -> datetime:
    return datetime.now(timezone.utc).astimezone()


def read_state() -> dict[str, Any]:
    path = state_path()
    if not path.exists():
        return {}
    try:
        loaded = json.loads(path.read_text(encoding="utf-8"))
        return loaded if isinstance(loaded, dict) else {}
    except Exception:
        return {}


def write_state(data: dict[str, Any]) -> None:
    path = state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    # 按 session_id:turn_id 保留多个并发会话，避免 Stop 时找不到对应开始时间。
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def parse_time(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        return datetime.fromisoformat(value)
    except ValueError:
        return None


def same_turn(state: dict[str, Any], context: dict[str, Any]) -> bool:
    session_id = str(context.get("session_id", "") or "")
    turn_id = str(context.get("turn_id", "") or "")
    state_session_id = str(state.get("session_id", "") or "")
    state_turn_id = str(state.get("turn_id", "") or "")
    if session_id and state_session_id and session_id != state_session_id:
        return False
    if turn_id and state_turn_id and turn_id != state_turn_id:
        return False
    return True


def state_key(context: dict[str, Any]) -> str:
    session_id = str(context.get("session_id", "") or "")
    turn_id = str(context.get("turn_id", "") or "")
    return f"{session_id}:{turn_id}"


def state_entries(state: dict[str, Any]) -> dict[str, Any]:
    entries = state.get("entries")
    if isinstance(entries, dict):
        return entries
    if state.get("started_at"):
        key = f"{state.get('session_id', '')}:{state.get('turn_id', '')}"
        return {key: state}
    return {}


def keep_entries_limit() -> int:
    try:
        return max(int(env("CODEX_HOOK_TIMER_KEEP_ENTRIES", str(DEFAULT_KEEP_ENTRIES)) or str(DEFAULT_KEEP_ENTRIES)), 1)
    except ValueError:
        return DEFAULT_KEEP_ENTRIES


def trim_entries(entries: dict[str, Any]) -> dict[str, Any]:
    limit = keep_entries_limit()
    ordered = sorted(
        entries.items(),
        key=lambda item: str(item[1].get("updated_at", "") or item[1].get("started_at", "")) if isinstance(item[1], dict) else "",
    )
    return dict(ordered[-limit:])


def elapsed_label(milliseconds: int) -> str:
    milliseconds = max(milliseconds, 0)
    total_seconds = int(milliseconds / 1000 + 0.5)
    if total_seconds < 60:
        return f"{total_seconds}s"
    minutes = total_seconds // 60
    seconds = total_seconds % 60
    return f"{minutes}m {seconds:02d}s"


def record_start(context: dict[str, Any]) -> None:
    started_at = now_time().isoformat(timespec="milliseconds")
    state = read_state()
    entries = state_entries(state)
    key = state_key(context)
    entries[key] = {
        "session_id": str(context.get("session_id", "") or ""),
        "turn_id": str(context.get("turn_id", "") or ""),
        "project": str(context.get("project", "") or ""),
        "title_summary": str(context.get("title_summary", "") or ""),
        "started_at": started_at,
        "updated_at": started_at,
    }
    write_state({"latest_key": key, "entries": trim_entries(entries)})


def record_stop(context: dict[str, Any]) -> None:
    state = read_state()
    entries = state_entries(state)
    key = state_key(context)
    entry = entries.get(key)
    entry = entry if isinstance(entry, dict) else {}
    started = parse_time(entry.get("started_at"))
    if not started or not same_turn(entry, context):
        return

    ended = now_time()
    elapsed_ms = max(int((ended - started).total_seconds() * 1000), 0)
    label = elapsed_label(elapsed_ms)
    entry.update(
        {
            "ended_at": ended.isoformat(timespec="milliseconds"),
            "elapsed_ms": elapsed_ms,
            "elapsed": label,
            "updated_at": ended.isoformat(timespec="milliseconds"),
        }
    )
    entries[key] = entry
    write_state({"latest_key": key, "entries": trim_entries(entries)})
    # 同一进程内后续插件可直接从 context 读取耗时，例如飞书插件。
    context["codex_timer_started_at"] = entry.get("started_at", "")
    context["codex_timer_ended_at"] = entry.get("ended_at", "")
    context["codex_timer_elapsed_ms"] = elapsed_ms
    context["codex_timer_elapsed_label"] = label


def handle(context: dict[str, Any]) -> None:
    event = str(context.get("event", "") or "")
    if event == "UserPromptSubmit":
        record_start(context)
    elif event == "Stop":
        record_stop(context)

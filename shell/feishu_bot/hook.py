#!/usr/bin/env python3
"""Codex 会话标题更新 hook。

只处理两类事件：
- UserPromptSubmit：提取并缓存本轮用户输入标题。
- Stop：读取缓存标题，通过 Codex 官方 app-server JSON-RPC `thread/name/set`
  更新会话标题，然后清理缓存。

默认不开启标题更新；需在 `.env` 或环境变量中设置：
`FEISHU_CODEX_HOOK_UPDATE_SESSION_TITLE=true`。
"""

from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_ENV_FILE = SCRIPT_DIR / ".env"
LEGACY_ENV_FILE = SCRIPT_DIR / "feishu.env"
TITLE_EVENTS = ("UserPromptSubmit", "Stop")


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


def enabled(value: str) -> bool:
    return value.lower() in {"1", "true", "yes", "on"}


def load_env_file() -> None:
    env_file = Path(env("FEISHU_ENV_FILE", env("FEISHU_BOT_ENV_FILE", str(DEFAULT_ENV_FILE))))
    if env_file == DEFAULT_ENV_FILE and not env_file.exists() and LEGACY_ENV_FILE.exists():
        env_file = LEGACY_ENV_FILE
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


def first_text(payload: dict[str, Any], *names: str) -> str:
    for name in names:
        value = payload.get(name)
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


def extract_last_prompt_segment(value: str) -> str:
    parts = re.split(r"[\n。！？!?]+", value)
    segments = [part.strip(" ，,。:：;；、-") for part in parts if part.strip(" ，,。:：;；、-")]
    return segments[-1] if segments else value.strip()


def title_from_prompt(prompt: str) -> str:
    prompt = strip_forwarded_title_prefix(prompt)
    prompt = extract_last_prompt_segment(prompt)
    return clean_title_summary(prompt, 40)


def title_state_path() -> Path:
    return Path(env("FEISHU_CODEX_HOOK_TITLE_STATE_PATH", str(SCRIPT_DIR / "codex_hook_title_state.json")))


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
    # 同一会话只保留当前待完成 turn 的标题，避免旧 turn 残留干扰后续 Stop。
    stale_keys = [
        key
        for key, value in data.items()
        if isinstance(value, dict)
        and value.get("session_id") == session_id
        and key != state_key(session_id, turn_id)
    ]
    for key in stale_keys:
        data.pop(key, None)
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


def thread_ids_from(session_id: str, transcript_path: str) -> list[str]:
    candidates = []
    if session_id:
        candidates.append(session_id)
    match = re.search(r"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$", transcript_path)
    if match:
        candidates.append(match.group(1))
    result = []
    for item in candidates:
        if item and item not in result:
            result.append(item)
    return result


def update_codex_session_title(session_id: str, transcript_path: str, title: str) -> bool:
    if not enabled(env("FEISHU_CODEX_HOOK_UPDATE_SESSION_TITLE", "false")) or not title.strip():
        return True
    if not shutil.which("codex"):
        return False

    thread_ids = thread_ids_from(session_id, transcript_path)
    if not thread_ids:
        return False
    messages = [
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "clientInfo": {"name": "codex-title-hook", "version": "1"},
                "subscribeToNotifications": [],
            },
        }
    ]
    for index, thread_id in enumerate(thread_ids, start=2):
        messages.append(
            {
                "jsonrpc": "2.0",
                "id": index,
                "method": "thread/name/set",
                "params": {"threadId": thread_id, "name": title.strip()},
            }
        )

    proc: subprocess.Popen[str] | None = None
    try:
        timeout = float(env("FEISHU_CODEX_HOOK_CODEX_APP_SERVER_TIMEOUT", "5"))
        drain_seconds = float(env("FEISHU_CODEX_HOOK_CODEX_APP_SERVER_DRAIN_SECONDS", "0.5"))
        request = "\n".join(json.dumps(item, ensure_ascii=False) for item in messages) + "\n"
        proc = subprocess.Popen(
            ["codex", "app-server", "--listen", "stdio://"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert proc.stdin is not None
        proc.stdin.write(request)
        proc.stdin.flush()
        # app-server 需要在 stdin 关闭前完成异步调度；立即关闭会导致请求被吞掉。
        time.sleep(max(0.0, drain_seconds))
        proc.stdin.close()
        proc.stdin = None
        stdout, _stderr = proc.communicate(timeout=timeout)
        return has_successful_title_update(stdout, len(thread_ids))
    except subprocess.TimeoutExpired:
        if proc is not None:
            proc.kill()
            proc.communicate()
        return False
    except Exception:
        if proc is not None and proc.poll() is None:
            proc.kill()
        return False


def has_successful_title_update(stdout: str, expected_updates: int) -> bool:
    if expected_updates <= 0:
        return False
    success_count = 0
    for line in stdout.splitlines():
        try:
            item = json.loads(line)
        except Exception:
            continue
        if not isinstance(item, dict):
            continue
        if item.get("method") == "thread/name/updated":
            success_count += 1
            continue
        if isinstance(item.get("result"), dict) and isinstance(item.get("id"), int) and item["id"] >= 2:
            success_count += 1
    return success_count > 0


def read_payload() -> str:
    if len(sys.argv) > 1 and sys.argv[1]:
        return sys.argv[1]
    return sys.stdin.read()


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

    event = first_text(payload, "hook_event_name", "hookEventName", "event_name", "eventName", "type")
    if event not in TITLE_EVENTS:
        return 0

    session_id = first_text(payload, "session_id", "sessionId")
    turn_id = first_text(payload, "turn_id", "turnId")
    if event == "UserPromptSubmit":
        set_title_state(session_id, turn_id, title_from_prompt(first_text(payload, "prompt")))
        return 0

    title = get_title_state(session_id, turn_id)
    if not title:
        title = clean_title_summary(first_text(payload, "last_assistant_message", "lastAssistantMessage"), 40)
    if update_codex_session_title(session_id, first_text(payload, "transcript_path", "transcriptPath"), title):
        clear_title_state(session_id, turn_id)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

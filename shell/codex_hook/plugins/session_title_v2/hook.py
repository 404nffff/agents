#!/usr/bin/env python3
"""Codex 会话标题 v2 插件。

插件在 Stop 事件读取当前会话 transcript，把会话内容发送给兼容 OpenAI
Chat Completions 的第三方 AI，总结出短标题后通过 Codex app-server 更新标题。
"""

from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


PLUGIN_DIR = Path(__file__).resolve().parent
DEFAULT_ENV_FILE = PLUGIN_DIR / ".env"
DEFAULT_LOG_PATH = PLUGIN_DIR / "session_title_v2.log"
DEFAULT_TRANSCRIPT_ROOT = Path.home() / ".codex" / "sessions"
TITLE_EVENTS = {"Stop"}


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


def enabled(value: str) -> bool:
    return value.strip().lower() not in {"0", "false", "no", "off"}


def safe_log_value(value: Any) -> Any:
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    if isinstance(value, Path):
        return str(value)
    return str(value)


def write_log(stage: str, **fields: Any) -> None:
    if not enabled(env("SESSION_TITLE_V2_LOG", "true")):
        return
    log_path = Path(env("SESSION_TITLE_V2_LOG_PATH", str(DEFAULT_LOG_PATH)) or str(DEFAULT_LOG_PATH))
    log_path.parent.mkdir(parents=True, exist_ok=True)
    entry = {
        "logged_at": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        "stage": stage,
    }
    # 日志只记录执行状态和长度信息，避免写入 API Key、payload 原文或 transcript 内容。
    entry.update({key: safe_log_value(value) for key, value in fields.items()})
    with log_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry, ensure_ascii=False) + "\n")
    trim_log(log_path)


def trim_log(log_path: Path) -> None:
    if not log_path.exists():
        return
    try:
        keep_lines = int(env("SESSION_TITLE_V2_LOG_KEEP_LINES", "100") or "100")
    except ValueError:
        keep_lines = 100
    if keep_lines <= 0:
        return
    lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
    log_path.write_text("\n".join(lines[-keep_lines:]) + ("\n" if lines else ""), encoding="utf-8")


def load_env_file() -> None:
    env_file = Path(env("SESSION_TITLE_V2_ENV_FILE", str(DEFAULT_ENV_FILE)) or str(DEFAULT_ENV_FILE))
    if not env_file.exists():
        write_log("env_file_missing", env_file=str(env_file))
        return
    loaded_keys: list[str] = []
    skipped_existing_keys: list[str] = []
    for raw_line in env_file.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if not key or key in os.environ:
            if key:
                skipped_existing_keys.append(key)
            continue
        try:
            parsed = shlex.split(value, comments=False, posix=True)
            value = parsed[0] if parsed else ""
        except ValueError:
            value = value.strip().strip("'\"")
        os.environ[key] = value
        loaded_keys.append(key)
    write_log(
        "env_file_loaded",
        env_file=str(env_file),
        loaded_keys=loaded_keys,
        skipped_existing_keys=skipped_existing_keys,
    )


def first_text(payload: dict[str, Any], *names: str) -> str:
    for name in names:
        value = payload.get(name)
        if value is not None and str(value):
            return str(value)
    return ""


def float_env(name: str, default: float) -> float:
    try:
        return float(env(name, str(default)))
    except ValueError:
        return default


def int_env(name: str, default: int) -> int:
    try:
        return int(env(name, str(default)))
    except ValueError:
        return default


def normalize_chat_url(raw_url: str) -> str:
    url = raw_url.strip().rstrip("/")
    if not url:
        return ""
    if url.endswith("/v1/chat/completions"):
        return url
    return f"{url}/v1/chat/completions"


def transcript_path_from(session_id: str, transcript_path: str) -> Path | None:
    if transcript_path:
        candidate = Path(transcript_path)
        if candidate.is_file():
            return candidate
    if not session_id:
        return None
    root = Path(env("SESSION_TITLE_V2_TRANSCRIPT_ROOT", str(DEFAULT_TRANSCRIPT_ROOT)) or str(DEFAULT_TRANSCRIPT_ROOT))
    if not root.exists():
        return None
    # Codex session 文件通常以 session_id 命名；递归搜索兼容日期分层目录。
    for candidate in root.rglob(f"{session_id}.jsonl"):
        if candidate.is_file():
            return candidate
    return None


def text_from_content(value: Any) -> str:
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return "\n".join(part for part in (text_from_content(item) for item in value) if part)
    if not isinstance(value, dict):
        return ""
    if isinstance(value.get("text"), str):
        return value["text"]
    if isinstance(value.get("content"), (str, list, dict)):
        return text_from_content(value["content"])
    if isinstance(value.get("message"), dict):
        return text_from_content(value["message"])
    if isinstance(value.get("item"), dict):
        return text_from_content(value["item"])
    return ""


def message_candidates(record: dict[str, Any]) -> list[dict[str, Any]]:
    candidates = [record]
    for key in ("payload", "message", "item"):
        value = record.get(key)
        if isinstance(value, dict):
            candidates.append(value)
    return candidates


def extract_transcript_text(path: Path, max_chars: int) -> str:
    messages: list[str] = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except Exception:
            continue
        if not isinstance(record, dict):
            continue
        for candidate in message_candidates(record):
            role = str(candidate.get("role", "")).lower()
            if role not in {"user", "assistant"}:
                continue
            content = text_from_content(candidate.get("content", candidate.get("text", ""))).strip()
            if not content:
                continue
            label = "用户" if role == "user" else "助手"
            messages.append(f"{label}: {content}")
            break
    text = "\n\n".join(messages)
    return text[-max_chars:] if len(text) > max_chars else text


def build_messages(transcript_text: str) -> list[dict[str, str]]:
    system_prompt = env(
        "SESSION_TITLE_V2_PROMPT",
        "你是会话标题生成器。请根据会话内容生成一个简短中文标题，最多20个汉字或40个字符。只输出标题，不要引号、标点解释或前后缀。",
    )
    return [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": f"会话内容如下：\n\n{transcript_text}"},
    ]


def request_openai_title(transcript_text: str) -> str:
    url = normalize_chat_url(env("SESSION_TITLE_V2_API_URL", ""))
    if not url:
        write_log("api_skipped", reason="missing_api_url")
        return ""
    body = {
        "model": env("SESSION_TITLE_V2_MODEL", "gpt-4o-mini"),
        "messages": build_messages(transcript_text),
        "temperature": float_env("SESSION_TITLE_V2_TEMPERATURE", 0.2),
        "max_tokens": int_env("SESSION_TITLE_V2_MAX_TOKENS", 32),
    }
    headers = {"Content-Type": "application/json"}
    api_key = env("SESSION_TITLE_V2_API_KEY", "")
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    request = urllib.request.Request(
        url,
        data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=float_env("SESSION_TITLE_V2_TIMEOUT", 10.0)) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as error:
        write_log("api_failed", error_type=type(error).__name__, error=str(error))
        raise RuntimeError(f"session_title_v2 API 请求失败: {error}") from error
    title = title_from_response(payload)
    write_log(
        "api_completed",
        api_url=url,
        model=body["model"],
        transcript_chars=len(transcript_text),
        title_chars=len(title),
        title_generated=bool(title),
    )
    return title


def title_from_response(payload: dict[str, Any]) -> str:
    choices = payload.get("choices")
    if not isinstance(choices, list) or not choices:
        return ""
    first = choices[0]
    if not isinstance(first, dict):
        return ""
    message = first.get("message")
    if isinstance(message, dict) and isinstance(message.get("content"), str):
        return clean_title(message["content"])
    if isinstance(first.get("text"), str):
        return clean_title(first["text"])
    return ""


def clean_title(value: str) -> str:
    text = value.strip().splitlines()[0].strip()
    text = re.sub(r"^标题[:：]\s*", "", text)
    text = text.strip("「」『』“”\"'`*# -_")
    text = re.sub(r"\s+", " ", text).strip()
    limit = int_env("SESSION_TITLE_V2_MAX_TITLE_CHARS", 40)
    return text[:limit].rstrip() if len(text) > limit else text


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
    if not title.strip():
        write_log("update_skipped", reason="empty_title")
        return False
    codex_bin = shutil.which("codex")
    if not codex_bin:
        write_log("update_skipped", reason="codex_not_found")
        return False
    thread_ids = thread_ids_from(session_id, transcript_path)
    if not thread_ids:
        write_log("update_skipped", reason="missing_thread_ids", session_id_present=bool(session_id))
        return False
    messages = [
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {"clientInfo": {"name": "codex-title-v2-hook", "version": "1"}, "subscribeToNotifications": []},
        }
    ]
    for index, thread_id in enumerate(thread_ids, start=2):
        messages.append({"jsonrpc": "2.0", "id": index, "method": "thread/name/set", "params": {"threadId": thread_id, "name": title.strip()}})
    proc: subprocess.Popen[str] | None = None
    try:
        request = "\n".join(json.dumps(item, ensure_ascii=False) for item in messages) + "\n"
        proc = subprocess.Popen(
            # Windows 下 npm shim 需先由 shutil.which 解析到 codex.CMD。
            [codex_bin, "app-server", "--listen", "stdio://"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert proc.stdin is not None
        proc.stdin.write(request)
        proc.stdin.flush()
        time.sleep(max(0.0, float_env("SESSION_TITLE_V2_CODEX_APP_SERVER_DRAIN_SECONDS", 0.5)))
        proc.stdin.close()
        proc.stdin = None
        stdout, _stderr = proc.communicate(timeout=float_env("SESSION_TITLE_V2_CODEX_APP_SERVER_TIMEOUT", 5.0))
        updated = has_successful_title_update(stdout, len(thread_ids))
        write_log("update_completed", updated=updated, thread_count=len(thread_ids), title_chars=len(title.strip()))
        return updated
    except subprocess.TimeoutExpired:
        if proc is not None:
            proc.kill()
            proc.communicate()
        write_log("update_failed", error_type="TimeoutExpired", thread_count=len(thread_ids))
        return False
    except Exception as error:
        if proc is not None and proc.poll() is None:
            proc.kill()
        write_log("update_failed", error_type=type(error).__name__, error=str(error), thread_count=len(thread_ids))
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


def handle(context: dict[str, Any]) -> None:
    event = str(context.get("event", ""))
    write_log("handle_received", event=event)
    if event not in TITLE_EVENTS:
        write_log("handle_skipped", reason="unsupported_event", event=event)
        return
    load_env_file()
    payload = context.get("payload")
    if not isinstance(payload, dict):
        write_log("handle_skipped", reason="invalid_payload")
        return
    session_id = first_text(payload, "session_id", "sessionId") or str(context.get("session_id", ""))
    transcript_path_text = first_text(payload, "transcript_path", "transcriptPath")
    write_log(
        "payload_ready",
        session_id_present=bool(session_id),
        transcript_path_present=bool(transcript_path_text),
    )
    path = transcript_path_from(session_id, transcript_path_text)
    if path is None:
        write_log("handle_skipped", reason="transcript_not_found", session_id_present=bool(session_id), transcript_path=transcript_path_text)
        return
    transcript_text = extract_transcript_text(path, int_env("SESSION_TITLE_V2_MAX_CONTEXT_CHARS", 12000))
    if not transcript_text:
        write_log("handle_skipped", reason="empty_transcript", transcript_path=str(path))
        return
    write_log("transcript_loaded", transcript_path=str(path), transcript_chars=len(transcript_text))
    title = request_openai_title(transcript_text)
    if title:
        write_log("title_generated", title=title, title_chars=len(title))
        context["session_title_v2_title"] = title
        context["session_title_v2_legacy_title"] = str(context.get("user_input", "") or context.get("title_summary", ""))
        updated = update_codex_session_title(session_id, str(path), title)
        context["session_title_v2_updated"] = updated
        write_log("handle_completed", updated=updated)
        return
    write_log("handle_skipped", reason="empty_title")

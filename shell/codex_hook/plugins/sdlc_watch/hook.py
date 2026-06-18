#!/usr/bin/env python3
"""sdlc-watch hook 插件入口。

默认只在 Stop 事件触发索引刷新，并把结果写入本地 JSONL 日志。
插件不返回 additionalContext，避免 Stop 事件 stdout 影响 Codex hook schema。
"""

from __future__ import annotations

import json
import os
import shlex
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from . import indexer


PLUGIN_DIR = Path(__file__).resolve().parent
SCRIPT_DIR = PLUGIN_DIR.parent.parent
DEFAULT_ENV_FILE = PLUGIN_DIR / ".env"
DEFAULT_LOG_PATH = SCRIPT_DIR / "codex_hook_sdlc_watch.log"


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


def enabled(value: str) -> bool:
    return value.strip().lower() not in {"0", "false", "no", "off"}


def load_plugin_env() -> None:
    """加载插件私有环境变量；只写入进程环境，不输出配置值。"""
    env_file = Path(env("SDLC_WATCH_ENV_FILE", str(DEFAULT_ENV_FILE)) or str(DEFAULT_ENV_FILE))
    if not env_file.exists():
        return
    for raw_line in env_file.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if not key or os.environ.get(key, ""):
            continue
        try:
            parsed = shlex.split(value, comments=False, posix=True)
            value = parsed[0] if parsed else ""
        except ValueError:
            value = value.strip().strip("'\"")
        os.environ[key] = value


def shorten(value: Any, limit: int = 1200) -> str:
    if value is None:
        return ""
    if not isinstance(value, str):
        value = json.dumps(value, ensure_ascii=False, sort_keys=True)
    text = value.strip()
    return text[:limit] + "...(已截断)" if len(text) > limit else text


def project_root(context: dict[str, Any]) -> Path:
    payload = context.get("payload")
    payload = payload if isinstance(payload, dict) else {}
    cwd = str(payload.get("cwd", "") or "")
    return Path(cwd).resolve() if cwd else Path.cwd().resolve()


def db_path() -> Path:
    configured = env("SDLC_WATCH_DB_PATH", "")
    return Path(configured).resolve() if configured else indexer.DEFAULT_DB_PATH


def docs_dir() -> str:
    return env("SDLC_WATCH_DOCS_DIR", "docs") or "docs"


def log_path() -> Path:
    configured = env("SDLC_WATCH_LOG_PATH", "")
    return Path(configured).resolve() if configured else DEFAULT_LOG_PATH


def write_log(stage: str, **fields: Any) -> None:
    if not enabled(env("SDLC_WATCH_LOG", "true")):
        return
    path = log_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    entry = {
        "logged_at": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        "stage": stage,
    }
    # 日志只写索引结果摘要，不写入文档全文。
    entry.update({key: shorten(value, 1000) for key, value in fields.items()})
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry, ensure_ascii=False) + "\n")
    trim_log(path)


def trim_log(path: Path) -> None:
    try:
        keep_lines = int(env("SDLC_WATCH_LOG_KEEP_LINES", "100") or "100")
    except ValueError:
        keep_lines = 100
    if keep_lines <= 0 or not path.exists():
        return
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    path.write_text("\n".join(lines[-keep_lines:]) + ("\n" if lines else ""), encoding="utf-8")


def should_handle_event(event: str) -> bool:
    events = env("SDLC_WATCH_EVENTS", "Stop") or "Stop"
    configured = {item.strip() for item in events.replace(";", ",").split(",") if item.strip()}
    return event in configured


def handle(context: dict[str, Any]) -> None:
    load_plugin_env()
    if not enabled(env("SDLC_WATCH_ENABLED", "true")):
        return None
    event = str(context.get("event", "") or "")
    if not should_handle_event(event):
        return None
    root = project_root(context)
    try:
        result = indexer.index_docs(root, db_path(), docs_dir())
        write_log(
            "index_completed",
            event=event,
            root=str(root),
            db_path=result.get("db_path", ""),
            scan_date=result.get("scan_date", ""),
            scanned_requirements=result.get("scanned_requirements", 0),
            scanned_documents=result.get("scanned_documents", 0),
            skipped_requirements=result.get("skipped_requirements", 0),
            skipped_files=result.get("skipped_files", 0),
            ai_status_enabled=result.get("ai_status_enabled", False),
            ai_status_generated=result.get("ai_status_generated", 0),
            ai_status_failed=result.get("ai_status_failed", 0),
            started_at=result.get("started_at", ""),
            finished_at=result.get("finished_at", ""),
        )
    except Exception as error:
        write_log("index_failed", event=event, root=str(root), error_type=type(error).__name__, error=str(error))
    return None

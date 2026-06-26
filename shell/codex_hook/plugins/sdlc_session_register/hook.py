#!/usr/bin/env python3
"""SDLC 会话登记插件。

职责：
- `SessionStart` 自动把当前会话身份写入 `docs/ai-register.db`。

插件只写本地 SQLite，不读取凭证文件，也不向外部网络发送内容。
阶段进度回填和历史查询由 `skills/software-dev-process-roles/scripts/sdlc_session_register.py` 负责。
"""

from __future__ import annotations

import json
import os
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


PLUGIN_DIR = Path(__file__).resolve().parent
SCRIPT_DIR = PLUGIN_DIR.parent.parent
DEFAULT_LOG_PATH = SCRIPT_DIR / "codex_hook_sdlc_session_register.log"
DEFAULT_DB_RELPATH = Path("docs") / "ai-register.db"


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


def enabled(value: str) -> bool:
    return value.strip().lower() not in {"0", "false", "no", "off"}


def first_text(payload: dict[str, Any], *names: str) -> str:
    for name in names:
        value = payload.get(name)
        if value is not None and str(value):
            return str(value)
    return ""


def now_str() -> str:
    """生成本地可读时间，用于登记库人工排查。"""
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def log_time() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def project_root(context: dict[str, Any] | None = None, cwd: str | None = None) -> Path:
    """按 hook payload 或 CLI 参数确定项目根目录。"""
    if cwd:
        return Path(cwd).resolve()
    payload = context.get("payload") if isinstance(context, dict) else {}
    payload = payload if isinstance(payload, dict) else {}
    payload_cwd = first_text(payload, "cwd")
    if payload_cwd:
        return Path(payload_cwd).resolve()
    return Path.cwd().resolve()


def default_db_path(root: Path) -> Path:
    return root / DEFAULT_DB_RELPATH


def db_path(root: Path, explicit: str | None = None) -> Path:
    configured = explicit or env("SDLC_SESSION_REGISTER_DB_PATH", "")
    return Path(configured).expanduser().resolve() if configured else default_db_path(root)


def log_path() -> Path:
    configured = env("SDLC_SESSION_REGISTER_LOG_PATH", "")
    return Path(configured).expanduser() if configured else DEFAULT_LOG_PATH


def write_log(stage: str, **fields: Any) -> None:
    if not enabled(env("SDLC_SESSION_REGISTER_LOG", "true")):
        return
    path = log_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    entry = {"logged_at": log_time(), "stage": stage, **fields}
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry, ensure_ascii=False, sort_keys=True) + "\n")
    trim_log(path)


def trim_log(path: Path) -> None:
    try:
        keep_lines = max(int(env("SDLC_SESSION_REGISTER_LOG_KEEP_LINES", "100") or "100"), 1)
    except ValueError:
        keep_lines = 100
    if not path.exists():
        return
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    path.write_text("\n".join(lines[-keep_lines:]) + ("\n" if lines else ""), encoding="utf-8")


def ensure_db(path: Path) -> sqlite3.Connection:
    """建库建表并开启 WAL，减少多会话同时写入时的锁冲突。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(path), timeout=10)
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS ai_register (
          session_id   TEXT PRIMARY KEY,
          tool         TEXT,
          model        TEXT,
          resume_shell TEXT,
          resume_cli   TEXT,
          cwd          TEXT,
          task_dir     TEXT,
          feature      TEXT,
          progress     TEXT,
          source       TEXT,
          created_at   TEXT,
          updated_at   TEXT
        );
        """
    )
    conn.commit()
    return conn


def build_resume(tool: str | None, session_id: str) -> tuple[str, str]:
    """按工具生成可复制的续接命令。"""
    tool_name = (tool or "").lower()
    if "codex" in tool_name:
        return f"codex resume {session_id}", "/resume"
    if "claude" in tool_name:
        return f"claude -r {session_id}", f"/resume {session_id}"
    return f"codex resume {session_id}", "/resume"


def upsert_identity(
    path: Path,
    session_id: str,
    tool: str | None = None,
    model: str | None = None,
    cwd: str | None = None,
    source: str | None = None,
) -> bool:
    """写入/更新会话身份列，不覆盖任务进度列。"""
    if not session_id:
        return False
    resume_shell, resume_cli = build_resume(tool, session_id)
    ts = now_str()
    conn = ensure_db(path)
    try:
        conn.execute(
            """
            INSERT INTO ai_register
              (session_id, tool, model, resume_shell, resume_cli, cwd, source, created_at, updated_at)
            VALUES (?,?,?,?,?,?,?,?,?)
            ON CONFLICT(session_id) DO UPDATE SET
              tool=excluded.tool,
              model=excluded.model,
              resume_shell=excluded.resume_shell,
              resume_cli=excluded.resume_cli,
              cwd=excluded.cwd,
              source=excluded.source,
              updated_at=excluded.updated_at
            """,
            (session_id, tool, model, resume_shell, resume_cli, cwd, source, ts, ts),
        )
        conn.commit()
        return True
    finally:
        conn.close()


def additional_context(title: str, lines: list[str]) -> str:
    clean_lines = [line.strip() for line in lines if line and line.strip()]
    return "\n".join([f"SDLC 会话登记：{title}", *[f"- {line}" for line in clean_lines]])


def handle_session_start(context: dict[str, Any]) -> str:
    payload = context.get("payload")
    payload = payload if isinstance(payload, dict) else {}
    root = project_root(context)
    path = db_path(root)
    session_id = str(context.get("session_id", "") or first_text(payload, "session_id", "sessionId"))
    model = first_text(payload, "model", "model_name", "modelName")
    source = first_text(payload, "source", "hook_source", "hookSource")
    tool = first_text(payload, "tool", "client", "app") or env("SDLC_SESSION_REGISTER_TOOL", "Codex")
    ok = upsert_identity(path, session_id, tool=tool, model=model, cwd=str(root), source=source)
    write_log(
        "session_start",
        ok=ok,
        db_path=str(path),
        session_id=session_id[:8] if session_id else "",
        tool=tool,
        model=model,
    )
    if not ok:
        return additional_context("SessionStart 跳过", ["payload 中没有 session_id，无法写入登记库。"])
    return additional_context(
        "SessionStart 已登记",
        [
            f"登记库：`{path}`。",
            f"sessionId：`{session_id[:8]}`。",
            "后续阶段进度用 `skills/software-dev-process-roles/scripts/sdlc_session_register.py progress` 回填。",
        ],
    )


def handle(context: dict[str, Any]) -> str | None:
    """hook.py 插件入口。当前只在 SessionStart 自动登记身份。"""
    if not enabled(env("SDLC_SESSION_REGISTER_ENABLE", "true")):
        return None
    event = str(context.get("event", "") or "")
    if event == "SessionStart":
        return handle_session_start(context)
    return None


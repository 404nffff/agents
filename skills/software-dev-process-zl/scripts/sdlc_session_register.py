#!/usr/bin/env python3
"""SDLC 会话登记库辅助脚本。

本脚本归属 `software-dev-process-zl` Skill，负责手动身份登记、阶段进度回填和历史查询。
首次会话身份登记仍由 `shell/codex_hook/plugins/sdlc_session_register/hook.py`
在 `SessionStart` 事件中完成。
"""

from __future__ import annotations

import argparse
import os
import sqlite3
from datetime import datetime
from pathlib import Path
from typing import Any


DEFAULT_DB_RELPATH = Path("docs") / "ai-register.db"


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


def now_str() -> str:
    """生成本地可读时间，用于登记库人工排查。"""
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def project_root(cwd: str | None = None) -> Path:
    """按 CLI 参数确定项目根目录，未传时使用当前目录。"""
    if cwd:
        return Path(cwd).resolve()
    return Path.cwd().resolve()


def default_db_path(root: Path) -> Path:
    return root / DEFAULT_DB_RELPATH


def db_path(root: Path, explicit: str | None = None) -> Path:
    configured = explicit or env("SDLC_SESSION_REGISTER_DB_PATH", "")
    return Path(configured).expanduser().resolve() if configured else default_db_path(root)


def ensure_db(path: Path) -> sqlite3.Connection:
    """建库建表并开启 WAL，保持与 SessionStart 插件写入结构兼容。"""
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


def update_progress(
    path: Path,
    session_id: str,
    task_dir: str | None = None,
    feature: str | None = None,
    progress: str | None = None,
) -> bool:
    """回填 SDLC 任务进度，只更新显式传入字段。"""
    if not session_id:
        return False
    ts = now_str()
    conn = ensure_db(path)
    try:
        conn.execute(
            "INSERT OR IGNORE INTO ai_register (session_id, created_at, updated_at) VALUES (?,?,?)",
            (session_id, ts, ts),
        )
        sets: list[str] = []
        params: list[str] = []
        if task_dir is not None:
            sets.append("task_dir=?")
            params.append(task_dir)
        if feature is not None:
            sets.append("feature=?")
            params.append(feature)
        if progress is not None:
            sets.append("progress=?")
            params.append(progress)
        sets.append("updated_at=?")
        params.extend([ts, session_id])
        conn.execute(f"UPDATE ai_register SET {', '.join(sets)} WHERE session_id=?", params)
        conn.commit()
        return True
    finally:
        conn.close()


def query_rows(path: Path, task_dir: str | None = None, keyword: str | None = None) -> list[dict[str, Any]]:
    """只读查询登记库；库不存在时返回空列表。"""
    if not path.exists():
        return []
    conn = sqlite3.connect(str(path), timeout=10)
    try:
        conn.row_factory = sqlite3.Row
        if task_dir:
            cursor = conn.execute("SELECT * FROM ai_register WHERE task_dir=? ORDER BY updated_at DESC", (task_dir,))
        elif keyword:
            like = f"%{keyword}%"
            cursor = conn.execute(
                """
                SELECT * FROM ai_register
                WHERE task_dir LIKE ?
                   OR feature LIKE ?
                   OR cwd LIKE ?
                   OR source LIKE ?
                   OR session_id LIKE ?
                ORDER BY updated_at DESC
                """,
                (like, like, like, like, like),
            )
        else:
            cursor = conn.execute("SELECT * FROM ai_register ORDER BY updated_at DESC")
        return [dict(row) for row in cursor.fetchall()]
    finally:
        conn.close()


def render_table(rows: list[dict[str, Any]]) -> str:
    """把查询结果渲染为纯文本表格，避免依赖 sqlite3 命令行。"""
    if not rows:
        return "（登记库为空或不存在）"
    columns = [
        ("tool", "工具"),
        ("model", "模型"),
        ("session_id", "sessionId"),
        ("progress", "进度"),
        ("feature", "完成功能"),
        ("resume_shell", "resume(shell)"),
        ("task_dir", "任务目录"),
        ("updated_at", "更新时间"),
    ]

    def cell(row: dict[str, Any], key: str) -> str:
        value = "" if row.get(key) is None else str(row.get(key))
        return value[:8] if key == "session_id" and len(value) > 8 else value

    table = [[label for _, label in columns]]
    table.extend([[cell(row, key) for key, _ in columns] for row in rows])
    widths = [max(len(row[index]) for row in table) for index in range(len(columns))]

    def fmt(row: list[str]) -> str:
        return "  ".join(value.ljust(widths[index]) for index, value in enumerate(row))

    separator = "  ".join("-" * width for width in widths)
    return "\n".join([fmt(table[0]), separator, *[fmt(row) for row in table[1:]]])


def build_cli() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="SDLC 会话登记库辅助脚本")
    sub = parser.add_subparsers(dest="cmd", required=True)

    upsert = sub.add_parser("upsert", help="写入/更新身份列")
    upsert.add_argument("--db")
    upsert.add_argument("--cwd")
    upsert.add_argument("--session", required=True)
    upsert.add_argument("--tool", default="Codex")
    upsert.add_argument("--model")
    upsert.add_argument("--source")

    progress = sub.add_parser("progress", help="回填任务进度")
    progress.add_argument("--db")
    progress.add_argument("--cwd")
    progress.add_argument("--session", required=True)
    progress.add_argument("--task-dir")
    progress.add_argument("--feature")
    progress.add_argument("--progress")

    query = sub.add_parser("query", help="只读查询登记库")
    query.add_argument("--db")
    query.add_argument("--cwd")
    query.add_argument("--task-dir")
    query.add_argument("--keyword")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_cli().parse_args(argv)
    root = project_root(getattr(args, "cwd", None))
    path = db_path(root, getattr(args, "db", None))
    if args.cmd == "upsert":
        return 0 if upsert_identity(path, args.session, args.tool, args.model, str(root), args.source) else 1
    if args.cmd == "progress":
        return 0 if update_progress(path, args.session, args.task_dir, args.feature, args.progress) else 1
    if args.cmd == "query":
        print(render_table(query_rows(path, task_dir=args.task_dir, keyword=args.keyword)))
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""SDLC 文档 SQLite 索引器。

该模块只扫描项目 `docs/*` 下的白名单 Markdown 文档，不读取凭证类文件。
CLI 固定输出 JSON，方便 hook、Web 服务和测试脚本复用。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sqlite3
import sys
import urllib.error
import urllib.request
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any, Iterable


PLUGIN_DIR = Path(__file__).resolve().parent
DEFAULT_DB_PATH = PLUGIN_DIR / "sdlc_watch.sqlite3"
SENSITIVE_SUFFIXES = {".env", ".pem", ".key", ".ini", ".conf"}
ROOT_DOC_NAMES = {"status.md", "mini-plan.md", "summary.md"}
ONLY_AI_DOC_NAMES = {
    "context.md",
    "operations-log.md",
    "review.md",
    "review-report.md",
    "testing.md",
    "verification.md",
}
DATE_DIR_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
EXEC_RESULT_RE = re.compile(r"^\d{1,2}时\d{1,2}分\d{1,2}秒\.md$", re.IGNORECASE)
PROBE_REQUEST_TIME_RE = re.compile(r"\b(\d{4}-\d{2}-\d{2})[ T](\d{1,2}):(\d{2}):(\d{2})\b")


def now_text() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def local_date_from_timestamp(timestamp: float) -> date:
    """按本机时区把文件系统时间转为日期，避免 UTC 跨日误判。"""
    return datetime.fromtimestamp(timestamp, tz=timezone.utc).astimezone().date()


def today_local_date() -> date:
    """返回本机当前日期，索引器用它判定当天修改的需求目录。"""
    return datetime.now(timezone.utc).astimezone().date()


def json_default(value: Any) -> str:
    if isinstance(value, Path):
        return str(value)
    return str(value)


def normalize_probe_request_time(raw_value: str) -> str:
    """把探针文档里的请求时间统一转成 ISO 文本，便于 SQLite 排序。"""
    match = PROBE_REQUEST_TIME_RE.search(raw_value.strip())
    if not match:
        return ""
    date_text, hour, minute, second = match.groups()
    year, month, day = date_text.split("-")
    return f"{year}-{month}-{day}T{int(hour):02d}:{minute}:{second}"


def latest_probe_request_time(text: str) -> str:
    values = []
    for match in PROBE_REQUEST_TIME_RE.finditer(text):
        values.append(normalize_probe_request_time(match.group(0)))
    values = [item for item in values if item]
    return max(values) if values else ""


def print_json(payload: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(payload, ensure_ascii=False, default=json_default, separators=(",", ":")) + "\n")


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


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


def connect(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS requirements (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            slug TEXT NOT NULL UNIQUE,
            project_name TEXT NOT NULL DEFAULT '',
            title TEXT NOT NULL,
            root_path TEXT NOT NULL UNIQUE,
            status TEXT NOT NULL DEFAULT '',
            summary TEXT NOT NULL DEFAULT '',
            document_count INTEGER NOT NULL DEFAULT 0,
            indexed_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS documents (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            requirement_id INTEGER NOT NULL,
            relative_path TEXT NOT NULL UNIQUE,
            document_type TEXT NOT NULL,
            title TEXT NOT NULL DEFAULT '',
            content TEXT NOT NULL,
            sha256 TEXT NOT NULL,
            size_bytes INTEGER NOT NULL,
            mtime REAL NOT NULL,
            probe_request_time TEXT NOT NULL DEFAULT '',
            indexed_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY(requirement_id) REFERENCES requirements(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            root_path TEXT NOT NULL,
            docs_path TEXT NOT NULL,
            scanned_requirements INTEGER NOT NULL DEFAULT 0,
            scanned_documents INTEGER NOT NULL DEFAULT 0,
            skipped_files INTEGER NOT NULL DEFAULT 0,
            started_at TEXT NOT NULL,
            finished_at TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_documents_requirement_id ON documents(requirement_id);
        CREATE INDEX IF NOT EXISTS idx_documents_type ON documents(document_type);
        """
    )
    columns = {row["name"] for row in conn.execute("PRAGMA table_info(requirements)").fetchall()}
    if "project_name" not in columns:
        conn.execute("ALTER TABLE requirements ADD COLUMN project_name TEXT NOT NULL DEFAULT ''")
    document_columns = {row["name"] for row in conn.execute("PRAGMA table_info(documents)").fetchall()}
    if "probe_request_time" not in document_columns:
        conn.execute("ALTER TABLE documents ADD COLUMN probe_request_time TEXT NOT NULL DEFAULT ''")
    conn.commit()


def project_root_from(value: str) -> Path:
    if value:
        return Path(value).resolve()
    return Path.cwd().resolve()


def db_path_from(value: str) -> Path:
    return Path(value).resolve() if value else DEFAULT_DB_PATH


def is_sensitive(path: Path) -> bool:
    name = path.name.lower()
    suffix = path.suffix.lower()
    return name in SENSITIVE_SUFFIXES or suffix in SENSITIVE_SUFFIXES


def is_series_doc(name: str) -> bool:
    lowered = name.lower()
    if not lowered.endswith(".md") or len(lowered) < 4:
        return False
    prefix = lowered[:3]
    return prefix in {"001", "002", "003", "004", "005", "006"} and (len(lowered) == 3 or lowered[3] in {"-", "_", "."})


def is_probe_result(name: str) -> bool:
    return name.lower().endswith("_probe_result.md")


def is_exec_result_path(relative_parts: tuple[str, ...]) -> bool:
    """识别 work-php-exec 生成的日期批次执行结果。"""
    if len(relative_parts) < 3:
        return False
    return bool(DATE_DIR_RE.match(relative_parts[-2]) and EXEC_RESULT_RE.match(relative_parts[-1]))


def classify_document(requirement_dir: Path, path: Path) -> str:
    relative_parts = path.relative_to(requirement_dir).parts
    name = path.name.lower()
    if len(relative_parts) >= 2 and relative_parts[0].lower() == "onlyai":
        stem = Path(name).stem.lower()
        if stem == "review-report":
            return "review"
        if stem == "operations-log":
            return "operations"
        return stem
    if name in ROOT_DOC_NAMES:
        return Path(name).stem.lower()
    if is_probe_result(name):
        return "probe_result"
    if is_exec_result_path(relative_parts):
        return "exec_result"
    if is_series_doc(name):
        return name[:3]
    return "other"


def should_scan_file(requirement_dir: Path, path: Path) -> bool:
    if not path.is_file() or is_sensitive(path):
        return False
    try:
        relative_parts = path.relative_to(requirement_dir).parts
    except ValueError:
        return False
    name = path.name.lower()
    if len(relative_parts) == 1:
        return name in ROOT_DOC_NAMES or is_series_doc(name) or is_probe_result(name)
    if len(relative_parts) == 2 and relative_parts[0].lower() == "onlyai":
        return name in ONLY_AI_DOC_NAMES or is_probe_result(name)
    if is_exec_result_path(relative_parts):
        return True
    return False


def iter_requirement_dirs(docs_path: Path, modified_date: date | None = None) -> Iterable[Path]:
    if not docs_path.exists():
        return []
    dirs = sorted(path for path in docs_path.iterdir() if path.is_dir())
    if modified_date is None:
        return dirs
    return [path for path in dirs if local_date_from_timestamp(path.stat().st_mtime) == modified_date]


def iter_candidate_files(requirement_dir: Path) -> Iterable[Path]:
    for path in sorted(requirement_dir.rglob("*")):
        if should_scan_file(requirement_dir, path):
            yield path


def first_heading(text: str) -> str:
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if line.startswith("#"):
            return line.lstrip("#").strip()
    return ""


def status_from_text(text: str) -> str:
    for raw_line in text.splitlines()[:40]:
        line = raw_line.strip().strip("-*| ")
        lowered = line.lower()
        if not line:
            continue
        if line.startswith("状态") or line.startswith("当前状态") or lowered.startswith("status"):
            if "：" in line:
                return line.split("：", 1)[1].strip()
            if ":" in line:
                return line.split(":", 1)[1].strip()
            return line
    return ""


def normalize_chat_url(raw_url: str) -> str:
    url = raw_url.strip().rstrip("/")
    if not url:
        return ""
    if url.endswith("/v1/chat/completions"):
        return url
    return f"{url}/v1/chat/completions"


def ai_status_enabled() -> bool:
    return bool(normalize_chat_url(env("SDLC_WATCH_AI_API_URL", "")) and env("SDLC_WATCH_AI_MODEL", "").strip())


def title_from_ai_response(payload: dict[str, Any]) -> str:
    choices = payload.get("choices")
    if not isinstance(choices, list) or not choices:
        return ""
    first = choices[0]
    if not isinstance(first, dict):
        return ""
    message = first.get("message")
    if isinstance(message, dict):
        content = message.get("content")
        return str(content).strip() if content else ""
    text = first.get("text")
    return str(text).strip() if text else ""


def ai_status_source_records(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [record for record in records if record.get("document_type") == "status"]


def build_ai_status_prompt(requirement_dir: Path, records: list[dict[str, Any]]) -> str:
    parts = [
        "请根据以下 status.md 内容，总结这个需求当前状态。",
        "只输出一句中文状态说明，不要解释、不要 Markdown、不要引号，长度控制在 80 个中文字符以内。",
        f"需求目录：{requirement_dir.name}",
    ]
    for record in ai_status_source_records(records):
        parts.append(f"\n--- 文件：{record['relative_path']} ---\n{record['content']}")
    return "\n".join(parts)


def request_ai_status(requirement_dir: Path, records: list[dict[str, Any]]) -> str:
    url = normalize_chat_url(env("SDLC_WATCH_AI_API_URL", ""))
    model = env("SDLC_WATCH_AI_MODEL", "").strip()
    if not url or not model:
        return ""
    if not ai_status_source_records(records):
        return ""
    body = {
        "model": model,
        "messages": [
            {"role": "system", "content": "你是 SDLC 文档状态摘要器，只根据用户提供的 status.md 内容输出状态字段。"},
            {"role": "user", "content": build_ai_status_prompt(requirement_dir, records)},
        ],
        "temperature": float_env("SDLC_WATCH_AI_TEMPERATURE", 0.2),
        "max_tokens": int_env("SDLC_WATCH_AI_MAX_TOKENS", 120),
    }
    headers = {"Content-Type": "application/json"}
    api_key = env("SDLC_WATCH_AI_API_KEY", "")
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    request = urllib.request.Request(
        url,
        data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=float_env("SDLC_WATCH_AI_TIMEOUT", 20.0)) as response:
        payload = json.loads(response.read().decode("utf-8"))
    return title_from_ai_response(payload)


def summary_from_text(text: str, limit: int = 240) -> str:
    lines = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or line.startswith("```"):
            continue
        lines.append(line)
        if sum(len(item) for item in lines) >= limit:
            break
    summary = " ".join(lines)
    return summary[:limit].rstrip()


def file_record(root: Path, requirement_dir: Path, path: Path) -> dict[str, Any]:
    content = path.read_text(encoding="utf-8", errors="replace")
    stat = path.stat()
    data = content.encode("utf-8")
    document_type = classify_document(requirement_dir, path)
    return {
        "relative_path": path.relative_to(root).as_posix(),
        "document_type": document_type,
        "title": first_heading(content),
        "content": content,
        "sha256": hashlib.sha256(data).hexdigest(),
        "size_bytes": len(data),
        "mtime": stat.st_mtime,
        "probe_request_time": latest_probe_request_time(content) if document_type == "probe_result" else "",
    }


def project_name_for(root: Path) -> str:
    return root.name or str(root)


def requirement_slug(root: Path, docs_path: Path, requirement_dir: Path) -> str:
    try:
        relative = requirement_dir.relative_to(docs_path).as_posix()
    except ValueError:
        relative = requirement_dir.name
    return f"{project_name_for(root)}/{relative}"


def upsert_requirement(conn: sqlite3.Connection, slug: str, project_name: str, root_path: str, title: str, status: str, summary: str, document_count: int) -> int:
    current = now_text()
    conn.execute(
        """
        INSERT INTO requirements(slug,project_name,title,root_path,status,summary,document_count,indexed_at,updated_at)
        VALUES(?,?,?,?,?,?,?,?,?)
        ON CONFLICT(root_path) DO UPDATE SET
            slug=excluded.slug,
            project_name=excluded.project_name,
            title=excluded.title,
            status=excluded.status,
            summary=excluded.summary,
            document_count=excluded.document_count,
            updated_at=excluded.updated_at
        """,
        (slug, project_name, title, root_path, status, summary, document_count, current, current),
    )
    row = conn.execute("SELECT id FROM requirements WHERE root_path = ?", (root_path,)).fetchone()
    return int(row["id"])


def upsert_document(conn: sqlite3.Connection, requirement_id: int, record: dict[str, Any]) -> None:
    current = now_text()
    conn.execute(
        """
        INSERT INTO documents(
            requirement_id,relative_path,document_type,title,content,sha256,size_bytes,mtime,probe_request_time,indexed_at,updated_at
        )
        VALUES(?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(relative_path) DO UPDATE SET
            requirement_id=excluded.requirement_id,
            document_type=excluded.document_type,
            title=excluded.title,
            content=excluded.content,
            sha256=excluded.sha256,
            size_bytes=excluded.size_bytes,
            mtime=excluded.mtime,
            probe_request_time=excluded.probe_request_time,
            updated_at=excluded.updated_at
        """,
        (
            requirement_id,
            record["relative_path"],
            record["document_type"],
            record["title"],
            record["content"],
            record["sha256"],
            record["size_bytes"],
            record["mtime"],
            record["probe_request_time"],
            current,
            current,
        ),
    )


def row_dict(row: sqlite3.Row | None) -> dict[str, Any] | None:
    return dict(row) if row is not None else None


def index_docs(root: Path, db_path: Path, docs_dir: str) -> dict[str, Any]:
    docs_path = (root / docs_dir).resolve()
    started = now_text()
    modified_date = today_local_date()
    scanned_requirements = 0
    scanned_documents = 0
    skipped_files = 0
    ai_status_generated = 0
    ai_status_failed = 0

    conn = connect(db_path)
    try:
        init_schema(conn)
        all_requirement_dirs = list(iter_requirement_dirs(docs_path))
        requirement_dirs = [path for path in all_requirement_dirs if local_date_from_timestamp(path.stat().st_mtime) == modified_date]
        skipped_requirements = max(len(all_requirement_dirs) - len(requirement_dirs), 0)
        for requirement_dir in requirement_dirs:
            records = [file_record(root, requirement_dir, path) for path in iter_candidate_files(requirement_dir)]
            total_files = sum(1 for item in requirement_dir.rglob("*") if item.is_file())
            skipped_files += max(total_files - len(records), 0)
            if not records:
                continue
            by_type = {item["document_type"]: item for item in records}
            title = by_type.get("summary", {}).get("title") or by_type.get("mini-plan", {}).get("title") or requirement_dir.name
            status = status_from_text(by_type.get("status", {}).get("content", ""))
            if ai_status_enabled():
                try:
                    ai_status = request_ai_status(requirement_dir, records)
                except (urllib.error.URLError, TimeoutError, OSError, ValueError, json.JSONDecodeError):
                    ai_status_failed += 1
                else:
                    if ai_status:
                        status = ai_status
                        ai_status_generated += 1
                    else:
                        ai_status_failed += 1
            summary = summary_from_text(by_type.get("summary", {}).get("content", "") or by_type.get("mini-plan", {}).get("content", ""))
            requirement_id = upsert_requirement(
                conn,
                requirement_slug(root, docs_path, requirement_dir),
                project_name_for(root),
                requirement_dir.relative_to(root).as_posix(),
                title,
                status,
                summary,
                len(records),
            )
            for record in records:
                upsert_document(conn, requirement_id, record)
            scanned_requirements += 1
            scanned_documents += len(records)
        finished = now_text()
        conn.execute(
            """
            INSERT INTO runs(root_path,docs_path,scanned_requirements,scanned_documents,skipped_files,started_at,finished_at)
            VALUES(?,?,?,?,?,?,?)
            """,
            (str(root), docs_path.relative_to(root).as_posix() if docs_path.is_relative_to(root) else str(docs_path), scanned_requirements, scanned_documents, skipped_files, started, finished),
        )
        conn.commit()
    finally:
        conn.close()

    return {
        "ok": True,
        "db_path": str(db_path),
        "root": str(root),
        "docs_path": str(docs_path),
        "scanned_requirements": scanned_requirements,
        "scanned_documents": scanned_documents,
        "skipped_requirements": skipped_requirements,
        "skipped_files": skipped_files,
        "scan_date": modified_date.isoformat(),
        "ai_status_enabled": ai_status_enabled(),
        "ai_status_generated": ai_status_generated,
        "ai_status_failed": ai_status_failed,
        "started_at": started,
        "finished_at": finished,
    }


def list_requirements(db_path: Path, limit: int) -> dict[str, Any]:
    conn = connect(db_path)
    try:
        init_schema(conn)
        rows = conn.execute(
            """
            SELECT id,slug,project_name,title,root_path,status,summary,document_count,indexed_at,updated_at
            FROM requirements
            ORDER BY project_name ASC, updated_at DESC, slug ASC
            LIMIT ?
            """,
            (limit,),
        ).fetchall()
    finally:
        conn.close()
    return {"ok": True, "requirements": [dict(row) for row in rows]}


def get_requirement(db_path: Path, slug_or_id: str) -> dict[str, Any]:
    conn = connect(db_path)
    try:
        init_schema(conn)
        if slug_or_id.isdigit():
            requirement = conn.execute("SELECT * FROM requirements WHERE id = ?", (int(slug_or_id),)).fetchone()
        else:
            requirement = conn.execute("SELECT * FROM requirements WHERE slug = ?", (slug_or_id,)).fetchone()
        if requirement is None:
            return {"ok": False, "error": "requirement_not_found", "requirement": None, "documents": []}
        documents = conn.execute(
            """
            SELECT id,relative_path,document_type,title,sha256,size_bytes,mtime,probe_request_time,indexed_at,updated_at
            FROM documents
            WHERE requirement_id = ?
            ORDER BY COALESCE(NULLIF(probe_request_time,''), updated_at) DESC, relative_path ASC
            """,
            (int(requirement["id"]),),
        ).fetchall()
    finally:
        conn.close()
    return {"ok": True, "requirement": dict(requirement), "documents": [dict(row) for row in documents]}


def get_document(db_path: Path, document: str, include_content: bool) -> dict[str, Any]:
    conn = connect(db_path)
    try:
        init_schema(conn)
        if document.isdigit():
            row = conn.execute("SELECT * FROM documents WHERE id = ?", (int(document),)).fetchone()
        else:
            row = conn.execute("SELECT * FROM documents WHERE relative_path = ?", (document.replace("\\", "/"),)).fetchone()
    finally:
        conn.close()
    data = row_dict(row)
    if data is None:
        return {"ok": False, "error": "document_not_found", "document": None}
    if not include_content:
        data.pop("content", None)
    return {"ok": True, "document": data}


def search_documents(db_path: Path, query: str, limit: int) -> dict[str, Any]:
    if not query.strip():
        return {"ok": True, "query": query, "results": []}
    pattern = f"%{query.strip()}%"
    conn = connect(db_path)
    try:
        init_schema(conn)
        rows = conn.execute(
            """
            SELECT d.id,d.relative_path,d.document_type,d.title,d.size_bytes,d.updated_at,d.probe_request_time,r.id AS requirement_id,r.slug AS requirement_slug,r.project_name AS project_name,r.title AS requirement_title,d.content
            FROM documents d
            JOIN requirements r ON r.id = d.requirement_id
            WHERE d.content LIKE ? OR d.title LIKE ? OR d.relative_path LIKE ?
            ORDER BY COALESCE(NULLIF(d.probe_request_time,''), d.updated_at) DESC, d.relative_path ASC
            LIMIT ?
            """,
            (pattern, pattern, pattern, limit),
        ).fetchall()
    finally:
        conn.close()
    results = []
    lowered = query.strip().lower()
    for row in rows:
        item = dict(row)
        content = item.pop("content", "")
        position = content.lower().find(lowered)
        if position < 0:
            snippet = summary_from_text(content, 180)
        else:
            start = max(position - 70, 0)
            end = min(position + len(query) + 110, len(content))
            snippet = content[start:end].replace("\n", " ").strip()
        item["snippet"] = snippet
        results.append(item)
    return {"ok": True, "query": query, "results": results}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Index and query SDLC docs.")
    parser.add_argument("--root", default="", help="项目根目录，默认当前工作目录")
    parser.add_argument("--db", default=os.environ.get("SDLC_WATCH_DB_PATH", ""), help="SQLite 文件路径")
    parser.add_argument("--docs-dir", default="docs", help="项目根下的 docs 目录名")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("index", help="扫描 docs 并写入索引")

    list_parser = subparsers.add_parser("list-requirements", help="列出需求")
    list_parser.add_argument("--limit", type=int, default=100)

    get_req = subparsers.add_parser("get-requirement", help="读取需求详情")
    get_req.add_argument("requirement")

    get_doc = subparsers.add_parser("get-document", help="读取文档详情")
    get_doc.add_argument("document")
    get_doc.add_argument("--content", action="store_true", help="返回全文")

    search = subparsers.add_parser("search", help="搜索文档")
    search.add_argument("query")
    search.add_argument("--limit", type=int, default=20)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    root = project_root_from(args.root)
    db_path = db_path_from(args.db)
    try:
        if args.command == "index":
            payload = index_docs(root, db_path, args.docs_dir)
        elif args.command == "list-requirements":
            payload = list_requirements(db_path, max(args.limit, 1))
        elif args.command == "get-requirement":
            payload = get_requirement(db_path, args.requirement)
        elif args.command == "get-document":
            payload = get_document(db_path, args.document, args.content)
        elif args.command == "search":
            payload = search_documents(db_path, args.query, max(args.limit, 1))
        else:
            payload = {"ok": False, "error": "unknown_command"}
    except Exception as error:
        payload = {"ok": False, "error": type(error).__name__, "message": str(error)}
    print_json(payload)
    return 0 if payload.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())

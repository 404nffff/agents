#!/usr/bin/env python3
"""ai-localbase 压缩记忆插件。

插件只负责在 Codex 压缩生命周期中调用 `~/.codex/skills/ai-localbase`
统一入口：PreCompact 上传压缩检查点，PostCompact 读取知识库记忆并返回
additionalContext。凭证加载、知识库映射和网络请求都交给 skill 脚本处理。
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


PLUGIN_DIR = Path(__file__).resolve().parent
SCRIPT_DIR = PLUGIN_DIR.parent.parent
DEFAULT_STATE_PATH = SCRIPT_DIR / "codex_hook_ai_localbase_state.json"
DEFAULT_LOG_PATH = SCRIPT_DIR / "codex_hook_ai_localbase.log"
DEFAULT_PROJECT_INDEX = "docs/index.md"
DEFAULT_SKILL_DIR = Path.home() / ".codex" / "skills" / "ai-localbase"


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


def shorten(value: Any, limit: int = 1200) -> str:
    if value is None:
        return ""
    if not isinstance(value, str):
        value = json.dumps(value, ensure_ascii=False, sort_keys=True)
    text = value.strip()
    return text[:limit] + "...(已截断)" if len(text) > limit else text


def additional_context(title: str, lines: list[str]) -> str:
    """沿用 agents_guard 的 additionalContext 文案形状。"""
    clean_lines = [line.strip() for line in lines if line and line.strip()]
    return "\n".join([f"AI LocalBase：{title}", *[f"- {line}" for line in clean_lines]])


def state_path() -> Path:
    configured = env("AI_LOCALBASE_HOOK_STATE_PATH", "")
    return Path(configured) if configured else DEFAULT_STATE_PATH


def log_path() -> Path:
    configured = env("AI_LOCALBASE_HOOK_LOG_PATH", "")
    return Path(configured) if configured else DEFAULT_LOG_PATH


def write_log(stage: str, **fields: Any) -> None:
    if not enabled(env("AI_LOCALBASE_HOOK_LOG", "true")):
        return
    path = log_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    entry = {
        "logged_at": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        "stage": stage,
    }
    # 日志只记录执行状态和长度摘要，避免写入 payload 原文或凭证。
    entry.update({key: shorten(value, 1000) for key, value in fields.items()})
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry, ensure_ascii=False) + "\n")
    trim_log(path)


def trim_log(path: Path) -> None:
    try:
        keep_lines = int(env("AI_LOCALBASE_HOOK_LOG_KEEP_LINES", "100") or "100")
    except ValueError:
        keep_lines = 100
    if keep_lines <= 0 or not path.exists():
        return
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    path.write_text("\n".join(lines[-keep_lines:]) + ("\n" if lines else ""), encoding="utf-8")


def project_root(context: dict[str, Any]) -> Path:
    payload = context.get("payload")
    payload = payload if isinstance(payload, dict) else {}
    cwd = first_text(payload, "cwd")
    return Path(cwd).resolve() if cwd else Path.cwd().resolve()


def skill_entry() -> Path:
    configured = env("AI_LOCALBASE_HOOK_SCRIPT", "")
    if configured:
        return Path(configured)
    if os.name == "nt":
        return DEFAULT_SKILL_DIR / "ai-localbase.ps1"
    return DEFAULT_SKILL_DIR / "ai-localbase.sh"


def command_for_entry(entry: Path, args: list[str]) -> list[str]:
    suffix = entry.suffix.lower()
    if suffix == ".ps1":
        shell = env("AI_LOCALBASE_HOOK_POWERSHELL", "powershell")
        return [shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(entry), *args]
    if suffix == ".sh":
        return ["bash", str(entry), *args]
    if suffix == ".py":
        return [sys.executable, str(entry), *args]
    return [str(entry), *args]


def run_ai_localbase(args: list[str], root: Path) -> tuple[int, str, str]:
    entry = skill_entry()
    if not entry.exists():
        return 127, "", f"ai-localbase entry not found: {entry}"
    try:
        timeout = int(env("AI_LOCALBASE_HOOK_TIMEOUT", "30") or "30")
    except ValueError:
        timeout = 30
    try:
        result = subprocess.run(
            command_for_entry(entry, args),
            cwd=str(root),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            check=False,
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired as error:
        return 124, error.stdout or "", error.stderr or "timeout"
    except Exception as error:
        return 1, "", f"{type(error).__name__}: {error}"


def git_status_summary(root: Path) -> str:
    if not (root / ".git").exists():
        return ""
    try:
        result = subprocess.run(
            ["git", "status", "--short", "--", "docs", "agents", "shell/codex_hook"],
            cwd=str(root),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
            check=False,
        )
        return shorten(result.stdout or result.stderr, 1000)
    except Exception as error:
        return f"{type(error).__name__}: {error}"


def extract_document_id(text: str) -> str:
    patterns = (
        r'"documentId"\s*:\s*"([^"]+)"',
        r'"id"\s*:\s*"(doc-[^"]+)"',
        r"\b(doc-[A-Za-z0-9_-]+)\b",
    )
    for pattern in patterns:
        match = re.search(pattern, text)
        if match:
            return match.group(1)
    return ""


def search_items(text: str) -> list[dict[str, Any]]:
    start = text.find("{")
    if start < 0:
        return []
    try:
        payload = json.loads(text[start:])
    except Exception:
        return []
    structured = payload.get("structuredContent") if isinstance(payload, dict) else {}
    items = structured.get("items") if isinstance(structured, dict) else []
    return [item for item in items if isinstance(item, dict)]


def build_checkpoint_content(root: Path, context: dict[str, Any]) -> tuple[str, dict[str, Any]]:
    payload = context.get("payload")
    payload = payload if isinstance(payload, dict) else {}
    now = datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")
    session_id = first_text(payload, "session_id", "sessionId") or str(context.get("session_id", ""))
    turn_id = first_text(payload, "turn_id", "turnId") or str(context.get("turn_id", ""))
    trigger = first_text(payload, "trigger", "source")
    index_exists = (root / DEFAULT_PROJECT_INDEX).exists()
    status = git_status_summary(root)
    meta = {
        "saved_at": now,
        "project_root": str(root),
        "session_id": session_id,
        "turn_id": turn_id,
        "trigger": trigger,
        "docs_index_exists": index_exists,
        "query": f"Codex Hook PreCompact {session_id} {turn_id}".strip(),
    }
    lines = [
        f"# Codex Hook PreCompact {now}",
        "",
        "执行者：Codex",
        "知识库：由 ai-localbase skill 按项目目录自动确认",
        "",
        "## 恢复索引",
        "",
        f"- 项目根：`{root}`",
        f"- Session：`{session_id}`",
        f"- Turn：`{turn_id}`",
        f"- Trigger：`{trigger}`",
        f"- docs/index.md 存在：`{index_exists}`",
        "",
        "## 工作区摘要",
        "",
        "```text",
        status,
        "```",
        "",
        "## 恢复提示",
        "",
        "- PostCompact 后先读取本条记忆，再确认最新用户请求是否变化。",
        "- 继续前复核 docs/index.md、当前任务目录状态和知识库同步状态。",
    ]
    return "\n".join(lines), meta


def write_state(data: dict[str, Any]) -> None:
    path = state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def read_state() -> dict[str, Any]:
    path = state_path()
    if not path.exists():
        return {}
    try:
        loaded = json.loads(path.read_text(encoding="utf-8"))
        return loaded if isinstance(loaded, dict) else {}
    except Exception:
        return {}


def handle_pre_compact(context: dict[str, Any], root: Path) -> str:
    content, meta = build_checkpoint_content(root, context)
    init_code, init_stdout, init_stderr = run_ai_localbase(["init", str(root)], root)
    document_id = env("AI_LOCALBASE_HOOK_COMPACT_DOC_ID", "")
    if document_id:
        action = "append"
        code, stdout, stderr = run_ai_localbase(["append", document_id, content, str(root)], root)
    else:
        action = "upload"
        filename = f"codex-hook-precompact-{datetime.now(timezone.utc).astimezone().strftime('%Y%m%d-%H%M%S')}.md"
        code, stdout, stderr = run_ai_localbase(["upload", filename, content, str(root)], root)
        document_id = extract_document_id(stdout)
    state = {
        **meta,
        "action": action,
        "document_id": document_id,
        "init_returncode": init_code,
        "returncode": code,
        "state_path": str(state_path()),
    }
    write_state(state)
    write_log(
        "precompact_completed",
        action=action,
        init_returncode=init_code,
        returncode=code,
        document_id=document_id,
        init_stdout=shorten(init_stdout, 800),
        init_stderr=shorten(init_stderr, 800),
        stdout=shorten(stdout, 800),
        stderr=shorten(stderr, 800),
    )
    status = "成功" if code == 0 else "失败"
    return additional_context(
        "PreCompact 记忆上传完成",
        [
            f"项目根：`{root}`。",
            f"上传状态：{status}（action={action}, returncode={code}）。",
            f"documentId：`{document_id or '未解析'}`。",
            f"本地状态：`{state_path()}`。",
        ],
    )


def handle_post_compact(context: dict[str, Any], root: Path) -> str:
    previous = read_state()
    query = env("AI_LOCALBASE_HOOK_POSTCOMPACT_QUERY", "") or str(previous.get("query", "")).strip()
    if not query:
        session_id = str(context.get("session_id", ""))
        turn_id = str(context.get("turn_id", ""))
        query = f"Codex Hook PreCompact {session_id} {turn_id}".strip()
    init_code, init_stdout, init_stderr = run_ai_localbase(["init", str(root)], root)
    code, stdout, stderr = run_ai_localbase(["search", query, str(root), env("AI_LOCALBASE_HOOK_POSTCOMPACT_TOPK", "3")], root)
    items = search_items(stdout)
    write_log(
        "postcompact_completed",
        query=query,
        init_returncode=init_code,
        returncode=code,
        item_count=len(items),
        init_stdout=shorten(init_stdout, 800),
        init_stderr=shorten(init_stderr, 800),
        stdout=shorten(stdout, 1000),
        stderr=shorten(stderr, 800),
    )
    lines = [
        f"项目根：`{root}`。",
        f"检索词：`{query}`。",
        f"读取状态：{'成功' if code == 0 else '失败'}（returncode={code}）。",
    ]
    if previous.get("document_id"):
        lines.append(f"压缩前 documentId：`{previous.get('document_id')}`。")
    if items:
        for index, item in enumerate(items[:3], start=1):
            name = str(item.get("documentName", "unknown"))
            text = shorten(item.get("text", ""), 260)
            lines.append(f"命中 {index}：`{name}` - {text}")
    else:
        lines.append("未读取到可用记忆片段；继续前手动复核 docs/index.md 和当前任务目录。")
    return additional_context("PostCompact 记忆读取完成", lines)


def handle(context: dict[str, Any]) -> str | None:
    event = str(context.get("event", ""))
    root = project_root(context)
    if event == "PreCompact":
        return handle_pre_compact(context, root)
    if event == "PostCompact":
        return handle_post_compact(context, root)
    return None

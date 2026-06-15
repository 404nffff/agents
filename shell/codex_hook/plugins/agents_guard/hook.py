#!/usr/bin/env python3
"""AGENTS hook v8 轻量守护插件。

插件把适合自动化的规则放到 Codex hook 生命周期中：
- SessionStart：检查项目索引与 Agent 文档，按需执行 ai-localbase init。
- PreToolUse：记录高风险命令或敏感文件读取迹象。
- PostToolUse：记录知识库握手相关错误，辅助后续排查。
- PreCompact：写入压缩前检查点，保留项目索引与工作区状态。
- PostCompact：读取压缩前检查点，写入压缩恢复记录。
- Stop：记录 docs/index.md 与工作区摘要，提醒收尾索引要求。

插件继续写本地脱敏日志，并把适合注入模型的简短上下文返回给通用入口。
stdout JSON 形状由通用入口统一处理，避免各插件重复实现官方 hooks 契约。
"""

from __future__ import annotations

import json
import os
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


PLUGIN_DIR = Path(__file__).resolve().parent
SCRIPT_DIR = PLUGIN_DIR.parent.parent
DEFAULT_LOG_PATH = SCRIPT_DIR / "codex_hook_agents_guard.log"
DEFAULT_COMPACT_STATE_PATH = SCRIPT_DIR / "codex_hook_compact_state.json"
DEFAULT_POSTCOMPACT_NOTE_PATH = SCRIPT_DIR / "codex_hook_postcompact_note.md"
DEFAULT_AGENT_DOC = "agents/AGENTS_SDP_AI_LOCALBASE_hook_v8.md"
DEFAULT_PROJECT_INDEX = "docs/index.md"
DEFAULT_AI_LOCALBASE_SCRIPT = Path.home() / ".codex" / "skills" / "ai-localbase" / "ai-localbase.sh"

# SessionStart 注入核心工作模式，保证 hook 版 AGENTS 规则在会话前置上下文中可见。
SESSION_START_SDLC_RULES = (
    "默认遵循 `software-dev-process` 的 `sdlc-design-1`、`sdlc-design-2`、`sdlc-implement`、`sdlc-test`、`sdlc-debug`、`sdlc-solo` 阶段指令。",
    "日常开发默认代码优先：先实现业务代码，再补单元、冒烟、功能测试，最后本地验证。",
    "常规新增或重构不自动 TDD；进入 `sdlc-debug` 时默认复现先行。",
    "自主执行当前阶段内的读写、编码、命令与验证；遇到红线、超范围、连续 3 次同类失败时停下并询问用户。",
)

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

RISKY_COMMAND_PATTERNS = (
    r"\brm\s+-[^\n;]*r[^\n;]*f\b",
    r"\bgit\s+reset\s+--hard\b",
    r"\bgit\s+checkout\s+--\s+",
    r"\bgit\s+push\b[^\n;]*(--force|-f)\b",
    r"\b(drop|truncate)\s+(table|database)\b",
    r"\balter\s+table\b[^\n;]*\bdrop\b",
)

SENSITIVE_FILE_PATTERNS = (
    r"(^|[/\s])\.env($|[.\s/])",
    r"\.pem\b",
    r"\.key\b",
    r"id_rsa\b",
    r"id_ed25519\b",
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


def log_path() -> Path:
    configured = env("AGENTS_GUARD_LOG_PATH", "")
    return Path(configured) if configured else DEFAULT_LOG_PATH


def compact_state_path() -> Path:
    configured = env("AGENTS_GUARD_COMPACT_STATE_PATH", "")
    return Path(configured) if configured else DEFAULT_COMPACT_STATE_PATH


def postcompact_note_path() -> Path:
    configured = env("AGENTS_GUARD_POSTCOMPACT_NOTE_PATH", "")
    return Path(configured) if configured else DEFAULT_POSTCOMPACT_NOTE_PATH


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


def shorten(value: Any, limit: int = 1200) -> str:
    if value is None:
        return ""
    if not isinstance(value, str):
        value = json.dumps(value, ensure_ascii=False, sort_keys=True)
    text = value.strip()
    return text[:limit] + "...(已截断)" if len(text) > limit else text


def bool_text(value: bool) -> str:
    return "存在" if value else "缺失"


def additional_context(title: str, lines: list[str]) -> str:
    """生成给 Codex 注入的简短上下文；只放规则提醒和脱敏状态，不放完整 payload。"""
    clean_lines = [line.strip() for line in lines if line and line.strip()]
    return "\n".join([f"AGENTS 守护：{title}", *[f"- {line}" for line in clean_lines]])


def write_log(event: str, level: str, message: str, details: dict[str, Any] | None = None) -> None:
    path = log_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    entry = {
        "logged_at": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        "event": event,
        "level": level,
        "message": message,
        "details": redact(details or {}),
    }
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry, ensure_ascii=False) + "\n")
    trim_log()


def trim_log() -> None:
    path = log_path()
    if not path.exists():
        return
    try:
        keep_lines = int(env("AGENTS_GUARD_LOG_KEEP_LINES", "200") or "200")
    except ValueError:
        keep_lines = 200
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    path.write_text("\n".join(lines[-keep_lines:]) + ("\n" if lines else ""), encoding="utf-8")


def project_root(context: dict[str, Any]) -> Path:
    payload = context.get("payload")
    payload = payload if isinstance(payload, dict) else {}
    cwd = first_text(payload, "cwd")
    return Path(cwd).resolve() if cwd else Path.cwd().resolve()


def run_command(command: list[str], cwd: Path, timeout: int) -> tuple[int, str, str]:
    try:
        result = subprocess.run(
            command,
            cwd=str(cwd),
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


def ai_localbase_script_path() -> Path:
    configured = env("AGENTS_GUARD_AI_LOCALBASE_SCRIPT", str(DEFAULT_AI_LOCALBASE_SCRIPT)) or str(DEFAULT_AI_LOCALBASE_SCRIPT)
    return Path(configured)


def run_ai_localbase(command: list[str], root: Path, timeout: int) -> tuple[int, str, str]:
    script = ai_localbase_script_path()
    if not script.exists():
        return 127, "", f"ai-localbase script not found: {script}"
    return run_command(["bash", str(script), *command], root, timeout)


def git_status_summary(root: Path) -> dict[str, Any]:
    if not (root / ".git").exists():
        return {"git_status_returncode": None, "git_status": ""}
    returncode, stdout, stderr = run_command(["git", "status", "--short", "--", "docs", "agents", "shell/codex_hook"], root, 5)
    return {"git_status_returncode": returncode, "git_status": shorten(stdout or stderr, 1000)}


def handle_session_start(context: dict[str, Any], root: Path) -> str:
    event = str(context.get("event", ""))
    index_path = root / DEFAULT_PROJECT_INDEX
    agent_doc_path = root / DEFAULT_AGENT_DOC
    init_status = "已跳过"
    init_detail = "AGENTS_GUARD_AI_LOCALBASE_INIT=false"
    write_log(
        event,
        "info",
        "会话启动检查完成",
        {
            "project_root": str(root),
            "docs_index_exists": index_path.exists(),
            "agent_doc_exists": agent_doc_path.exists(),
            "hook_scope_note": "hook 可做预热和记录；MCP 工具暴露仍应配置在 config.toml 的 mcp_servers 中。",
        },
    )

    if not enabled(env("AGENTS_GUARD_AI_LOCALBASE_INIT", "true")):
        return additional_context(
            "SessionStart 项目规则检查完成",
            [
                f"项目根：`{root}`。",
                f"`{DEFAULT_PROJECT_INDEX}`：{bool_text(index_path.exists())}。",
                f"`{DEFAULT_AGENT_DOC}`：{bool_text(agent_doc_path.exists())}。",
                f"ai-localbase init：{init_status}（{init_detail}）。",
                *SESSION_START_SDLC_RULES,
                "进入任务前先复核 docs/index.md 与当前项目知识库。",
            ],
        )
    script = ai_localbase_script_path()
    if not script.exists():
        write_log(event, "warning", "ai-localbase 入口不存在，跳过 SessionStart 握手", {"script": str(script)})
        init_status = "入口缺失"
        init_detail = str(script)
        return additional_context(
            "SessionStart 项目规则检查完成",
            [
                f"项目根：`{root}`。",
                f"`{DEFAULT_PROJECT_INDEX}`：{bool_text(index_path.exists())}。",
                f"`{DEFAULT_AGENT_DOC}`：{bool_text(agent_doc_path.exists())}。",
                f"ai-localbase init：{init_status}（`{init_detail}`）。",
                *SESSION_START_SDLC_RULES,
                "如需检索记忆，先恢复 ai-localbase 入口再继续。",
            ],
        )
    try:
        timeout = int(env("AGENTS_GUARD_INIT_TIMEOUT", "20") or "20")
    except ValueError:
        timeout = 20
    returncode, stdout, stderr = run_ai_localbase(["init", str(root)], root, timeout)
    write_log(
        event,
        "info" if returncode == 0 else "warning",
        "ai-localbase init 执行完成" if returncode == 0 else "ai-localbase init 执行异常",
        {"returncode": returncode, "stdout": shorten(stdout, 1200), "stderr": shorten(stderr, 1200)},
    )
    init_status = "成功" if returncode == 0 else "异常"
    init_detail = f"returncode={returncode}"
    return additional_context(
        "SessionStart 项目规则检查完成",
        [
            f"项目根：`{root}`。",
            f"`{DEFAULT_PROJECT_INDEX}`：{bool_text(index_path.exists())}。",
            f"`{DEFAULT_AGENT_DOC}`：{bool_text(agent_doc_path.exists())}。",
            f"ai-localbase init：{init_status}（{init_detail}）。",
            *SESSION_START_SDLC_RULES,
            "后续回答前优先复用当前知识库命中内容；不要把知识库名当作 knowledgeBaseId。",
        ],
    )


def command_text(payload: dict[str, Any]) -> str:
    tool_input = payload.get("tool_input")
    if isinstance(tool_input, dict):
        return first_text(tool_input, "cmd", "command")
    return ""


def matched_patterns(text: str, patterns: tuple[str, ...]) -> list[str]:
    lowered = text.lower()
    return [pattern for pattern in patterns if re.search(pattern, lowered, flags=re.IGNORECASE)]


def handle_pre_tool_use(context: dict[str, Any]) -> str:
    event = str(context.get("event", ""))
    payload = context.get("payload")
    payload = payload if isinstance(payload, dict) else {}
    tool_name = first_text(payload, "tool_name", "toolName")
    command = command_text(payload)
    if not command:
        return additional_context(
            "PreToolUse 检查完成",
            [
                f"工具：`{tool_name or 'unknown'}`。",
                "本次工具调用没有可检查的 shell 命令文本；继续遵守 AGENTS 红线。",
            ],
        )

    risky = matched_patterns(command, RISKY_COMMAND_PATTERNS)
    sensitive = matched_patterns(command, SENSITIVE_FILE_PATTERNS)
    if risky:
        write_log(event, "warning", "命令命中高风险模式；按 AGENTS 红线需显式确认", {"patterns": risky, "command": shorten(command, 600)})
    if sensitive:
        write_log(event, "warning", "命令疑似读取敏感凭证文件；按 AGENTS 红线需避免输出或外传", {"patterns": sensitive, "command": shorten(command, 600)})
    if risky or sensitive:
        lines = [f"工具：`{tool_name or 'unknown'}`。"]
        if risky:
            lines.append("命中高风险命令模式；继续前必须按 AGENTS 红线确认。")
        if sensitive:
            lines.append("疑似读取敏感凭证文件；禁止输出、记录或外传凭证内容。")
        return additional_context("PreToolUse 风险提示", lines)
    return additional_context(
        "PreToolUse 检查完成",
        [
            f"工具：`{tool_name or 'unknown'}`。",
            "未命中高风险命令或敏感文件读取模式。",
        ],
    )


def handle_post_tool_use(context: dict[str, Any]) -> str:
    event = str(context.get("event", ""))
    payload = context.get("payload")
    payload = payload if isinstance(payload, dict) else {}
    raw = json.dumps(payload, ensure_ascii=False)
    markers = ("knowledge base not found", "knowledgeBaseId", "ai-localbase", "HTTP Error 503")
    if any(marker.lower() in raw.lower() for marker in markers):
        write_log(event, "info", "工具结果包含知识库相关信息，必要时按 v7 错误恢复规则重新 init", {"excerpt": shorten(raw, 1200)})
        return additional_context(
            "PostToolUse 知识库信号",
            [
                "工具结果包含 ai-localbase / knowledgeBaseId 相关内容。",
                "若出现 knowledge base not found 或 knowledgeBaseId 为空，先执行 list/init 刷新真实 kb_id。",
            ],
        )
    return additional_context(
        "PostToolUse 检查完成",
        ["未发现知识库握手异常关键词；如测试或命令失败，按最多 3 次排查规则处理。"],
    )


def handle_pre_compact(context: dict[str, Any], root: Path) -> str:
    event = str(context.get("event", ""))
    payload = context.get("payload")
    payload = payload if isinstance(payload, dict) else {}
    state = {
        "saved_at": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        "project_root": str(root),
        "trigger": first_text(payload, "trigger", "source"),
        "session_id": first_text(payload, "session_id", "sessionId"),
        "turn_id": first_text(payload, "turn_id", "turnId"),
        "docs_index_exists": (root / DEFAULT_PROJECT_INDEX).exists(),
        **git_status_summary(root),
    }
    path = compact_state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(redact(state), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_log(event, "info", "压缩前检查点已写入", {"compact_state_path": str(path), **state})
    upload_precompact_memory(event, root, state)
    return additional_context(
        "PreCompact 检查点已写入",
        [
            f"检查点：`{path}`。",
            f"`{DEFAULT_PROJECT_INDEX}`：{bool_text(bool(state.get('docs_index_exists')))}。",
            "压缩恢复后先复核 docs/index.md、任务目录状态和知识库同步状态。",
        ],
    )


def upload_precompact_memory(event: str, root: Path, state: dict[str, Any]) -> None:
    if not enabled(env("AGENTS_GUARD_PRECOMPACT_UPLOAD_MEMORY", "false")):
        return
    try:
        timeout = int(env("AGENTS_GUARD_INIT_TIMEOUT", "20") or "20")
    except ValueError:
        timeout = 20
    lines = [
        f"# PreCompact Checkpoint {state.get('saved_at', '')}",
        "",
        f"- 项目根：`{state.get('project_root', '')}`",
        f"- Trigger：`{state.get('trigger', '')}`",
        f"- Session：`{state.get('session_id', '')}`",
        f"- Turn：`{state.get('turn_id', '')}`",
        f"- docs/index.md 存在：`{state.get('docs_index_exists', False)}`",
        "",
        "## 工作区摘要",
        "",
        "```text",
        str(state.get("git_status", "")),
        "```",
        "",
        "## 用途",
        "",
        "用于会话压缩前保留恢复检查点，供 PostCompact 与后续排查使用。",
    ]
    content = "\n".join(lines)
    document_id = env("AGENTS_GUARD_PRECOMPACT_MEMORY_DOC_ID", "")
    if document_id:
        returncode, stdout, stderr = run_ai_localbase(["append", document_id, content, str(root)], root, timeout)
        action = "append"
    else:
        filename = f"compact-checkpoint-{datetime.now(timezone.utc).astimezone().strftime('%Y%m%d-%H%M%S')}.md"
        returncode, stdout, stderr = run_ai_localbase(["upload", filename, content, str(root)], root, timeout)
        action = "upload"
    write_log(
        event,
        "info" if returncode == 0 else "warning",
        "PreCompact 检查点已同步知识库" if returncode == 0 else "PreCompact 检查点同步知识库失败",
        {"action": action, "returncode": returncode, "stdout": shorten(stdout, 1200), "stderr": shorten(stderr, 1200)},
    )


def write_postcompact_note(root: Path, previous: dict[str, Any], current_status: dict[str, Any]) -> Path:
    path = postcompact_note_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# PostCompact Recovery Note",
        "",
        "压缩后优先复核以下内容：",
        "",
        f"- 项目根：`{root}`",
        f"- 压缩前 docs/index.md：`{previous.get('docs_index_exists', '')}`",
        f"- 当前 docs/index.md：`{current_status.get('current_docs_index_exists', '')}`",
        f"- Trigger：`{previous.get('trigger', '')}`",
        f"- Session：`{previous.get('session_id', '')}`",
        f"- Turn：`{previous.get('turn_id', '')}`",
        "",
        "## 压缩前工作区摘要",
        "",
        "```text",
        str(previous.get("git_status", "")),
        "```",
        "",
        "## 当前工作区摘要",
        "",
        "```text",
        str(current_status.get("git_status", "")),
        "```",
        "",
        "## 建议",
        "",
        "- 先确认最新用户请求是否改变。",
        "- 先复核 docs/index.md、任务目录状态、知识库同步状态。",
        "- 不要假设压缩前任务已经完成。",
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


def handle_post_compact(context: dict[str, Any], root: Path) -> str:
    event = str(context.get("event", ""))
    path = compact_state_path()
    previous: dict[str, Any] = {}
    if path.exists():
        try:
            loaded = json.loads(path.read_text(encoding="utf-8"))
            previous = loaded if isinstance(loaded, dict) else {}
        except Exception:
            previous = {}
    current_status = {
        "current_docs_index_exists": (root / DEFAULT_PROJECT_INDEX).exists(),
        **git_status_summary(root),
    }
    note_path = write_postcompact_note(root, previous, current_status)
    write_log(
        event,
        "info",
        "压缩后恢复记录已写入；后续回复应优先复核 docs/index.md 与当前任务状态",
        {
            "compact_state_path": str(path),
            "postcompact_note_path": str(note_path),
            "previous": previous,
            **current_status,
        },
    )
    return additional_context(
        "PostCompact 恢复记录已写入",
        [
            f"恢复说明：`{note_path}`。",
            f"当前 `{DEFAULT_PROJECT_INDEX}`：{bool_text(bool(current_status.get('current_docs_index_exists')))}。",
            "继续前先确认最新用户请求是否改变，不要假设压缩前任务已完成。",
        ],
    )


def handle_stop(context: dict[str, Any], root: Path) -> str:
    event = str(context.get("event", ""))
    details: dict[str, Any] = {"docs_index_exists": (root / DEFAULT_PROJECT_INDEX).exists()}
    details.update(git_status_summary(root))
    write_log(event, "info", "回合结束检查完成；任务收尾前需同步 docs/index.md 与知识库", details)
    return additional_context(
        "Stop 收尾检查完成",
        [
            f"`{DEFAULT_PROJECT_INDEX}`：{bool_text(bool(details.get('docs_index_exists')))}。",
            "任务真正完成前必须更新 docs/index.md，并同步当前项目 ai-localbase 知识库。",
        ],
    )


def handle_user_prompt_submit(context: dict[str, Any], root: Path) -> str:
    payload = context.get("payload")
    payload = payload if isinstance(payload, dict) else {}
    prompt = first_text(payload, "prompt")
    return additional_context(
        "UserPromptSubmit 已接收",
        [
            f"项目根：`{root}`。",
            f"用户输入摘要：`{shorten(prompt, 120)}`。" if prompt else "未收到 prompt 文本。",
            "回复和施工前优先检索当前项目知识库，并遵守 AGENTS 红线与本地验证要求。",
        ],
    )


def handle_subagent_start(context: dict[str, Any]) -> str:
    payload = context.get("payload")
    payload = payload if isinstance(payload, dict) else {}
    agent_type = first_text(payload, "agent_type", "agentType")
    return additional_context(
        "SubagentStart 检查完成",
        [
            f"子代理类型：`{agent_type or 'unknown'}`。",
            "子代理执行也必须遵守当前项目 AGENTS 红线、知识库优先和本地验证要求。",
        ],
    )


def handle(context: dict[str, Any]) -> str | None:
    event = str(context.get("event", ""))
    root = project_root(context)
    if event == "SessionStart":
        return handle_session_start(context, root)
    if event == "SubagentStart":
        return handle_subagent_start(context)
    elif event == "PreToolUse":
        return handle_pre_tool_use(context)
    elif event == "PostToolUse":
        return handle_post_tool_use(context)
    elif event == "PreCompact":
        return handle_pre_compact(context, root)
    elif event == "PostCompact":
        return handle_post_compact(context, root)
    elif event == "UserPromptSubmit":
        return handle_user_prompt_submit(context, root)
    elif event == "Stop":
        return handle_stop(context, root)
    return None

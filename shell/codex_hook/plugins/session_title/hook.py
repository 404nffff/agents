#!/usr/bin/env python3
"""Codex 会话标题更新插件。

只处理 UserPromptSubmit / Stop：
- UserPromptSubmit：缓存当前 turn 的标题。
- Stop：调用既有标题 hook，通过 Codex app-server 更新会话标题。
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import Any


PLUGIN_DIR = Path(__file__).resolve().parent
SCRIPT_DIR = PLUGIN_DIR.parent.parent
LEGACY_TITLE_HOOK = SCRIPT_DIR.parent / "feishu_bot" / "hook.py"
DEFAULT_TITLE_STATE_PATH = SCRIPT_DIR / "codex_hook_title_state.json"


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


def title_state_path() -> Path:
    configured = env("SESSION_TITLE_STATE_PATH", env("CODEX_HOOK_TITLE_STATE_PATH", ""))
    if configured:
        return Path(configured)
    return DEFAULT_TITLE_STATE_PATH


def call_legacy_title_hook(raw: str) -> None:
    if not LEGACY_TITLE_HOOK.exists():
        return
    python = os.environ.get("PYTHON") or ("python" if os.name == "nt" else "python3")
    child_env = os.environ.copy()
    # 旧标题 hook 默认会读 feishu_bot/.env；这里显式指向不存在文件，避免触碰飞书敏感配置。
    child_env["FEISHU_ENV_FILE"] = str(PLUGIN_DIR / ".no-feishu-env")
    child_env["FEISHU_CODEX_HOOK_UPDATE_SESSION_TITLE"] = "true"
    child_env["FEISHU_CODEX_HOOK_TITLE_STATE_PATH"] = str(title_state_path())
    child_env["FEISHU_CODEX_HOOK_CODEX_APP_SERVER_TIMEOUT"] = env("SESSION_TITLE_CODEX_APP_SERVER_TIMEOUT", "5")
    child_env["FEISHU_CODEX_HOOK_CODEX_APP_SERVER_DRAIN_SECONDS"] = env("SESSION_TITLE_CODEX_APP_SERVER_DRAIN_SECONDS", "0.5")
    try:
        subprocess.run([python, str(LEGACY_TITLE_HOOK), raw], env=child_env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    except Exception:
        return


def handle(context: dict[str, Any]) -> None:
    event = str(context.get("event", ""))
    if event not in {"UserPromptSubmit", "Stop"}:
        return
    raw = str(context.get("raw", ""))
    if raw:
        call_legacy_title_hook(raw)

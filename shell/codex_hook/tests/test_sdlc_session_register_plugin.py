#!/usr/bin/env python3
"""SDLC 会话登记插件回归测试。"""

from __future__ import annotations

import importlib.util
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECT_ROOT = ROOT.parents[1]
HOOK_PATH = ROOT / "hook.py"
PLUGIN_PATH = ROOT / "plugins" / "sdlc_session_register" / "hook.py"
SCRIPT_PATH = PROJECT_ROOT / "skills" / "software-dev-process-roles" / "scripts" / "sdlc_session_register.py"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class AiRegisterPluginTests(unittest.TestCase):
    def test_session_start_writes_identity_row(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            db_path = root / "docs" / "ai-register.db"
            payload = {
                "hook_event_name": "SessionStart",
                "cwd": str(root),
                "session_id": "session-1234567890",
                "turn_id": "turn-1",
                "model": "gpt-test",
                "source": "startup",
            }
            env = {
                **os.environ,
                "CODEX_HOOK_ENV_FILE": str(ROOT / "__missing_test_env__"),
                "CODEX_HOOK_EVENTS_SESSION_START": "sdlc_session_register",
                "CODEX_HOOK_LOG_PAYLOAD": "false",
                "CODEX_HOOK_LOG_ERRORS": "false",
                "SDLC_SESSION_REGISTER_LOG": "false",
            }
            result = subprocess.run(
                [sys.executable, str(HOOK_PATH), json.dumps(payload, ensure_ascii=False)],
                cwd=str(ROOT),
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            conn = sqlite3.connect(db_path)
            try:
                row = conn.execute("SELECT session_id, tool, model, cwd, source, resume_shell FROM ai_register").fetchone()
            finally:
                conn.close()

        self.assertEqual(result.returncode, 0, result.stderr)
        output = json.loads(result.stdout)
        self.assertEqual(output["hookSpecificOutput"]["hookEventName"], "SessionStart")
        self.assertIn("SessionStart 已登记", output["hookSpecificOutput"]["additionalContext"])
        self.assertEqual(row[0], "session-1234567890")
        self.assertEqual(row[1], "Codex")
        self.assertEqual(row[2], "gpt-test")
        self.assertEqual(row[4], "startup")
        self.assertEqual(row[5], "codex resume session-1234567890")

    def test_plugin_exposes_only_session_start_hook_surface(self) -> None:
        module = load_module("sdlc_session_register_hook_surface_test", PLUGIN_PATH)

        self.assertTrue(hasattr(module, "handle"))
        self.assertFalse(hasattr(module, "main"))
        self.assertFalse(hasattr(module, "build_cli"))
        self.assertFalse(hasattr(module, "update_progress"))
        self.assertFalse(hasattr(module, "query_rows"))
        self.assertFalse(hasattr(module, "render_table"))

    def test_skill_script_progress_and_query(self) -> None:
        module = load_module("sdlc_session_register_skill_script_for_cli_test", SCRIPT_PATH)
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            db_path = root / "docs" / "ai-register.db"
            self.assertEqual(
                module.main(
                    [
                        "upsert",
                        "--cwd",
                        str(root),
                        "--session",
                        "session-abcdef",
                        "--tool",
                        "Codex",
                        "--model",
                        "gpt-test",
                    ]
                ),
                0,
            )
            self.assertEqual(
                module.main(
                    [
                        "progress",
                        "--cwd",
                        str(root),
                        "--session",
                        "session-abcdef",
                        "--task-dir",
                        "docs/demo/",
                        "--feature",
                        "插件化登记",
                        "--progress",
                        "75%",
                    ]
                ),
                0,
            )
            rows = module.query_rows(db_path, keyword="demo")
            output = module.render_table(rows)

        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["task_dir"], "docs/demo/")
        self.assertEqual(rows[0]["feature"], "插件化登记")
        self.assertEqual(rows[0]["progress"], "75%")
        self.assertEqual(rows[0]["tool"], "Codex")
        self.assertEqual(rows[0]["model"], "gpt-test")
        self.assertEqual(rows[0]["resume_shell"], "codex resume session-abcdef")
        self.assertIn("docs/demo/", output)
        self.assertIn("插件化登记", output)


if __name__ == "__main__":
    unittest.main()

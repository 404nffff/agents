#!/usr/bin/env python3
"""agents_guard additionalContext 输出回归测试。"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HOOK_PATH = ROOT / "hook.py"


class AgentsGuardAdditionalContextTests(unittest.TestCase):
    def make_project(self, temp_dir: str) -> Path:
        root = Path(temp_dir)
        (root / "docs").mkdir(parents=True)
        (root / "agents").mkdir(parents=True)
        (root / "docs" / "index.md").write_text("# 项目索引\n", encoding="utf-8")
        (root / "agents" / "AGENTS_SDP_AI_LOCALBASE_hook_v8.md").write_text("# Agent\n", encoding="utf-8")
        return root

    def run_hook(self, payload: dict[str, object], env: dict[str, str]) -> subprocess.CompletedProcess[str]:
        base_env = {
            **os.environ,
            # 测试不读取本地真实 .env，避免凭证类配置进入测试进程。
            "CODEX_HOOK_ENV_FILE": str(ROOT / "__missing_test_env__"),
            "AGENTS_GUARD_ENV_FILE": str(ROOT / "plugins" / "agents_guard" / "__missing_test_env__"),
            "CODEX_HOOK_LOG_PAYLOAD": "false",
            "CODEX_HOOK_LOG_ERRORS": "false",
            "AGENTS_GUARD_AI_LOCALBASE_INIT": "false",
        }
        base_env.update(env)
        return subprocess.run(
            [sys.executable, str(HOOK_PATH), json.dumps(payload, ensure_ascii=False)],
            cwd=str(ROOT),
            env=base_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def test_session_start_outputs_hook_specific_additional_context(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = self.make_project(temp_dir)
            result = self.run_hook(
                {
                    "hook_event_name": "SessionStart",
                    "cwd": str(root),
                    "session_id": "s1",
                    "turn_id": "t1",
                },
                {"CODEX_HOOK_EVENTS_SESSION_START": "agents_guard"},
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        output = json.loads(result.stdout)
        self.assertEqual(output["hookSpecificOutput"]["hookEventName"], "SessionStart")
        self.assertIn("AGENTS 守护：SessionStart", output["hookSpecificOutput"]["additionalContext"])
        self.assertIn("ai-localbase init", output["hookSpecificOutput"]["additionalContext"])
        self.assertIn("sdlc-design-1", output["hookSpecificOutput"]["additionalContext"])
        self.assertIn("日常开发默认代码优先", output["hookSpecificOutput"]["additionalContext"])
        self.assertIn("进入 `sdlc-debug` 时默认复现先行", output["hookSpecificOutput"]["additionalContext"])
        self.assertIn("连续 3 次同类失败", output["hookSpecificOutput"]["additionalContext"])

    def test_pre_tool_use_outputs_risk_context_without_blocking(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = self.make_project(temp_dir)
            log_path = Path(temp_dir) / "agents_guard.log"
            result = self.run_hook(
                {
                    "hook_event_name": "PreToolUse",
                    "cwd": str(root),
                    "tool_name": "Bash",
                    "tool_input": {"command": "rm -rf build"},
                },
                {
                    "CODEX_HOOK_EVENTS_PRE_TOOL_USE": "agents_guard",
                    "AGENTS_GUARD_LOG_PATH": str(log_path),
                },
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        output = json.loads(result.stdout)
        context = output["hookSpecificOutput"]["additionalContext"]
        self.assertEqual(output["hookSpecificOutput"]["hookEventName"], "PreToolUse")
        self.assertIn("高风险命令", context)
        self.assertNotIn("rm -rf build", context)

    def test_stop_does_not_emit_unsupported_additional_context(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = self.make_project(temp_dir)
            result = self.run_hook(
                {
                    "hook_event_name": "Stop",
                    "cwd": str(root),
                    "session_id": "s1",
                    "turn_id": "t1",
                },
                {"CODEX_HOOK_EVENTS_STOP": "agents_guard"},
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_compact_events_do_not_emit_unsupported_additional_context(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = self.make_project(temp_dir)
            for event in ("PreCompact", "PostCompact"):
                with self.subTest(event=event):
                    result = self.run_hook(
                        {
                            "hook_event_name": event,
                            "cwd": str(root),
                            "session_id": "s1",
                            "turn_id": "t1",
                        },
                        {f"CODEX_HOOK_EVENTS_{event.upper()}": "agents_guard"},
                    )

                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()

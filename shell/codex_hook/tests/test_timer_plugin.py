#!/usr/bin/env python3
"""计时器插件与 hook 顺序回归测试。"""

from __future__ import annotations

import importlib.util
import json
import os
import tempfile
import types
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
HOOK_PATH = ROOT / "hook.py"
TIMER_PATH = ROOT / "plugins" / "timer" / "hook.py"
FEISHU_PATH = ROOT / "plugins" / "feishu" / "hook.py"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TimerPluginTests(unittest.TestCase):
    def test_timer_records_multiple_turns_and_elapsed(self) -> None:
        module = load_module("timer_hook_for_elapsed_test", TIMER_PATH)
        with tempfile.TemporaryDirectory() as temp_dir:
            state_path = Path(temp_dir) / "timer.json"
            first_start = datetime(2026, 6, 17, 10, 0, 0, tzinfo=timezone.utc)
            second_start = datetime(2026, 6, 17, 10, 1, 0, tzinfo=timezone.utc)
            first_stop = datetime(2026, 6, 17, 10, 0, 5, tzinfo=timezone.utc)
            second_stop = datetime(2026, 6, 17, 10, 1, 2, 345000, tzinfo=timezone.utc)
            with mock.patch.dict(os.environ, {"CODEX_HOOK_TIMER_STATE_PATH": str(state_path)}, clear=False):
                with mock.patch.object(module, "now_time", return_value=first_start):
                    module.handle({"event": "UserPromptSubmit", "session_id": "s1", "turn_id": "t1", "project": "agents"})
                with mock.patch.object(module, "now_time", return_value=second_start):
                    module.handle({"event": "UserPromptSubmit", "session_id": "s2", "turn_id": "t2", "project": "agents"})

                first_context = {"event": "Stop", "session_id": "s1", "turn_id": "t1", "project": "agents"}
                with mock.patch.object(module, "now_time", return_value=first_stop):
                    module.handle(first_context)
                stop_context = {"event": "Stop", "session_id": "s2", "turn_id": "t2", "project": "agents"}
                with mock.patch.object(module, "now_time", return_value=second_stop):
                    module.handle(stop_context)
                state = json.loads(state_path.read_text(encoding="utf-8"))

        self.assertIn("s1:t1", state["entries"])
        self.assertIn("s2:t2", state["entries"])
        self.assertEqual(state["entries"]["s1:t1"]["elapsed"], "5s")
        self.assertEqual(state["entries"]["s2:t2"]["elapsed_ms"], 2345)
        self.assertEqual(first_context["codex_timer_elapsed_label"], "5s")
        self.assertEqual(stop_context["codex_timer_elapsed_label"], "2s")

    def test_hook_uses_env_example_event_order_for_plugin_sources(self) -> None:
        module = load_module("codex_hook_main_for_timer_order_test", HOOK_PATH)
        with mock.patch.dict(
            os.environ,
            {
                "CODEX_HOOK_EVENTS_ALL": "agents_guard",
                "CODEX_HOOK_EVENTS_STOP": "timer,session_title_v2,feishu",
            },
            clear=False,
        ):
            module.CONFIG_EVENT_ENV_ORDER = []
            result = module.event_plugins("Stop")

        self.assertEqual(result, ["agents_guard", "timer", "session_title_v2", "feishu"])

    def test_feishu_markdown_includes_timer_elapsed(self) -> None:
        module = load_module("feishu_hook_for_timer_test", FEISHU_PATH)
        context = {
            "event": "Stop",
            "project": "agents",
            "title_summary": "用户请求",
            "codex_timer_elapsed_label": "2s",
            "payload": {
                "cwd": "D:\\www\\agents",
                "session_id": "s1",
                "turn_id": "t1",
                "model": "gpt-5",
                "permission_mode": "bypassPermissions",
            },
        }
        title = module.build_send_title(context)
        markdown = module.build_markdown(context)

        self.assertEqual(title, "[agents] 2s 用户请求")
        self.assertIn("- 耗时：`2s`", markdown)

    def test_elapsed_label_rounds_minute_seconds_without_decimal(self) -> None:
        module = load_module("timer_hook_for_rounding_test", TIMER_PATH)

        self.assertEqual(module.elapsed_label(107910), "1m 48s")
        self.assertEqual(module.elapsed_label(59600), "1m 00s")

    def test_feishu_push_enabled_by_default(self) -> None:
        module = load_module("feishu_hook_for_default_push_test", FEISHU_PATH)
        with mock.patch.dict(os.environ, {"FEISHU_CODEX_HOOK_ENV_FILE": str(ROOT / "__missing_feishu_env__")}, clear=True):
            with mock.patch.object(module, "send_markdown") as send_markdown:
                module.handle({"event": "Stop", "payload": {}})

        send_markdown.assert_called_once()

    def test_plugin_execution_log_records_results_and_keeps_100_lines(self) -> None:
        module = load_module("codex_hook_main_for_plugin_execution_log_test", HOOK_PATH)

        def success_handle(context):
            context["title_summary"] = "AI 总结标题"
            return "插件返回内容"

        success_module = types.SimpleNamespace(handle=success_handle)

        def fail_handle(context):
            raise RuntimeError("boom")

        failed_module = types.SimpleNamespace(handle=fail_handle)

        def fake_import(module_name: str):
            plugin_name = module_name.split(".")[1]
            return failed_module if plugin_name == "p050" else success_module

        with tempfile.TemporaryDirectory() as temp_dir:
            log_path = Path(temp_dir) / "plugin-execution.jsonl"
            with mock.patch.dict(os.environ, {"CODEX_HOOK_LOG_ERRORS": "false"}, clear=False):
                with mock.patch.object(module, "DEFAULT_PLUGIN_EXECUTION_LOG_PATH", log_path):
                    with mock.patch.object(module.importlib, "import_module", side_effect=fake_import):
                        module.dispatch_plugins({"event": "Stop", "title_summary": "初始标题"}, [f"p{index:03d}" for index in range(101)])

            lines = [json.loads(line) for line in log_path.read_text(encoding="utf-8").splitlines()]

        self.assertEqual(len(lines), 100)
        self.assertEqual(lines[0]["plugin"], "p001")
        self.assertEqual(lines[-1]["plugin"], "p100")
        self.assertIn({"event": "Stop", "plugin": "p050", "result": "error:RuntimeError"}, [
            {"event": item["event"], "plugin": item["plugin"], "result": item["result"]} for item in lines
        ])
        self.assertIn({"event": "Stop", "plugin": "p100", "result": "success"}, [
            {"event": item["event"], "plugin": item["plugin"], "result": item["result"]} for item in lines
        ])
        failed = next(item for item in lines if item["plugin"] == "p050")
        self.assertEqual(failed["plugin_output"], "boom")
        self.assertEqual(lines[0]["session_title"], "AI 总结标题")
        self.assertEqual(lines[-1]["session_title"], "AI 总结标题")
        self.assertEqual(lines[-1]["plugin_output"], "插件返回内容")
        self.assertRegex(lines[-1]["executed_at"], r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$")


if __name__ == "__main__":
    unittest.main()

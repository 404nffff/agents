#!/usr/bin/env python3
"""飞书与 session_title_v2 协作测试。"""

from __future__ import annotations

import importlib.util
import os
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
HOOK_PATH = ROOT / "hook.py"
FEISHU_PATH = ROOT / "plugins" / "feishu" / "hook.py"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FeishuSessionTitleV2Tests(unittest.TestCase):
    def test_stop_keeps_configured_plugin_order(self) -> None:
        module = load_module("codex_hook_main_for_order_test", HOOK_PATH)
        with mock.patch.dict(os.environ, {"CODEX_HOOK_EVENTS_STOP": "timer,session_title_v2,feishu"}, clear=False):
            module.CONFIG_EVENT_ENV_ORDER = []
            result = module.event_plugins("Stop")

        self.assertEqual(result, ["timer", "session_title_v2", "feishu"])

    def test_stop_context_reads_full_user_input_from_title_state(self) -> None:
        module = load_module("codex_hook_main_for_user_input_test", HOOK_PATH)
        long_user_input = "请处理这个很长的用户输入：" + "正文" * 500
        with mock.patch.dict(os.environ, {"CODEX_HOOK_TITLE_STATE_PATH": str(ROOT / "__test_title_state.json")}, clear=False):
            state_path = module.title_state_path()
            if state_path.exists():
                state_path.unlink()
            try:
                module.build_context(
                    "{}",
                    {
                        "hook_event_name": "UserPromptSubmit",
                        "session_id": "s1",
                        "turn_id": "t1",
                        "prompt": long_user_input,
                    },
                )
                context = module.build_context(
                    "{}",
                    {
                        "hook_event_name": "Stop",
                        "session_id": "s1",
                        "turn_id": "t1",
                    },
                )
            finally:
                if state_path.exists():
                    state_path.unlink()

        self.assertEqual(context["user_input"], long_user_input)
        self.assertLess(len(context["title_summary"]), len(long_user_input))

    def test_feishu_uses_ai_title_and_keeps_legacy_user_input_in_body(self) -> None:
        module = load_module("feishu_hook_for_title_test", FEISHU_PATH)
        long_user_input = "用户输入的旧标题" + "很长" * 700
        context = {
            "event": "Stop",
            "project": "agents",
            "title_summary": "用户输入的旧标题",
            "session_title_v2_title": "AI 总结标题",
            "session_title_v2_legacy_title": long_user_input,
            "payload": {
                "cwd": "D:\\www\\agents",
                "session_id": "s1",
                "turn_id": "t1",
                "model": "gpt-5.5",
                "permission_mode": "bypassPermissions",
                "transcript_path": "C:\\Users\\w\\.codex\\sessions\\demo.jsonl",
                "last_assistant_message": "最终回复内容",
            },
        }

        title = module.build_send_title(context)
        markdown = module.build_markdown(context)

        self.assertEqual(title, "[agents] AI 总结标题")
        self.assertIn("**用户输入**", markdown)
        self.assertIn(long_user_input, markdown)
        self.assertNotIn("...(已截断)", markdown.split("**最终回复**", 1)[0])
        self.assertIn("**最终回复**", markdown)
        self.assertIn("最终回复内容", markdown)


if __name__ == "__main__":
    unittest.main()

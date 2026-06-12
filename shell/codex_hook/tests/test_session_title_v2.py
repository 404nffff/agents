#!/usr/bin/env python3
"""session_title_v2 插件测试。"""

from __future__ import annotations

import importlib.util
import json
import os
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
HOOK_PATH = ROOT / "plugins" / "session_title_v2" / "hook.py"


def load_module():
    spec = importlib.util.spec_from_file_location("session_title_v2_hook", HOOK_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CaptureHandler(BaseHTTPRequestHandler):
    requests: list[dict[str, object]] = []

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode("utf-8")
        self.__class__.requests.append(
            {
                "path": self.path,
                "authorization": self.headers.get("Authorization", ""),
                "body": json.loads(body),
            }
        )
        response = {"choices": [{"message": {"content": "「新的会话标题」"}}]}
        encoded = json.dumps(response).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, format: str, *args: object) -> None:
        return


class SessionTitleV2Tests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_module()

    def write_transcript(self, path: Path) -> None:
        rows = [
            {"role": "user", "content": [{"type": "input_text", "text": "请新增标题插件"}]},
            {"role": "assistant", "content": [{"type": "output_text", "text": "已分析现有实现"}]},
            {"item": {"role": "user", "content": "需要兼容 OpenAI API"}},
            {"type": "response_item", "payload": {"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": "已支持 Codex 新 transcript 格式"}]}},
        ]
        path.write_text("\n".join(json.dumps(row, ensure_ascii=False) for row in rows), encoding="utf-8")

    def test_extract_transcript_text_reads_user_and_assistant_messages(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            transcript = Path(temp_dir) / "session.jsonl"
            self.write_transcript(transcript)

            result = self.module.extract_transcript_text(transcript, 10000)

        self.assertIn("用户: 请新增标题插件", result)
        self.assertIn("助手: 已分析现有实现", result)
        self.assertIn("用户: 需要兼容 OpenAI API", result)
        self.assertIn("助手: 已支持 Codex 新 transcript 格式", result)

    def test_transcript_path_from_searches_session_id_under_configured_root(self) -> None:
        session_id = "11111111-1111-1111-1111-111111111111"
        with tempfile.TemporaryDirectory() as temp_dir:
            nested = Path(temp_dir) / "2026" / "06" / "12"
            nested.mkdir(parents=True)
            transcript = nested / f"{session_id}.jsonl"
            transcript.write_text("{}", encoding="utf-8")
            with mock.patch.dict(os.environ, {"SESSION_TITLE_V2_TRANSCRIPT_ROOT": temp_dir}, clear=False):
                result = self.module.transcript_path_from(session_id, "")

        self.assertEqual(result, transcript)

    def test_handle_posts_openai_chat_completions_and_updates_title(self) -> None:
        CaptureHandler.requests = []
        server = HTTPServer(("127.0.0.1", 0), CaptureHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        updates: list[tuple[str, str, str]] = []

        with tempfile.TemporaryDirectory() as temp_dir:
            transcript = Path(temp_dir) / "22222222-2222-2222-2222-222222222222.jsonl"
            self.write_transcript(transcript)
            env = {
                "SESSION_TITLE_V2_API_URL": f"http://127.0.0.1:{server.server_port}",
                "SESSION_TITLE_V2_MODEL": "test-model",
                "SESSION_TITLE_V2_API_KEY": "test-key",
                "SESSION_TITLE_V2_MAX_CONTEXT_CHARS": "10000",
                "SESSION_TITLE_V2_LOG_PATH": str(Path(temp_dir) / "session_title_v2.log"),
            }
            context = {
                "event": "Stop",
                "user_input": "完整用户输入，不应该被旧标题长度限制截断",
                "payload": {
                    "session_id": "22222222-2222-2222-2222-222222222222",
                    "transcript_path": str(transcript),
                },
            }
            with mock.patch.dict(os.environ, env, clear=False), mock.patch.object(
                self.module,
                "update_codex_session_title",
                side_effect=lambda session_id, path, title: updates.append((session_id, path, title)) or True,
            ):
                self.module.handle(context)
            log_path = Path(env["SESSION_TITLE_V2_LOG_PATH"])
            log_rows = [json.loads(line) for line in log_path.read_text(encoding="utf-8").splitlines()]

        server.shutdown()
        server.server_close()
        self.assertEqual(len(CaptureHandler.requests), 1)
        request = CaptureHandler.requests[0]
        self.assertEqual(request["path"], "/v1/chat/completions")
        self.assertEqual(request["authorization"], "Bearer test-key")
        body = request["body"]
        self.assertEqual(body["model"], "test-model")
        self.assertEqual(body["messages"][0]["role"], "system")
        self.assertIn("请新增标题插件", body["messages"][1]["content"])
        self.assertEqual(updates[0][2], "新的会话标题")
        self.assertEqual(context["session_title_v2_title"], "新的会话标题")
        self.assertEqual(context["session_title_v2_legacy_title"], "完整用户输入，不应该被旧标题长度限制截断")
        self.assertIs(context["session_title_v2_updated"], True)
        stages = [row["stage"] for row in log_rows]
        self.assertIn("handle_received", stages)
        self.assertIn("transcript_loaded", stages)
        self.assertIn("api_completed", stages)
        self.assertIn("title_generated", stages)
        self.assertIn("handle_completed", stages)

    def test_write_log_keeps_latest_100_lines_by_default(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_path = Path(temp_dir) / "session_title_v2.log"
            with mock.patch.dict(os.environ, {"SESSION_TITLE_V2_LOG_PATH": str(log_path)}, clear=False):
                for index in range(105):
                    self.module.write_log("probe", index=index)
            rows = [json.loads(line) for line in log_path.read_text(encoding="utf-8").splitlines()]

        self.assertEqual(len(rows), 100)
        self.assertEqual(rows[0]["index"], 5)
        self.assertEqual(rows[-1]["index"], 104)


if __name__ == "__main__":
    unittest.main()

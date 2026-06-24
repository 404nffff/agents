#!/usr/bin/env python3
"""sdlc_watch 插件回归测试。"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from shell.codex_hook.plugins.sdlc_watch import hook, indexer


PROJECT_ROOT = Path(__file__).resolve().parents[3]


class SdlcWatchPluginTests(unittest.TestCase):
    def setUp(self) -> None:
        self.ai_env = mock.patch.dict(
            os.environ,
            {
                "SDLC_WATCH_AI_API_URL": "",
                "SDLC_WATCH_AI_MODEL": "",
                "SDLC_WATCH_AI_API_KEY": "",
                "SDLC_WATCH_AI_TEMPERATURE": "",
                "SDLC_WATCH_AI_MAX_TOKENS": "",
                "SDLC_WATCH_AI_TIMEOUT": "",
            },
            clear=False,
        )
        self.ai_env.start()
        self.addCleanup(self.ai_env.stop)

    def make_project(self, temp_dir: str) -> Path:
        root = Path(temp_dir) / "project"
        task_dir = root / "docs" / "demo-task"
        only_ai = task_dir / "onlyAI"
        only_ai.mkdir(parents=True)
        (task_dir / "status.md").write_text("# Demo Task\n状态：进行中\n", encoding="utf-8")
        (task_dir / "001-概要设计.md").write_text("# Demo 概要\n\n需要写入 SQLite。\n", encoding="utf-8")
        (task_dir / "002-详细设计.md").write_text("# Demo 详细\n\nElectron 只读查询。\n", encoding="utf-8")
        (only_ai / "testing.md").write_text("# 测试记录\n\n覆盖索引与查询。\n", encoding="utf-8")
        (task_dir / "demo_probe_result.md").write_text(
            "\n".join(
                [
                    "| 接口地址 | 入参 | 出参 | 测试条件 | 边界条件 | 测试结果 | 请求时间 | 关联脚本文件 |",
                    "| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |",
                    "| /demo/old | {} | {} | 正常 | 无 | 通过 | 2026-06-17 14:18:48 | demo_probe.php |",
                    "| /demo/new | {} | {} | 正常 | 无 | 通过 | 2026-06-17 14:18:59 | demo_probe.php |",
                ]
            ),
            encoding="utf-8",
        )
        exec_dir = task_dir / "demo_probe" / "2026-06-18"
        exec_dir.mkdir(parents=True)
        (exec_dir / "14时18分47秒.md").write_text(
            "# 执行结果\n\n- 脚本名称：`demo_probe.php`\n\n## 输出结果\n```text\n{\"ok\":true}\n```\n",
            encoding="utf-8",
        )
        (task_dir / ".env").write_text("SECRET=hidden\n", encoding="utf-8")
        (task_dir / "private.pem").write_text("PRIVATE KEY\n", encoding="utf-8")
        return root

    def run_cli(self, root: Path, db_path: Path, *args: str) -> dict[str, object]:
        result = subprocess.run(
            [
                sys.executable,
                "-m",
                "shell.codex_hook.plugins.sdlc_watch.indexer",
                "--root",
                str(root),
                "--db",
                str(db_path),
                *args,
            ],
            cwd=str(PROJECT_ROOT),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_indexer_skips_sensitive_files_and_is_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = self.make_project(temp_dir)
            db_path = Path(temp_dir) / "sdlc.sqlite3"

            first = indexer.index_docs(root, db_path, "docs")
            second = indexer.index_docs(root, db_path, "docs")
            requirements = indexer.list_requirements(db_path, 10)
            requirement = indexer.get_requirement(db_path, "project/demo-task")

        self.assertEqual(first["scanned_requirements"], 1)
        self.assertEqual(first["scanned_documents"], 6)
        self.assertGreaterEqual(first["skipped_files"], 2)
        self.assertEqual(second["scanned_documents"], 6)
        self.assertEqual(len(requirements["requirements"]), 1)
        self.assertEqual(requirements["requirements"][0]["slug"], "project/demo-task")
        self.assertEqual(requirements["requirements"][0]["project_name"], "project")
        self.assertEqual(len(requirement["documents"]), 6)
        self.assertTrue(any(document["document_type"] == "exec_result" for document in requirement["documents"]))
        probe_document = next(document for document in requirement["documents"] if document["document_type"] == "probe_result")
        self.assertEqual(probe_document["probe_request_time"], "2026-06-17T14:18:59")
        self.assertNotIn(".env", json.dumps(requirement, ensure_ascii=False))
        self.assertNotIn("private.pem", json.dumps(requirement, ensure_ascii=False))

    def test_indexer_groups_by_current_project_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir) / "client-a"
            task_dir = root / "docs" / "feature-one"
            task_dir.mkdir(parents=True)
            (task_dir / "status.md").write_text("# Feature One\n状态：已完成\n", encoding="utf-8")
            db_path = Path(temp_dir) / "project.sqlite3"

            payload = indexer.index_docs(root, db_path, "docs")
            listing = indexer.list_requirements(db_path, 10)

        self.assertEqual(payload["scanned_requirements"], 1)
        self.assertEqual(listing["requirements"][0]["slug"], "client-a/feature-one")
        self.assertEqual(listing["requirements"][0]["project_name"], "client-a")

    def test_indexer_only_scans_requirement_dirs_modified_today(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir) / "project"
            today_dir = root / "docs" / "today-task"
            old_dir = root / "docs" / "old-task"
            today_dir.mkdir(parents=True)
            old_dir.mkdir(parents=True)
            (today_dir / "status.md").write_text("# Today Task\n状态：进行中\n", encoding="utf-8")
            (old_dir / "status.md").write_text("# Old Task\n状态：旧数据\n", encoding="utf-8")
            # 用目录自身 mtime 控制增量范围，避免 Stop hook 每次全量扫旧需求目录。
            yesterday = today_dir.stat().st_mtime - 86400
            os.utime(old_dir, (yesterday, yesterday))
            db_path = Path(temp_dir) / "today.sqlite3"

            payload = indexer.index_docs(root, db_path, "docs")
            listing = indexer.list_requirements(db_path, 10)

        self.assertEqual(payload["scanned_requirements"], 1)
        self.assertEqual(payload["scanned_documents"], 1)
        self.assertEqual(payload["skipped_requirements"], 1)
        self.assertEqual([item["slug"] for item in listing["requirements"]], ["project/today-task"])

    def test_indexer_uses_openai_compatible_api_for_status_when_configured(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = self.make_project(temp_dir)
            db_path = Path(temp_dir) / "ai.sqlite3"
            response = mock.MagicMock()
            response.read.return_value = json.dumps(
                {"choices": [{"message": {"content": "AI 总结：当前处于联调验证阶段"}}]},
                ensure_ascii=False,
            ).encode("utf-8")
            response.__enter__.return_value = response
            response.__exit__.return_value = None

            with mock.patch.dict(
                os.environ,
                {
                    "SDLC_WATCH_AI_API_URL": "https://example.test",
                    "SDLC_WATCH_AI_MODEL": "test-model",
                    "SDLC_WATCH_AI_API_KEY": "test-key",
                    "SDLC_WATCH_AI_MAX_TOKENS": "80",
                },
                clear=False,
            ), mock.patch("shell.codex_hook.plugins.sdlc_watch.indexer.urllib.request.urlopen", return_value=response) as urlopen:
                payload = indexer.index_docs(root, db_path, "docs")

            requirement = indexer.get_requirement(db_path, "project/demo-task")["requirement"]
            request = urlopen.call_args.args[0]
            request_body = json.loads(request.data.decode("utf-8"))
            user_content = request_body["messages"][1]["content"]

        self.assertEqual(payload["ai_status_generated"], 1)
        self.assertEqual(payload["ai_status_failed"], 0)
        self.assertEqual(requirement["status"], "AI 总结：当前处于联调验证阶段")
        self.assertEqual(request.full_url, "https://example.test/v1/chat/completions")
        self.assertEqual(request_body["model"], "test-model")
        self.assertIn("--- 文件：docs/demo-task/status.md ---", user_content)
        self.assertIn("状态：进行中", user_content)
        self.assertNotIn("需要写入 SQLite", user_content)
        self.assertNotIn("Electron 只读查询", user_content)

    def test_cli_queries_return_json_payloads(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = self.make_project(temp_dir)
            db_path = Path(temp_dir) / "sdlc.sqlite3"
            self.run_cli(root, db_path, "index")

            listing = self.run_cli(root, db_path, "list-requirements", "--limit", "5")
            detail = self.run_cli(root, db_path, "get-requirement", "project/demo-task")
            search = self.run_cli(root, db_path, "search", "Electron", "--limit", "5")
            document_id = str(detail["documents"][0]["id"])
            document = self.run_cli(root, db_path, "get-document", document_id, "--content")
            probe_document = next(item for item in detail["documents"] if item["document_type"] == "probe_result")
            probe_detail = indexer.get_document(db_path, str(probe_document["id"]), True)

        self.assertTrue(listing["ok"])
        self.assertEqual(listing["requirements"][0]["slug"], "project/demo-task")
        self.assertTrue(search["results"])
        self.assertEqual(probe_detail["document"]["probe_request_time"], "2026-06-17T14:18:59")
        self.assertIn("content", document["document"])

    def test_hook_stop_indexes_docs_without_stdout_contract(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = self.make_project(temp_dir)
            db_path = Path(temp_dir) / "hook.sqlite3"
            log_path = Path(temp_dir) / "hook.jsonl"
            context = {"event": "Stop", "payload": {"cwd": str(root)}}

            with mock.patch.dict(
                os.environ,
                {
                    "SDLC_WATCH_DB_PATH": str(db_path),
                    "SDLC_WATCH_LOG_PATH": str(log_path),
                    "SDLC_WATCH_LOG_KEEP_LINES": "5",
                    "SDLC_WATCH_EVENTS": "Stop",
                },
                clear=False,
            ):
                result = hook.handle(context)

            log_line = json.loads(log_path.read_text(encoding="utf-8").splitlines()[-1])
            requirements = indexer.list_requirements(db_path, 10)

        self.assertIsNone(result)
        self.assertEqual(log_line["stage"], "index_completed")
        self.assertIn("scan_date", log_line)
        self.assertIn("skipped_requirements", log_line)
        self.assertIn("ai_status_generated", log_line)
        self.assertEqual(requirements["requirements"][0]["slug"], "project/demo-task")

    def test_hook_loads_plugin_env_for_ai_status(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = self.make_project(temp_dir)
            db_path = Path(temp_dir) / "hook-ai.sqlite3"
            log_path = Path(temp_dir) / "hook-ai.jsonl"
            env_path = Path(temp_dir) / "sdlc-watch.env"
            env_path.write_text(
                "\n".join(
                    [
                        "SDLC_WATCH_AI_API_URL='https://example.test'",
                        "SDLC_WATCH_AI_MODEL='test-model'",
                        "SDLC_WATCH_AI_API_KEY='test-key'",
                    ]
                ),
                encoding="utf-8",
            )
            response = mock.MagicMock()
            response.read.return_value = json.dumps(
                {"choices": [{"message": {"content": "AI 环境文件状态摘要"}}]},
                ensure_ascii=False,
            ).encode("utf-8")
            response.__enter__.return_value = response
            response.__exit__.return_value = None

            with mock.patch.dict(
                os.environ,
                {
                    "SDLC_WATCH_DB_PATH": str(db_path),
                    "SDLC_WATCH_LOG_PATH": str(log_path),
                    "SDLC_WATCH_ENV_FILE": str(env_path),
                    "SDLC_WATCH_EVENTS": "Stop",
                },
                clear=False,
            ), mock.patch("shell.codex_hook.plugins.sdlc_watch.indexer.urllib.request.urlopen", return_value=response):
                hook.handle({"event": "Stop", "payload": {"cwd": str(root)}})

            log_line = json.loads(log_path.read_text(encoding="utf-8").splitlines()[-1])
            requirement = indexer.get_requirement(db_path, "project/demo-task")["requirement"]

        self.assertEqual(log_line["ai_status_enabled"], "true")
        self.assertEqual(log_line["ai_status_generated"], "1")
        self.assertEqual(requirement["status"], "AI 环境文件状态摘要")


if __name__ == "__main__":
    unittest.main()

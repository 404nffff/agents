#!/usr/bin/env python3
"""ai_localbase compact 插件回归测试。"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HOOK_PATH = ROOT / "hook.py"


class AiLocalbaseCompactPluginTests(unittest.TestCase):
    def make_project(self, temp_dir: str) -> Path:
        root = Path(temp_dir) / "project"
        (root / "docs").mkdir(parents=True)
        (root / "docs" / "index.md").write_text("# 项目索引\n", encoding="utf-8")
        return root

    def make_fake_ai_localbase(self, temp_dir: str) -> Path:
        script = Path(temp_dir) / "fake_ai_localbase.py"
        script.write_text(
            textwrap.dedent(
                r'''
                import json
                import sys
                from pathlib import Path

                log_path = Path(sys.argv[-1]) / ".." / "fake_ai_localbase_args.jsonl"
                log_path = log_path.resolve()
                with log_path.open("a", encoding="utf-8") as handle:
                    handle.write(json.dumps(sys.argv[1:], ensure_ascii=False) + "\n")

                command = sys.argv[1] if len(sys.argv) > 1 else ""
                if command == "init":
                    print(json.dumps({"knowledgeBaseId": "kb-test"}, ensure_ascii=False))
                elif command == "upload":
                    print(json.dumps({"structuredContent": {"documentId": "doc-test-1"}}, ensure_ascii=False))
                elif command == "search":
                    print(json.dumps({
                        "structuredContent": {
                            "items": [
                                {
                                    "documentName": "codex-hook-precompact.md",
                                    "text": "压缩前检查点：继续前复核 docs/index.md 与任务状态。",
                                }
                            ]
                        }
                    }, ensure_ascii=False))
                elif command == "append":
                    print(json.dumps({"ok": True}, ensure_ascii=False))
                else:
                    print(json.dumps({"ok": True}, ensure_ascii=False))
                '''
            ).strip()
            + "\n",
            encoding="utf-8",
        )
        return script

    def run_hook(self, payload: dict[str, object], env: dict[str, str]) -> subprocess.CompletedProcess[str]:
        base_env = {
            **os.environ,
            "CODEX_HOOK_ENV_FILE": str(ROOT / "__missing_test_env__"),
            "CODEX_HOOK_LOG_PAYLOAD": "false",
            "CODEX_HOOK_LOG_ERRORS": "false",
            "AI_LOCALBASE_HOOK_LOG": "false",
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

    def test_precompact_uploads_checkpoint_without_stdout(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = self.make_project(temp_dir)
            fake_script = self.make_fake_ai_localbase(temp_dir)
            state_path = Path(temp_dir) / "state.json"
            result = self.run_hook(
                {
                    "hook_event_name": "PreCompact",
                    "cwd": str(root),
                    "session_id": "s1",
                    "turn_id": "t1",
                    "trigger": "manual",
                },
                {
                    "CODEX_HOOK_EVENTS_PRE_COMPACT": "ai_localbase",
                    "AI_LOCALBASE_HOOK_SCRIPT": str(fake_script),
                    "AI_LOCALBASE_HOOK_STATE_PATH": str(state_path),
                },
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "")
            state = json.loads(state_path.read_text(encoding="utf-8"))
            self.assertEqual(state["document_id"], "doc-test-1")

    def test_postcompact_reads_memory_without_stdout(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = self.make_project(temp_dir)
            fake_script = self.make_fake_ai_localbase(temp_dir)
            state_path = Path(temp_dir) / "state.json"
            state_path.write_text(
                json.dumps({"query": "Codex Hook PreCompact s1 t1", "document_id": "doc-test-1"}, ensure_ascii=False),
                encoding="utf-8",
            )
            result = self.run_hook(
                {
                    "hook_event_name": "PostCompact",
                    "cwd": str(root),
                    "session_id": "s1",
                    "turn_id": "t1",
                },
                {
                    "CODEX_HOOK_EVENTS_POST_COMPACT": "ai_localbase",
                    "AI_LOCALBASE_HOOK_SCRIPT": str(fake_script),
                    "AI_LOCALBASE_HOOK_STATE_PATH": str(state_path),
                },
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()

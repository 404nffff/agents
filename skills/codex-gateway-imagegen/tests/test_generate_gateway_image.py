#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "generate_gateway_image.py"


def load_module():
    spec = importlib.util.spec_from_file_location("generate_gateway_image", SCRIPT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load script: {SCRIPT_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class RuntimeEnvTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_module()
        self.tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmpdir.cleanup)
        self.env_path = Path(self.tmpdir.name) / ".env"

    def test_env_file_values_take_priority_over_process_environment(self) -> None:
        self.env_path.write_text(
            "\n".join(
                [
                    "OPENAI_BASE_URL=https://file.example/v1",
                    "OPENAI_API_KEY=file-key",
                    "GATEWAY_IMAGEGEN_MODEL=file-model",
                    "GATEWAY_IMAGEGEN_TIMEOUT=11",
                    "GATEWAY_IMAGEGEN_SIZE=1024x1024",
                    "GATEWAY_IMAGEGEN_ACTION=generate",
                ]
            ),
            encoding="utf-8",
        )

        with mock.patch.dict(
            os.environ,
            {
                "OPENAI_BASE_URL": "https://process.example/v1",
                "OPENAI_API_KEY": "process-key",
                "GATEWAY_IMAGEGEN_MODEL": "process-model",
                "GATEWAY_IMAGEGEN_TIMEOUT": "99",
                "GATEWAY_IMAGEGEN_SIZE": "1024x1536",
                "GATEWAY_IMAGEGEN_ACTION": "edit",
            },
            clear=False,
        ):
            values, env_path = self.module.load_runtime_env(str(self.env_path))

        self.assertEqual(env_path, self.env_path)
        self.assertEqual(values["OPENAI_BASE_URL"], "https://file.example/v1")
        self.assertEqual(values["OPENAI_API_KEY"], "file-key")
        self.assertEqual(values["GATEWAY_IMAGEGEN_MODEL"], "file-model")
        self.assertEqual(values["GATEWAY_IMAGEGEN_TIMEOUT"], "11")
        self.assertEqual(values["GATEWAY_IMAGEGEN_SIZE"], "1024x1024")
        self.assertEqual(values["GATEWAY_IMAGEGEN_ACTION"], "generate")

    def test_process_environment_is_used_when_env_file_is_absent(self) -> None:
        with mock.patch.dict(
            os.environ,
            {
                "OPENAI_BASE_URL": "https://process.example/v1",
                "OPENAI_API_KEY": "process-key",
            },
            clear=False,
        ), mock.patch.object(self.module, "_skill_root", return_value=Path(self.tmpdir.name)):
            values, env_path = self.module.load_runtime_env(None)

        self.assertEqual(env_path, Path(self.tmpdir.name) / ".env")
        self.assertEqual(values["OPENAI_BASE_URL"], "https://process.example/v1")
        self.assertEqual(values["OPENAI_API_KEY"], "process-key")


if __name__ == "__main__":
    unittest.main()

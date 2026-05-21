#!/usr/bin/env python3
"""
Generate an image through the Responses-compatible gateway configured for Codex.
"""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from urllib.parse import unquote_to_bytes
import ssl


DEFAULT_MODEL = "gpt-5.4"
DEFAULT_TIMEOUT = 600
DEFAULT_SIZE = "1024x1024"
DEFAULT_ACTION = "auto"
DEFAULT_ENV_FILENAME = ".env"
ENV_KEY_BASE_URL = "OPENAI_BASE_URL"
ENV_KEY_API_KEY = "OPENAI_API_KEY"
ENV_KEY_MODEL = "GATEWAY_IMAGEGEN_MODEL"
ENV_KEY_TIMEOUT = "GATEWAY_IMAGEGEN_TIMEOUT"
ENV_KEY_SIZE = "GATEWAY_IMAGEGEN_SIZE"
ENV_KEY_ACTION = "GATEWAY_IMAGEGEN_ACTION"


def _skill_root() -> Path:
    return Path(__file__).resolve().parent.parent


def _strip_inline_comment(value: str) -> str:
    if " #" in value:
        return value.split(" #", 1)[0].rstrip()
    return value


def _parse_env_value(raw_value: str) -> str:
    value = _strip_inline_comment(raw_value.strip())
    if not value:
        return ""
    if value.startswith('"') and value.endswith('"') and len(value) >= 2:
        return bytes(value[1:-1], "utf-8").decode("unicode_escape")
    if value.startswith("'") and value.endswith("'") and len(value) >= 2:
        return value[1:-1]
    return value


def load_env_file(env_path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        if "=" not in line:
            continue
        key, raw_value = line.split("=", 1)
        key = key.strip()
        if not key:
            continue
        values[key] = _parse_env_value(raw_value)
    return values


def load_runtime_env(env_file: str | None) -> tuple[dict[str, str], Path]:
    env_path = Path(env_file).expanduser() if env_file else _skill_root() / DEFAULT_ENV_FILENAME
    values: dict[str, str] = {}
    if env_path.exists():
        values.update(load_env_file(env_path))
    elif env_file:
        raise RuntimeError(f"Missing env file: {env_path}")
    else:
        # 默认 .env 不存在时才回退到进程环境，避免宿主机全局变量悄悄覆盖技能本地配置。
        for key in (
            ENV_KEY_BASE_URL,
            ENV_KEY_API_KEY,
            ENV_KEY_MODEL,
            ENV_KEY_TIMEOUT,
            ENV_KEY_SIZE,
            ENV_KEY_ACTION,
        ):
            runtime_value = os.environ.get(key, "").strip()
            if runtime_value:
                values[key] = runtime_value

    return values, env_path


def _env_default(env_values: dict[str, str], key: str, fallback: str) -> str:
    return env_values.get(key, "").strip() or fallback


def _env_timeout(env_values: dict[str, str]) -> int:
    raw_timeout = _env_default(env_values, ENV_KEY_TIMEOUT, str(DEFAULT_TIMEOUT))
    try:
        return int(raw_timeout)
    except ValueError as exc:
        raise RuntimeError(f"{ENV_KEY_TIMEOUT} must be an integer: {raw_timeout}") from exc


def build_parser(env_values: dict[str, str]) -> argparse.ArgumentParser:
    default_action = _env_default(env_values, ENV_KEY_ACTION, DEFAULT_ACTION)
    if default_action not in {"auto", "generate", "edit"}:
        raise RuntimeError(
            f"{ENV_KEY_ACTION} must be one of auto, generate, edit: {default_action}"
        )

    parser = argparse.ArgumentParser(description="Generate an image via the configured Responses gateway.")
    parser.add_argument(
        "--env-file",
        help=f"Env file path. Defaults to {_skill_root() / DEFAULT_ENV_FILENAME}.",
    )
    parser.add_argument("--prompt", required=True, help="Image generation prompt.")
    parser.add_argument("--out", required=True, help="Output image path.")
    parser.add_argument(
        "--size",
        default=_env_default(env_values, ENV_KEY_SIZE, DEFAULT_SIZE),
        help="Image size, e.g. 1024x1024 or 1024x1536.",
    )
    parser.add_argument(
        "--action",
        choices=("auto", "generate", "edit"),
        default=default_action,
        help="Image tool action. Use edit when providing a reference image or mask.",
    )
    parser.add_argument(
        "--image",
        action="append",
        default=[],
        help="Reference image path. Repeat the flag to include multiple images.",
    )
    parser.add_argument(
        "--image-url",
        action="append",
        default=[],
        help="Reference image URL. Repeat the flag to include multiple images.",
    )
    parser.add_argument(
        "--mask",
        help="Optional mask image path for edit workflows.",
    )
    parser.add_argument(
        "--model",
        default=_env_default(env_values, ENV_KEY_MODEL, DEFAULT_MODEL),
        help="Responses model to call.",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=_env_timeout(env_values),
        help="HTTP timeout in seconds.",
    )
    return parser


def parse_args() -> tuple[argparse.Namespace, dict[str, str], Path]:
    bootstrap_parser = argparse.ArgumentParser(add_help=False)
    bootstrap_parser.add_argument("--env-file")
    bootstrap_args, _ = bootstrap_parser.parse_known_args()

    env_values, env_path = load_runtime_env(bootstrap_args.env_file)
    parser = build_parser(env_values)
    return parser.parse_args(), env_values, env_path


def load_config(env_values: dict[str, str], env_path: Path) -> tuple[str, str]:
    base_url = env_values.get(ENV_KEY_BASE_URL, "").strip().rstrip("/")
    api_key = env_values.get(ENV_KEY_API_KEY, "").strip()

    if not base_url:
        raise RuntimeError(
            f"Missing {ENV_KEY_BASE_URL}. Set it in {env_path} or export it before running the script."
        )
    if not api_key:
        raise RuntimeError(
            f"Missing {ENV_KEY_API_KEY}. Set it in {env_path} or export it before running the script."
        )

    return base_url, api_key


def encode_image_data_url(image_path: str) -> str:
    path = Path(image_path).expanduser().resolve()
    if not path.exists():
        raise RuntimeError(f"Image file does not exist: {path}")

    mime_type, _ = mimetypes.guess_type(path.name)
    if not mime_type:
        mime_type = "application/octet-stream"

    encoded = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:{mime_type};base64,{encoded}"


def build_responses_payload(args: argparse.Namespace) -> bytes:
    input_content: list[dict[str, str]] = [
        {
            "type": "input_text",
            "text": args.prompt,
        }
    ]

    for image_path in args.image:
        input_content.append(
            {
                "type": "input_image",
                "image_url": encode_image_data_url(image_path),
            }
        )

    for image_url in args.image_url:
        input_content.append(
            {
                "type": "input_image",
                "image_url": image_url,
            }
        )

    if args.mask:
        input_content.append(
            {
                "type": "input_image_mask",
                "image_url": encode_image_data_url(args.mask),
            }
        )

    payload = {
        "model": args.model,
        "input": [
            {
                "role": "user",
                "content": input_content,
            }
        ],
        "tools": [
            {
                "type": "image_generation",
                "size": args.size,
                "action": args.action,
            }
        ],
    }
    return json.dumps(payload, ensure_ascii=False).encode("utf-8")


def build_images_payload(args: argparse.Namespace) -> bytes:
    payload = {
        "model": args.model,
        "prompt": args.prompt,
        "size": args.size,
    }
    return json.dumps(payload, ensure_ascii=False).encode("utf-8")


def extract_image_base64(data: dict) -> str:
    for item in data.get("output", []):
        if item.get("type") == "image_generation_call" and item.get("result"):
            return item["result"]
    raise RuntimeError("No image_generation_call result returned")


def extract_images_api_result(data: dict) -> str:
    if isinstance(data, dict):
        for item in data.get("data", []):
            if not isinstance(item, dict):
                continue
            if item.get("b64_json"):
                return item["b64_json"]
            if item.get("url"):
                return item["url"]
            if item.get("result"):
                return item["result"]
        if data.get("b64_json"):
            return data["b64_json"]
        if data.get("url"):
            return data["url"]
        if data.get("result"):
            return data["result"]
        for item in data.get("output", []):
            if isinstance(item, dict) and item.get("result"):
                return item["result"]
    raise RuntimeError("No image result returned from images API")


def _decode_svg_data_url(data_url: str) -> bytes:
    prefix = "data:image/svg+xml"
    if not data_url.startswith(prefix):
        raise RuntimeError("Not an SVG data URL")

    metadata, separator, payload = data_url.partition(",")
    if not separator:
        raise RuntimeError("Invalid SVG data URL")
    if ";base64" in metadata:
        return base64.b64decode(payload)
    return unquote_to_bytes(payload)


def _write_image_result(output_path: Path, image_result: str, timeout: int) -> None:
    if image_result.lstrip().startswith("<svg"):
        output_path.write_bytes(image_result.encode("utf-8"))
        return
    if image_result.startswith("<?xml"):
        output_path.write_bytes(image_result.encode("utf-8"))
        return
    if image_result.startswith("data:image/svg+xml"):
        output_path.write_bytes(_decode_svg_data_url(image_result))
        return
    if image_result.startswith("data:"):
        metadata, separator, payload = image_result.partition(",")
        if not separator:
            raise RuntimeError("Invalid data URL returned by image API")
        if ";base64" in metadata:
            output_path.write_bytes(base64.b64decode(payload))
        else:
            output_path.write_bytes(unquote_to_bytes(payload))
        return
    if image_result.startswith("http://") or image_result.startswith("https://"):
        with urlopen(image_result, context=ssl.create_default_context(), timeout=timeout) as response:
            output_path.write_bytes(response.read())
        return
    output_path.write_bytes(base64.b64decode(image_result))


def main() -> int:
    args, env_values, env_path = parse_args()

    try:
        base_url, api_key = load_config(env_values, env_path)
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        }
        if args.model == "gpt-image-2":
            body = build_images_payload(args)
            request = Request(
                f"{base_url}/images/generations",
                data=body,
                headers=headers,
                method="POST",
            )
            with urlopen(request, context=ssl.create_default_context(), timeout=args.timeout) as response:
                data = json.loads(response.read().decode("utf-8", errors="replace"))
            image_result = extract_images_api_result(data)
        else:
            body = build_responses_payload(args)
            request = Request(
                f"{base_url}/responses",
                data=body,
                headers=headers,
                method="POST",
            )

            with urlopen(request, context=ssl.create_default_context(), timeout=args.timeout) as response:
                data = json.loads(response.read().decode("utf-8", errors="replace"))

            image_result = extract_image_base64(data)

        output_path = Path(args.out).resolve()
        output_path.parent.mkdir(parents=True, exist_ok=True)
        _write_image_result(output_path, image_result, args.timeout)
        print(json.dumps({"saved": str(output_path), "bytes": output_path.stat().st_size}, ensure_ascii=False))
        return 0
    except HTTPError as exc:
        message = exc.read().decode("utf-8", errors="replace")
        print(
            json.dumps(
                {
                    "error": "http_error",
                    "status": exc.code,
                    "body": message,
                },
                ensure_ascii=False,
            ),
            file=sys.stderr,
        )
        return 1
    except URLError as exc:
        print(json.dumps({"error": "network_error", "message": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 1
    except TimeoutError as exc:
        print(json.dumps({"error": "timeout", "message": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 1
    except Exception as exc:
        print(json.dumps({"error": "runtime_error", "message": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

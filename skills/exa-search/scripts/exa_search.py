import argparse
import json
import os
import time
from typing import Any

import requests


DEFAULT_BASE_URL = "https://api.exa.ai"
PLACEHOLDER_KEYS = {
    "YOUR_EXA_API_KEY",
    "YOUR_API_KEY",
    "API_KEY",
    "CHANGE_ME",
    "REPLACE_ME",
    "<YOUR_EXA_API_KEY>",
}
FAILOVER_STATUS_CODES = {401, 403, 429}
FAILOVER_TEXT_PATTERNS = [
    "rate limit",
    "too many requests",
    "quota",
    "credits",
    "credit balance",
    "insufficient",
    "billing",
    "unauthorized",
    "forbidden",
    "invalid api key",
    "api key invalid",
    "api_key_invalid",
    "exhaust",
    "usage limit",
]


def _skill_root() -> str:
    return os.path.abspath(os.path.join(os.path.dirname(__file__), os.pardir))


def _default_config_paths() -> list[str]:
    root = _skill_root()
    home = os.path.expanduser("~")
    # Merge order: legacy fallback -> shared defaults -> local override.
    return [
        os.path.join(home, ".codex", "config", "exa-search.json"),
        os.path.join(root, "config.json"),
        os.path.join(root, "config.local.json"),
    ]


def _load_json_file(path: str) -> dict[str, Any]:
    try:
        with open(path, "r", encoding="utf-8-sig") as f:
            value = json.load(f)
    except FileNotFoundError:
        return {}
    if not isinstance(value, dict):
        raise ValueError(f"config at {path} must be a JSON object")
    return value


def _resolve_config(explicit_path: str) -> tuple[dict[str, Any], list[str], str]:
    if explicit_path:
        return _load_json_file(explicit_path), [explicit_path], explicit_path

    merged: dict[str, Any] = {}
    used: list[str] = []
    for path in _default_config_paths():
        if os.path.exists(path):
            merged.update(_load_json_file(path))
            used.append(path)
    primary = used[-1] if used else _default_config_paths()[-1]
    return merged, used, primary


def _normalize_api_key(value: str | None) -> str:
    key = (value or "").strip()
    if not key or key.upper() in PLACEHOLDER_KEYS:
        return ""
    return key


def _normalize_csv(value: str | None) -> list[str] | None:
    if not value:
        return None
    parts = [p.strip() for p in value.split(",") if p.strip()]
    return parts or None


def _shorten(text: str | None, limit: int = 240) -> str:
    if not text:
        return ""
    text = text.strip()
    if len(text) <= limit:
        return text
    return text[: limit - 3] + "..."


def _normalize_result(item: dict[str, Any], *, include_text: bool, include_highlights: bool) -> dict[str, Any]:
    out = {
        "id": item.get("id"),
        "title": item.get("title") or "",
        "url": item.get("url") or item.get("id") or "",
        "publishedDate": item.get("publishedDate"),
        "author": item.get("author") or "",
        "score": item.get("score"),
    }
    if include_text and "text" in item:
        out["text"] = item.get("text") or ""
    if include_highlights and "highlights" in item:
        out["highlights"] = item.get("highlights") or []
    if "image" in item:
        out["image"] = item.get("image")
    if "favicon" in item:
        out["favicon"] = item.get("favicon")
    return out


def _extract_profiles(
    config: dict[str, Any],
    *,
    cli_api_key: str,
    env_api_key: str,
    env_api_keys: list[str],
    forced_profile: str,
) -> list[dict[str, Any]]:
    def apply_filter(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
        if not forced_profile:
            return items
        return [p for p in items if p.get("id") == forced_profile]

    if cli_api_key:
        return [{"id": "cli", "api_key": cli_api_key, "source": "--api-key", "base_url": ""}]

    if env_api_keys:
        return apply_filter([
            {"id": f"env-{i}", "api_key": key, "source": "EXA_API_KEYS", "base_url": ""}
            for i, key in enumerate(env_api_keys, start=1)
            if key
        ])

    if env_api_key:
        return apply_filter([
            {"id": "env", "api_key": env_api_key, "source": "EXA_API_KEY", "base_url": ""}
        ])

    profiles: list[dict[str, Any]] = []
    raw_profiles = config.get("profiles")
    if isinstance(raw_profiles, list) and raw_profiles:
        for i, item in enumerate(raw_profiles, start=1):
            if isinstance(item, str):
                api_key = _normalize_api_key(item)
                if api_key:
                    profiles.append({
                        "id": f"profile-{i}",
                        "api_key": api_key,
                        "source": "config.profiles",
                        "base_url": "",
                    })
                continue
            if not isinstance(item, dict):
                continue
            if item.get("enabled", True) is False:
                continue
            api_key = _normalize_api_key(str(item.get("api_key") or item.get("key") or ""))
            if not api_key:
                continue
            profiles.append({
                "id": str(item.get("id") or f"profile-{i}"),
                "api_key": api_key,
                "source": "config.profiles",
                "base_url": str(item.get("base_url") or "").strip(),
            })
        return apply_filter(profiles)

    raw_api_keys = config.get("api_keys")
    if isinstance(raw_api_keys, list) and raw_api_keys:
        profiles = [
            {"id": f"key-{i}", "api_key": _normalize_api_key(str(key)), "source": "config.api_keys", "base_url": ""}
            for i, key in enumerate(raw_api_keys, start=1)
        ]
        profiles = [p for p in profiles if p.get("api_key")]
        return apply_filter(profiles)

    single_key = _normalize_api_key(str(config.get("api_key") or ""))
    if single_key:
        return apply_filter([
            {
                "id": str(config.get("profile_id") or "main"),
                "api_key": single_key,
                "source": "config.api_key",
                "base_url": "",
            }
        ])

    return []


def _should_failover(status_code: int | None, detail: str) -> bool:
    if status_code in FAILOVER_STATUS_CODES:
        return True
    lower = (detail or "").lower()
    return any(token in lower for token in FAILOVER_TEXT_PATTERNS)


def _request(endpoint: str, *, headers: dict[str, str], payload: dict[str, Any], timeout_seconds: float) -> dict[str, Any]:
    response = requests.post(endpoint, json=payload, headers=headers, timeout=timeout_seconds)
    response.raise_for_status()
    return response.json()


def search_exa(*, base_url: str, api_key: str, query: str, num_results: int, search_type: str,
               use_autoprompt: bool, include_text: bool, include_highlights: bool,
               start_published_date: str | None, include_domains: list[str] | None,
               exclude_domains: list[str] | None, category: str | None,
               timeout_seconds: float) -> dict[str, Any]:
    endpoint = f"{base_url.rstrip('/')}/search"
    headers = {
        "accept": "application/json",
        "content-type": "application/json",
        "x-api-key": api_key,
    }
    payload: dict[str, Any] = {
        "query": query,
        "numResults": num_results,
        "type": search_type,
        "useAutoprompt": use_autoprompt,
    }
    if include_text or include_highlights:
        payload["contents"] = {
            "text": include_text,
            "highlights": include_highlights,
        }
    if start_published_date:
        payload["startPublishedDate"] = start_published_date
    if include_domains:
        payload["includeDomains"] = include_domains
    if exclude_domains:
        payload["excludeDomains"] = exclude_domains
    if category:
        payload["category"] = category
    return _request(endpoint, headers=headers, payload=payload, timeout_seconds=timeout_seconds)


def find_similar(*, base_url: str, api_key: str, url_to_match: str, num_results: int,
                 timeout_seconds: float) -> dict[str, Any]:
    endpoint = f"{base_url.rstrip('/')}/findSimilar"
    headers = {
        "accept": "application/json",
        "content-type": "application/json",
        "x-api-key": api_key,
    }
    payload = {
        "url": url_to_match,
        "numResults": num_results,
    }
    return _request(endpoint, headers=headers, payload=payload, timeout_seconds=timeout_seconds)


def _emit(data: dict[str, Any], *, plain: bool = False, urls_only: bool = False) -> int:
    if urls_only:
        for item in data.get("results", []):
            url = item.get("url")
            if url:
                print(url)
        return 0

    if plain:
        if data.get("profileId"):
            source = data.get("profileSource") or ""
            suffix = f" [{source}]" if source else ""
            print(f"Profile: {data['profileId']}{suffix}")
        attempts = data.get("attempts") or []
        if attempts:
            print("Attempts:")
            for attempt in attempts:
                parts = [f"- {attempt.get('profileId', 'unknown')}"]
                parts.append("ok" if attempt.get("ok") else "fail")
                if attempt.get("status") is not None:
                    parts.append(f"status={attempt['status']}")
                if attempt.get("failover"):
                    parts.append("failover")
                if attempt.get("detail"):
                    parts.append(_shorten(str(attempt.get("detail")), 160))
                print(" | ".join(parts))
            print()

        if data.get("error"):
            print(f"ERROR: {data['error']}")
            if data.get("detail"):
                print(data["detail"])
            return 0

        for idx, item in enumerate(data.get("results", []), start=1):
            print(f"[{idx}] {item.get('title', '')}")
            print(f"URL: {item.get('url', '')}")
            if item.get("score") is not None:
                print(f"Score: {item.get('score')}")
            if item.get("publishedDate"):
                print(f"Published: {item.get('publishedDate')}")
            if item.get("author"):
                print(f"Author: {item.get('author')}")
            text = item.get("text")
            if text:
                preview = text[:1200]
                print("Text:")
                print(preview)
                if len(text) > len(preview):
                    print("...[truncated]")
            highlights = item.get("highlights") or []
            if highlights:
                print("Highlights:")
                for h in highlights[:5]:
                    print(f"- {h}")
            print()
        return 0

    print(json.dumps(data, ensure_ascii=False, indent=2))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Exa search for source-first research")
    parser.add_argument("--config", default="", help="Path to config JSON file")
    parser.add_argument("--api-key", default="", help="Override Exa API key (single key only)")
    parser.add_argument("--base-url", default="", help="Override base URL")
    parser.add_argument("--timeout", type=float, default=0.0, help="Request timeout in seconds")
    subparsers = parser.add_subparsers(dest="command", help="Commands")

    def add_output_flags(p):
        p.add_argument("--plain", action="store_true", help="Human-readable output")
        p.add_argument("--urls", action="store_true", help="Print URLs only")
        p.add_argument("--profile", default="", help="Force one configured profile id")

    def add_common_search_flags(p):
        p.add_argument("--query", required=True, help="Search query")
        p.add_argument("--num", type=int, default=5, help="Number of results")
        p.add_argument("--type", choices=["neural", "keyword", "magic"], default="neural")
        p.add_argument("--text", action="store_true", help="Include full text")
        p.add_argument("--highlights", action="store_true", help="Include highlights")
        p.add_argument("--start-date", help="ISO date filter")
        p.add_argument("--include-domains", help="Comma-separated domains")
        p.add_argument("--exclude-domains", help="Comma-separated domains")
        p.add_argument("--category", help="e.g. company, research paper, news")
        p.add_argument("--no-autoprompt", action="store_true", help="Disable Exa autoprompt")

    search_parser = subparsers.add_parser("search", help="General source-first search")
    add_output_flags(search_parser)
    add_common_search_flags(search_parser)

    docs_parser = subparsers.add_parser("docs", help="Official docs search (defaults to docs.openclaw.ai)")
    add_output_flags(docs_parser)
    add_common_search_flags(docs_parser)

    research_parser = subparsers.add_parser("research", help="Deep extraction mode")
    add_output_flags(research_parser)
    add_common_search_flags(research_parser)

    similar_parser = subparsers.add_parser("similar", help="Find similar pages")
    add_output_flags(similar_parser)
    similar_parser.add_argument("--url", required=True, help="Canonical URL")
    similar_parser.add_argument("--num", type=int, default=5, help="Number of results")

    args = parser.parse_args()

    config, config_paths, primary_config_path = _resolve_config(args.config)
    cli_api_key = _normalize_api_key(args.api_key)
    env_api_key = _normalize_api_key(os.environ.get("EXA_API_KEY", ""))
    env_api_keys = [
        key for key in (_normalize_api_key(p) for p in os.environ.get("EXA_API_KEYS", "").split(",")) if key
    ]
    forced_profile = getattr(args, "profile", "").strip()
    profiles = _extract_profiles(
        config,
        cli_api_key=cli_api_key,
        env_api_key=env_api_key,
        env_api_keys=env_api_keys,
        forced_profile=forced_profile,
    )

    if not profiles:
        detail = "Pass --api-key, set EXA_API_KEY/EXA_API_KEYS, or configure config.local.json/config.json"
        if forced_profile:
            detail += f" (requested profile: {forced_profile})"
        return _emit({
            "ok": False,
            "error": "missing_api_key",
            "detail": detail,
            "config_path": primary_config_path,
            "config_paths": config_paths,
        }, plain=getattr(args, "plain", False), urls_only=getattr(args, "urls", False))

    base_url = (args.base_url or os.environ.get("EXA_BASE_URL", "") or str(config.get("base_url") or "") or DEFAULT_BASE_URL).strip().rstrip("/")
    timeout_seconds = args.timeout or float(os.environ.get("EXA_TIMEOUT_SECONDS", "0") or 0) or float(config.get("timeout_seconds") or 30)

    started = time.time()
    attempts: list[dict[str, Any]] = []
    last_error: dict[str, Any] | None = None

    def emit_error(error_code: str, detail: str, failover_exhausted: bool = False) -> int:
        return _emit({
            "ok": False,
            "error": error_code,
            "detail": detail,
            "failoverExhausted": failover_exhausted,
            "attempts": attempts,
            "config_path": primary_config_path,
            "config_paths": config_paths,
            "base_url": base_url,
            "elapsed_ms": int((time.time() - started) * 1000),
        }, plain=getattr(args, "plain", False), urls_only=getattr(args, "urls", False))

    for idx, profile in enumerate(profiles):
        profile_base_url = (profile.get("base_url") or base_url).rstrip("/")
        try:
            if args.command in {"search", "docs", "research"}:
                include_domains = _normalize_csv(getattr(args, "include_domains", None))
                exclude_domains = _normalize_csv(getattr(args, "exclude_domains", None))
                include_text = bool(getattr(args, "text", False))
                include_highlights = bool(getattr(args, "highlights", False))
                category = getattr(args, "category", None)

                if args.command == "docs":
                    include_domains = include_domains or ["docs.openclaw.ai"]
                if args.command == "research" and not include_text and not include_highlights:
                    include_text = True

                raw = search_exa(
                    base_url=profile_base_url,
                    api_key=profile["api_key"],
                    query=args.query,
                    num_results=args.num,
                    search_type=args.type,
                    use_autoprompt=not args.no_autoprompt,
                    include_text=include_text,
                    include_highlights=include_highlights,
                    start_published_date=getattr(args, "start_date", None),
                    include_domains=include_domains,
                    exclude_domains=exclude_domains,
                    category=category,
                    timeout_seconds=timeout_seconds,
                )
                attempts.append({"profileId": profile["id"], "ok": True})
                data = {
                    "ok": True,
                    "mode": args.command,
                    "query": args.query,
                    "profileId": profile["id"],
                    "profileSource": profile.get("source") or "",
                    "attempts": attempts,
                    "config_path": primary_config_path,
                    "config_paths": config_paths,
                    "base_url": profile_base_url,
                    "resolvedSearchType": raw.get("resolvedSearchType") or args.type,
                    "requestId": raw.get("requestId"),
                    "searchTime": raw.get("searchTime"),
                    "costDollars": raw.get("costDollars"),
                    "results": [
                        _normalize_result(item, include_text=include_text, include_highlights=include_highlights)
                        for item in (raw.get("results") or [])
                    ],
                    "elapsed_ms": int((time.time() - started) * 1000),
                }
                return _emit(data, plain=getattr(args, "plain", False), urls_only=getattr(args, "urls", False))

            if args.command == "similar":
                raw = find_similar(
                    base_url=profile_base_url,
                    api_key=profile["api_key"],
                    url_to_match=args.url,
                    num_results=args.num,
                    timeout_seconds=timeout_seconds,
                )
                attempts.append({"profileId": profile["id"], "ok": True})
                data = {
                    "ok": True,
                    "mode": "similar",
                    "url": args.url,
                    "profileId": profile["id"],
                    "profileSource": profile.get("source") or "",
                    "attempts": attempts,
                    "config_path": primary_config_path,
                    "config_paths": config_paths,
                    "base_url": profile_base_url,
                    "requestId": raw.get("requestId"),
                    "searchTime": raw.get("searchTime"),
                    "costDollars": raw.get("costDollars"),
                    "results": [
                        _normalize_result(item, include_text=False, include_highlights=False)
                        for item in (raw.get("results") or [])
                    ],
                    "elapsed_ms": int((time.time() - started) * 1000),
                }
                return _emit(data, plain=getattr(args, "plain", False), urls_only=getattr(args, "urls", False))

            break
        except requests.HTTPError as e:
            status_code = getattr(e.response, "status_code", None)
            detail = ""
            try:
                detail = e.response.text or str(e)
            except Exception:
                detail = str(e)
            failover = _should_failover(status_code, detail)
            attempts.append({
                "profileId": profile["id"],
                "ok": False,
                "status": status_code,
                "failover": failover,
                "detail": _shorten(detail),
            })
            last_error = {
                "error": f"http_{status_code or 'error'}",
                "detail": detail,
                "failover": failover,
            }
            if failover and idx < len(profiles) - 1:
                continue
            break
        except Exception as e:
            detail = str(e)
            attempts.append({
                "profileId": profile["id"],
                "ok": False,
                "failover": False,
                "detail": _shorten(detail),
            })
            last_error = {
                "error": "request_failed",
                "detail": detail,
                "failover": False,
            }
            break

    if last_error:
        failover_exhausted = bool(last_error.get("failover")) and len(attempts) == len(profiles)
        error_code = "all_profiles_failed" if failover_exhausted and len(profiles) > 1 else str(last_error.get("error") or "request_failed")
        return emit_error(error_code, str(last_error.get("detail") or "Request failed"), failover_exhausted=failover_exhausted)

    parser.print_help()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env bash
set -euo pipefail

# Sub2API 管理端账号工具。
# 只依赖 bash + Python 标准库，不再依赖 jq。
# 默认读取脚本同目录的 .env，只使用 x-api-key 鉴权。

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd -- "$(dirname "$0")" && pwd)"
DEFAULT_ENV_FILE="${SCRIPT_DIR}/.env"
ENV_FILE="${SUB2API_ENV_FILE:-${DEFAULT_ENV_FILE}}"

load_sub2api_env_file() {
  local env_file="${1:-}"
  local -a preserved_names=()
  local -A preserved_values=()
  local var_name
  [[ -n "${env_file}" ]] || return 0
  [[ -f "${env_file}" ]] || return 0

  while IFS= read -r var_name; do
    [[ -n "${var_name}" ]] || continue
    preserved_names+=("${var_name}")
    preserved_values["${var_name}"]="${!var_name}"
  done < <(compgen -A variable SUB2API_ || true)

  # 只加载本工具约定的本地配置文件；调用方显式传入的 SUB2API_* 优先生效。
  # shellcheck disable=SC1090
  . "${env_file}"

  for var_name in "${preserved_names[@]}"; do
    printf -v "${var_name}" '%s' "${preserved_values[${var_name}]}"
    export "${var_name}"
  done

  # .env 通常只写 KEY=VALUE；Python 子进程只能读取 export 后的变量。
  while IFS= read -r var_name; do
    [[ -n "${var_name}" ]] || continue
    export "${var_name}"
  done < <(compgen -A variable SUB2API_ || true)
}

usage() {
  cat <<EOF
用法:
  ./${SCRIPT_NAME} [all|accounts|keys|usage|schedulable|disable|enable|delete|priority|bulk-update|raw] [选项]

说明:
  查询或更新 Sub2API 管理端账号状态。
  默认读取 ${DEFAULT_ENV_FILE}；如需覆盖路径，可设置 SUB2API_ENV_FILE。
  默认动作是 all，会先输出账号汇总，再输出令牌汇总。
  accounts/keys 列表默认写入:
    ${SCRIPT_DIR}/accounts.json
    ${SCRIPT_DIR}/keys.json
  其他动作仅在显式传 --output 时保存 JSON。
  本版本不依赖 jq，仅需要 Python 标准库。

选项:
  --base-url <url>          Sub2API 地址，也可用 SUB2API_BASE_URL
  --api-key <key>           x-api-key，也可用 SUB2API_API_KEY
  --output <path>           保存响应 JSON；未指定时按动作自动命名
  --account-id <id>         usage/schedulable/disable/enable/delete/priority 的账号 id
  --account-ids <csv>       bulk-update/priority 的账号 id 列表，例如 16,17
  --schedulable <bool>      schedulable 动作设置 true/false
  --priority <int>          priority/bulk-update 动作设置优先级
  SUB2API_PARALLELISM       accounts/keys 内部 usage 并发数，默认 6
  SUB2API_TIMEOUT           请求超时时间秒数，默认 30
  -h, --help                显示帮助

示例:
  SUB2API_BASE_URL='http://127.0.0.1:3335' SUB2API_API_KEY='***' ./${SCRIPT_NAME}
  ./${SCRIPT_NAME} accounts --base-url 'http://127.0.0.1:3335' --api-key '***'
  ./${SCRIPT_NAME} keys --base-url 'http://127.0.0.1:3335' --api-key '***'
  ./${SCRIPT_NAME} usage --account-id '15'
  ./${SCRIPT_NAME} disable --account-id '16'
  ./${SCRIPT_NAME} enable --account-id '16'
  ./${SCRIPT_NAME} delete --account-id '14'
  ./${SCRIPT_NAME} priority --account-id '16' --priority 1
EOF
}

die() {
  printf '[%s] 错误: %s\n' "${SCRIPT_NAME}" "$*" >&2
  exit 1
}

find_python() {
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys' >/dev/null 2>&1; then
    printf 'python3'
    return 0
  fi
  if command -v python >/dev/null 2>&1 && python -c 'import sys' >/dev/null 2>&1; then
    printf 'python'
    return 0
  fi
  if command -v py >/dev/null 2>&1 && py -3 -c 'import sys' >/dev/null 2>&1; then
    printf 'py -3'
    return 0
  fi
  die "缺少命令: python3 或 python"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

load_sub2api_env_file "${ENV_FILE}"

PYTHON_BIN="$(find_python)"
export SCRIPT_DIR

# Python 负责参数校验、HTTP 请求、JSON 归一化和 Markdown 渲染。
# 这里用 heredoc 保持单文件分发，避免额外脚本路径依赖。
${PYTHON_BIN} - "$@" <<'PY'
import argparse
import concurrent.futures
import datetime as dt
import json
import os
import ssl
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


SCRIPT_NAME = Path(sys.argv[0]).name or "query.sh"
SCRIPT_DIR = Path(os.environ.get("SCRIPT_DIR", "") or Path(__file__).resolve().parent)
DEFAULT_ACCOUNTS_PAGE_SIZE = 10
DEFAULT_KEYS_PAGE_SIZE = 20
DEFAULT_KEY_USAGE_PAGE_SIZE = 20
TIMEZONE = "Etc/GMT-8"
TODAY_DATE = dt.date.today().isoformat()
GENERATED_AT = dt.datetime.now(dt.timezone.utc).astimezone().isoformat()
DEFAULT_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36"
)


def fail(message: str) -> None:
    print(f"[query.sh] 错误: {message}", file=sys.stderr)
    raise SystemExit(1)


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


def number(value, default=0):
    if value is None or value == "":
        return default
    try:
        if isinstance(value, bool):
            return int(value)
        if isinstance(value, (int, float)):
            return value
        text = str(value).strip()
        if "." in text:
            return float(text)
        return int(text)
    except (TypeError, ValueError):
        return default


def get_path(data, *keys, default=None):
    current = data
    for key in keys:
        if not isinstance(current, dict) or key not in current:
            return default
        current = current[key]
    return current


def first_value(data, paths, default=None):
    for path in paths:
        value = get_path(data, *path, default=None)
        if value is not None:
            return value
    return default


def as_list(value):
    return value if isinstance(value, list) else []


def unique_text(values):
    result = []
    seen = set()
    for value in values:
        if value is None or value == "":
            continue
        text = str(value)
        if text in seen:
            continue
        seen.add(text)
        result.append(text)
    return result


def mask_secret(value):
    if value is None:
        return None
    text = str(value)
    if len(text) <= 12:
        return text
    return f"{text[:6]}...{text[-4:]}"


def bool_text(value):
    if value is None:
        return "-"
    return str(bool(value)).lower()


def format_remaining_quota(value):
    if value in (None, "", "null", "-"):
        return "-"
    try:
        return str(100 - float(value)).rstrip("0").rstrip(".")
    except (TypeError, ValueError):
        return str(value)


def format_tokens_m(value):
    try:
        return f"{float(value or 0) / 1_000_000:.2f}M"
    except (TypeError, ValueError):
        return str(value)


def format_display_time(value):
    if value in (None, "", "null", "-"):
        return "-"
    text = str(value)
    if text.isdigit():
        try:
            return dt.datetime.fromtimestamp(int(text)).strftime("%m-%d %H:%M:%S")
        except (OverflowError, OSError, ValueError):
            return text
    normalized = text.replace("Z", "+00:00")
    try:
        return dt.datetime.fromisoformat(normalized).strftime("%m-%d %H:%M:%S")
    except ValueError:
        return text


def markdown_cell(value):
    text = "-" if value is None or value == "" else str(value)
    return text.replace("|", "\\|").replace("\n", " ")


class Client:
    def __init__(self, base_url, api_key, timeout, user_agent):
        raw = base_url.rstrip("/")
        for suffix in ("/api/v1", "/api"):
            if raw.endswith(suffix):
                raw = raw[: -len(suffix)]
        self.base_url = raw
        self.api_key = api_key
        self.timeout = int(timeout)
        self.user_agent = user_agent
        self.ssl_context = ssl._create_unverified_context()

    def url(self, path, params=None):
        query = urllib.parse.urlencode(params or {})
        return f"{self.base_url}{path}" + (f"?{query}" if query else "")

    def referer(self, kind, account_id=None):
        if kind in {"usage", "usage_internal"}:
            return f"{self.base_url}/admin/accounts/{account_id}/usage"
        if kind in {"keys", "keys_internal"}:
            return f"{self.base_url}/keys"
        if kind == "key_usage_internal":
            return f"{self.base_url}/admin/usage/stats"
        return f"{self.base_url}/admin/accounts"

    def request(self, method, url, kind, account_id=None, body=None):
        headers = {
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "zh",
            "x-api-key": self.api_key,
            "Referer": self.referer(kind, account_id),
            "User-Agent": self.user_agent,
        }
        data = None
        if body is not None:
            headers["Content-Type"] = "application/json"
            data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=self.timeout, context=self.ssl_context) as response:
                payload = response.read()
        except urllib.error.HTTPError as exc:
            body_text = exc.read().decode("utf-8", "replace")[:800]
            print(
                f"[query.sh] HTTP_STATUS={exc.code} CONTENT_TYPE={exc.headers.get('content-type', 'unknown')} BODY_BYTES={len(body_text)}",
                file=sys.stderr,
            )
            if body_text:
                print(body_text, file=sys.stderr)
            raise
        except urllib.error.URLError as exc:
            print(f"[query.sh] 请求失败: {exc}", file=sys.stderr)
            raise
        if not payload:
            return {}
        try:
            return json.loads(payload.decode("utf-8"))
        except json.JSONDecodeError:
            return {"raw": payload.decode("utf-8", "replace")}

    def get_json(self, url, kind, account_id=None):
        return self.request("GET", url, kind, account_id)

    def post_json(self, url, body, kind, account_id=None):
        return self.request("POST", url, kind, account_id, body)

    def delete_json(self, url, kind, account_id=None):
        return self.request("DELETE", url, kind, account_id)


def build_accounts_url(client, page):
    return client.url(
        "/api/v1/admin/accounts",
        {
            "page": page,
            "page_size": DEFAULT_ACCOUNTS_PAGE_SIZE,
            "platform": "",
            "type": "",
            "status": "",
            "privacy_mode": "",
            "group": "",
            "search": "",
            "sort_by": "schedulable",
            "sort_order": "desc",
            "lite": "1",
            "timezone": TIMEZONE,
        },
    )


def build_keys_url(client, page):
    return client.url(
        "/api/v1/admin/users/1/api-keys",
        {"page": page, "page_size": DEFAULT_KEYS_PAGE_SIZE, "timezone": TIMEZONE},
    )


def build_usage_url(client, account_id):
    return client.url(f"/api/v1/admin/accounts/{account_id}/usage", {"timezone": TIMEZONE})


def build_key_usage_stats_url(client, api_key_id):
    return client.url(
        "/api/v1/admin/usage/stats",
        {"start_date": TODAY_DATE, "end_date": TODAY_DATE, "api_key_id": api_key_id, "timezone": TIMEZONE},
    )


def extract_page_items(payload, names):
    data = payload.get("data") if isinstance(payload.get("data"), dict) else payload
    for name in names:
        items = data.get(name) if isinstance(data, dict) else None
        if isinstance(items, list):
            return items
    return []


def page_count(payload):
    data = payload.get("data") if isinstance(payload.get("data"), dict) else payload
    return int(number(data.get("pages") if isinstance(data, dict) else 1, 1))


def total_count(payload):
    data = payload.get("data") if isinstance(payload.get("data"), dict) else payload
    return int(number(data.get("total") if isinstance(data, dict) else 0, 0))


def normalize_usage(payload, account_id):
    return {
        "code": payload.get("code", 0),
        "message": payload.get("message", payload.get("msg", "success")),
        "generated_at": GENERATED_AT,
        "data": {
            "account_id": int(account_id),
            "updated_at": first_value(payload, [("data", "updated_at"), ("updated_at",)]),
            "five_hour": {
                "utilization": first_value(payload, [("data", "five_hour", "utilization"), ("five_hour", "utilization")]),
                "resets_at": first_value(payload, [("data", "five_hour", "resets_at"), ("five_hour", "resets_at")]),
                "remaining_seconds": first_value(payload, [("data", "five_hour", "remaining_seconds"), ("five_hour", "remaining_seconds")]),
                "window_stats": first_value(payload, [("data", "five_hour", "window_stats"), ("five_hour", "window_stats")]),
            },
            "seven_day": {
                "utilization": first_value(payload, [("data", "seven_day", "utilization"), ("seven_day", "utilization")]),
                "resets_at": first_value(payload, [("data", "seven_day", "resets_at"), ("seven_day", "resets_at")]),
                "remaining_seconds": first_value(payload, [("data", "seven_day", "remaining_seconds"), ("seven_day", "remaining_seconds")]),
                "window_stats": first_value(payload, [("data", "seven_day", "window_stats"), ("seven_day", "window_stats")]),
            },
        },
    }


def normalize_schedulable(payload, account_id, desired):
    data = payload.get("data") if isinstance(payload.get("data"), dict) else payload
    credentials = data.get("credentials") if isinstance(data.get("credentials"), dict) else {}
    return {
        "code": payload.get("code", 0),
        "message": payload.get("message", payload.get("msg", "success")),
        "generated_at": GENERATED_AT,
        "data": {
            "account_id": int(account_id),
            "requested_schedulable": desired == "true",
            "current_schedulable": data.get("schedulable"),
            "name": data.get("name"),
            "platform": data.get("platform"),
            "type": data.get("type"),
            "status": data.get("status"),
            "error_message": data.get("error_message"),
            "credentials_disabled": credentials.get("disabled"),
            "priority": data.get("priority"),
            "updated_at": data.get("updated_at"),
            "rate_limited_at": data.get("rate_limited_at"),
            "rate_limit_reset_at": data.get("rate_limit_reset_at"),
            "overload_until": data.get("overload_until"),
            "temp_unschedulable_until": data.get("temp_unschedulable_until"),
            "temp_unschedulable_reason": data.get("temp_unschedulable_reason"),
            "session_window_start": data.get("session_window_start"),
            "session_window_end": data.get("session_window_end"),
            "session_window_status": data.get("session_window_status"),
        },
    }


def normalize_delete(payload, account_id):
    data = payload.get("data") if isinstance(payload.get("data"), dict) else payload
    return {
        "code": payload.get("code", 0),
        "message": payload.get("message", payload.get("msg", "success")),
        "generated_at": GENERATED_AT,
        "data": {
            "account_id": int(account_id),
            "deleted": True,
            "id": data.get("id"),
            "name": data.get("name"),
            "status": data.get("status"),
            "error_message": data.get("error_message"),
            "updated_at": data.get("updated_at"),
        },
    }


def normalize_bulk_update(payload, account_ids, priority):
    data = payload.get("data")
    updated_count = len(data) if isinstance(data, list) else None
    if isinstance(data, dict) and isinstance(data.get("items"), list):
        updated_count = len(data["items"])
    return {
        "code": payload.get("code", 0),
        "message": payload.get("message", payload.get("msg", "success")),
        "generated_at": GENERATED_AT,
        "data": {
            "account_ids": [int(item) for item in account_ids.split(",") if item],
            "requested_priority": int(priority),
            "updated_count": updated_count,
            "raw": data,
        },
    }


def build_account_item(account, usage=None, usage_error=None):
    credentials = account.get("credentials") if isinstance(account.get("credentials"), dict) else {}
    groups = as_list(account.get("groups"))
    return {
        "id": account.get("id"),
        "name": account.get("name"),
        "platform": account.get("platform"),
        "type": account.get("type"),
        "status": account.get("status"),
        "schedulable": account.get("schedulable"),
        "priority": account.get("priority"),
        "rate_multiplier": account.get("rate_multiplier"),
        "notes": account.get("notes"),
        "error_message": account.get("error_message"),
        "last_used_at": account.get("last_used_at"),
        "group_ids": account.get("group_ids") or [],
        "group_names": [group.get("name") for group in groups if isinstance(group, dict) and group.get("name")],
        "credentials": {
            "email": credentials.get("email"),
            "disabled": credentials.get("disabled"),
            "plan_type": credentials.get("plan_type"),
            "priority": credentials.get("priority"),
            "type": credentials.get("type"),
            "expires_at": credentials.get("expires_at"),
            "expired": credentials.get("expired"),
            "last_refresh": credentials.get("last_refresh"),
            "account_id": credentials.get("account_id"),
            "chatgpt_user_id": credentials.get("chatgpt_user_id"),
        },
        "usage": usage.get("data") if usage else None,
        "usage_error": usage_error,
        "account_updated_at": account.get("updated_at"),
    }


def raw_usage_5h(item):
    return get_path(item, "usage", "five_hour", "utilization")


def raw_usage_7d(item):
    return get_path(item, "usage", "seven_day", "utilization")


def raw_5h_tokens(item):
    return get_path(item, "usage", "five_hour", "window_stats", "tokens")


def raw_7d_tokens(item):
    return get_path(item, "usage", "seven_day", "window_stats", "tokens")


def remaining_quota_value(value):
    if value is None:
        return None
    try:
        return 100 - float(value)
    except (TypeError, ValueError):
        return None


def abnormal_reasons(item):
    reasons = []
    if item.get("usage_error"):
        reasons.append(f"usage 拉取失败: {item['usage_error']}")
    if item.get("error_message"):
        reasons.append(f"error_message: {item['error_message']}")
    if (item.get("status") or "") != "active":
        reasons.append(f"status={item.get('status') or 'unknown'}")
    if get_path(item, "usage", "five_hour", "resets_at") is None:
        reasons.append("five_hour.resets_at=null")
    if get_path(item, "usage", "seven_day", "resets_at") is None:
        reasons.append("seven_day.resets_at=null")
    if get_path(item, "credentials", "disabled") is True:
        reasons.append("credentials.disabled=true")
    if reasons == ["credentials.disabled=true"]:
        return []
    return reasons


def summary_item(item):
    five = raw_usage_5h(item)
    week = raw_usage_7d(item)
    return {
        "id": item.get("id"),
        "name": item.get("name"),
        "平台": item.get("platform"),
        "类型": item.get("type"),
        "账号状态": item.get("status"),
        "调度状态": "可调度" if item.get("schedulable") is True else "不可调度",
        "套餐": get_path(item, "credentials", "plan_type"),
        "优先级": item.get("priority") if item.get("priority") is not None else get_path(item, "credentials", "priority"),
        "过期时间": get_path(item, "credentials", "expires_at"),
        "最近使用时间": item.get("last_used_at"),
        "限额状态": item.get("summary_status"),
        "异常原因": item.get("summary_reasons") or [],
        "5h限额": {
            "utilization": five,
            "remaining": remaining_quota_value(five),
            "resets_at": get_path(item, "usage", "five_hour", "resets_at"),
            "tokens": raw_5h_tokens(item),
        },
        "周限额": {
            "utilization": week,
            "remaining": remaining_quota_value(week),
            "resets_at": get_path(item, "usage", "seven_day", "resets_at"),
            "tokens": raw_7d_tokens(item),
        },
        "usage_updated_at": get_path(item, "usage", "updated_at"),
    }


def normalize_accounts_with_usage(client, accounts_payload, parallelism):
    pages = page_count(accounts_payload)
    total = total_count(accounts_payload)
    accounts = extract_page_items(accounts_payload, ["items", "accounts", "list"])

    def with_usage(account):
        account_id = account.get("id")
        try:
            usage = normalize_usage(client.get_json(build_usage_url(client, account_id), "usage_internal", account_id), account_id)
            return build_account_item(account, usage)
        except Exception:
            return build_account_item(account, None, "usage_request_failed")

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, parallelism)) as pool:
        items = list(pool.map(with_usage, accounts))

    usage_failed = sum(1 for item in items if item.get("usage_error"))
    for item in items:
        reasons = abnormal_reasons(item)
        item["summary_reasons"] = reasons
        item["summary_status"] = "异常" if reasons else "正常"

    normal_items = [item for item in items if item["summary_status"] == "正常"]
    abnormal_items = [item for item in items if item["summary_status"] == "异常"]

    def usable_5h_remaining(item):
        five = raw_usage_5h(item)
        week = raw_usage_7d(item)
        five_remaining = remaining_quota_value(five)
        week_remaining = remaining_quota_value(week)
        if five_remaining is None:
            return None
        if week_remaining is None or week_remaining > 0:
            return five_remaining
        return None

    return {
        "code": 0,
        "message": "success",
        "generated_at": GENERATED_AT,
        "data": {
            "pages": pages,
            "page_size": DEFAULT_ACCOUNTS_PAGE_SIZE,
            "count": len(items),
            "total": total,
            "usage_failed": usage_failed,
            "summary": {
                "5h限额汇总": {
                    "account_count": len(normal_items),
                    "known_count": sum(1 for item in normal_items if raw_usage_5h(item) is not None),
                    "utilization_sum": sum(number(raw_usage_5h(item), 0) for item in normal_items if raw_usage_5h(item) is not None),
                    "remaining_sum": sum(number(usable_5h_remaining(item), 0) for item in normal_items if usable_5h_remaining(item) is not None),
                },
                "周限额汇总": {
                    "account_count": len(normal_items),
                    "known_count": sum(1 for item in normal_items if raw_usage_7d(item) is not None),
                    "utilization_sum": sum(number(raw_usage_7d(item), 0) for item in normal_items if raw_usage_7d(item) is not None),
                    "remaining_sum": sum(number(remaining_quota_value(raw_usage_7d(item)), 0) for item in normal_items if raw_usage_7d(item) is not None),
                },
                "正常账号数": len(normal_items),
                "异常账号数": len(abnormal_items),
                "正常账号汇总": {
                    "account_count": len(normal_items),
                    "5h_tokens_sum": sum(number(raw_5h_tokens(item), 0) for item in normal_items),
                    "周_tokens_sum": sum(number(raw_7d_tokens(item), 0) for item in normal_items),
                },
                "异常账号汇总": {
                    "account_count": len(abnormal_items),
                    "5h_tokens_sum": sum(number(raw_5h_tokens(item), 0) for item in abnormal_items),
                    "周_tokens_sum": sum(number(raw_7d_tokens(item), 0) for item in abnormal_items),
                },
                "账号限额列表": [summary_item(item) for item in items],
                "正常账号": [summary_item(item) for item in normal_items],
                "异常账号": [summary_item(item) for item in abnormal_items],
            },
            "items": items,
        },
    }


def fetch_all_accounts(client, parallelism):
    first = client.get_json(build_accounts_url(client, 1), "accounts_internal")
    pages = page_count(first)
    total = total_count(first)
    items = extract_page_items(first, ["items", "accounts", "list"])
    for page in range(2, pages + 1):
        payload = client.get_json(build_accounts_url(client, page), "accounts_internal")
        items.extend(extract_page_items(payload, ["items", "accounts", "list"]))
    return normalize_accounts_with_usage(client, {"pages": pages, "total": total, "items": items}, parallelism)


def fetch_key_usage_stats(client, key_id):
    payload = client.get_json(build_key_usage_stats_url(client, key_id), "key_usage_internal")
    data = payload.get("data") if isinstance(payload.get("data"), dict) else payload
    return data if isinstance(data, dict) else {}


def build_key_item(key, usage_stats=None, usage_error=None):
    usage_stats = usage_stats or {}
    status = key.get("status")
    if status is None:
        status = "disabled" if key.get("disabled") is True or key.get("enabled") is False else "active"
    return {
        "id": key.get("id"),
        "name": key.get("name") or key.get("label") or key.get("title"),
        "key_preview": mask_secret(key.get("key") or key.get("token") or key.get("value") or key.get("prefix") or key.get("key_preview") or key.get("preview")),
        "status": status,
        "enabled": key.get("enabled") if key.get("enabled") is not None else (False if key.get("disabled") is True else None),
        "created_at": key.get("created_at"),
        "updated_at": key.get("updated_at"),
        "expires_at": key.get("expires_at"),
        "last_used_at": key.get("last_used_at"),
        "usage_error": usage_error,
        "usage": {
            "date": TODAY_DATE,
            "request_count": number(
                first_value(usage_stats, [("request_count",), ("total_requests",), ("requests",), ("count",)], 0),
                0,
            ),
            "input_tokens": number(usage_stats.get("total_input_tokens"), 0),
            "output_tokens": number(usage_stats.get("total_output_tokens"), 0),
            "account_names": [],
            "models": [],
            "ip_addresses": [],
            "stats": usage_stats,
        },
    }


def fetch_all_keys(client, parallelism):
    first = client.get_json(build_keys_url(client, 1), "keys_internal")
    pages = page_count(first)
    total = total_count(first)
    keys = extract_page_items(first, ["items", "keys", "list"])
    for page in range(2, pages + 1):
        payload = client.get_json(build_keys_url(client, page), "keys_internal")
        keys.extend(extract_page_items(payload, ["items", "keys", "list"]))

    def with_usage(key):
        key_id = key.get("id")
        try:
            return build_key_item(key, fetch_key_usage_stats(client, key_id))
        except Exception:
            return build_key_item(key, None, "usage_request_failed")

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, parallelism)) as pool:
        items = list(pool.map(with_usage, keys))
    return {
        "code": 0,
        "message": "success",
        "generated_at": GENERATED_AT,
        "data": {
            "date": TODAY_DATE,
            "pages": pages,
            "page_size": DEFAULT_KEYS_PAGE_SIZE,
            "count": len(items),
            "total": total,
            "usage_failed": sum(1 for item in items if item.get("usage_error")),
            "summary": {
                "request_count": sum(number(get_path(item, "usage", "request_count"), 0) for item in items),
                "input_tokens": sum(number(get_path(item, "usage", "input_tokens"), 0) for item in items),
                "output_tokens": sum(number(get_path(item, "usage", "output_tokens"), 0) for item in items),
            },
            "items": items,
        },
    }


def write_json(path, payload):
    if not path:
        return
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def render_usage(payload):
    data = payload["data"]
    lines = [
        "# Sub2API 单账号 Usage",
        "",
        "| 字段 | 值 |",
        "| --- | --- |",
        f"| 生成时间 | {payload.get('generated_at', '-')} |",
        f"| 账号 ID | {data.get('account_id', '-')} |",
        f"| 更新时间 | {format_display_time(data.get('updated_at'))} |",
        f"| 5h 剩余额度 | {format_remaining_quota(get_path(data, 'five_hour', 'utilization'))} |",
        f"| 5h 重置时间 | {format_display_time(get_path(data, 'five_hour', 'resets_at'))} |",
        f"| 周剩余额度 | {format_remaining_quota(get_path(data, 'seven_day', 'utilization'))} |",
        f"| 周重置时间 | {format_display_time(get_path(data, 'seven_day', 'resets_at'))} |",
    ]
    return "\n".join(lines) + "\n"


def render_schedulable(payload):
    data = payload["data"]
    rows = [
        ("生成时间", payload.get("generated_at", "-")),
        ("账号 ID", data.get("account_id")),
        ("账号", data.get("name")),
        ("请求调度状态", bool_text(data.get("requested_schedulable"))),
        ("当前调度状态", bool_text(data.get("current_schedulable"))),
        ("账号状态", data.get("status")),
        ("凭证禁用", bool_text(data.get("credentials_disabled"))),
        ("优先级", data.get("priority")),
        ("错误信息", data.get("error_message")),
        ("更新时间", format_display_time(data.get("updated_at"))),
        ("限流开始", format_display_time(data.get("rate_limited_at"))),
        ("限流恢复", format_display_time(data.get("rate_limit_reset_at"))),
        ("过载截止", format_display_time(data.get("overload_until"))),
        ("临时不可调度截止", format_display_time(data.get("temp_unschedulable_until"))),
        ("临时不可调度原因", data.get("temp_unschedulable_reason")),
        ("会话窗口开始", format_display_time(data.get("session_window_start"))),
        ("会话窗口结束", format_display_time(data.get("session_window_end"))),
        ("会话窗口状态", data.get("session_window_status")),
    ]
    lines = ["# Sub2API 账号调度状态更新", "", "| 字段 | 值 |", "| --- | --- |"]
    lines.extend(f"| {name} | {markdown_cell(value)} |" for name, value in rows)
    return "\n".join(lines) + "\n"


def render_delete(payload):
    data = payload["data"]
    rows = [
        ("生成时间", payload.get("generated_at", "-")),
        ("账号 ID", data.get("account_id")),
        ("删除结果", data.get("deleted")),
        ("账号", data.get("name")),
        ("状态", data.get("status")),
        ("错误信息", data.get("error_message")),
        ("更新时间", format_display_time(data.get("updated_at"))),
    ]
    lines = ["# Sub2API 账号删除结果", "", "| 字段 | 值 |", "| --- | --- |"]
    lines.extend(f"| {name} | {markdown_cell(value)} |" for name, value in rows)
    return "\n".join(lines) + "\n"


def render_bulk_update(payload):
    data = payload["data"]
    rows = [
        ("生成时间", payload.get("generated_at", "-")),
        ("账号 ID 列表", ", ".join(str(item) for item in data.get("account_ids", []))),
        ("请求优先级", data.get("requested_priority")),
        ("更新数量", data.get("updated_count")),
        ("返回消息", payload.get("message")),
    ]
    lines = ["# Sub2API 批量优先级更新结果", "", "| 字段 | 值 |", "| --- | --- |"]
    lines.extend(f"| {name} | {markdown_cell(value)} |" for name, value in rows)
    return "\n".join(lines) + "\n"


def render_keys(payload):
    data = payload["data"]
    summary = data["summary"]
    lines = [
        "# Sub2API 令牌汇总",
        "",
        "| 指标 | 值 |",
        "| --- | ---: |",
        f"| 生成时间 | {payload.get('generated_at', '-')} |",
        f"| 日期 | {data.get('date', '-')} |",
        f"| 页数 | {data.get('pages', '-')} |",
        f"| 每页条数 | {data.get('page_size', '-')} |",
        f"| 令牌总数 | {data.get('total', '-')} |",
        f"| 今日请求数 | {summary.get('request_count', 0)} |",
        f"| 输入 tokens | {summary.get('input_tokens', 0)}（{format_tokens_m(summary.get('input_tokens', 0))}） |",
        f"| 输出 tokens | {summary.get('output_tokens', 0)}（{format_tokens_m(summary.get('output_tokens', 0))}） |",
        "",
        "## 令牌列表",
        "",
        "| ID | 名称 | 令牌 | 状态 | 创建时间 | 最近使用时间 | 今日请求 | 账号 | 模型 | IP | 输入tokens(M) | 输出tokens(M) |",
        "| --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | ---: | ---: |",
    ]
    if not data.get("items"):
        lines.append("| - | - | - | - | - | - | - | - | - | - | - | - |")
    for item in data.get("items", []):
        usage = item.get("usage", {})
        lines.append(
            "| {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} |".format(
                markdown_cell(item.get("id")),
                markdown_cell(item.get("name")),
                markdown_cell(item.get("key_preview")),
                markdown_cell(item.get("status")),
                markdown_cell(format_display_time(item.get("created_at"))),
                markdown_cell(format_display_time(item.get("last_used_at"))),
                markdown_cell(usage.get("request_count", 0)),
                markdown_cell(", ".join(usage.get("account_names") or []) or "-"),
                markdown_cell(", ".join(usage.get("models") or []) or "-"),
                markdown_cell(", ".join(usage.get("ip_addresses") or []) or "-"),
                markdown_cell(format_tokens_m(usage.get("input_tokens", 0))),
                markdown_cell(format_tokens_m(usage.get("output_tokens", 0))),
            )
        )
    return "\n".join(lines) + "\n"


def render_accounts(payload):
    data = payload["data"]
    summary = data["summary"]
    normal = summary.get("正常账号", [])
    abnormal = summary.get("异常账号", [])
    lines = [
        "# Sub2API 账号汇总",
        "",
        "| 指标 | 值 |",
        "| --- | ---: |",
        f"| 生成时间 | {payload.get('generated_at', '-')} |",
        f"| 页数 | {data.get('pages', '-')} |",
        f"| 每页条数 | {data.get('page_size', '-')} |",
        f"| 账号总数 | {data.get('total', '-')} |",
        f"| 正常账号 | {summary.get('正常账号数', 0)} |",
        f"| 异常账号 | {summary.get('异常账号数', 0)} |",
        f"| 5h 限额汇总 | {get_path(summary, '5h限额汇总', 'remaining_sum') or 0} |",
        f"| 周限额汇总 | {get_path(summary, '周限额汇总', 'remaining_sum') or 0} |",
        "",
        f"## 正常账号（{summary.get('正常账号数', 0)}个 | 5h tokens {format_tokens_m(get_path(summary, '正常账号汇总', '5h_tokens_sum') or 0)} | 周 tokens {format_tokens_m(get_path(summary, '正常账号汇总', '周_tokens_sum') or 0)}）",
        "",
        "| ID | 账号 | 套餐 | 优先级 | 过期时间 | 最近使用时间 | 5h限额 | 周限额 | 5h消耗 | 周消耗 | 5h刷新时间 | 周刷新时间 |",
        "| --- | --- | --- | ---: | --- | --- | ---: | ---: | ---: | ---: | --- | --- |",
    ]
    if not normal:
        lines.append("| - | - | - | - | - | - | - | - | - | - | - | - |")
    normal_sorted = sorted(
        normal,
        key=lambda item: (
            number(item.get("优先级"), 999999),
            "" if item.get("最近使用时间") in (None, "-") else str(item.get("最近使用时间")),
        ),
    )
    for item in normal_sorted:
        lines.append(
            "| {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} |".format(
                markdown_cell(item.get("id")),
                markdown_cell(item.get("name")),
                markdown_cell(item.get("套餐")),
                markdown_cell(item.get("优先级")),
                markdown_cell(format_display_time(item.get("过期时间"))),
                markdown_cell(format_display_time(item.get("最近使用时间"))),
                markdown_cell(format_remaining_quota(get_path(item, "5h限额", "utilization"))),
                markdown_cell(format_remaining_quota(get_path(item, "周限额", "utilization"))),
                markdown_cell(format_tokens_m(get_path(item, "5h限额", "tokens"))),
                markdown_cell(format_tokens_m(get_path(item, "周限额", "tokens"))),
                markdown_cell(format_display_time(get_path(item, "5h限额", "resets_at"))),
                markdown_cell(format_display_time(get_path(item, "周限额", "resets_at"))),
            )
        )
    lines.extend(
        [
            "",
            f"## 异常账号（{summary.get('异常账号数', 0)}个 | 5h tokens {format_tokens_m(get_path(summary, '异常账号汇总', '5h_tokens_sum') or 0)} | 周 tokens {format_tokens_m(get_path(summary, '异常账号汇总', '周_tokens_sum') or 0)}）",
            "",
            "| ID | 账号 | 套餐 | 优先级 | 过期时间 | 最近使用时间 | 账号状态 | 调度状态 | 5h限额 | 周限额 | 5h消耗 | 周消耗 | 异常原因 |",
            "| --- | --- | --- | ---: | --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- |",
        ]
    )
    if not abnormal:
        lines.append("| - | - | - | - | - | - | - | - | - | - | - | - | - |")
    for item in abnormal:
        lines.append(
            "| {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} |".format(
                markdown_cell(item.get("id")),
                markdown_cell(item.get("name")),
                markdown_cell(item.get("套餐")),
                markdown_cell(item.get("优先级")),
                markdown_cell(format_display_time(item.get("过期时间"))),
                markdown_cell(format_display_time(item.get("最近使用时间"))),
                markdown_cell(item.get("账号状态")),
                markdown_cell(item.get("调度状态")),
                markdown_cell(format_remaining_quota(get_path(item, "5h限额", "utilization"))),
                markdown_cell(format_remaining_quota(get_path(item, "周限额", "utilization"))),
                markdown_cell(format_tokens_m(get_path(item, "5h限额", "tokens"))),
                markdown_cell(format_tokens_m(get_path(item, "周限额", "tokens"))),
                markdown_cell("; ".join(item.get("异常原因") or [])),
            )
        )
    return "\n".join(lines) + "\n"


def resolved_output(action, output):
    if output:
        return output
    if action == "keys":
        return str(SCRIPT_DIR / "keys.json")
    return str(SCRIPT_DIR / "accounts.json")


def parse_args(argv):
    action = "all"
    rest = list(argv)
    if rest and not rest[0].startswith("-"):
        action = rest.pop(0)
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--base-url", default=env("SUB2API_BASE_URL"))
    parser.add_argument("--api-key", "--key", dest="api_key", default=env("SUB2API_API_KEY"))
    parser.add_argument("--output", default=env("SUB2API_OUTPUT_FILE"))
    parser.add_argument("--account-id", "--id", dest="account_id", default=env("SUB2API_ACCOUNT_ID"))
    parser.add_argument("--account-ids", default=env("SUB2API_ACCOUNT_IDS"))
    parser.add_argument("--schedulable", default=env("SUB2API_SCHEDULABLE"))
    parser.add_argument("--priority", default=env("SUB2API_PRIORITY"))
    ns, unknown = parser.parse_known_args(rest)
    if unknown:
        fail(f"未知参数: {unknown[0]}")
    ns.action = action
    return ns


def normalize_bool(value):
    text = str(value or "").lower()
    if text in {"true", "1", "yes", "y", "on"}:
        return "true"
    if text in {"false", "0", "no", "n", "off"}:
        return "false"
    fail("SCHEDULABLE 需要 true/false")


def validate(ns):
    allowed = {"all", "accounts", "keys", "usage", "schedulable", "disable", "enable", "delete", "priority", "bulk-update", "raw"}
    if ns.action not in allowed:
        fail(f"未知动作: {ns.action}")
    if ns.action == "priority":
        ns.action = "bulk-update"
    if not ns.base_url:
        fail("缺少 SUB2API_BASE_URL 或 --base-url")
    if not ns.api_key:
        fail("缺少 SUB2API_API_KEY 或 --api-key")
    if ns.action in {"usage", "schedulable", "disable", "enable", "delete"}:
        if not str(ns.account_id or "").isdigit():
            fail("该动作需要 SUB2API_ACCOUNT_ID 或 --account-id 整数")
    if ns.action == "bulk-update":
        if not ns.account_ids:
            if not str(ns.account_id or "").isdigit():
                fail("bulk-update 动作需要 --account-id 或 --account-ids")
            ns.account_ids = str(ns.account_id)
        ns.account_ids = "".join(str(ns.account_ids).split())
        parts = ns.account_ids.split(",")
        if not parts or any(not part.isdigit() for part in parts):
            fail("ACCOUNT_IDS 需要逗号分隔整数，例如 16,17")
        if not str(ns.priority or "").lstrip("-").isdigit():
            fail("bulk-update 动作需要 --priority 整数")
    if ns.action == "disable":
        ns.schedulable = "false"
    if ns.action == "enable":
        ns.schedulable = "true"
    if ns.action in {"schedulable", "disable", "enable"}:
        ns.schedulable = normalize_bool(ns.schedulable)
    return ns


def main(argv):
    ns = validate(parse_args(argv))
    timeout = int(env("SUB2API_TIMEOUT", "30"))
    parallelism = max(1, int(env("SUB2API_PARALLELISM", "6")))
    user_agent = env("SUB2API_USER_AGENT", DEFAULT_UA)
    client = Client(ns.base_url, ns.api_key, timeout, user_agent)

    if ns.action == "all":
        accounts_output = str(SCRIPT_DIR / "accounts.json")
        keys_output = str(SCRIPT_DIR / "keys.json")
        accounts = fetch_all_accounts(client, parallelism)
        write_json(accounts_output, accounts)
        print(render_accounts(accounts), end="")
        print()
        keys = fetch_all_keys(client, parallelism)
        write_json(keys_output, keys)
        print(render_keys(keys), end="")
        return

    output_file = resolved_output(ns.action, ns.output)
    if ns.action == "accounts":
        payload = fetch_all_accounts(client, parallelism)
        write_json(output_file, payload)
        print(render_accounts(payload), end="")
    elif ns.action == "keys":
        payload = fetch_all_keys(client, parallelism)
        write_json(output_file, payload)
        print(render_keys(payload), end="")
    elif ns.action == "raw":
        payload = client.get_json(build_accounts_url(client, 1), "raw")
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    elif ns.action == "usage":
        payload = normalize_usage(client.get_json(build_usage_url(client, ns.account_id), "usage", ns.account_id), ns.account_id)
        if ns.output:
            write_json(output_file, payload)
        print(render_usage(payload), end="")
    elif ns.action in {"schedulable", "disable", "enable"}:
        url = client.url(f"/api/v1/admin/accounts/{ns.account_id}/schedulable")
        raw = client.post_json(url, {"schedulable": ns.schedulable == "true"}, ns.action, ns.account_id)
        payload = normalize_schedulable(raw, ns.account_id, ns.schedulable)
        if ns.output:
            write_json(output_file, payload)
        print(render_schedulable(payload), end="")
    elif ns.action == "delete":
        raw = client.delete_json(client.url(f"/api/v1/admin/accounts/{ns.account_id}"), "delete", ns.account_id)
        payload = normalize_delete(raw, ns.account_id)
        if ns.output:
            write_json(output_file, payload)
        print(render_delete(payload), end="")
    elif ns.action == "bulk-update":
        body = {"account_ids": [int(item) for item in ns.account_ids.split(",")], "priority": int(ns.priority)}
        raw = client.post_json(client.url("/api/v1/admin/accounts/bulk-update"), body, "bulk-update")
        payload = normalize_bulk_update(raw, ns.account_ids, ns.priority)
        if ns.output:
            write_json(output_file, payload)
        print(render_bulk_update(payload), end="")


if __name__ == "__main__":
    main(sys.argv[1:])
PY

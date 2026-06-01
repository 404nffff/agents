#!/usr/bin/env python3
import json
import math
import urllib.request
import urllib.parse
from pathlib import Path
from datetime import datetime, timezone
ENV_PATH = Path('/opt/data/workspace/shell/sub2api/.env')
TIMEZONE = 'Etc/GMT-8'
def parse_env(path: Path):
    vals = {}
    for raw in path.read_text(encoding='utf-8').splitlines():
        line = raw.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        k, v = line.split('=', 1)
        vals[k.strip()] = v.strip().strip('"').strip("'")
    return vals
def fmt_time(ts: str) -> str:
    if not ts:
        return '-'
    try:
        return datetime.fromisoformat(ts.replace('Z', '+00:00')).strftime('%m-%d %H:%M:%S')
    except Exception:
        return str(ts)
def fmt_m(n: int) -> str:
    return f"{n / 1_000_000:.2f}M"
def main():
    env = parse_env(ENV_PATH)
    base = env['SUB2API_BASE_URL'].rstrip('/')
    api_key = env['SUB2API_API_KEY']
    headers = {
        'x-api-key': api_key,
        'accept': 'application/json',
        'user-agent': 'Mozilla/5.0',
    }
    def get_json(url: str):
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)
    accounts_url = f"{base}/api/v1/admin/accounts?timezone={urllib.parse.quote(TIMEZONE)}&page=1&page_size=100&sort_by=schedulable&sort_order=desc&lite=1"
    accounts_data = get_json(accounts_url)
    accounts = ((accounts_data.get('data') or {}).get('items') or accounts_data.get('items') or [])
    def get_usage(account_id: int):
        url = f"{base}/api/v1/admin/accounts/{account_id}/usage?timezone={urllib.parse.quote(TIMEZONE)}"
        data = get_json(url)
        return data.get('data', data)
    usages = {acct['id']: get_usage(acct['id']) for acct in accounts}
    total = len(accounts)
    normal_rows = []
    abnormal_rows = []
    card2_rows = []
    weekly_rows = []
    expiring_rows = []
    now = datetime.now(timezone.utc)
    for acct in accounts:
        usage = usages.get(acct['id'], {}) or {}
        extra = acct.get('extra') or {}
        five_used = (usage.get('five_hour') or {}).get('utilization')
        week_used = (usage.get('seven_day') or {}).get('utilization')
        if five_used is None:
            five_used = extra.get('codex_5h_used_percent')
        if week_used is None:
            week_used = extra.get('codex_7d_used_percent')
        five_remaining_raw = None if five_used is None else max(0, 100 - int(five_used))
        week_remaining = None if week_used is None else max(0, 100 - int(week_used))
        five_remaining = None if five_remaining_raw is None or week_remaining is None else (0 if week_remaining <= 0 else five_remaining_raw)
        is_normal = acct.get('status') == 'active' and acct.get('schedulable') is True
        row = {
            'id': acct['id'],
            'name': acct['name'],
            'priority': acct.get('priority') if acct.get('priority') is not None else 9999,
            'five_remaining': five_remaining or 0,
            'week_remaining': week_remaining or 0,
            'five_reset_at': (usage.get('five_hour') or {}).get('resets_at'),
            'week_reset_at': (usage.get('seven_day') or {}).get('resets_at'),
            'error_message': acct.get('error_message') or '',
        }
        if is_normal:
            normal_rows.append(row)
            if row['five_reset_at'] and row['week_remaining'] > 0:
                card2_rows.append(row)
            if row['week_reset_at'] and row['week_remaining'] > 0:
                weekly_rows.append(row)
            cred = acct.get('credentials') or {}
            exp = cred.get('expires_at') or acct.get('expires_at')
            if exp:
                try:
                    if isinstance(exp, (int, float)) or (isinstance(exp, str) and exp.isdigit()):
                        ts = int(exp)
                        if ts > 0:
                            dt = datetime.fromtimestamp(ts, tz=timezone.utc)
                        else:
                            dt = None
                    else:
                        dt = datetime.fromisoformat(str(exp).replace('Z', '+00:00')).astimezone(timezone.utc)
                    if dt is not None:
                        days_left = (dt - now).total_seconds() / 86400
                        expiring_rows.append((acct['name'], math.floor(days_left) if days_left >= 0 else math.floor(days_left), days_left))
                except Exception:
                    pass
        else:
            abnormal_rows.append(acct)
    card2_rows.sort(key=lambda x: (x['priority'], x['five_reset_at']))
    weekly_rows.sort(key=lambda x: (x['priority'], x['week_reset_at']))
    expiring_rows.sort(key=lambda x: x[2])
    token_revoked = []
    refresh_bad = []
    missing_refresh = []
    for acct in abnormal_rows:
        name = acct['name']
        msg = (acct.get('error_message') or '').lower()
        if 'token revoked' in msg:
            token_revoked.append(name)
        elif 'refresh_token_reused' in msg or 'refresh token' in msg:
            refresh_bad.append(name)
        else:
            missing_refresh.append(name)
    keys_url = f"{base}/api/v1/admin/users/1/api-keys?page=1&page_size=100&sort_by=created_at&sort_order=desc&timezone={urllib.parse.quote(TIMEZONE)}"
    keys_data = get_json(keys_url)
    keys = ((keys_data.get('data') or {}).get('items') or keys_data.get('items') or [])
    today = datetime.now().strftime('%Y-%m-%d')
    used_keys = []
    for key in keys:
        kid = key.get('id')
        name = key.get('name')
        url = f"{base}/api/v1/admin/usage?start_date={today}&end_date={today}&api_key_id={kid}&sort_by=created_at&sort_order=desc&timezone={urllib.parse.quote(TIMEZONE)}&page=1&page_size=100"
        data = get_json(url)
        items = ((data.get('data') or {}).get('items') or (data.get('data') or {}).get('usages') or data.get('items') or [])
        in_tok = 0
        out_tok = 0
        for it in items:
            usage = it.get('usage') or {}
            in_tok += int(it.get('input_tokens') or it.get('prompt_tokens') or usage.get('input_tokens') or usage.get('prompt_tokens') or 0)
            out_tok += int(it.get('output_tokens') or it.get('completion_tokens') or usage.get('output_tokens') or usage.get('completion_tokens') or 0)
        if in_tok or out_tok:
            used_keys.append((name, in_tok, out_tok))
    normal_count = len(normal_rows)
    abnormal_count = len(abnormal_rows)
    card2_count = len(card2_rows)
    five_total = sum(r['five_remaining'] for r in normal_rows)
    week_total = sum(r['week_remaining'] for r in normal_rows)
    markers = ['①','②','③','④','⑤','⑥','⑦','⑧','⑨','⑩']
    lines = []
    lines.append('# Sub2API 卡片版汇报')
    lines.append('')
    lines.append('## 📊 卡片 1｜总体情况')
    lines.append(f'`账号` **{total}** ｜ `正常` **{normal_count}** ｜ `异常` **{abnormal_count}**  ')
    lines.append(f'`5h总剩余` **{five_total}** ｜ `周总剩余` **{week_total}**')
    lines.append('')
    lines.append('> 本版数据已按实时接口重新组装，已排除异常账号干扰。')
    lines.append('')
    lines.append('## ⏱️ 卡片 2｜最近 5h 可用账号')
    lines.append(f'`可用账号数` **{card2_count}** ｜ `5h可用汇总` **{five_total}** ｜ `周可用汇总` **{week_total}**')
    lines.append('')
    lines.append('> 仅保留 **当前正常可调度** 且 **周额度仍大于 0** 的账号，按 **5h 时间升序** 展示。')
    lines.append('')
    for idx, row in enumerate(card2_rows, 1):
        marker = markers[idx - 1] if idx <= len(markers) else str(idx)
        lines.append(f'**{marker} {row["name"]}**  ')
        lines.append(f'`{fmt_time(row["five_reset_at"] )}` ｜ 5h/week **({row["five_remaining"]}/{row["week_remaining"]})**')
        lines.append('')
    lines.append('## 🔄 卡片 3｜周刷新列表')
    lines.append(f'`周可用账号数` **{len(weekly_rows)}** ｜ `5h可用汇总` **{five_total}** ｜
`周可用汇总` **{week_total}**')
    lines.append('')
    lines.append('> 仅保留 **当前正常可调度** 且 **周额度仍大于 0** 的账号，按 **周刷新时间升序** 展示。')
    lines.append('')
    for idx, row in enumerate(weekly_rows, 1):
        marker = markers[idx - 1] if idx <= len(markers) else str(idx)
        lines.append(f'**{marker} {row["name"]}**  ')
        lines.append(f'`{fmt_time(row["week_reset_at"] )}` ｜ 5h/week **({row["five_remaining"]}/{row["week_remaining"]})**')
        lines.append('')
    lines.append('## ⚠️ 卡片 4｜异常账号情况')
    lines.append(f'`异常账号数` **{abnormal_count}** ｜ `Token revoked` **{len(token_revoked)}** ｜ `Refresh异常` **{len(refresh_bad)}** ｜ `缺refresh_token` **{len(missing_refresh)}**')
    lines.append('')
    if token_revoked:
        lines.append('- **Token revoked**：' + '、'.join(f'`{x}`' for x in token_revoked))
    if refresh_bad:
        lines.append('- **Refresh token 失效 / 复用**：' + '、'.join(f'`{x}`' for x in refresh_bad))
    if missing_refresh:
        lines.append('- **Access token 过期且缺少 refresh token**：' + '、'.join(f'`{x}`' for x in missing_refresh))
    lines.append('')
    lines.append('> 说明：当前异常主要集中在 token 被撤销、refresh token 失效/复用，以及 access token 过期但缺少 refresh token 三类。')
    lines.append('')
    lines.append('## ⌛ 卡片 5｜快过期账号')
    top_expiring = expiring_rows[:3]
    lines.append(f'`快过期账号数` **{len(top_expiring)}**')
    lines.append('')
    for idx, (name, days_label, _) in enumerate(top_expiring, 1):
        marker = markers[idx - 1] if idx <= len(markers) else str(idx)
        lines.append(f'{marker} `{name}` ｜ 剩余 **{days_label}天**')
    lines.append('')
    lines.append('> 说明：仅保留当前正常账号，并按到期时间从近到远展示。过期时间取自 `credentials.expires_at`。')
    lines.append('')
    lines.append('## 🔑 卡片 6｜今日令牌用量')
    lines.append(f'`令牌数` **{len(keys)}** ｜ `今日有用量` **{len(used_keys)}**')
    lines.append('')
    for idx, (name, i_tok, o_tok) in enumerate(used_keys, 1):
        marker = markers[idx - 1] if idx <= len(markers) else str(idx)
        lines.append(f'{marker} `{name}` ｜ 输入 **{fmt_m(i_tok)}** ｜ 输出 **{fmt_m(o_tok)}**')
    lines.append('')
    lines.append('> 说明：仅展示今日有实际用量的令牌；输入/输出已按百万 tokens（M）展示。')
    print('\n'.join(lines))
if __name__ == '__main__':
    main()
---
name: exa-search
description: 面向“来源优先”研究场景的语义 Web 搜索能力，尤其适用于官方文档、API 参考、价格页面、产品规格、公司官网，以及任何需要低噪声结果和直接提取正文的任务。当你需要高精度、高质量、非 SEO 噪声导向的搜索结果，或需要获取页面正文/高亮内容时优先使用。相比通用搜索，它更适合官方文档与结构化资料检索；对于突发新闻、X/Twitter 动态、实时舆情或多来源实时综合分析，应优先使用 grok-search。
---

# Exa Search

Use Exa for **source-first retrieval**.

Prefer it when the task is about:
- official documentation
- API/reference pages
- pricing/plan details
- product/company pages
- extracting the text of a page instead of just finding the link
- expanding from one canonical page to similar pages

Do **not** default to Exa for:
- breaking news
- X/Twitter chatter
- live sentiment / fast-moving discourse
- broad real-time synthesis across many fresh sources

For those, prefer `grok-search`.

## Workflow

1. Start with `docs` for official documentation lookups.
2. Use `search --text` or `research` when you need extracted body text.
3. Restrict domains aggressively when the user wants official sources.
4. Use `similar` when you already have the best canonical page and want adjacent sources.
5. For official-doc-only work, prefer `docs` plus domain restriction over `similar`; `similar` is semantic, not source-pure.
6. Return links plus extracted evidence, not just titles.

## Config

Preferred key resolution order:
1. `--api-key`
2. `EXA_API_KEY`
3. `EXA_API_KEYS` (comma-separated)
4. `config.local.json`
5. `config.json`
6. `~/.codex/config/exa-search.json`

Recommended setup for this workspace: keep the real key inside the skill folder in `config.local.json` so the entire skill can be backed up or moved as one directory.

### Single key

```json
{
  "profiles": [
    { "id": "main", "api_key": "YOUR_EXA_API_KEY" }
  ],
  "base_url": "https://api.exa.ai",
  "timeout_seconds": 30
}
```

### Multiple keys with auto failover

```json
{
  "profiles": [
    { "id": "main", "api_key": "KEY_1" },
    { "id": "backup-1", "api_key": "KEY_2" },
    { "id": "backup-2", "api_key": "KEY_3" }
  ],
  "base_url": "https://api.exa.ai",
  "timeout_seconds": 30
}
```

Failover behavior:
- profiles are tried in order
- 401 / 403 / 429 and quota / billing / rate-limit style errors automatically move to the next key
- the output includes `profileId` and `attempts` so you can see which key was used

## Commands

### Official docs search
```bash
python scripts/exa_search.py docs --query "telegram streaming openclaw"
```

### Official docs search with extracted text
```bash
python scripts/exa_search.py docs --query "model failover openclaw" --text --num 2
```

### General source-first search
```bash
python scripts/exa_search.py search --query "OpenClaw Telegram streaming" --num 5
```

### Deep extraction / research
```bash
python scripts/exa_search.py research --query "OpenClaw model failover" --num 3
```

### Force a specific key/profile
```bash
python scripts/exa_search.py docs --query "telegram streaming openclaw" --profile main
```

### Find similar pages
```bash
python scripts/exa_search.py similar --url "https://docs.openclaw.ai/channels/telegram" --num 5
```

## Notes

- `docs` defaults to `includeDomains=docs.openclaw.ai`.
- `research` defaults to text extraction.
- output is normalized JSON so downstream agents can consume it reliably.
- use `references/query-recipes.md` for ready-made query patterns.

# Query Recipes

## 1. Official docs only

Use `docs` first.

```bash
python3 scripts/exa_search.py docs --query "telegram streaming openclaw"
```

## 2. Official docs with extracted text

```bash
python3 scripts/exa_search.py docs --query "model failover openclaw" --text --num 2
```

## 3. Pricing / plan / API params from official sites

```bash
python3 scripts/exa_search.py search \
  --query "OpenClaw pricing API parameters" \
  --include-domains docs.openclaw.ai,openclaw.ai \
  --text --num 3
```

## 4. Research a product/company page and extract text

```bash
python3 scripts/exa_search.py research --query "Exa AI company overview" --num 3
```

## 5. Expand from one canonical source page

```bash
python3 scripts/exa_search.py similar --url "https://docs.openclaw.ai/channels/telegram" --num 5
```

Warning: `similar` is semantic similarity, not official-source-only discovery. If you must stay on official docs, prefer a `docs` search with strict domain restriction instead of trusting `similar` blindly.

## 6. Freshness filter

```bash
python3 scripts/exa_search.py search \
  --query "OpenClaw releases" \
  --start-date 2026-01-01 \
  --num 5
```

## 7. Domain hygiene

Prefer include-domains over broad search when the user says:
- 官方文档
- 官网
- API 文档
- 价格页
- 参数说明

Examples:
- `docs.openclaw.ai`
- `openclaw.ai`
- `github.com`

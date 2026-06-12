---
name: day-log-v2
description: 根据当前项目 docs 下的需求目录生成日报；先列出需求目录让用户选择，再检索当前项目 ai-localbase 记忆库内容，按日报格式生成并润色，支持 OpenAI API 兼容的第三方 AI 对话补全接口配置。
---

# Day Log V2

## 角色

使用 `Technical Writer`（技术文档编写者）视角整理日报。目标是把需求目录、知识库命中内容和会话上下文压缩成清晰、专业、可交付的日报 Markdown。

## 工作流

1. 在项目根目录执行脚本。
2. 先列出 `docs/` 下的需求目录。
3. 让用户选择或传入目录名称。
4. 调用当前项目的 `ai-localbase` 入口检索对应记忆库内容。
5. 将检索内容整理成日报四段格式。
6. 如配置第三方 AI，则调用 OpenAI 兼容对话补全接口润色；未配置时使用本地规则润色。
7. 写入 `$PWD/docs/day-log/day_log-YYYY-MM-DD.md`。

## 命令

### 列出需求目录

```bash
php skills/day-log-v2/scripts/generate_day_log.php --list-dirs
```

### 交互式生成

```bash
php skills/day-log-v2/scripts/generate_day_log.php
```

### 指定需求目录生成

```bash
php skills/day-log-v2/scripts/generate_day_log.php \
  --task-dir "session-title-v2"
```

### 指定检索关键词

```bash
php skills/day-log-v2/scripts/generate_day_log.php \
  --task-dir "session-title-v2" \
  --memory-query "Codex Hook AI 会话标题 v2"
```

## OpenAI 兼容润色配置

支持 OpenAI API 格式的对话补全接口。配置文件放在脚本目录：

```bash
cp skills/day-log-v2/scripts/.env.example skills/day-log-v2/scripts/.env
```

填写 `skills/day-log-v2/scripts/.env` 后直接执行：

```bash
php skills/day-log-v2/scripts/generate_day_log.php --task-dir "session-title-v2"
```

字段说明见 `skills/day-log-v2/scripts/.env.example`。脚本启动时会自动读取同目录 `.env`；命令行参数仍可临时覆盖 `.env` 中的配置。

### 接口兼容

- 标准默认端点：`/v1/chat/completions`
- 兼容用户指定端点：`/v1/chat/completion`
- `--ai-url` 可传基础地址，也可传完整端点。
- `--ai-endpoint` 可覆盖默认端点。

请求体遵循 OpenAI 对话补全格式：

```json
{
  "model": "gpt-4.1-mini",
  "messages": [
    {"role": "system", "content": "..."},
    {"role": "user", "content": "..."}
  ],
  "temperature": 0.2
}
```

读取响应字段：`choices[0].message.content`。

## 参数

### 项目与目录

- `--project-dir`：项目根目录，默认当前目录。
- `--list-dirs`：只列出 `docs/` 下的需求目录。
- `--task-dir`：需求目录名或路径，例如 `session-title-v2`。
- `--memory-query`：记忆库检索关键词，默认使用 `task-dir`。
- `--top-k`：记忆库检索条数，默认 `8`。

### 日报字段

- `--requirement`：需求描述。
- `--module`：功能模块。
- `--completed-item`：完成项，可多次传入。
- `--main-prompt`：主要提示词。
- `--estimated-time`：初始评估时间，默认 `0.2天`。
- `--ai-dev-time`：AI 开发时间，默认 `0.05天`。
- `--api-usage`：API 用量百分比，默认 `0%`。
- `--auto-composer`：Auto + Composer 用量百分比，默认 `0%`。

### 输出

- `--output-dir`：输出目录，默认 `$PWD/docs/day-log`。
- `--output-file`：输出文件名。
- `--date`：日报日期，默认当天。
- `--print`：写入文件后同时输出内容。

### AI 润色

- `--ai-url`：临时覆盖 `.env` 中的 OpenAI 兼容服务基础 URL 或完整 chat completion URL。
- `--ai-model`：临时覆盖 `.env` 中的模型名称。
- `--ai-key`：临时覆盖 `.env` 中的 API Key。不建议直接写命令行。
- `--ai-endpoint`：临时覆盖 `.env` 中的对话补全端点，默认 `/v1/chat/completions`。
- `--no-ai`：强制禁用外部 AI 润色。

`.env` 支持字段：

- `DAY_LOG_V2_AI_URL`
- `DAY_LOG_V2_AI_MODEL`
- `DAY_LOG_V2_AI_KEY`
- `DAY_LOG_V2_AI_ENDPOINT`

## 输出格式

固定四段：

```markdown
今日AI调用百分比:
免费
API用量：0%
Auto + Composer：0%


今日使用AI完成功能:
需求：<需求描述>
功能模块：<模块/文件名>
完成内容：
1. <完成项1>
2. <完成项2>


今日主要提示词:
<关键提示词内容>


今日AI提升工作效率:
需求：<对应需求>
功能模块：<对应模块>
初始评估时间：0.2天、使用AI开发时间：0.05天
```

## 约束

1. 只自动读取 `skills/day-log-v2/scripts/.env`，不扫描其他配置文件。
2. 不把 API Key 写入输出、日志或项目文件。
3. 未配置 AI 时不访问外网。
4. 配置 AI 后如果接口调用失败，脚本直接报错退出，不静默降级。
5. 原 `skills/day-log` 保持不变，v2 只在 `skills/day-log-v2` 内演进。

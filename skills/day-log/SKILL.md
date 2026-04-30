---
name: day-log
description: 根据当前会话内容生成日报 markdown，样式对齐 day_log 模板，并写入当前启动目录。
---

# Day Log

脚本目录：`~/.codex/skills/day-log/`（可直接使用绝对路径执行，无需先进入目录）

使用这个 skill 时，执行顺序必须是：

1. 先调用 `php ~/.codex/skills/day-log/scripts/generate_day_log.php`

模板样式固定参考：`day_log-2026-03-19.md`（即使该文件后续删除，也必须按下文“模板格式（内置规范）”输出）
输出文件默认：`day_log-YYYY-MM-DD.md`
输出目录建议固定传：`--output-dir "$PWD"`（当前启动目录）

## 模板格式（内置规范）

必须严格使用以下 4 个段落，顺序不可变，字段名不可改：

1. `今日AI调用百分比:`
2. `今日使用AI完成功能:`
3. `今日主要提示词:`
4. `今日AI提升工作效率:`

段落字段要求：

- 段落 1 固定 3 行值：`免费/付费`、`API用量：x%`、`Auto + Composer：x%`
- 段落 2 固定字段：`需求：`、`功能模块：`、`完成内容：`（后面必须是编号列表 `1.` `2.` `3.` ...）
- 段落 3 为提示词正文，允许多行
- 段落 4 固定字段：`需求：`、`功能模块：`、`初始评估时间：x天、使用AI开发时间：x天`

空行规则：

- 每个大段落之间保留 2 个空行（即视觉上分段明显）
- `完成内容：` 与编号列表之间不加额外说明行
- 文件结尾保留换行

输出骨架（必须同结构）：

```markdown
今日AI调用百分比:
免费
API用量：0%
Auto + Composer：0%


今日使用AI完成功能:
需求：<本次需求>
功能模块：<模块/文件>
完成内容：
1. <完成项1>
2. <完成项2>


今日主要提示词:
<关键提示词，可多行>


今日AI提升工作效率:
需求：<效率评估对应需求>
功能模块：<效率评估对应模块>
初始评估时间：<例如 0.2天>、使用AI开发时间：<例如 0.05天>
```

## 快速开始

1. 用会话全文自动提取内容：

```bash
php ~/.codex/skills/day-log/scripts/generate_day_log.php \
  --output-dir "$PWD" \
  --session-text "这里放当前会话全文"
```

2. 用结构化参数生成（推荐）：

```bash
php ~/.codex/skills/day-log/scripts/generate_day_log.php \
  --output-dir "$PWD" \
  --requirement "本次会话核心需求" \
  --module "涉及模块或文件" \
  --completed-item "完成点1" \
  --completed-item "完成点2" \
  --main-prompt "本次会话关键提示词" \
  --estimated-time "0.2天" \
  --ai-dev-time "0.05天"
```

3. 用文件输入会话全文：

```bash
php ~/.codex/skills/day-log/scripts/generate_day_log.php \
  --output-dir "$PWD" \
  --session-file /path/to/session.txt
```

## 参数说明

- 输入来源优先级：`--session-text` > `--session-file` > `stdin`
- 可选字段：`--requirement`、`--module`、`--completed-item`、`--main-prompt`
- 效率字段：`--estimated-time`、`--ai-dev-time`
- AI 调用字段：`--ai-call-tier`、`--api-usage`、`--auto-composer`
- 自定义输出：`--output-file`、`--date`

## 约束

- 必须输出 markdown 文件，不可只在回复中展示。
- 必须写入当前启动目录，不写入 skill 目录。

---
name: day-log
description: 使用 Technical Writer 角色生成日报 markdown，根据会话内容优化输出，写入 `docs/day-log/`
---

# Day Log

## 角色要求

**必须使用角色**：`Technical Writer`（技术文档编写者）

**工作流程**：
1. 先加载 Technical Writer 角色
2. 用该角色分析会话内容，提取并改写为专业技术文档风格
3. 将改写后的内容传给脚本生成日报

该角色会优化日报内容的：
- 清晰度和可读性
- 技术术语准确性
- 结构化表达
- 开发者友好的描述方式

**文案优化要求**：
- 在传给脚本前，必须先用 Technical Writer 角色润色内容
- 确保表达简洁、专业、易读
- 避免冗余和口语化表达
- 统一术语和格式

**文案填充策略**：
- 每次生成时，对相同主题使用不同的表达方式
- 适当调整句式结构和用词，保持内容新鲜感
- 核心技术点保持一致，但描述角度可以变化
- 示例：
  - "实现了用户登录功能" → "完成用户身份验证模块开发"
  - "优化了数据库查询" → "提升数据库查询性能"
  - "修复了 Bug" → "解决了系统异常问题"

## 使用方式

执行脚本生成日报：

```bash
php ~/.codex/skills/day-log/scripts/generate_day_log.php
```

**输出规范**：
- 文件名：`day_log-YYYY-MM-DD.md`
- 输出目录：`$PWD/docs/day-log/`
- 推荐参数：`--output-dir "$PWD/docs/day-log"`

## 标准模板格式

日报包含 4 个固定段落：

### 1. 今日AI调用百分比
```
API用量：0%
Auto + Composer：0%
```

### 2. 今日使用AI完成功能
```
需求：<需求描述>
功能模块：<模块/文件名>
完成内容：
1. <完成项1>
2. <完成项2>
```

### 3. 今日主要提示词
```
<关键提示词内容，可多行>
```

### 4. 今日AI提升工作效率
```
需求：<对应需求>
功能模块：<对应模块>
初始评估时间：0.2天、使用AI开发时间：0.05天
```

**格式要求**：段落间保留 2 个空行，文件结尾保留换行

## 使用示例

### 结构化参数（推荐）

```bash
php ~/.codex/skills/day-log/scripts/generate_day_log.php \
  --output-dir "$PWD/docs/day-log" \
  --requirement "优化用户登录流程" \
  --module "auth/login.php" \
  --completed-item "实现验证码功能" \
  --completed-item "添加登录日志记录" \
  --main-prompt "使用 Backend Architect 角色设计 Redis 缓存方案" \
  --estimated-time "0.5天" \
  --ai-dev-time "0.1天"
```

### 会话文本自动提取

```bash
php ~/.codex/skills/day-log/scripts/generate_day_log.php \
  --output-dir "$PWD/docs/day-log" \
  --session-text "$(cat session.txt)"
```

### 从文件读取

```bash
php ~/.codex/skills/day-log/scripts/generate_day_log.php \
  --output-dir "$PWD/docs/day-log" \
  --session-file /path/to/session.txt
```

## 参数说明

### 输入来源
- `--session-text`：直接传入会话文本
- `--session-file`：从文件读取会话文本
- `stdin`：标准输入

### 内容字段
- `--requirement`：需求描述
- `--module`：功能模块或文件名
- `--completed-item`：完成项（可多次使用）
- `--main-prompt`：关键提示词

### 效率评估
- `--estimated-time`：初始评估时间（如 "0.5天"）
- `--ai-dev-time`：使用 AI 开发时间（如 "0.1天"）

### AI 使用统计
- `--api-usage`：API 用量百分比
- `--auto-composer`：Auto + Composer 用量百分比

### 输出控制
- `--output-dir`：输出目录（默认：`$PWD/docs/day-log`）
- `--output-file`：自定义文件名
- `--date`：指定日期（默认：今天）

### 效率评估
- `--estimated-time`：初始评估时间（如 "0.5天"）
- `--ai-dev-time`：使用 AI 开发时间（如 "0.1天"）

### AI 使用统计
- `--api-usage`：API 用量百分比
- `--auto-composer`：Auto + Composer 用量百分比

### 输出控制
- `--output-dir`：输出目录（默认：`$PWD/docs/day-log`）
- `--output-file`：自定义文件名
- `--date`：指定日期（默认：今天）

## 重要约束

1. **必须生成文件**：不可只在回复中展示内容，必须写入 markdown 文件
2. **固定输出位置**：必须写入 `$PWD/docs/day-log/`，不写入 skill 目录或项目根目录
3. **格式严格遵守**：4 个段落的顺序和字段名不可更改
4. **角色信息体现**：会话中使用的 `skills/who` 角色应在"完成内容"和"主要提示词"中体现

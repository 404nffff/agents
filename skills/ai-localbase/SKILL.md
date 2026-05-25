---
name: ai-localbase
description: Use when starting any conversation in a project that uses ai_localbase as its primary knowledge base - establishes per-session ai-localbase initialization, directory-scoped knowledge mapping, and default knowledge retrieval before responding
---

## 运行位置

以下内容是在说明 skill 自身的安装与运行位置，不是让你在项目目录里创建一个名为“固定运行目录”或“运行位置”的文件。

- skill 安装目录：`~/.codex/skills/ai-localbase/`
- 配置文件：`~/.codex/skills/ai-localbase/.env`
- 知识库映射缓存：`~/.codex/skills/ai-localbase/knowledge.json`
- Bash 入口：`~/.codex/skills/ai-localbase/ai-localbase.sh`
- PowerShell 入口：`~/.codex/skills/ai-localbase/ai-localbase.ps1`

# AI LocalBase 项目知识库入口

本 skill 的设计口径是：在启用了 `ai_localbase` 的项目里，每次会话启动时默认加载，并优先完成当前启动目录对应知识库的初始化。

本 skill 提供两个统一入口：

- `ai-localbase.sh`：Bash 版本
- `ai-localbase.ps1`：Windows / PowerShell 版本

两者都使用同一套子命令：`init`、`upload`、`append`、`update`、`delete`、`search`、`chat`，并按目录自动复用 `knowledgeBaseId`。其中 `init` 会把你传入的启动目录 basename 映射为知识库名，例如 `/mnt/sync2/www/agents -> agents`。

## 使用场景

**适用**：
- 项目把 `ai_localbase` 作为主知识库
- 需要在会话启动时初始化当前目录对应的知识库
- 需要批量操作知识库、文档、检索或问答
- 需要排查目录映射、缓存或脚本行为问题

**不适用**：
- 项目未启用 `ai_localbase`
- 上传二进制文件（仅支持文本）
- 批量上传目录（需客户端遍历后逐文件上传）

## 核心规则

1. **会话初始化**：每次会话开始时先进入 `~/.codex/skills/ai-localbase/` 并执行 `init` 子命令，让脚本自动加载同目录下的 `.env`，再把启动目录映射到其 basename 对应的知识库名，例如 `/mnt/sync2/www/agents -> agents`
2. **认证安全**：Token 存入环境变量，避免命令历史泄露
3. **目录隔离**：每个启动目录映射到其 basename 对应的独立知识库，映射缓存写入 `knowledge.json`
4. **检索 vs 问答**：`search` 用于片段检索，`chat` 用于基于知识库上下文的直接问答
5. **文档维护策略**：新文档优先上传；增量内容用 `append`；全文覆盖用 `update`；废弃文档用 `delete`
6. **依赖前置**：Bash 版本依赖 `bash`、`curl`；PowerShell 版本依赖 `Invoke-RestMethod`

## 检索返回结构

`knowledge_base.search` 返回的是 MCP tool result 外层对象，不能只读取 `content[].text`。`content` 通常只包含“共检索到 N 条结果”这类摘要，真正可用的命中片段在 `structuredContent.items`。

入参结构：

```json
{
  "query": "搜索关键词",
  "knowledgeBaseId": "",
  "documentId": "",
  "topK": 5
}
```

字段规则：

- `query` 必填
- `knowledgeBaseId` 为空表示跨知识库搜索；日常项目检索应优先使用 `init` 确认出的当前项目知识库 ID
- `documentId` 不为空时只检索单个文档
- `topK` 是 MCP 层二次截断；不传时后端默认跨知识库最多选 10 条、每个文档默认最多 2 条
- `score` 是检索或重排后的相关性分数，越高越相关

返回结构示例：

```json
{
  "content": [
    {
      "type": "text",
      "text": "共检索到 N 条结果"
    }
  ],
  "structuredContent": {
    "items": [
      {
        "knowledgeBaseId": "kb-1",
        "documentId": "doc-1",
        "documentName": "xxx.md",
        "chunkId": "chunk-xxx",
        "text": "命中的原文片段",
        "score": 0.83,
        "index": 0
      }
    ]
  },
  "isError": false
}
```

处理结果时必须遍历 `structuredContent.items`，读取每条命中的 `text`、`documentName`、`documentId`、`chunkId`、`score` 和 `index`。若 `structuredContent.items` 为空，即使 `content[].text` 存在摘要，也应按“未命中可用片段”处理。

## 快速开始

**1. 配置环境**
```bash
cd "${HOME}/.codex/skills/ai-localbase"
cp .env.example .env
# 编辑 .env 填入实际配置
```

**2. Bash 使用方式**
```bash
# 不需要先设置 SKILL_DIR，直接用固定路径调用

# 初始化目录到知识库的映射，`/www/agents` 会映射为知识库名 `agents`
"${HOME}/.codex/skills/ai-localbase/ai-localbase.sh" init "/path/to/project"

# 上传文档（参数：文件名、内容、目录）
"${HOME}/.codex/skills/ai-localbase/ai-localbase.sh" upload "my-doc.md" "# 内容" "/path/to/project"

# 追加文档内容（参数：documentId、内容、目录）
"${HOME}/.codex/skills/ai-localbase/ai-localbase.sh" append "doc-123" "追加内容" "/path/to/project"

# 覆盖文档内容（参数：documentId、内容、目录）
"${HOME}/.codex/skills/ai-localbase/ai-localbase.sh" update "doc-123" "# 全量新内容" "/path/to/project"

# 删除文档（参数：documentId、目录）
"${HOME}/.codex/skills/ai-localbase/ai-localbase.sh" delete "doc-123" "/path/to/project"

# 检索内容（参数：关键词、目录）
"${HOME}/.codex/skills/ai-localbase/ai-localbase.sh" search "关键词" "/path/to/project"

# 检索内容并限制返回数量（参数：关键词、目录、topK）
"${HOME}/.codex/skills/ai-localbase/ai-localbase.sh" search "关键词" "/path/to/project" 5

# 问答（参数：问题、目录）
"${HOME}/.codex/skills/ai-localbase/ai-localbase.sh" chat "你的问题" "/path/to/project"
```

**3. PowerShell 使用方式**
```powershell
# 初始化目录到知识库的映射，`C:\work\agents` 会映射为知识库名 `agents`
& "$HOME/.codex/skills/ai-localbase/ai-localbase.ps1" init "C:\work\project"

# 上传文档
& "$HOME/.codex/skills/ai-localbase/ai-localbase.ps1" upload "my-doc.md" "# 内容" "C:\work\project"

# 追加文档内容
& "$HOME/.codex/skills/ai-localbase/ai-localbase.ps1" append "doc-123" "追加内容" "C:\work\project"

# 覆盖文档内容
& "$HOME/.codex/skills/ai-localbase/ai-localbase.ps1" update "doc-123" "# 全量新内容" "C:\work\project"

# 删除文档
& "$HOME/.codex/skills/ai-localbase/ai-localbase.ps1" delete "doc-123" "C:\work\project"

# 检索
& "$HOME/.codex/skills/ai-localbase/ai-localbase.ps1" search "关键词" "C:\work\project"

# 问答
& "$HOME/.codex/skills/ai-localbase/ai-localbase.ps1" chat "你的问题" "C:\work\project"
```

统一入口会自动：
- 加载 `.env` 配置
- 检查 `knowledge.json`，若知识库名映射或知识库 ID 不存在则自动创建
- 执行对应操作

## 使用流程

1. **先进入固定目录**：所有命令、`.env`、`knowledge.json` 都固定在 `~/.codex/skills/ai-localbase/`
2. **会话开始先跑 `init`**：传入当前项目启动目录，让脚本确认知识库并刷新本地映射
3. **先用 `search` 查历史**：需要看片段、找已有方案、确认历史决策时优先使用
4. **需要直接结论时用 `chat`**：让知识库基于现有文档输出精简答案
5. **新增内容用 `upload`**：把新的任务文档、摘要或阶段结论写入当前目录对应的知识库
6. **已有文档按需维护**：过程记录优先 `append`；需要整篇替换时用 `update`；废弃文档用 `delete`
7. **收尾时再统一整理**：过程里先保持增量沉淀，阶段收尾再做集中整理和归档

## 常见问题

| 问题 | 原因与解决 |
|------|-----------|
| `401`/`403` 错误 | 检查 `.env` 中的 `MCP_AUTH_TOKEN` 是否正确，以及目标服务是否可访问 |
| `knowledgeBaseId` 为空 | 先重新执行一次 `init`，确认当前目录 basename 是否映射到正确知识库 |
| 不知道 `documentId` | `upload` 的返回结果里会带文档 ID；`search` 命中结果里也会带 `documentId` |
| 无法上传目录 | 需客户端先遍历目录，再逐文件调用 `upload` |
| 搜索返回空 | 确认文档已上传并完成索引，尝试缩小 `query` 或增大 `topK` |
| 文本里有引号或换行 | Bash / PowerShell 入口都已处理转义，直接通过脚本传参即可 |

---
name: low-model-search-code-explorer
description: 当 Codex 需要以低 token 成本只读探索代码、定位文件行号、路由到文件映射、相似实现、调用链入口，或在编辑 PHP 后端代码前获取紧凑 file:line 引用时使用。
---

# Low Model Search Code Explorer

## 概览

本技能用于以低 token 成本做仓库只读定位，并返回紧凑引用；主 Agent 负责读取引用范围、推理、编辑和验证。

## 强制委派

本技能是强制委派协议，不是主 Agent 自行搜索流程。

本项目规则已明确授权：凡代码收集、接口/路由定位、相似实现查找和调用链入口定位，必须使用本技能并开启或复用 `explorer` 子代理；不得跳过本技能直接进入 code-index、rg、grep 或其他随意 shell 搜索。

触发本技能且存在 `explorer` 子代理能力时，主 Agent 必须在任何仓库搜索工具调用前先检查是否有同一任务中已打开的 `explorer`。有则复用该子代理；没有可复用子代理时，才派新的 `explorer` 子代理使用 `skill[low-model-search-code-explorer]` 进行只读探索。

spawn explorer 时，主 Agent 必须显式指定 `model: gpt-5.4-mini` 与 `reasoning_effort: low`；仅当当前工具不支持指定模型时，才允许继承主模型。不要依赖继承模型默认值。仅当第一次 mini explorer 结果不足，或任务上下文另有明确模型要求时，才使用更强模型。

如果已有同一任务或强相关后续搜索的 `explorer` 子代理仍打开，使用 `send_input` 复用，不要新建 explorer。当前搜索阶段保持 explorer 打开；仅在任务完成、搜索主题变化或不再需要 explorer 时关闭。explorer 输出限制为 `文件:行号范围 + 一句话理由`。

explorer 返回前，主 Agent 不得直接调用 code-index MCP，也不得读取仓库文件来重复定位代码。

允许例外：

- 用户明确禁止子代理。
- 当前会话没有子代理工具。
- 启动 explorer 失败。
- 首次 explorer 搜索超过 300 秒，复用 explorer 的后续搜索超过 120 秒，发生超时，或返回结果不足/明显错误。

若适用例外，简短说明原因，然后主 Agent 按同一搜索链路继续。

不要把等待上限视作自动取消。如果 explorer 仍在运行且主 Agent 有不重叠工作可做，先继续那些工作，等 explorer 返回后再使用结果。只有下一步被缺失定位结果阻塞时，主 Agent 才允许接手搜索。

## 核心规则

搜索不是分析。explorer 只负责找到该看哪里，不负责解释完整实现。

## 完整性要求

对于路由或接口定位任务，结果必须包含所有相关的精确文件与行号范围，否则视为不完整：

- Controller 入口方法。
- Controller 派发或调用的下游 Task / Logic 方法。
- 若目标是异步导出，必须包含进度或状态端点。
- 用户要求相似实现时，必须包含三个相似接口入口。

不要只返回符号名而不带文件和行号。如果通过名称找到下游符号但未知精确位置，继续使用 code-index MCP 的 `search_code_advanced` / `get_file_summary` / `get_symbol_body` 定位。仍无法定位时，把缺失符号放到 `Open questions`。

主 Agent 不得为了补强缺失或较弱引用而自行追加搜索。若任务仍需要缺失行号，复用同一个 explorer，通过 `send_input` 要求它补齐引用。

## 最终自检

最终回复前，必须确认每一条非空结果都符合以下形态：

```text
path/to/file.php:start-end
```

规则：

- 不返回裸类名、方法名、Task 名、路由字符串或符号名。
- 不允许只返回 Controller 引用，却把其派发的 Task / Logic 只写成符号名。
- 如果用户要求“只输出文件和行号”，省略相关说明，只输出引用。
- 若任何必需引用缺失，必须继续搜索后再最终回复。
- 若必需引用确实无法定位，只把该缺失项放入 `Open questions`；不要静默省略。

## 工作流

1. 主 Agent 优先复用同一任务已有打开的 explorer；否则启动 `explorer` 子代理，传入 `model: gpt-5.4-mini` 和 `reasoning_effort: low`，并发送下方 Explorer Prompt。
2. explorer 先查项目记忆：优先 `ai_localbase` 历史设计。
3. explorer 随后使用 code-index MCP 做代码定位、文件摘要和方法范围确认。先确认项目路径与索引，再用 `search_code_advanced` 定位文本/符号，用 `get_file_summary` 补文件结构，用 `get_symbol_body` 补方法范围。
4. explorer 只返回下面的紧凑结果契约。不要粘贴完整源码、宽泛命令输出或长解释。
5. 同一任务的相关后续搜索中，主 Agent 保持 explorer 打开；任务或搜索阶段结束后关闭。

## Explorer Prompt

启动 `explorer` 子代理时，使用此提示并填充占位符：

```text
Use low-model-search-code-explorer.

Task: <要定位什么>
Repository: <必要时填写仓库路径>

Rules:
- Read-only exploration only. Do not edit files.
- Prefer ai_localbase, then code-index MCP.
- Do not paste full source code.
- Do not produce a design or implementation plan.
- Return only exact citations. If the user asks for file lines only, output no reasons.

Required citations:
- Target Controller entry method: file:start-end
- Downstream Task/Logic method called or dispatched by the Controller: file:start-end
- Progress/status endpoint for async export, if applicable: file:start-end
- Async task entry, if applicable: file:start-end
- Similar interface entry points requested by the user: file:start-end

Before final:
- Verify every result line is file:start-end.
- Do not return symbols without file lines.
- If any required citation is missing, continue searching inside explorer.
- If impossible to locate, list the missing item under Open questions.

Output contract:
Entry points:
- path/to/file.php:12-45 - why relevant

Core implementation:
- path/to/file.php:80-140 - why relevant

Similar implementations:
- path/to/file.php:20-60 - why relevant
- path/to/file.php:90-130 - why relevant
- path/to/file.php:150-210 - why relevant

Open questions:
- unresolved fact that affects locating code, if any
```

## 输出限制

- 最多 12 个引用范围。
- 每条引用最多 1 句说明。
- 优先使用 `file.php:start-end`；只有确实精确到单行时才使用单行。
- 如果没有强匹配，返回最好的 3 个弱线索，并说明弱在哪里。
- 如果涉及数据库字段，只报告代码中发现的表名，不推断表结构；主 Agent 必须用 `db-query` 验证 schema。

## 常见错误

- 不要让 explorer 或主 Agent 的搜索阶段解决业务问题。
- 不要接受源码大段粘贴作为最终定位结果。
- 不要绕过 `ai_localbase -> code-index MCP` 链路做仓库定位。
- 不要把定位引用当作正确性证明；它们只是给主 Agent 继续检查的指针。

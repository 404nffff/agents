# Codex Hook 通用入口

本目录是通用 Codex hooks 分发层。入口脚本只负责安装 hooks、读取 payload、调用 Python 事件层；具体动作通过 `plugins/<插件名>/hook.py` 完成。

## 文件说明

| 文件 | 用途 |
| --- | --- |
| `codex_hook.sh` | Linux/macOS Bash 入口，支持 `create` 和 payload 调试。 |
| `codex_hook.ps1` | Windows PowerShell 入口，支持 `create` 和 payload 调试。 |
| `hook.py` | 通用事件分发入口，负责 payload 读取、事件归一、脱敏日志、标题摘要和插件路由。 |
| `plugins/agents_guard/hook.py` | AGENTS 轻量守护插件，负责 SessionStart 知识库握手、风险命令记录和收尾提醒。 |
| `plugins/ai_localbase/hook.py` | ai-localbase 压缩记忆插件，负责 PreCompact 上传记忆、PostCompact 读取记忆并输出恢复上下文。 |
| `plugins/feishu/hook.py` | 飞书插件，复用 `shell/feishu_bot/feishu_bot_push.sh`，Windows 可直接调用飞书 API。 |
| `plugins/feishu/.env.example` | 飞书插件配置示例。 |
| `plugins/session_title/hook.py` | Codex 会话标题更新插件。 |
| `plugins/session_title_v2/hook.py` | AI 总结版 Codex 会话标题更新插件，兼容 OpenAI Chat Completions。 |
| `.env.example` | 通用 hook 配置示例。 |

## 安装 hooks

Linux/macOS：

```bash
./shell/codex_hook/codex_hook.sh create linux
```

Windows：

```powershell
.\shell\codex_hook\codex_hook.ps1 create win
```

生成位置：

```text
~/.codex/hooks.json
```

## 插件配置

通用入口只保留拆分式插件路由配置：

```bash
CODEX_HOOK_EVENTS_ALL=''
CODEX_HOOK_EVENTS_SESSION_START='agents_guard,feishu'
CODEX_HOOK_EVENTS_SUBAGENTSTART='feishu'
CODEX_HOOK_EVENTS_PRE_TOOL_USE='agents_guard,feishu'
CODEX_HOOK_EVENTS_PERMISSION_REQUEST='feishu'
CODEX_HOOK_EVENTS_POST_TOOL_USE='agents_guard,feishu'
CODEX_HOOK_EVENTS_PRE_COMPACT='agents_guard,ai_localbase,feishu'
CODEX_HOOK_EVENTS_POST_COMPACT='agents_guard,ai_localbase,feishu'
CODEX_HOOK_EVENTS_USER_PROMPT_SUBMIT='session_title'
CODEX_HOOK_EVENTS_SUBAGENTSTOP='feishu'
CODEX_HOOK_EVENTS_STOP='agents_guard,feishu,session_title'
```

格式：

- `CODEX_HOOK_EVENTS_ALL` 会注册到所有支持的事件。
- `CODEX_HOOK_EVENTS_<EVENT>` 只注册到单个事件，事件名支持驼峰转下划线写法和压缩写法，例如 `CODEX_HOOK_EVENTS_SESSION_START` / `CODEX_HOOK_EVENTS_SESSIONSTART`、`CODEX_HOOK_EVENTS_SUBAGENT_START` / `CODEX_HOOK_EVENTS_SUBAGENTSTART`。
- 插件列表支持逗号、分号或空白分隔。
- 多个来源同时配置时，执行顺序为全局注册、单事件注册，重复插件只执行一次。
- 插件会从 `plugins/<插件名>/hook.py` 加载，并调用其中的 `handle(context)`。
- `session_title` 不需要单独配置；挂到 `UserPromptSubmit` 和 `Stop` 后就会更新 Codex 会话标题。
- `session_title_v2` 只需要挂到 `Stop`；它会读取 transcript 并调用 OpenAI 兼容接口总结标题。

推荐把 `agents_guard` 挂到：

- `SessionStart`：检查 `docs/index.md`、hook v8 Agent 文档，并执行 `ai-localbase init <cwd>` 完成知识库握手；同时注入核心 SDLC 工作模式，包含阶段指令、代码优先、debug 复现先行和红线暂停规则。
- `PreToolUse`：记录 `rm -rf`、`git reset --hard`、强推、破坏性 SQL、读取 `.env` / `.pem` / `*.key` 等风险迹象。
- `PostToolUse`：记录知识库相关异常，便于按规则重新 init。
- `PreCompact`：写入压缩前检查点，记录 `docs/index.md` 是否存在、压缩触发来源和相关工作区状态；可选同步到 `ai-localbase`。
- `PostCompact`：读取压缩前检查点，写入恢复记录和本地恢复说明文件，提醒后续先复核项目索引与当前任务状态。
- `Stop`：记录 `docs/index.md` 是否存在和相关工作区摘要，提醒收尾索引与知识库同步。

不推荐放进 hook 的内容：

- 完整 SDLC 判断、任务规划、代码实现规则。这些需要模型理解上下文，应保留在 AGENTS 文档和 skill 中。
- MCP server 动态注册。hook 可以在 `SessionStart` 预热或检查，但当前会话可用 MCP 工具仍应通过 `config.toml` 的 `mcp_servers` 配置。
- 破坏性操作自动阻断。当前入口会吞掉插件输出并不中断 Codex 主流程，风险控制仍依赖 Codex 权限、AGENTS 红线和人工确认。

飞书通知标题：

- `UserPromptSubmit` 会把本轮用户输入缓存为标题。
- `Stop` 的飞书通知优先复用该标题，缺失时才退回最终回复摘要。
- `codex_hook.sh create` / `codex_hook.ps1 create` 生成的 `hooks.json` 已包含 `UserPromptSubmit`；需要更新标题时，把 `session_title` 配到 `CODEX_HOOK_EVENTS_USER_PROMPT_SUBMIT` 和 `CODEX_HOOK_EVENTS_STOP`。
- 标题状态默认写入 `shell/codex_hook/codex_hook_title_state.json`，可用 `CODEX_HOOK_TITLE_STATE_PATH` 覆盖。

飞书插件配置放插件目录：

```bash
cp shell/codex_hook/plugins/feishu/.env.example shell/codex_hook/plugins/feishu/.env
```

会话标题插件不需要独立 `.env`。需要启用时，把 `session_title` 挂到 `UserPromptSubmit` 和 `Stop`。

AI 总结版会话标题插件：

```bash
CODEX_HOOK_EVENTS_STOP='agents_guard,feishu,session_title_v2'
SESSION_TITLE_V2_API_URL='https://api.example.com/v1/chat/completions'
SESSION_TITLE_V2_MODEL='gpt-4o-mini'
SESSION_TITLE_V2_API_KEY=''
```

配置说明：

- `SESSION_TITLE_V2_API_URL` 支持完整 `/v1/chat/completions` 地址，也支持 base URL，插件会自动追加 `/v1/chat/completions`。
- `SESSION_TITLE_V2_MODEL` 是 OpenAI 兼容模型名。
- `SESSION_TITLE_V2_API_KEY` 只写入 `Authorization: Bearer ...` 请求头，不写入日志。
- `SESSION_TITLE_V2_MAX_CONTEXT_CHARS` 控制发送给 AI 的最近会话内容长度，默认 `12000`。
- `SESSION_TITLE_V2_MAX_TITLE_CHARS` 控制最终标题长度，默认 `40`。
- 若 payload 没有 `transcript_path`，插件会用 `session_id` 到 `~/.codex/sessions` 下搜索同名 `.jsonl`；可用 `SESSION_TITLE_V2_TRANSCRIPT_ROOT` 覆盖搜索根目录。
- 不建议同时启用 `session_title` 和 `session_title_v2`，否则 Stop 时可能发生两次标题更新。

AGENTS 守护插件默认不需要独立配置文件；需要调整时直接用进程环境变量覆盖。默认开启 `SessionStart` 的 `ai-localbase init`，日志写入 `shell/codex_hook/codex_hook_agents_guard.log`。如只想记录不想预热知识库：

```bash
AGENTS_GUARD_AI_LOCALBASE_INIT='false'
```

如需在 `PreCompact` 把检查点同步到 `ai-localbase`：

```bash
AGENTS_GUARD_PRECOMPACT_UPLOAD_MEMORY='true'
```

如需固定追加到某个知识库文档：

```bash
AGENTS_GUARD_PRECOMPACT_MEMORY_DOC_ID='doc-123'
```

`PostCompact` 会默认额外写一份本地恢复说明：

```text
shell/codex_hook/codex_hook_postcompact_note.md
```

`ai_localbase` 插件用于把压缩前上下文沉淀到当前项目知识库，并在压缩后读取后输出给 Codex：

```bash
CODEX_HOOK_EVENTS_PRE_COMPACT='ai_localbase'
CODEX_HOOK_EVENTS_POST_COMPACT='ai_localbase'
```

默认入口：

- Windows：`~/.codex/skills/ai-localbase/ai-localbase.ps1`
- Linux/macOS：`~/.codex/skills/ai-localbase/ai-localbase.sh`

可用环境变量覆盖：

```bash
AI_LOCALBASE_HOOK_SCRIPT='/path/to/ai-localbase.sh'
AI_LOCALBASE_HOOK_TIMEOUT='30'
AI_LOCALBASE_HOOK_STATE_PATH='shell/codex_hook/codex_hook_ai_localbase_state.json'
AI_LOCALBASE_HOOK_COMPACT_DOC_ID=''
AI_LOCALBASE_HOOK_POSTCOMPACT_QUERY=''
AI_LOCALBASE_HOOK_POSTCOMPACT_TOPK='3'
```

行为：

- `PreCompact`：先执行 `init <cwd>`，再 `upload` 一份压缩检查点；若配置 `AI_LOCALBASE_HOOK_COMPACT_DOC_ID`，改为 `append` 到固定文档。
- `PostCompact`：先执行 `init <cwd>`，再按压缩前状态或自定义 query 调用 `search`，把命中文档名与片段摘要写入 `hookSpecificOutput.additionalContext`。
- 插件不直接读取 `.env`，凭证加载仍由 `~/.codex/skills/ai-localbase` 入口脚本负责；日志只记录状态和长度摘要。

关于“hook 输出内容”：

- 通用入口会聚合插件 `handle(context)` 的返回值，并在官方支持的事件中输出 `hookSpecificOutput.additionalContext`。
- 当前会输出 `additionalContext` 的事件：`SessionStart`、`SubagentStart`、`PreToolUse`、`PostToolUse`、`PreCompact`、`PostCompact`、`UserPromptSubmit`。
- `PermissionRequest` 只支持审批决策形状；`Stop`、`SubagentStop` 继续以日志和本地恢复文件为主，不强行塞 unsupported 字段。
- 插件仍应避免直接写 stdout；返回字符串或 `{"additionalContext": "..."}` 即可，由通用入口统一包装 JSON。

开启飞书推送：

```bash
FEISHU_CODEX_HOOK_ENABLE_PUSH='true'
```

飞书插件复用 `shell/feishu_bot` 的应用机器人配置与发送脚本，并在插件内部构建飞书 Markdown 卡片内容。真实密钥仍放在本地 `.env` 或进程环境变量里，不要提交。

## 本地调试

```bash
./shell/codex_hook/codex_hook.sh ./payload.json
```

```powershell
.\shell\codex_hook\codex_hook.ps1 .\payload.json
```

默认会写脱敏 payload 日志，路径为 `shell/codex_hook/codex_hook_payload.log`，可用 `CODEX_HOOK_PAYLOAD_LOG_PATH` 覆盖。

插件异常不会写 stdout，也不会阻断 Codex 主流程；默认写入 `shell/codex_hook/codex_hook_error.log`，可用 `CODEX_HOOK_ERROR_LOG_PATH` 覆盖。

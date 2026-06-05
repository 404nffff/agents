# Codex Hook 通用入口

本目录是通用 Codex hooks 分发层。入口脚本只负责安装 hooks、读取 payload、调用 Python 事件层；具体动作通过 `plugins/<插件名>/hook.py` 完成。

## 文件说明

| 文件 | 用途 |
| --- | --- |
| `codex_hook.sh` | Linux/macOS Bash 入口，支持 `create` 和 payload 调试。 |
| `codex_hook.ps1` | Windows PowerShell 入口，支持 `create` 和 payload 调试。 |
| `hook.py` | 通用事件分发入口，负责 payload 读取、事件归一、脱敏日志、标题摘要和插件路由。 |
| `plugins/feishu/hook.py` | 飞书插件，复用 `shell/feishu_bot/feishu_bot_push.sh`，Windows 可直接调用飞书 API。 |
| `plugins/feishu/.env.example` | 飞书插件配置示例。 |
| `plugins/session_title/hook.py` | Codex 会话标题更新插件。 |
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

通用入口只保留事件到插件的路由配置：

```bash
CODEX_HOOK_EVENTS='SessionStart:feishu;SubagentStart:feishu;PreToolUse:feishu;PermissionRequest:feishu;PostToolUse:feishu;PreCompact:feishu;PostCompact:feishu;UserPromptSubmit:session_title;SubagentStop:feishu;Stop:feishu,session_title;'
```

格式：

- `;` 分隔事件。
- `:` 左侧是 Codex hook 事件名。
- `:` 右侧是插件列表，`,` 分隔。
- 插件会从 `plugins/<插件名>/hook.py` 加载，并调用其中的 `handle(context)`。
- `session_title` 不需要单独配置；挂到 `UserPromptSubmit` 和 `Stop` 后就会更新 Codex 会话标题。

飞书通知标题：

- `UserPromptSubmit` 会把本轮用户输入缓存为标题。
- `Stop` 的飞书通知优先复用该标题，缺失时才退回最终回复摘要。
- `codex_hook.sh create` / `codex_hook.ps1 create` 生成的 `hooks.json` 已包含 `UserPromptSubmit`，因此即使 `CODEX_HOOK_EVENTS` 没有给 `UserPromptSubmit` 配置插件，也会执行标题缓存。
- 标题状态默认写入 `shell/codex_hook/codex_hook_title_state.json`，可用 `CODEX_HOOK_TITLE_STATE_PATH` 覆盖。

飞书插件配置放插件目录：

```bash
cp shell/codex_hook/plugins/feishu/.env.example shell/codex_hook/plugins/feishu/.env
```

会话标题插件不需要独立 `.env`。需要启用时，把 `session_title` 挂到 `UserPromptSubmit` 和 `Stop`。

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

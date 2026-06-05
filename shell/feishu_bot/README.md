# 飞书机器人脚本说明

本目录收拢飞书机器人推送、Codex notify hook、Codex hooks 生命周期通知相关脚本。脚本默认读取当前目录下的 `.env`，可从 `.env.example` 复制后填写真实配置。不要提交真实 webhook、app_secret、token 或其他敏感值。

## 文件说明

| 文件 | 用途 |
| --- | --- |
| `feishu_bot_push.sh` | 通用飞书发送入口，支持自定义机器人和应用机器人。 |
| `feishu_bot_codex_notify.sh` | Codex `notify` hook 入口，仅处理 `agent-turn-complete`。 |
| `feishu_bot_codex_notify.ps1` | Windows PowerShell 版 Codex `notify` hook。 |
| `feishu_codex_hook.sh` | Codex `hooks` 生命周期入口，支持 `SessionStart`、`PreToolUse`、`Stop` 等事件。 |
| `feishu_codex_hook.ps1` | Windows PowerShell 版 Codex `hooks` 生命周期入口。 |
| `hook.py` | Codex 会话标题更新辅助脚本。 |
| `.env.example` | 配置模板。复制为 `.env` 后填写真实值。 |

## 配置

复制模板：

```bash
cp shell/feishu_bot/.env.example shell/feishu_bot/.env
```

应用机器人发送需要：

```bash
FEISHU_APP_ID=''
FEISHU_APP_SECRET=''
FEISHU_CHAT_ID=''
```

自定义机器人发送需要：

```bash
FEISHU_BOT_WEBHOOK=''
FEISHU_BOT_SECRET=''
```

接收者只能启用一种：`FEISHU_CHAT_ID`、`FEISHU_OPEN_ID`、`FEISHU_USER_ID`、`FEISHU_EMAIL`、`FEISHU_MOBILE`。邮箱和手机号查询需要飞书应用开通 `contact:user.id:readonly` 权限。

也可以用环境变量覆盖配置文件：

```bash
FEISHU_ENV_FILE=/path/to/feishu.env ./shell/feishu_bot/feishu_bot_push.sh --help
```

## 通用推送

查看帮助：

```bash
./shell/feishu_bot/feishu_bot_push.sh --help
```

发送普通文本：

```bash
./shell/feishu_bot/feishu_bot_push.sh text --text '部署完成'
```

发送 Markdown 卡片：

```bash
./shell/feishu_bot/feishu_bot_push.sh markdown --title '发布结果' --markdown '**状态**：成功'
```

应用机器人发送群消息：

```bash
./shell/feishu_bot/feishu_bot_push.sh app-markdown --title 'Codex 通知' --markdown '### 任务完成'
```

调试请求体，不实际发送：

```bash
./shell/feishu_bot/feishu_bot_push.sh markdown --title '测试' --markdown '**ok**' --dry-run
```

## Codex notify hook

`notify` 只在 Codex 回合完成时触发，适合发送“任务完成”摘要。

Linux/macOS 示例：

```toml
notify = ["bash", "/mnt/sync2/www/agents/shell/feishu_bot/feishu_bot_codex_notify.sh"]
```

Windows 示例：

```toml
notify = ["powershell", "-ExecutionPolicy", "Bypass", "-File", "C:\\path\\to\\shell\\feishu_bot\\feishu_bot_codex_notify.ps1"]
```

常用配置：

```bash
FEISHU_CODEX_NOTIFY_TITLE='Codex 任务完成'
FEISHU_CODEX_NOTIFY_STATUS='已完成'
FEISHU_CODEX_NOTIFY_TEMPLATE='green'
FEISHU_CODEX_NOTIFY_MAX_CHARS='3500'
FEISHU_CODEX_NOTIFY_LOG_PATH=''
```

## Codex hooks 生命周期通知

查看帮助：

```bash
./shell/feishu_bot/feishu_codex_hook.sh -h
```

生成当前平台 hooks 配置：

```bash
./shell/feishu_bot/feishu_codex_hook.sh create
```

该命令只写入当前平台对应配置到：

```text
~/.codex/hooks.json
```

强制生成指定平台配置：

```bash
./shell/feishu_bot/feishu_codex_hook.sh create linux
./shell/feishu_bot/feishu_codex_hook.sh create win
```

默认行为：

- 始终记录脱敏后的 hook payload，默认路径为 `shell/feishu_bot/codex_hook_payload.log`。
- 默认不发送飞书 hooks 通知，需设置 `FEISHU_CODEX_HOOK_ENABLE_PUSH=true`。
- 默认不把完整 `tool_input` / `tool_response` 发到飞书，避免敏感参数或输出泄露。
- `Stop` 阶段会裁剪 payload 日志，只保留最后 50 条。

常用配置：

```bash
FEISHU_CODEX_HOOK_ENABLE_PUSH='false'
FEISHU_CODEX_HOOK_EVENTS=''
FEISHU_CODEX_HOOK_UPDATE_SESSION_TITLE='false'
```

只推送部分事件：

```bash
FEISHU_CODEX_HOOK_EVENTS='Stop,PostToolUse'
```

开启飞书 hooks 通知：

```bash
FEISHU_CODEX_HOOK_ENABLE_PUSH='true'
```

开启 Codex 会话标题更新：

```bash
FEISHU_CODEX_HOOK_UPDATE_SESSION_TITLE='true'
```

标题更新只调用官方 `codex app-server --listen stdio://` 的 `thread/name/set`，不直接修改 Codex SQLite 状态库。

## 本地调试

使用保存的 hook payload 文件调试：

```bash
./shell/feishu_bot/feishu_codex_hook.sh ./payload.json
```

临时开启 hooks 推送：

```bash
FEISHU_CODEX_HOOK_ENABLE_PUSH=true ./shell/feishu_bot/feishu_codex_hook.sh ./payload.json
```

检查生成的 hooks JSON：

```bash
python3 -m json.tool ~/.codex/hooks.json
```

## 安全注意

- `.env` 已用于本地敏感配置，不要提交真实值。
- 不要把 `FEISHU_APP_SECRET`、`FEISHU_BOT_WEBHOOK`、`FEISHU_BOT_SECRET` 写入 README、测试日志或提交说明。
- `FEISHU_CODEX_HOOK_INCLUDE_PAYLOAD=true` 会把脱敏后的 payload 摘要放入飞书通知；只有确认输出不含敏感内容时再开启。
- hook 脚本失败时默认不阻断 Codex 主流程，错误信息优先查看 `codex_notify.log` 或 `codex_hook_payload.log`。

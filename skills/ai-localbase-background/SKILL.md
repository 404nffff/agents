---
name: ai-localbase-background
description: Use when starting any conversation in a project that uses ai_localbase as its primary knowledge base and may require background queueing, async polling, or automatic sync fallback when Python 3 is unavailable.
---

## 运行位置

以下内容是在说明 skill 自身的安装位置与项目运行状态目录，不是让你在项目目录里创建同名说明文件。

- skill 安装目录：`~/.codex/skills/ai-localbase-background/`
- 默认配置文件：`~/.codex/skills/ai-localbase-background/.env`
- 每个项目的运行状态目录：`<project>/docs/.ai-localbase-background/`

## 适用场景

- 需要把文档上传改成后台执行
- 需要先返回 `jobId`，稍后轮询状态
- 需要把 worker、日志、任务队列和结果按项目隔离
- 需要保持 `search / chat` 同步返回，不走后台队列
- 需要在没有 Python 的环境里继续可用

## 当前范围

这是最小后台版本，目前只提供：

- `init`
- `upload`
- `append`
- `update`
- `delete`
- `worker-start`
- `worker-status`
- `worker-logs`
- `worker-stop`
- `queue-upload`
- `queue-append`
- `queue-update`
- `queue-delete`
- `search`
- `chat`
- `job-status`
- `job-result`

其中：

- 每次进入项目仍然先执行 `init`，用于确认当前目录对应的 `knowledgeBaseId`
- Bash 入口同时内置同步 `upload / append / update / delete / search / chat`
- `queue-*` 在发现 worker 未运行时会自动拉起后台 worker
- 自动拉起的 worker 在队列清空并空闲一小段时间后会自行退出
- `search / chat` 保持同步执行，不进后台队列
- 若 Bash 入口未检测到 Python，则 `init` 和 `queue-*` 会自动回退为同步执行；`worker-*` 与 `job-*` 不可用

## 使用流程

1. 每次进入项目先执行 `init`
2. 需要立刻完成写入时，直接调用同步 `upload / append / update / delete`
3. 需要异步写入时，把任务写入 `queue-*`
4. `queue-*` 会在需要时自动启动后台 worker
5. 通过 `job-status` 轮询任务状态
6. 通过 `job-result` 查看最终返回结果
7. 需要即时检索或问答时，直接调用同步 `search / chat`
8. 一般不用手动停 worker；队列处理完并空闲后会自动退出
9. `worker-start / worker-stop` 只用于调试或批量任务排查
10. 若当前环境没有 Python，继续使用同一个 Bash 入口；`queue-*` 会自动回退为同步写入

## Bash 示例

```bash
# 每次进入项目先 init，确认知识库 ID
"${HOME}/.codex/skills/ai-localbase-background/ai-localbase-background.sh" init "/path/to/project"

# 直接同步上传
"${HOME}/.codex/skills/ai-localbase-background/ai-localbase-background.sh" upload "notes.md" "# 内容" "/path/to/project"

# 直接同步追加
"${HOME}/.codex/skills/ai-localbase-background/ai-localbase-background.sh" append "doc-123" "追加内容" "/path/to/project"

# 直接同步覆盖
"${HOME}/.codex/skills/ai-localbase-background/ai-localbase-background.sh" update "doc-123" "# 新内容" "/path/to/project"

# 直接同步删除
"${HOME}/.codex/skills/ai-localbase-background/ai-localbase-background.sh" delete "doc-123" "/path/to/project"

# 写入上传任务；若 worker 未运行会自动拉起
"${HOME}/.codex/skills/ai-localbase-background/ai-localbase-background.sh" queue-upload "notes.md" "# 内容" "/path/to/project"

# 追加文档任务
"${HOME}/.codex/skills/ai-localbase-background/ai-localbase-background.sh" queue-append "doc-123" "追加内容" "/path/to/project"

# 覆盖文档任务
"${HOME}/.codex/skills/ai-localbase-background/ai-localbase-background.sh" queue-update "doc-123" "# 新内容" "/path/to/project"

# 删除文档任务
"${HOME}/.codex/skills/ai-localbase-background/ai-localbase-background.sh" queue-delete "doc-123" "/path/to/project"

# 查询任务状态
"${HOME}/.codex/skills/ai-localbase-background/ai-localbase-background.sh" job-status "job-123" "/path/to/project"

# 查询任务结果
"${HOME}/.codex/skills/ai-localbase-background/ai-localbase-background.sh" job-result "job-123" "/path/to/project"

# 查看 worker 日志
"${HOME}/.codex/skills/ai-localbase-background/ai-localbase-background.sh" worker-logs "/path/to/project" 100

# 同步检索与问答
"${HOME}/.codex/skills/ai-localbase-background/ai-localbase-background.sh" search "关键词" "/path/to/project"
"${HOME}/.codex/skills/ai-localbase-background/ai-localbase-background.sh" search "/path/to/project" "关键词" 5
"${HOME}/.codex/skills/ai-localbase-background/ai-localbase-background.sh" chat "你的问题" "/path/to/project"

# 停止 worker
"${HOME}/.codex/skills/ai-localbase-background/ai-localbase-background.sh" worker-stop "/path/to/project"
```

## PowerShell 示例

```powershell
& "$HOME/.codex/skills/ai-localbase-background/ai-localbase-background.ps1" init "C:\work\project"
& "$HOME/.codex/skills/ai-localbase-background/ai-localbase-background.ps1" queue-upload "notes.md" "# 内容" "C:\work\project"
& "$HOME/.codex/skills/ai-localbase-background/ai-localbase-background.ps1" queue-append "doc-123" "追加内容" "C:\work\project"
& "$HOME/.codex/skills/ai-localbase-background/ai-localbase-background.ps1" queue-update "doc-123" "# 新内容" "C:\work\project"
& "$HOME/.codex/skills/ai-localbase-background/ai-localbase-background.ps1" queue-delete "doc-123" "C:\work\project"
& "$HOME/.codex/skills/ai-localbase-background/ai-localbase-background.ps1" job-status "job-123" "C:\work\project"
& "$HOME/.codex/skills/ai-localbase-background/ai-localbase-background.ps1" job-result "job-123" "C:\work\project"
& "$HOME/.codex/skills/ai-localbase-background/ai-localbase-background.ps1" search "关键词" "C:\work\project"
& "$HOME/.codex/skills/ai-localbase-background/ai-localbase-background.ps1" chat "你的问题" "C:\work\project"
& "$HOME/.codex/skills/ai-localbase-background/ai-localbase-background.ps1" worker-stop "C:\work\project"
```

## 状态目录

后台版会在项目 `docs/` 下维护：

- `docs/.ai-localbase-background/knowledge.json`
- `docs/.ai-localbase-background/worker.pid`
- `docs/.ai-localbase-background/worker.log`
- `docs/.ai-localbase-background/queue/`
- `docs/.ai-localbase-background/jobs/`
- `docs/.ai-localbase-background/results/`

## 注意点

- Bash 入口现在同时支持同步 `upload / append / update / delete / search / chat`
- `queue-upload / queue-append / queue-update / queue-delete` 在有 Python 时只负责投递任务，不保证任务立刻完成
- 若 `worker` 没启动，`queue-*` 会自动拉起一个后台 worker
- 若当前环境没有 Python，`queue-*` 会自动回退成对应的同步写入命令
- 无 Python 时，`worker-*` 和 `job-*` 不可用
- `job-result` 只有在任务成功或失败后才有结果
- `search / chat` 不依赖 worker，继续按同步方式立即返回
- 自动拉起的 worker 会在队列清空并空闲后自动退出
- 运行状态目录建议加入项目 `.gitignore`

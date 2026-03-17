# AGENTS.md 安装与更新指南

本仓库提供脚本 [`codex/install_agents.sh`](./codex/install_agents.sh)，用于将 `AGENTS.md` 安装到：

- 用户级：`~/.codex/AGENTS.md`
- 可选项目级：`当前目录/AGENTS.md`

脚本支持本地文件、URL、GitHub 仓库三种来源，并带有旧/新文件片段预览与替换确认。

## 1. 环境要求

- Linux / macOS / WSL / Git Bash（需要 `bash`）
- 可用命令：`bash`、`curl`、`diff`、`awk`
- Windows 用户请先确认 `bash` 可用（推荐 Git for Windows）

## 2. 快速开始

### 2.1 远程一键执行（交互模式）

```bash
curl -fsSL "https://raw.githubusercontent.com/404nffff/agents/master/codex/install_agents.sh" | bash
```

默认行为：

1. 未传参数时，优先使用仓库远程源：
   `https://raw.githubusercontent.com/404nffff/agents/master/codex/AGENTS.md`
2. 若远程源不可达，回退到脚本同目录本地 `AGENTS.md`
3. 若目标文件已存在，展示旧文件与新文件的部分内容后询问是否替换

### 2.2 远程一键执行（无交互自动覆盖）

```bash
curl -fsSL "https://raw.githubusercontent.com/404nffff/agents/master/codex/install_agents.sh" | bash -s -- --yes
```

适合自动化场景（CI/CD、初始化脚本、批量装机）。

## 3. 本地执行

```bash
chmod +x codex/install_agents.sh
./codex/install_agents.sh
```

无交互：

```bash
./codex/install_agents.sh --yes
```

## 4. 参数说明

```bash
./install_agents.sh [--source <path_or_url>]
./install_agents.sh [--github <owner/repo|https://github.com/owner/repo>] [--ref <branch_or_tag>] [--file <path_in_repo>]
./install_agents.sh [--yes]
```

- `--source`
  - 指定来源为本地文件路径或 HTTP(S) URL
  - 示例：
    - `--source ./AGENTS.md`
    - `--source https://example.com/AGENTS.md`
- `--github`
  - 指定 GitHub 仓库来源（`owner/repo` 或完整 URL）
- `--ref`
  - 指定分支或标签，默认 `main`
- `--file`
  - 指定仓库内文件路径，默认 `AGENTS.md`
- `--yes`
  - 无交互模式，遇到可替换文件直接替换

## 5. 常见用法

### 5.1 从指定 GitHub 仓库拉取

```bash
curl -fsSL "https://raw.githubusercontent.com/404nffff/agents/master/codex/install_agents.sh" | bash -s -- --github 404nffff/agents --ref master --file codex/AGENTS.md
```

### 5.2 从自定义 URL 拉取

```bash
curl -fsSL "https://raw.githubusercontent.com/404nffff/agents/master/codex/install_agents.sh" | bash -s -- --source "https://raw.githubusercontent.com/404nffff/agents/master/codex/AGENTS.md"
```

### 5.3 本地文件作为来源

```bash
./codex/install_agents.sh --source ./my-agents/AGENTS.md
```

## 6. 交互行为说明

当目标文件已存在时：

1. 脚本先显示旧文件前 20 行
2. 再显示新文件前 20 行
3. 最后询问是否替换

说明：

- 若旧文件与新文件无差异，会直接跳过替换且不再询问
- 若你使用 `--yes`，则跳过确认直接替换
- 管道执行（`curl | bash`）时，脚本通过 `/dev/tty` 读取确认输入

## 7. Windows 用法

### 7.1 Git Bash（推荐）

在 Git Bash 终端直接运行：

```bash
curl -fsSL "https://raw.githubusercontent.com/404nffff/agents/master/codex/install_agents.sh" | bash
```

```bash
curl -fsSL "https://raw.githubusercontent.com/404nffff/agents/master/codex/install_agents.sh" | bash -s -- --yes
```

### 7.2 PowerShell

`irm` 仅在 PowerShell 可用（`irm` = `Invoke-RestMethod`）：

```powershell
irm "https://raw.githubusercontent.com/404nffff/agents/master/codex/install_agents.sh" | bash
```

无交互自动替换：

```powershell
irm "https://raw.githubusercontent.com/404nffff/agents/master/codex/install_agents.sh" | bash -s -- --yes
```

如果提示找不到 `bash`，请安装 Git for Windows，或改在 Git Bash 终端执行。

### 7.3 cmd.exe（命令提示符）

`cmd.exe` 里不能用 `irm`。建议使用专用 bat 脚本：

```bat
curl -fsSL -o install_agents_windows.bat "https://raw.githubusercontent.com/404nffff/agents/master/codex/install_agents_windows.bat"
install_agents_windows.bat --yes
```

交互模式（会询问是否替换）：

```bat
install_agents_windows.bat
```

bat 脚本支持参数：

```bat
install_agents_windows.bat --source .\AGENTS.md
install_agents_windows.bat --source https://example.com/AGENTS.md
install_agents_windows.bat --github 404nffff/agents --ref master --file codex/AGENTS.md
```

可用环境：

- WSL
- Git Bash
- MSYS2
- cmd.exe（推荐使用 bat 脚本）

## 8. 常见问题

### Q1: 为什么 `wget -qO-` 在 PowerShell 报错？

PowerShell 的 `wget` 是 `Invoke-WebRequest` 别名，不支持 `-qO-`。请改用：

- `irm "...script..." | bash`
- 或 `curl.exe -fsSL "...script..." | bash`

### Q2: 为什么 `cmd.exe` 下 `irm` 不存在？

因为 `irm` 是 PowerShell 命令，不是 `cmd.exe` 命令。`cmd.exe` 请使用 bat 脚本：

- `curl -o install_agents_windows.bat ...`
- 然后执行：`install_agents_windows.bat --yes`

### Q3: 远程执行时为什么没有停下来等确认？

旧版本脚本可能从管道 `stdin` 读输入。当前版本已改为 `/dev/tty` 读取；无交互环境建议使用 `--yes`。

### Q4: 安装后覆盖了哪些文件？

- 必定处理：`~/.codex/AGENTS.md`
- 可选处理：`当前目录/AGENTS.md`（交互询问或 `--yes` 自动执行）

## 9. 返回码

- `0`：成功
- 非 `0`：失败（如来源文件不可用、参数错误等）

可通过 `echo $?` 查看最近一次执行状态。

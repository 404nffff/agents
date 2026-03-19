# Agents 安装说明（统一入口）

推荐使用统一脚本：`codex/install.sh`。

它整合了以下安装流程：
- `mcp`：按 `mcp.md` 清单安装/更新 `~/.codex/config.toml` 的 `mcp_servers`
- `agents`：安装/更新 `AGENTS.md`
- `skills`：安装 `skills` 到 `~/.codex/skills`
- `all`：按顺序执行 `mcp -> agents -> skills`

## 1) 快速开始

### 本地仓库运行（推荐）

交互选择安装目标：

```bash
bash ./codex/install.sh
```

直接指定目标：

```bash
bash ./codex/install.sh mcp
bash ./codex/install.sh agents
bash ./codex/install.sh skills
bash ./codex/install.sh all
```

无交互自动确认：

```bash
bash ./codex/install.sh all --yes
```

### 远程运行（Linux / macOS / Git Bash）

交互选择安装目标：

```bash
curl -fsSL "https://raw.githubusercontent.com/404nffff/agents/master/codex/install.sh" | bash
```

直接安装 skills（自动确认）：

```bash
curl -fsSL "https://raw.githubusercontent.com/404nffff/agents/master/codex/install.sh" | bash -s -- skills --yes
```

## 2) install.sh 用法

```bash
./install.sh
./install.sh <mcp|agents|skills|all> [目标参数...]
./install.sh --target <mcp|agents|skills|all> [目标参数...]
./install.sh --mcp|--agents|--skills|--all [目标参数...]
```

目标帮助：

```bash
./install.sh mcp --help
./install.sh agents --help
./install.sh skills --help
./install.sh all --help
```

## 3) 各目标参数

### mcp

```bash
--source <path_or_url>
--github <owner/repo>
--ref <branch_or_tag>
--mcp-path <path_in_repo>
--config <config_path>
--yes
```

说明：
- 默认读取：`404nffff/agents@master:codex/mcp.md`
- 远程失败时回退到本地：`codex/mcp.md`（含脚本同目录和当前目录候选）
- 仅更新 `config.toml` 中 `mcp_servers` 相关段落

### agents

```bash
--source <path_or_url>
--github <owner/repo>
--ref <branch_or_tag>
--file <path_in_repo>
--yes
```

说明：
- 默认优先远程：`404nffff/agents@master:codex/AGENTS.md`
- 安装目标：`~/.codex/AGENTS.md`
- 可选生成：`当前目录/AGENTS.md`

### skills

```bash
--github <owner/repo>
--ref <branch_or_tag>
--skills-path <path_in_repo>
--yes
```

说明：
- 优先读取本地 `codex/skills`
- 本地不存在时读取远程 `404nffff/agents@master:codex/skills`
- 安装到 `~/.codex/skills/<name>`
- 同名 skill 覆盖时保留本地 `config.env`

### all

```bash
--yes
```

说明：
- `all` 模式只支持 `--yes`，用于统一自动确认

## 4) Windows 说明

Windows 仍可使用已有批处理脚本：
- `codex/install_agents_windows.bat`
- `codex/install_skills_windows.bat`

当前统一入口 `codex/install.sh` 主要面向 Bash 环境（Linux/macOS/Git Bash）。

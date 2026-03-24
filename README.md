# Agents 安装说明（统一入口）

推荐使用统一脚本：`codex/install.sh`。

统一入口支持以下目标：
- `mcp`：按 `mcp.md` 清单安装/更新 `~/.codex/config.toml` 的 `mcp_servers`
- `agents`：安装/更新 `AGENTS.md`
- `skills`：安装 `skills` 到 `~/.codex/skills`
- `all`：按顺序执行 `mcp -> agents -> skills`

## 1) 安装方式

### 本地仓库安装（推荐）

交互安装：

```bash
bash ./codex/install.sh
```

指定目标安装：

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

### 远程安装（Linux / macOS / Git Bash）

默认跟随最新 tag：

```bash
INSTALL_URL="https://cdn.jsdelivr.net/gh/404nffff/agents@latest/codex/install.sh"
curl -fsSL "${INSTALL_URL}" | bash
```

直接安装 `skills`（自动确认）：

```bash
curl -fsSL "${INSTALL_URL}" | bash -s -- skills --yes
```

固定版本安装（便于回滚）：

```bash
curl -fsSL "https://cdn.jsdelivr.net/gh/404nffff/agents@v1.0.0/codex/install.sh" | bash
```

### 远程安装（Raw GitHub）

默认分支（master）：

```bash
curl -fsSL "https://raw.githubusercontent.com/404nffff/agents/master/codex/install.sh" | bash
```

仅安装 skills（自动确认）：

```bash
curl -fsSL "https://raw.githubusercontent.com/404nffff/agents/master/codex/install.sh" | bash -s -- skills --yes
```

固定版本 tag：

```bash
curl -fsSL "https://raw.githubusercontent.com/404nffff/agents/v1.0.0/codex/install.sh" | bash
```

## 2) install.sh 命令总览

```bash
./install.sh
./install.sh <mcp|agents|skills|all> [目标参数...]
./install.sh --target <mcp|agents|skills|all> [目标参数...]
./install.sh --mcp|--agents|--skills|--all [目标参数...]
```

查看目标帮助：

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
--db-query-tag <tag>
--db-query-download <yes|no>
--yes
```

说明：
- 优先读取本地 `codex/skills`
- 本地不存在时读取远程 `404nffff/agents@master:codex/skills`
- 安装到 `~/.codex/skills/<name>`
- 同名 skill 覆盖时保留本地 `config.env`
- 安装 `db-query` 时会提示输入 release tag（默认自动带出远程最近 tag）
- 安装 `db-query` 时会先判断当前平台并只下载对应 bin；若选不远程下载，脚本会提示 release 页面和目标 `bin` 目录，需手动下载并复制

### all

```bash
--yes
```

说明：
- `all` 模式只支持 `--yes`，用于统一自动确认

## 4) 维护者发布 Tag

```bash
# 1) 在当前提交打带注释 tag
git tag -a v1.0.0 -m "release: v1.0.0"

# 2) 推送该 tag
git push origin v1.0.0

# 3)（可选）一次性推送所有本地 tags
git push origin --tags
```

推送后可直接按版本安装：

```bash
curl -fsSL "https://cdn.jsdelivr.net/gh/404nffff/agents@v1.0.0/codex/install.sh" | bash
```

## 5) Nginx 配置（可选）

仓库内已提供 Nginx + 静态页面示例：
- `codex/nginx-install.conf`（`/install.sh` 302 跳转 + `/` 静态页）
- `codex/index.html`（静态说明页面模板）

## 6) Windows 说明

Windows 仍可使用已有批处理脚本：
- `codex/install_agents_windows.bat`
- `codex/install_skills_windows.bat`

统一入口 `codex/install.sh` 主要面向 Bash 环境（Linux/macOS/Git Bash）。

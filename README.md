# Agents 安装说明（精简版）

本仓库提供两个安装脚本：

- `install_agents.sh`：安装/更新 `AGENTS.md`
- `install_skills.sh`：安装 `skills` 到 `~/.codex/skills`

## 1) AGENTS.md 安装

### Linux / macOS / Git Bash

交互模式：

```bash
curl -fsSL "https://raw.githubusercontent.com/404nffff/agents/master/codex/install_agents.sh" | bash
```

无交互自动覆盖：

```bash
curl -fsSL "https://raw.githubusercontent.com/404nffff/agents/master/codex/install_agents.sh" | bash -s -- --yes
```

### Windows（PowerShell，推荐）

```powershell
$bat = "$env:TEMP\install_agents_windows.bat"
Invoke-WebRequest "https://raw.githubusercontent.com/404nffff/agents/master/codex/install_agents_windows.bat" -OutFile $bat
& $bat --yes
```

### Windows（cmd.exe）

```bat
curl -fsSL -o install_agents_windows.bat "https://raw.githubusercontent.com/404nffff/agents/master/codex/install_agents_windows.bat"
install_agents_windows.bat --yes
```

### install_agents.sh 常用参数

```bash
--source <path_or_url>
--github <owner/repo>
--ref <branch_or_tag>
--file <path_in_repo>
--yes
```

说明：

- 默认源：`https://raw.githubusercontent.com/404nffff/agents/master/codex/AGENTS.md`
- 安装目标：`~/.codex/AGENTS.md`
- 可选创建：`当前目录/AGENTS.md`

## 2) Skills 安装

### 本地仓库运行

```bash
bash ./codex/install_skills.sh
```

### 远程运行（默认仓库）

```bash
curl -fsSL "https://raw.githubusercontent.com/404nffff/agents/master/codex/install_skills.sh" | bash
```

### 指定远程仓库

```bash
curl -fsSL "https://raw.githubusercontent.com/404nffff/agents/master/codex/install_skills.sh" | bash -s -- --github 404nffff/agents --ref master --skills-path codex/skills
```

### install_skills.sh 说明

- 读取每个 skill 的 `SKILL.md/skill.md` 中的 `name`、`description`
- 通过文本菜单勾选要安装的 skills
- 安装到 `~/.codex/skills/<name>`
- 同名 skill 会询问是否覆盖
  - 选择覆盖：仅覆盖同名文件，保留目标目录其他文件
  - 选择跳过：保持现状

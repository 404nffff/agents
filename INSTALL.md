# INSTALL.md - MCP / Agents / Skills 安装指南

> **目标读者:** AI Agent & 自动化执行脚本
> **标准仓库位置:** `https://github.com/404nffff/agents`
> **标准脚本位置:** `https://raw.githubusercontent.com/404nffff/agents/master/shell/codex/install_codex.sh`
> **核心准则:** 本文档可以部署到任意位置，但安装来源必须始终指向标准仓库。Codex 使用 `shell/codex/install_codex.sh` 自动安装；Claude Code、OpenClaw 复用本仓库资源并按各自客户端格式导入，不要把 Codex 脚本当作跨客户端安装器。

## 快速开始

Codex 默认安装方式是直接从 Raw GitHub 拉取标准安装脚本执行，不要求当前机器已有本仓库源码。

默认必须使用交互安装：脚本会先列出可安装的 MCP servers、Agent 文件或 Skills，用户选择条目并输入 `d` 后才开始安装。部分 MCP server 需要 API Token 或 Bearer Token，安装脚本会在写入 `~/.codex/config.toml` 前提示用户输入，输入完成后再继续安装：

```bash
INSTALL_URL="https://raw.githubusercontent.com/404nffff/agents/master/shell/codex/install_codex.sh"

# 1. 先列出 MCP servers，选择需要安装的项；如选中项需要 token，按提示输入后继续
curl -fsSL "${INSTALL_URL}" | bash -s -- mcp

# 2. 列出 Agent 文件，选择一个需要安装的 agent
curl -fsSL "${INSTALL_URL}" | bash -s -- agents

# 3. 列出 Skills，勾选需要安装的 skill
curl -fsSL "${INSTALL_URL}" | bash -s -- skills
```

只有在自动化环境中已明确知道要安装默认项，且接受不先人工选择列表时，才使用无交互安装：

```bash
curl -fsSL "${INSTALL_URL}" | bash -s -- all --yes
```

`--yes` 模式不会停下来要求用户选择条目，也不会要求输入 token；遇到空 token 或占位 token 时会保留原占位并输出提示。日常安装不要使用 `--yes`。

---

## 按客户端安装

### Codex

`shell/codex/install_codex.sh` 当前只自动写入 Codex 目录和配置：

| 资源 | 安装目标 | 安装命令 |
| --- | --- | --- |
| MCP | `~/.codex/config.toml` 的 `mcp_servers` 区域 | `curl -fsSL "${INSTALL_URL}" | bash -s -- mcp`，先列出 MCP servers，再选择安装项 |
| Agents | `~/.codex/AGENTS.md` 或当前项目 `AGENTS.md` | `curl -fsSL "${INSTALL_URL}" | bash -s -- agents`，先列出 Agent 文件，再选择一个安装项 |
| Skills | `~/.codex/skills/` | `curl -fsSL "${INSTALL_URL}" | bash -s -- skills`，先列出 Skills，再勾选安装项 |

推荐执行顺序：

```bash
INSTALL_URL="https://raw.githubusercontent.com/404nffff/agents/master/shell/codex/install_codex.sh"

# 1. 先列出 MCP servers，选择需要安装的项；如选中项需要 token，按提示输入后继续
curl -fsSL "${INSTALL_URL}" | bash -s -- mcp

# 2. 列出 Agent 文件，选择一个需要安装的 agent
curl -fsSL "${INSTALL_URL}" | bash -s -- agents

# 3. 列出 Skills，勾选需要安装的 skill
curl -fsSL "${INSTALL_URL}" | bash -s -- skills
```

仅当处于自动化环境、已明确接受跳过人工选择列表时，才使用全量无交互安装：

```bash
curl -fsSL "${INSTALL_URL}" | bash -s -- all --yes
```

### Claude Code

本仓库不直接写入 `~/.claude`。Claude Code 需要按当前版本官方命令和目录导入，建议按资源类型处理。以下命令示例默认在目标项目根目录执行。

| 资源 | 本仓库来源 | Claude Code 安装方式 |
| --- | --- | --- |
| MCP | `mcp/mcp.md` | 从目标 `mcp_servers.<name>` TOML 块转换为 Claude Code JSON；用 `claude mcp add-json` / `claude mcp add` 导入，或写入项目 `.mcp.json`。 |
| Agents / 规则 | `agents/AGENTS_GLOBAL.md`、`agents/*.md` | Claude Code 读取 `CLAUDE.md`，不直接读取 `AGENTS.md`。把通用规则写入 `~/.claude/CLAUDE.md`，项目规则写入 `./CLAUDE.md` 或 `./.claude/CLAUDE.md`；已有 `AGENTS.md` 时可在 `CLAUDE.md` 中用 `@AGENTS.md` 导入。 |
| Subagents | `agents/*.md` | 如需 Claude Code custom subagent，把选定 agent 文件改写为带 YAML frontmatter 的 subagent markdown，放入 `.claude/agents/` 或 `~/.claude/agents/`。 |
| Skills | `skills/<name>/` | 保留完整目录结构，复制到 `.claude/skills/<name>/` 或 `~/.claude/skills/<name>/`；`SKILL.md` 必须位于 skill 目录根部。 |

#### Claude Code MCP

先从 `mcp/mcp.md` 选一个 server。Codex TOML 来源示例：

```toml
[mcp_servers.sequential-thinking]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-sequential-thinking"]
startup_timeout_sec = 120.0
```

可用 Claude Code CLI 导入为本项目可用的 MCP server：

```bash
claude mcp add --transport stdio sequential-thinking -- npx -y @modelcontextprotocol/server-sequential-thinking
claude mcp list
```

如果需要从 JSON 导入：

```bash
claude mcp add-json sequential-thinking '{"type":"stdio","command":"npx","args":["-y","@modelcontextprotocol/server-sequential-thinking"]}'
claude mcp get sequential-thinking
```

作用域按使用场景选择：
- `--scope local`：默认值，仅当前项目可用，私有配置，适合含个人 token 的 MCP。
- `--scope project`：写入项目根 `.mcp.json`，可提交给团队共享；不要把真实 token 写入仓库。
- `--scope user`：写入用户配置，所有项目可用。

若手写 `.mcp.json`，结构应为：

```json
{
  "mcpServers": {
    "sequential-thinking": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
    }
  }
}
```

含 token 的 MCP server 必须在导入前补齐真实 token，或改成环境变量注入；不要把 token 提交到 `.mcp.json`。Windows 原生环境下，如果 server 通过 `npx` 启动，通常需要用 `cmd /c npx ...` 包一层。

#### Claude Code Agents / CLAUDE.md

Claude Code 的常驻项目规则入口是 `CLAUDE.md`，不是 `AGENTS.md`。推荐二选一：

```bash
# 项目级：让 Claude Code 复用本项目已有 AGENTS.md
printf '@AGENTS.md\n\n## Claude Code\n\n遵循本项目现有 Agent 规则。\n' > CLAUDE.md

# 用户级：把本仓库全局规则复制到 Claude Code 用户规则
mkdir -p ~/.claude
cp agents/AGENTS_GLOBAL.md ~/.claude/CLAUDE.md
```

如果要使用 Claude Code subagents，不要直接把 `agents/AGENTS_GLOBAL.md` 原样复制进去；需要转换为 subagent 格式：

```bash
mkdir -p .claude/agents
cat > .claude/agents/codex-engineer.md <<'EOF'
---
name: codex-engineer
description: 使用本仓库 Codex 工程规范处理代码、文档、验证和交付任务。
tools: Read, Grep, Glob, Bash
model: inherit
---

请遵循 agents/AGENTS_GLOBAL.md 中的工程规范，并按当前项目上下文执行任务。
EOF
```

#### Claude Code Skills

Claude Code skills 是目录式资源，目录中必须有 `SKILL.md`。安装时保留 supporting files：

```bash
# 用户级 skill：所有项目可用
mkdir -p ~/.claude/skills
cp -R skills/git-commit-helper ~/.claude/skills/git-commit-helper

# 项目级 skill：只在当前项目可用，可提交给团队
mkdir -p .claude/skills
cp -R skills/git-commit-helper .claude/skills/git-commit-helper
```

验证方式：

```bash
claude mcp list
test -f CLAUDE.md || test -f .claude/CLAUDE.md
test -f .claude/skills/git-commit-helper/SKILL.md || test -f ~/.claude/skills/git-commit-helper/SKILL.md
```

Claude Code 官方参考：
- MCP：`https://docs.claude.com/en/docs/claude-code/mcp`
- CLAUDE.md / AGENTS.md 导入：`https://docs.claude.com/en/docs/claude-code/memory`
- Subagents：`https://docs.claude.com/en/docs/claude-code/sub-agents`
- Skills：`https://docs.claude.com/en/docs/claude-code/skills`

### OpenClaw

本仓库不提供 OpenClaw 专用写入脚本。OpenClaw 需要按当前版本的 CLI 和配置入口导入。以下命令示例默认在目标 workspace 或项目根目录执行。

| 资源 | 本仓库来源 | OpenClaw 安装方式 |
| --- | --- | --- |
| MCP | `mcp/mcp.md` | 从目标 `mcp_servers.<name>` TOML 块转换为 JSON，用 `openclaw mcp set <name> '<json>'` 保存到 OpenClaw 管理的 MCP registry。 |
| Agent 规则 / bootstrap | `agents/AGENTS_GLOBAL.md`、`agents/*.md` | OpenClaw workspace 可使用 `AGENTS.md` 等 bootstrap 文件。把全局规则复制到目标 workspace 的 `AGENTS.md`，或按 agent profile 写入对应 workspace/agent 目录。 |
| Agent 配置 | `agents/*.md` | 通过 `~/.openclaw/openclaw.json` 的 `agents.defaults` / `agents.list[]` 配置 workspace、repoRoot、skills allowlist、模型、runtime 等。 |
| Skills | `skills/<name>/` | OpenClaw 支持 AgentSkills-compatible skill folders。完整复制 skill 目录到 `<workspace>/skills`、`<workspace>/.agents/skills`、`~/.agents/skills` 或 `~/.openclaw/skills`。 |

#### OpenClaw MCP

从 `mcp/mcp.md` 选择一个 server，转换为 OpenClaw `openclaw mcp set` 需要的 JSON：

```bash
openclaw mcp set sequential-thinking '{"command":"npx","args":["-y","@modelcontextprotocol/server-sequential-thinking"]}'
openclaw mcp list
openclaw mcp show sequential-thinking --json
```

带环境变量的 MCP 示例：

```bash
openclaw mcp set context7 '{"command":"npx","args":["-y","@upstash/context7-mcp","--api-key",""],"env":{"CONTEXT7_API_KEY":"${CONTEXT7_API_KEY}"}}'
```

含 token 的配置优先使用 OpenClaw secrets、环境变量或本机私有配置，不要写入仓库。

#### OpenClaw Agent 规则 / 配置

OpenClaw 的 agent 配置在 `~/.openclaw/openclaw.json` 中按 `agents.defaults` 和 `agents.list[]` 管理；workspace 中的 bootstrap 文件（如 `AGENTS.md`）会作为 agent 上下文。推荐：

```bash
# 当前 workspace 使用本仓库全局规则
cp agents/AGENTS_GLOBAL.md AGENTS.md
```

如需给某个 OpenClaw agent 固定 workspace、repoRoot 和 skill allowlist，可在 `~/.openclaw/openclaw.json` 中加入类似配置：

```json
{
  "agents": {
    "defaults": {
      "workspace": "~/.openclaw/workspace",
      "repoRoot": "~/Projects/agents"
    },
    "list": [
      {
        "id": "codex-docs",
        "name": "Codex Docs Agent",
        "workspace": "~/Projects/agents",
        "repoRoot": "~/Projects/agents",
        "skills": ["git-commit-helper", "db-query"]
      }
    ]
  }
}
```

`skills` 是 allowlist：设置后该 agent 只使用列表中的 skill；如果希望不限制 skills，不要设置该字段。

#### OpenClaw Skills

OpenClaw 的 skills 是 AgentSkills-compatible 目录。按作用域选择复制位置：

```bash
# 当前 workspace 最高优先级
mkdir -p skills
cp -R /path/to/agents/skills/git-commit-helper skills/git-commit-helper

# 当前 workspace 的 project agent skills
mkdir -p .agents/skills
cp -R /path/to/agents/skills/git-commit-helper .agents/skills/git-commit-helper

# 当前用户所有 OpenClaw agent 可用
mkdir -p ~/.agents/skills
cp -R /path/to/agents/skills/git-commit-helper ~/.agents/skills/git-commit-helper

# OpenClaw 管理/本地 skills
mkdir -p ~/.openclaw/skills
cp -R /path/to/agents/skills/git-commit-helper ~/.openclaw/skills/git-commit-helper
```

OpenClaw skill 优先级从高到低通常是：`<workspace>/skills`、`<workspace>/.agents/skills`、`~/.agents/skills`、`~/.openclaw/skills`、bundled skills、`skills.load.extraDirs`。

验证方式：

```bash
openclaw mcp list
openclaw agents list
test -f skills/git-commit-helper/SKILL.md || test -f .agents/skills/git-commit-helper/SKILL.md || test -f ~/.agents/skills/git-commit-helper/SKILL.md || test -f ~/.openclaw/skills/git-commit-helper/SKILL.md
```

OpenClaw 官方参考：
- MCP CLI：`https://docs.openclaw.ai/cli/mcp`
- Agent runtime / workspace bootstrap：`https://docs.openclaw.ai/concepts/agent`
- Agents CLI：`https://docs.openclaw.ai/cli/agents`
- Agents config：`https://docs.openclaw.ai/gateway/config-agents`
- Skills：`https://docs.openclaw.ai/skills`

---

## 标准仓库与路径

| 项目 | 标准位置 |
| --- | --- |
| GitHub 仓库 | `https://github.com/404nffff/agents` |
| Raw GitHub 安装脚本 | `https://raw.githubusercontent.com/404nffff/agents/master/shell/codex/install_codex.sh` |
| MCP 配置来源 | `mcp/mcp.md` |
| Agents 目录索引 | `agents/README.md` |
| Skills 目录索引 | `skills/README.md` |

---

## 安装目标说明

`shell/codex/install_codex.sh` 是 Codex 自动安装器，支持 4 个安装目标：

### 1. `all` (自动化专用)
按顺序完整执行安装流程：`mcp` -> `agents` -> `skills`。
- **命令:** `curl -fsSL "${INSTALL_URL}" | bash -s -- all --yes`
- *注意: `all` 模式必须配合 `--yes` 参数使用，因此不会先让用户选择 MCP、Agent 或 Skill 条目，也不会交互输入 MCP token。日常安装不要使用 `all`，请分别执行 `mcp`、`agents`、`skills`。*

### 2. `mcp`
将 `mcp/mcp.md` 中的 `mcp_servers` 配置写入到目标机器的 `~/.codex/config.toml`。
- **交互命令:** `curl -fsSL "${INSTALL_URL}" | bash -s -- mcp`
- **无交互命令:** `curl -fsSL "${INSTALL_URL}" | bash -s -- mcp --yes`
- *注意: 交互模式会先列出 MCP servers，用户勾选后输入 `d` 才开始安装。此操作仅更新 `mcp_servers` 节点，不会破坏或修改用户的其他配置。部分 MCP server 需要配置 token；交互模式会提示用户输入，`--yes` 模式不会输入 token，会保留占位。*

### 3. `agents`
将全局代理规则文件安装至 `~/.codex/AGENTS.md`。
- **交互命令:** `curl -fsSL "${INSTALL_URL}" | bash -s -- agents`
- **无交互命令:** `curl -fsSL "${INSTALL_URL}" | bash -s -- agents --yes`
- *行为: 交互模式会先读取标准仓库的 `agents/README.md` 并列出可安装 Agent 文件；用户选择一个条目并输入 `d` 后才开始安装。`--yes` 会跳过人工选择，日常安装不要使用。*

### 4. `skills`
将 `skills/` 下的所有可用技能安装至 `~/.codex/skills/`。
- **交互命令:** `curl -fsSL "${INSTALL_URL}" | bash -s -- skills`
- **无交互命令:** `curl -fsSL "${INSTALL_URL}" | bash -s -- skills --yes`
- *行为: 交互模式会先读取标准仓库的 `skills/README.md` 并列出可安装 Skills；用户勾选条目并输入 `d` 后才开始安装。如遇同名 skill，覆盖时会保留原有的配置文件。只有安装或同步 `db-query` skill 时，才会下载 db-query release 二进制；安装 MCP、Agents 或其他 Skills 不会下载下方二进制文件。`--yes` 会跳过人工选择，日常安装不要使用。*

`db-query` skill 涉及的 release 二进制地址：

- `https://github.com/404nffff/agents/releases/download/v0.0.1/db-query-linux-amd64`
- `https://github.com/404nffff/agents/releases/download/v0.0.1/db-query-windows-amd64.exe`

---

## Codex 默认远程安装方式

```bash
INSTALL_URL="https://raw.githubusercontent.com/404nffff/agents/master/shell/codex/install_codex.sh"

# 1. 先列出 MCP servers，选择需要安装的项；如选中项需要 token，按提示输入后继续
curl -fsSL "${INSTALL_URL}" | bash -s -- mcp

# 2. 列出 Agent 文件，选择一个需要安装的 agent
curl -fsSL "${INSTALL_URL}" | bash -s -- agents

# 3. 列出 Skills，勾选需要安装的 skill
curl -fsSL "${INSTALL_URL}" | bash -s -- skills

# 自动化专用：不先人工选择列表，日常安装不要使用
curl -fsSL "${INSTALL_URL}" | bash -s -- all --yes
```

远程执行 `mcp`、`agents`、`skills` 安装时，脚本会先列出可安装项，只有在用户选择条目并输入 `d` 后才会写入本机配置或文件。远程执行 `mcp` 安装时，如果选中的 MCP 配置包含 `API_KEY`、`TOKEN`、`Authorization Bearer token` 或空 `--api-key` 等占位，脚本会提示输入。可直接输入 token；也可以留空保留占位，后续再手动补齐 `~/.codex/config.toml`。

只有安装流程实际选中 `db-query` skill 时，脚本才会访问 GitHub Release 下载 `db-query-linux-amd64` 或 `db-query-windows-amd64.exe`。其他安装目标不会触发这两个二进制下载。

指定版本安装时，将 `master` 替换为固定 tag：

```bash
INSTALL_URL="https://raw.githubusercontent.com/404nffff/agents/v1.0.0/shell/codex/install_codex.sh"
curl -fsSL "${INSTALL_URL}" | bash -s -- mcp
curl -fsSL "${INSTALL_URL}" | bash -s -- agents
curl -fsSL "${INSTALL_URL}" | bash -s -- skills
```

---

## Codex 安装后验证步骤

**AI 执行强制要求:** 安装完成后，绝对不能仅回复“已完成”。必须立即执行以下命令进行存在性检查，并向用户反馈验证结果：

```bash
# 1. 检查基础目录结构
ls -la ~/.codex
ls -la ~/.codex/skills

# 2. 验证核心文件与配置状态
test -f ~/.codex/AGENTS.md && echo "✅ AGENTS OK" || echo "❌ AGENTS MISSING"
test -f ~/.codex/config.toml && grep -q "mcp_servers" ~/.codex/config.toml && echo "✅ CONFIG OK" || echo "❌ CONFIG MISSING/INVALID"
```

完整的安装预期结果应当是：
1. `~/.codex/AGENTS.md` 文件已存在。
2. `~/.codex/config.toml` 文件已存在，且包含有效的 `mcp_servers` 配置段。
3. `~/.codex/skills/` 目录下出现已安装的各个 skill 文件夹。

---

## 目录结构参考

为了帮助 AI 更好地理解上下文，以下是关键文件的说明：
- `shell/codex/install_codex.sh`：Codex 自动安装逻辑的统一入口。
- `mcp/mcp.md`：MCP (Model Context Protocol) 原始配置来源。
- `agents/README.md`：可安装的 Agent 规则文件目录索引。
- `skills/README.md`：可安装的 Skill 扩展包目录索引。

---

## Codex 安装脚本帮助

要查看任何命令或目标的详细帮助信息，请执行：

```bash
INSTALL_URL="https://raw.githubusercontent.com/404nffff/agents/master/shell/codex/install_codex.sh"

curl -fsSL "${INSTALL_URL}" | bash -s -- --help
curl -fsSL "${INSTALL_URL}" | bash -s -- mcp --help
curl -fsSL "${INSTALL_URL}" | bash -s -- agents --help
curl -fsSL "${INSTALL_URL}" | bash -s -- skills --help
curl -fsSL "${INSTALL_URL}" | bash -s -- all --help
```

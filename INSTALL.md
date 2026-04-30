# INSTALL.md - MCP / Agents / Skills 安装指南

> **目标读者:** AI Agent & 自动化执行脚本
> **标准仓库位置:** `https://github.com/404nffff/agents`
> **标准资源位置:** `mcp/*.md`、`agents/README.md`、`skills/README.md`
> **核心准则:** 本文档是标准仓库资源的全局安装入口，覆盖 Codex、Claude Code、OpenClaw 三类客户端。所有客户端都必须从标准仓库读取 MCP、Agents、Skills 源文件，并在安装前先确认要导入的条目。不要把任一客户端的安装方式当作其他客户端的通用安装器。

## 前置要求

- **操作系统:** Linux / macOS / Windows (WSL)
- **必需工具:** `curl`、`bash`
- **网络要求:** 能访问 GitHub 和 npm registry
- **权限要求:** 对目标配置目录有写入权限

## 客户端选择

先确认目标客户端，再按对应章节安装。不要跳过客户端选择，也不要把 Codex 的脚本入口用于 Claude Code 或 OpenClaw。

| 客户端 | 安装方式 | 配置位置 |
| --- | --- | --- |
| **Codex** | 交互式脚本自动安装 | `~/.codex/` |
| **Claude Code** | 手动转换并使用官方 CLI | `~/.claude/` 或项目 `.claude/` |
| **OpenClaw** | 手动转换并使用官方 CLI | `~/.openclaw/` 或项目配置 |

---

## 一、Codex 安装

### 安装脚本入口

```bash
INSTALL_URL="https://raw.githubusercontent.com/404nffff/agents/master/shell/codex/install_codex.sh"
```

### 安装目标

| 资源 | 安装位置 | 说明 |
| --- | --- | --- |
| MCP | `~/.codex/config.toml` | 写入 `mcp_servers` 配置段 |
| Agents | `~/.codex/AGENTS.md` | 全局 Agent 规则文件 |
| Skills | `~/.codex/skills/` | Skill 扩展包目录 |

### 交互式安装（推荐）

脚本会先列出可安装项，用户选择后输入 `d` 确认安装。部分 MCP 需要 token，会在安装时提示输入：

```bash
# 1. 安装 MCP servers（如需 token 会提示输入）
curl -fsSL "${INSTALL_URL}" | bash -s -- mcp

# 2. 安装 Agent 规则文件（选择一个）
curl -fsSL "${INSTALL_URL}" | bash -s -- agents

# 3. 安装 Skills（可多选）
curl -fsSL "${INSTALL_URL}" | bash -s -- skills

# 或一次性安装全部（会分三个阶段交互）
curl -fsSL "${INSTALL_URL}" | bash -s -- all
```

### 自动化安装（仅限 CI/CD）

⚠️ **警告:** `--yes` 模式会跳过所有交互和 token 输入，仅适合自动化环境：

```bash
curl -fsSL "${INSTALL_URL}" | bash -s -- all --yes
```

### 指定版本安装

将 `master` 替换为具体 tag：

```bash
INSTALL_URL="https://raw.githubusercontent.com/404nffff/agents/v1.0.0/shell/codex/install_codex.sh"
curl -fsSL "${INSTALL_URL}" | bash -s -- mcp
```

### 安装验证

**AI 执行强制要求:** 安装完成后必须执行以下验证命令并反馈结果：

```bash
# 检查目录结构
ls -la ~/.codex
ls -la ~/.codex/skills

# 验证核心文件
test -f ~/.codex/AGENTS.md && echo "✅ AGENTS.md 已安装" || echo "❌ AGENTS.md 缺失"
test -f ~/.codex/config.toml && grep -q "mcp_servers" ~/.codex/config.toml && echo "✅ MCP 配置已写入" || echo "❌ MCP 配置缺失"

# 列出已安装的 Skills
ls ~/.codex/skills/ 2>/dev/null && echo "✅ Skills 已安装" || echo "❌ Skills 目录为空"
```

### 查看帮助

```bash
curl -fsSL "${INSTALL_URL}" | bash -s -- --help
curl -fsSL "${INSTALL_URL}" | bash -s -- mcp --help
curl -fsSL "${INSTALL_URL}" | bash -s -- agents --help
curl -fsSL "${INSTALL_URL}" | bash -s -- skills --help
```

---

## 二、Claude Code 安装

⚠️ **重要:** 本仓库不提供 Claude Code 自动安装脚本，需手动转换配置并使用官方 CLI。

### 资源映射

| 资源类型 | 本仓库来源 | Claude Code 目标位置 |
| --- | --- | --- |
| MCP | `mcp/*.md` | 使用 `claude mcp add` 或写入 `.mcp.json` |
| Agent 规则 | `agents/AGENTS_GLOBAL.md` | `~/.claude/CLAUDE.md` 或 `./CLAUDE.md` |
| Subagents | `agents/*.md` | `.claude/agents/` 或 `~/.claude/agents/` |
| Skills | `skills/<name>/` | `.claude/skills/<name>/` 或 `~/.claude/skills/<name>/` |

### 2.1 安装 MCP

从 `mcp/*.md` 选择需要的 MCP server，转换 TOML 配置为 Claude Code 格式。

**示例：安装 sequential-thinking**

原始 TOML 配置（`mcp/sequential-thinking.md`）：
```toml
[mcp_servers.sequential-thinking]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-sequential-thinking"]
startup_timeout_sec = 120.0
```

**方式一：使用 CLI 添加**

```bash
# 添加到当前项目（默认 --scope local）
claude mcp add --transport stdio sequential-thinking -- npx -y @modelcontextprotocol/server-sequential-thinking

# 添加到项目共享配置（写入 .mcp.json，可提交）
claude mcp add --scope project --transport stdio sequential-thinking -- npx -y @modelcontextprotocol/server-sequential-thinking

# 添加到用户全局配置（所有项目可用）
claude mcp add --scope user --transport stdio sequential-thinking -- npx -y @modelcontextprotocol/server-sequential-thinking

# 验证安装
claude mcp list
claude mcp get sequential-thinking
```

**方式二：使用 JSON 格式添加**

```bash
claude mcp add-json sequential-thinking '{"type":"stdio","command":"npx","args":["-y","@modelcontextprotocol/server-sequential-thinking"]}'
```

**方式三：手动编辑 .mcp.json**

在项目根目录创建或编辑 `.mcp.json`：

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

**含 Token 的 MCP 配置**

⚠️ **安全提示:** 不要把真实 token 提交到 `.mcp.json`，使用环境变量：

```bash
# 使用环境变量
claude mcp add-json context7 '{"type":"stdio","command":"npx","args":["-y","@upstash/context7-mcp"],"env":{"CONTEXT7_API_KEY":"${CONTEXT7_API_KEY}"}}'
```

**Windows 注意事项**

Windows 原生环境下，通过 `npx` 启动的 MCP 需要用 `cmd /c` 包装：

```bash
claude mcp add --transport stdio sequential-thinking -- cmd /c npx -y @modelcontextprotocol/server-sequential-thinking
```

### 2.2 安装 Agent 规则

⚠️ **重要:** Claude Code 使用 `CLAUDE.md`，不是 `AGENTS.md`。

**方式一：项目级引用（推荐）**

如果项目已有 `AGENTS.md`，在 `CLAUDE.md` 中引用：

```bash
cat > CLAUDE.md <<'EOF'
@AGENTS.md

## Claude Code 配置

遵循本项目现有 Agent 规则。
EOF
```

**方式二：用户级全局规则**

将全局规则复制到用户配置：

```bash
mkdir -p ~/.claude
cp agents/AGENTS_GLOBAL.md ~/.claude/CLAUDE.md
```

**方式三：创建 Subagent**

如需自定义 subagent，转换为带 frontmatter 的格式：

```bash
mkdir -p .claude/agents
cat > .claude/agents/codex-engineer.md <<'EOF'
---
name: codex-engineer
description: 使用 Codex 工程规范处理代码、文档、验证和交付任务
tools: Read, Grep, Glob, Bash
model: inherit
---

遵循 agents/AGENTS_GLOBAL.md 中的工程规范，并按当前项目上下文执行任务。
EOF
```

### 2.3 安装 Skills

Claude Code skills 是目录式资源，必须包含 `SKILL.md` 文件。安装时保留完整目录结构。

**用户级安装（所有项目可用）**

```bash
mkdir -p ~/.claude/skills
cp -R skills/git-commit-helper ~/.claude/skills/
```

**项目级安装（仅当前项目，可提交）**

```bash
mkdir -p .claude/skills
cp -R skills/git-commit-helper .claude/skills/
```

**批量安装多个 Skills**

```bash
# 用户级
for skill in git-commit-helper db-query agent-browser; do
  cp -R skills/$skill ~/.claude/skills/ 2>/dev/null || echo "跳过 $skill"
done

# 项目级
mkdir -p .claude/skills
for skill in git-commit-helper db-query; do
  cp -R skills/$skill .claude/skills/ 2>/dev/null || echo "跳过 $skill"
done
```

### 2.4 安装验证

```bash
# 验证 MCP 配置
claude mcp list

# 验证 CLAUDE.md
test -f CLAUDE.md && echo "✅ 项目级 CLAUDE.md 已配置" || echo "⚠️  未找到项目级配置"
test -f ~/.claude/CLAUDE.md && echo "✅ 用户级 CLAUDE.md 已配置" || echo "⚠️  未找到用户级配置"

# 验证 Skills
ls -la .claude/skills/ 2>/dev/null && echo "✅ 项目级 Skills 已安装" || echo "⚠️  未安装项目级 Skills"
ls -la ~/.claude/skills/ 2>/dev/null && echo "✅ 用户级 Skills 已安装" || echo "⚠️  未安装用户级 Skills"

# 检查 Skill 结构
test -f .claude/skills/git-commit-helper/SKILL.md && echo "✅ git-commit-helper 结构正确" || echo "❌ SKILL.md 缺失"
```

### 参考文档

- MCP：https://docs.claude.com/en/docs/claude-code/mcp
- CLAUDE.md：https://docs.claude.com/en/docs/claude-code/memory
- Subagents：https://docs.claude.com/en/docs/claude-code/sub-agents
- Skills：https://docs.claude.com/en/docs/claude-code/skills

---

## 三、OpenClaw 安装

⚠️ **重要:** 本仓库不提供 OpenClaw 自动安装脚本，需手动转换配置并使用官方 CLI。

### 资源映射

| 资源类型 | 本仓库来源 | OpenClaw 目标位置 |
| --- | --- | --- |
| MCP | `mcp/*.md` | 使用 `openclaw mcp set` 写入 MCP registry |
| Agent 规则 | `agents/AGENTS_GLOBAL.md` | workspace 的 `AGENTS.md` |
| Agent 配置 | `agents/*.md` | `~/.openclaw/openclaw.json` |
| Skills | `skills/<name>/` | `<workspace>/skills` 或 `~/.agents/skills` |

### 3.1 安装 MCP

从 `mcp/*.md` 选择需要的 MCP server，转换为 JSON 格式并使用 `openclaw mcp set` 命令。

**示例：安装 sequential-thinking**

原始 TOML 配置（`mcp/sequential-thinking.md`）：
```toml
[mcp_servers.sequential-thinking]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-sequential-thinking"]
```

转换为 OpenClaw 命令：

```bash
openclaw mcp set sequential-thinking '{"command":"npx","args":["-y","@modelcontextprotocol/server-sequential-thinking"]}'

# 验证安装
openclaw mcp list
openclaw mcp show sequential-thinking --json
```

**含环境变量的 MCP**

```bash
openclaw mcp set context7 '{"command":"npx","args":["-y","@upstash/context7-mcp"],"env":{"CONTEXT7_API_KEY":"${CONTEXT7_API_KEY}"}}'
```

⚠️ **安全提示:** 优先使用 OpenClaw secrets 或环境变量，不要把 token 硬编码到配置中。

### 3.2 安装 Agent 规则

OpenClaw workspace 使用 `AGENTS.md` 作为 bootstrap 文件。

**复制全局规则到 workspace**

```bash
cp agents/AGENTS_GLOBAL.md AGENTS.md
```

**配置 Agent（可选）**

在 `~/.openclaw/openclaw.json` 中配置 agent 的 workspace、repoRoot 和 skills allowlist：

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

⚠️ **注意:** `skills` 字段是 allowlist，设置后该 agent 只能使用列表中的 skills。如不限制，不要设置该字段。

### 3.3 安装 Skills

OpenClaw skills 是 AgentSkills-compatible 目录。按作用域选择安装位置。

**优先级说明**（从高到低）：
1. `<workspace>/skills` - workspace 最高优先级
2. `<workspace>/.agents/skills` - workspace project skills
3. `~/.agents/skills` - 用户级所有 agent 可用
4. `~/.openclaw/skills` - OpenClaw 管理的本地 skills

**安装示例**

```bash
# Workspace 最高优先级
mkdir -p skills
cp -R /path/to/agents/skills/git-commit-helper skills/

# Workspace project skills
mkdir -p .agents/skills
cp -R /path/to/agents/skills/git-commit-helper .agents/skills/

# 用户级（所有 agent 可用）
mkdir -p ~/.agents/skills
cp -R /path/to/agents/skills/git-commit-helper ~/.agents/skills/

# OpenClaw 管理的本地 skills
mkdir -p ~/.openclaw/skills
cp -R /path/to/agents/skills/git-commit-helper ~/.openclaw/skills/
```

### 3.4 安装验证

```bash
# 验证 MCP
openclaw mcp list

# 验证 Agents
openclaw agents list

# 验证 AGENTS.md
test -f AGENTS.md && echo "✅ AGENTS.md 已配置" || echo "❌ AGENTS.md 缺失"

# 验证 Skills（检查各优先级目录）
test -f skills/git-commit-helper/SKILL.md && echo "✅ Workspace skills 已安装" || \
test -f .agents/skills/git-commit-helper/SKILL.md && echo "✅ Project skills 已安装" || \
test -f ~/.agents/skills/git-commit-helper/SKILL.md && echo "✅ 用户级 skills 已安装" || \
test -f ~/.openclaw/skills/git-commit-helper/SKILL.md && echo "✅ OpenClaw skills 已安装" || \
echo "❌ 未找到 skills"
```

### 参考文档

- MCP CLI：https://docs.openclaw.ai/cli/mcp
- Agent runtime：https://docs.openclaw.ai/concepts/agent
- Agents CLI：https://docs.openclaw.ai/cli/agents
- Agents config：https://docs.openclaw.ai/gateway/config-agents
- Skills：https://docs.openclaw.ai/skills

---

## 附录

### A. 标准仓库路径

| 项目 | 地址 |
| --- | --- |
| GitHub 仓库 | https://github.com/404nffff/agents |
| Codex 安装脚本 | https://raw.githubusercontent.com/404nffff/agents/master/shell/codex/install_codex.sh |
| MCP 配置来源 | `mcp/*.md` - [查看列表](mcp/README.md) |
| Agents 目录 | `agents/README.md` |
| Skills 目录 | `skills/README.md` |

### B. Codex 安装目标说明

`shell/codex/install_codex.sh` 支持 4 个安装目标：

| 目标 | 说明 | 交互命令 | 自动化命令 |
| --- | --- | --- | --- |
| `all` | 完整安装流程（mcp → agents → skills） | `bash -s -- all` | `bash -s -- all --yes` |
| `mcp` | 安装 MCP servers 到 `~/.codex/config.toml` | `bash -s -- mcp` | `bash -s -- mcp --yes` |
| `agents` | 安装 Agent 规则到 `~/.codex/AGENTS.md` | `bash -s -- agents` | `bash -s -- agents --yes` |
| `skills` | 安装 Skills 到 `~/.codex/skills/` | `bash -s -- skills` | `bash -s -- skills --yes` |

⚠️ **注意:**
- 交互模式会列出可选项，用户选择后输入 `d` 确认安装
- `--yes` 模式跳过所有交互，仅适合 CI/CD 环境
- 部分 MCP 需要 token，交互模式会提示输入
- 只有安装 `db-query` skill 时才会下载二进制文件

### C. db-query 二进制文件

`db-query` skill 的 release 二进制地址：

- Linux: https://github.com/404nffff/agents/releases/download/v0.0.1/db-query-linux-amd64
- Windows: https://github.com/404nffff/agents/releases/download/v0.0.1/db-query-windows-amd64.exe

只有在安装 `db-query` skill 时才会自动下载。

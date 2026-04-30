# agents

本仓库维护 Codex / Claude Code / OpenClaw 等 AI Agent 可复用的安装资源，包括 MCP 配置、全局 Agent 规则和 Skills 扩展包。

## 给 AI Agent 的入口

如果你是 AI Agent、自动化脚本或需要在新环境中安装本仓库资源，请直接读取并执行 [INSTALL.md](./INSTALL.md)。

远程给 AI 读取的安装说明地址：

```text
读取 https://raw.githubusercontent.com/404nffff/agents/master/INSTALL.md
```

`README.md` 只保留最小安装入口和客户端选择说明。完整安装方法、MCP token 输入说明、`db-query` 二进制下载边界都以 [INSTALL.md](./INSTALL.md) 为准。

## Codex 快速安装

当前 `shell/codex/install_codex.sh` 是 Codex 专用安装入口。默认安装必须先列出可安装项，用户选择后才执行安装：

```bash
INSTALL_URL="https://raw.githubusercontent.com/404nffff/agents/master/shell/codex/install_codex.sh"

# 先列出 MCP servers，选择需要安装的项后输入 d 开始安装
curl -fsSL "${INSTALL_URL}" | bash -s -- mcp

# 再列出 Agent 文件，选择一个需要安装的 agent 后输入 d 开始安装
curl -fsSL "${INSTALL_URL}" | bash -s -- agents

# 最后列出 Skills，勾选需要安装的 skill 后输入 d 开始安装
curl -fsSL "${INSTALL_URL}" | bash -s -- skills
```

不要把 `--yes` 作为日常安装方式；`--yes` 会跳过人工选择列表，仅适合已明确接受默认项的自动化环境。需要在安装 MCP 时现场输入 API Token 时，必须使用上面的交互式 `mcp` 安装。

## 按客户端安装方式

| 客户端 | MCP | Agents | Skills | 说明 |
| --- | --- | --- | --- | --- |
| Codex | 使用 `shell/codex/install_codex.sh mcp` 先列出 MCP servers，选择后写入 `~/.codex/config.toml` | 使用 `shell/codex/install_codex.sh agents` 先列出 Agent 文件，选择后写入 `~/.codex/AGENTS.md` 或当前项目 `AGENTS.md` | 使用 `shell/codex/install_codex.sh skills` 先列出 Skills，勾选后写入 `~/.codex/skills/` | 当前唯一支持脚本安装的客户端；默认必须交互选择，不直接自动安装。 |
| Claude Code | 从 `mcp/mcp.md` 复制并转换为 Claude Code MCP 配置，或用 `claude mcp add` / `claude mcp add-json` 导入 | 将通用规则整理到 `CLAUDE.md`，或把选定 agent 转成 `.claude/agents/` / `~/.claude/agents/` 下的 Claude Code subagent 文件 | 将 `skills/<name>/` 复制到 `.claude/skills/<name>/` 或 `~/.claude/skills/<name>/` | 需要按 Claude Code 当前版本的官方目录和命令适配，本仓库不直接写 `~/.claude`。 |
| OpenClaw | 从 `mcp/mcp.md` 复制对应 server 配置，按 OpenClaw MCP 配置格式导入 | 将 `agents/AGENTS_GLOBAL.md` 或目标 agent 文件导入 OpenClaw 的全局/项目规则或 agent 配置 | 将 `skills/<name>/` 作为 Agent Skills 目录导入；若当前 OpenClaw 版本不支持目录式 skill，则导入 `SKILL.md` 并保持附件可访问 | 需要按 OpenClaw 当前版本的配置入口适配，本仓库不提供 OpenClaw 专用写入脚本。 |

## 仓库内容

| 路径 | 说明 |
| --- | --- |
| `INSTALL.md` | 标准安装说明，面向 AI Agent 和自动化执行脚本。 |
| `shell/codex/install_codex.sh` | Codex 交互安装入口，支持 `mcp`、`agents`、`skills`、`all`；默认先列出选项再安装。 |
| `mcp/mcp.md` | MCP server 配置清单；Codex 安装时写入 `~/.codex/config.toml`，其他客户端需按各自格式转换导入。 |
| `agents/README.md` | 可安装 Agent 规则文件目录索引。 |
| `agents/` | Agent 规则文件集合。 |
| `skills/README.md` | 可安装 Skill 目录索引。 |
| `skills/` | Skill 扩展包集合。 |

## 维护原则

- 安装说明统一维护在 `INSTALL.md`，`README.md` 只保留最小安装入口和客户端选择说明。
- 新增、删除或移动 Agent 文件后，同步更新 `agents/README.md`。
- 新增、删除或移动 Skill 目录后，同步更新 `skills/README.md`。
- 修改 MCP 配置清单后，同步检查 `shell/codex/install_codex.sh mcp` 的解析行为。
- `db-query` skill 的 release 二进制下载说明以 `INSTALL.md` 和 `shell/codex/install_codex.sh` 当前实现为准。

## 标准仓库位置

- GitHub: `https://github.com/404nffff/agents`
- 安装说明: [INSTALL.md](./INSTALL.md)

# INSTALL.md - MCP / Agents / Skills 安装指南

> **目标读者:** AI Agent & 自动化执行脚本
> **标准仓库位置:** `https://github.com/404nffff/agents`
> **标准脚本位置:** `https://raw.githubusercontent.com/404nffff/agents/master/shell/codex/install_codex.sh`
> **核心准则:** 本文档可以部署到任意位置，但安装来源必须始终指向标准仓库。Codex 使用 `shell/codex/install_codex.sh` 自动安装；Claude Code、OpenClaw 复用本仓库资源并按各自客户端格式导入，不要把 Codex 脚本当作跨客户端安装器。

## 快速开始

Codex 默认安装方式是直接从 Raw GitHub 拉取标准安装脚本执行，不要求当前机器已有本仓库源码。

需要安装 MCP 时，推荐先交互安装 `mcp`，按提示选择 MCP server。部分 MCP server 需要 API Token 或 Bearer Token，安装脚本会在写入 `~/.codex/config.toml` 前提示用户输入，输入完成后再继续安装：

```bash
INSTALL_URL="https://raw.githubusercontent.com/404nffff/agents/master/shell/codex/install_codex.sh"

# 先安装 MCP：如选中的 MCP 需要 token，按提示输入后继续
curl -fsSL "${INSTALL_URL}" | bash -s -- mcp

# 再安装全局 Agents 与 Skills
curl -fsSL "${INSTALL_URL}" | bash -s -- agents --yes
curl -fsSL "${INSTALL_URL}" | bash -s -- skills --yes
```

如果所有 MCP Token 已通过环境变量预先配置，或确认本次不需要填写 token，才使用全量无交互安装：

```bash
curl -fsSL "${INSTALL_URL}" | bash -s -- all --yes
```

`--yes` 模式不会停下来要求输入 token；遇到空 token 或占位 token 时会保留原占位并输出提示。

---

## 按客户端安装

### Codex

`shell/codex/install_codex.sh` 当前只自动写入 Codex 目录和配置：

| 资源 | 安装目标 | 安装命令 |
| --- | --- | --- |
| MCP | `~/.codex/config.toml` 的 `mcp_servers` 区域 | `curl -fsSL "${INSTALL_URL}" | bash -s -- mcp` |
| Agents | `~/.codex/AGENTS.md` 或当前项目 `AGENTS.md` | `curl -fsSL "${INSTALL_URL}" | bash -s -- agents --yes` |
| Skills | `~/.codex/skills/` | `curl -fsSL "${INSTALL_URL}" | bash -s -- skills --yes` |

推荐执行顺序：

```bash
INSTALL_URL="https://raw.githubusercontent.com/404nffff/agents/master/shell/codex/install_codex.sh"

# 先安装 MCP：如选中的 MCP 需要 token，按提示输入后继续
curl -fsSL "${INSTALL_URL}" | bash -s -- mcp

# 再安装全局 Agents 与 Skills
curl -fsSL "${INSTALL_URL}" | bash -s -- agents --yes
curl -fsSL "${INSTALL_URL}" | bash -s -- skills --yes
```

仅当所有 MCP Token 已通过环境变量配置、或确认无需 token 时，才使用全量无交互安装：

```bash
curl -fsSL "${INSTALL_URL}" | bash -s -- all --yes
```

### Claude Code

本仓库不直接写入 `~/.claude`。Claude Code 需要按当前版本官方命令和目录导入，建议按资源类型处理：

| 资源 | 本仓库来源 | Claude Code 安装方式 |
| --- | --- | --- |
| MCP | `mcp/mcp.md` | 读取目标 `mcp_servers.<name>` 的 TOML 块，转换为 Claude Code 的 MCP 配置；优先使用 `claude mcp add` 或 `claude mcp add-json` 导入，也可按项目需要写入 `.mcp.json`。 |
| Agents | `agents/AGENTS_GLOBAL.md`、`agents/*.md` | 通用规则放入项目 `CLAUDE.md`；需要自定义 subagent 时，把选定 agent 文件整理为 Claude Code subagent 格式，放入 `.claude/agents/` 或 `~/.claude/agents/`。 |
| Skills | `skills/<name>/` | 保留 `SKILL.md`、`references/`、`scripts/`、`assets/` 等目录结构，复制到 `.claude/skills/<name>/` 或 `~/.claude/skills/<name>/`。 |

MCP 转换示例：

```toml
# mcp/mcp.md 中的 Codex TOML 来源
[mcp_servers.sequential-thinking]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-sequential-thinking"]
startup_timeout_sec = 120.0
```

可用 Claude Code CLI 导入为：

```bash
claude mcp add --transport stdio sequential-thinking -- npx -y @modelcontextprotocol/server-sequential-thinking
claude mcp list
```

如果使用 JSON 配置，字段通常需要从 `mcp_servers` 转为 `mcpServers`，并保留 `command`、`args`、`env` 等语义。含 token 的 MCP server 必须在导入前补齐真实 token，或按 Claude Code 支持的环境变量方式注入。

### OpenClaw

本仓库不提供 OpenClaw 专用写入脚本。OpenClaw 需要按当前版本的配置入口导入：

| 资源 | 本仓库来源 | OpenClaw 安装方式 |
| --- | --- | --- |
| MCP | `mcp/mcp.md` | 从目标 `mcp_servers.<name>` TOML 块复制 `command`、`args`、`env`、`type` 等字段，按 OpenClaw MCP 配置格式导入；如 OpenClaw 使用 JSON，则把 `mcp_servers` 语义转换为对应的 `mcpServers` 或等价结构。 |
| Agents | `agents/AGENTS_GLOBAL.md`、`agents/*.md` | 将 `AGENTS_GLOBAL.md` 作为全局规则导入；将具体 agent 文件按 OpenClaw 的 agent / project instruction 格式导入。 |
| Skills | `skills/<name>/` | 如果 OpenClaw 支持目录式 Agent Skills，复制完整目录；如果只支持提示词或工具说明导入，则导入 `SKILL.md` 正文，并确保同目录的脚本、参考文档和资源文件可被运行环境访问。 |

OpenClaw 导入后至少验证三项：MCP server 列表可见且能启动，项目/全局规则已加载，目标 skill 能被检索或触发。

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

### 1. `all` (推荐)
按顺序完整执行安装流程：`mcp` -> `agents` -> `skills`。
- **命令:** `curl -fsSL "${INSTALL_URL}" | bash -s -- all --yes`
- *注意: `all` 模式必须配合 `--yes` 参数使用，因此不会交互输入 MCP token。若需要用户现场输入 token，请先单独执行 `mcp` 安装。*

### 2. `mcp`
将 `mcp/mcp.md` 中的 `mcp_servers` 配置写入到目标机器的 `~/.codex/config.toml`。
- **交互命令:** `curl -fsSL "${INSTALL_URL}" | bash -s -- mcp`
- **无交互命令:** `curl -fsSL "${INSTALL_URL}" | bash -s -- mcp --yes`
- *注意: 此操作仅更新 `mcp_servers` 节点，不会破坏或修改用户的其他配置。部分 MCP server 需要配置 token；交互模式会提示用户输入，`--yes` 模式不会输入 token，会保留占位。*

### 3. `agents`
将全局代理规则文件安装至 `~/.codex/AGENTS.md`。
- **命令:** `curl -fsSL "${INSTALL_URL}" | bash -s -- agents --yes`
- *行为: 远程执行时读取标准仓库的 `agents/README.md`。*

### 4. `skills`
将 `skills/` 下的所有可用技能安装至 `~/.codex/skills/`。
- **命令:** `curl -fsSL "${INSTALL_URL}" | bash -s -- skills --yes`
- *行为: 如遇同名 skill，覆盖时会保留原有的配置文件。只有安装或同步 `db-query` skill 时，才会下载 db-query release 二进制；安装 MCP、Agents 或其他 Skills 不会下载下方二进制文件。*

`db-query` skill 涉及的 release 二进制地址：

- `https://github.com/404nffff/agents/releases/download/v0.0.1/db-query-linux-amd64`
- `https://github.com/404nffff/agents/releases/download/v0.0.1/db-query-windows-amd64.exe`

---

## Codex 默认远程安装方式

```bash
INSTALL_URL="https://raw.githubusercontent.com/404nffff/agents/master/shell/codex/install_codex.sh"

# 推荐流程：先交互安装 MCP，按提示填写需要的 token
curl -fsSL "${INSTALL_URL}" | bash -s -- mcp

# 再安装 Agents 与 Skills
curl -fsSL "${INSTALL_URL}" | bash -s -- agents --yes
curl -fsSL "${INSTALL_URL}" | bash -s -- skills --yes

# 仅在 token 已通过环境变量配置、或确认无需 token 时使用全量无交互安装
curl -fsSL "${INSTALL_URL}" | bash -s -- all --yes
```

远程执行 `mcp` 安装时，如果选中的 MCP 配置包含 `API_KEY`、`TOKEN`、`Authorization Bearer token` 或空 `--api-key` 等占位，脚本会提示输入。可直接输入 token；也可以留空保留占位，后续再手动补齐 `~/.codex/config.toml`。

只有安装流程实际选中 `db-query` skill 时，脚本才会访问 GitHub Release 下载 `db-query-linux-amd64` 或 `db-query-windows-amd64.exe`。其他安装目标不会触发这两个二进制下载。

指定版本安装时，将 `master` 替换为固定 tag：

```bash
curl -fsSL "https://raw.githubusercontent.com/404nffff/agents/v1.0.0/shell/codex/install_codex.sh" | bash -s -- all --yes
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

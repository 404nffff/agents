# INSTALL.md - Codex Agents & Skills 安装指南

> **目标读者:** AI Agent & 自动化执行脚本
> **标准仓库位置:** `https://github.com/404nffff/agents`
> **标准脚本位置:** `https://raw.githubusercontent.com/404nffff/agents/master/codex/install.sh`
> **核心准则:** 本文档可以部署到任意位置，但安装来源必须始终指向标准仓库。不要手动拷贝 `AGENTS.md`、`skills` 或 `mcp` 配置文件，必须通过统一安装脚本安装。

## 快速开始

默认安装方式是直接从 Raw GitHub 拉取标准安装脚本执行，不要求当前机器已有本仓库源码。

需要安装 MCP 时，推荐先交互安装 `mcp`，按提示选择 MCP server。部分 MCP server 需要 API Token 或 Bearer Token，安装脚本会在写入 `~/.codex/config.toml` 前提示用户输入，输入完成后再继续安装：

```bash
INSTALL_URL="https://raw.githubusercontent.com/404nffff/agents/master/codex/install.sh"

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

## 标准仓库与路径

| 项目 | 标准位置 |
| --- | --- |
| GitHub 仓库 | `https://github.com/404nffff/agents` |
| Raw GitHub 安装脚本 | `https://raw.githubusercontent.com/404nffff/agents/master/codex/install.sh` |
| MCP 配置来源 | `codex/mcp.md` |
| Agents 目录索引 | `codex/agents/README.md` |
| Skills 目录索引 | `codex/skills/README.md` |

---

## 安装目标说明

`codex/install.sh` 支持 4 个安装目标：

### 1. `all` (推荐)
按顺序完整执行安装流程：`mcp` -> `agents` -> `skills`。
- **命令:** `curl -fsSL "${INSTALL_URL}" | bash -s -- all --yes`
- *注意: `all` 模式必须配合 `--yes` 参数使用，因此不会交互输入 MCP token。若需要用户现场输入 token，请先单独执行 `mcp` 安装。*

### 2. `mcp`
将 `codex/mcp.md` 中的 `mcp_servers` 配置写入到目标机器的 `~/.codex/config.toml`。
- **交互命令:** `curl -fsSL "${INSTALL_URL}" | bash -s -- mcp`
- **无交互命令:** `curl -fsSL "${INSTALL_URL}" | bash -s -- mcp --yes`
- *注意: 此操作仅更新 `mcp_servers` 节点，不会破坏或修改用户的其他配置。部分 MCP server 需要配置 token；交互模式会提示用户输入，`--yes` 模式不会输入 token，会保留占位。*

### 3. `agents`
将全局代理规则文件安装至 `~/.codex/AGENTS.md`。
- **命令:** `curl -fsSL "${INSTALL_URL}" | bash -s -- agents --yes`
- *行为: 远程执行时读取标准仓库的 `codex/agents/README.md`。*

### 4. `skills`
将 `codex/skills/` 下的所有可用技能安装至 `~/.codex/skills/`。
- **命令:** `curl -fsSL "${INSTALL_URL}" | bash -s -- skills --yes`
- *行为: 如遇同名 skill，覆盖时会保留原有的配置文件。只有安装或同步 `db-query` skill 时，才会下载 db-query release 二进制；安装 MCP、Agents 或其他 Skills 不会下载下方二进制文件。*

`db-query` skill 涉及的 release 二进制地址：

- `https://github.com/404nffff/agents/releases/download/v0.0.1/db-query-linux-amd64`
- `https://github.com/404nffff/agents/releases/download/v0.0.1/db-query-windows-amd64.exe`

---

## 默认远程安装方式

```bash
INSTALL_URL="https://raw.githubusercontent.com/404nffff/agents/master/codex/install.sh"

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
curl -fsSL "https://raw.githubusercontent.com/404nffff/agents/v1.0.0/codex/install.sh" | bash -s -- all --yes
```

---

## 安装后验证步骤

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
- `codex/install.sh`：所有安装逻辑的统一入口。
- `codex/mcp.md`：MCP (Model Context Protocol) 原始配置来源。
- `codex/agents/README.md`：可安装的 Agent 规则文件目录索引。
- `codex/skills/README.md`：可安装的 Skill 扩展包目录索引。

---

## 获取帮助

要查看任何命令或目标的详细帮助信息，请执行：

```bash
INSTALL_URL="https://raw.githubusercontent.com/404nffff/agents/master/codex/install.sh"

curl -fsSL "${INSTALL_URL}" | bash -s -- --help
curl -fsSL "${INSTALL_URL}" | bash -s -- mcp --help
curl -fsSL "${INSTALL_URL}" | bash -s -- agents --help
curl -fsSL "${INSTALL_URL}" | bash -s -- skills --help
curl -fsSL "${INSTALL_URL}" | bash -s -- all --help
```

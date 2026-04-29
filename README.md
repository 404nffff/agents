# agents

本仓库维护 Codex / AI Agent 可复用的安装资源，包括 MCP 配置、全局 Agent 规则和 Skills 扩展包。

## 给 AI Agent 的入口

如果你是 AI Agent、自动化脚本或需要在新环境中安装本仓库资源，请直接读取并执行 [INSTALL.md](./INSTALL.md)。

远程给 AI 读取的安装说明地址：

```text
读取 https://raw.githubusercontent.com/404nffff/agents/master/INSTALL.md
```

`README.md` 只保留最小 `curl` 安装入口。完整安装方法、MCP token 输入说明、`db-query` 二进制下载边界都以 [INSTALL.md](./INSTALL.md) 为准。

## 快速安装

默认从 Raw GitHub 拉取标准安装脚本：

```bash
INSTALL_URL="https://raw.githubusercontent.com/404nffff/agents/master/codex/install.sh"
curl -fsSL "${INSTALL_URL}" | bash -s -- all --yes
```

如果需要在安装 MCP 时现场输入 API Token，请按 [INSTALL.md](./INSTALL.md) 的交互流程先执行 `mcp` 安装。

## 仓库内容

| 路径 | 说明 |
| --- | --- |
| `INSTALL.md` | 标准安装说明，面向 AI Agent 和自动化执行脚本。 |
| `codex/install.sh` | 统一安装入口，支持 `mcp`、`agents`、`skills`、`all`。 |
| `codex/mcp.md` | MCP server 配置清单，安装后写入 `~/.codex/config.toml`。 |
| `codex/agents/README.md` | 可安装 Agent 规则文件目录索引。 |
| `codex/agents/` | Agent 规则文件集合。 |
| `codex/skills/README.md` | 可安装 Skill 目录索引。 |
| `codex/skills/` | Skill 扩展包集合。 |

## 维护原则

- 安装说明统一维护在 `INSTALL.md`，`README.md` 只保留最小 `curl` 入口。
- 新增、删除或移动 Agent 文件后，同步更新 `codex/agents/README.md`。
- 新增、删除或移动 Skill 目录后，同步更新 `codex/skills/README.md`。
- 修改 MCP 配置清单后，同步检查 `codex/install.sh mcp` 的解析行为。
- `db-query` skill 的 release 二进制下载说明以 `INSTALL.md` 和 `codex/install.sh` 当前实现为准。

## 标准仓库位置

- GitHub: `https://github.com/404nffff/agents`
- 安装说明: [INSTALL.md](./INSTALL.md)

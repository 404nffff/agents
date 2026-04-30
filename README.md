# Agents - AI Agent 资源仓库

为 Codex、Claude Code、OpenClaw 等 AI Agent 提供可复用的 MCP 配置、Agent 规则和 Skills 扩展包。

## 快速开始

**AI Agent 请直接阅读:** [INSTALL.md](./INSTALL.md) 或 https://raw.githubusercontent.com/404nffff/agents/master/INSTALL.md

**人类用户请选择客户端:**

| 客户端 | 安装方式 | 跳转 |
| --- | --- | --- |
| **Codex** | 一键交互式安装脚本 | [👉 Codex 安装](#codex-安装) |
| **Claude Code** | 手动转换配置 | [📖 查看 INSTALL.md](./INSTALL.md#二claude-code-安装) |
| **OpenClaw** | 手动转换配置 | [📖 查看 INSTALL.md](./INSTALL.md#三openclaw-安装) |

---

## Codex 安装

### 一键安装（推荐）

```bash
INSTALL_URL="https://raw.githubusercontent.com/404nffff/agents/master/shell/codex/install_codex.sh"

# 1. 安装 MCP servers（会列出可选项，选择后输入 d 确认）
curl -fsSL "${INSTALL_URL}" | bash -s -- mcp

# 2. 安装 Agent 规则（会列出可选项，选择后输入 d 确认）
curl -fsSL "${INSTALL_URL}" | bash -s -- agents

# 3. 安装 Skills（会列出可选项，选择后输入 d 确认）
curl -fsSL "${INSTALL_URL}" | bash -s -- skills
```

### 安装说明

- **交互式安装:** 脚本会先列出可安装项，用户选择后输入 `d` 确认
- **Token 输入:** 部分 MCP 需要 API Token，安装时会提示输入
- **自动化模式:** 添加 `--yes` 参数可跳过交互（仅限 CI/CD 环境）

完整文档请查看 [INSTALL.md](./INSTALL.md#一codex-安装)

---

## 仓库结构

```
agents/
├── INSTALL.md                    # 完整安装文档（AI Agent 必读）
├── README.md                     # 本文件（快速入口）
├── shell/codex/
│   └── install_codex.sh         # Codex 交互式安装脚本
├── mcp/
│   └── *.md                     # 每个 MCP server 一个配置文件
├── agents/
│   ├── README.md                # Agent 规则文件索引
│   ├── AGENTS_GLOBAL.md         # 全局 Agent 规则
│   └── *.md                     # 其他 Agent 规则文件
└── skills/
    ├── README.md                # Skills 目录索引
    ├── git-commit-helper/       # Git 提交助手
    ├── db-query/                # 数据库查询工具
    └── ...                      # 其他 Skills
```

---

## 资源说明

### MCP Servers
位于 `mcp/*.md`，每个文件对应一个 MCP server 配置：
- **文档查询:** context7
- **网络搜索:** exa、duckduckgo-search、fetch
- **顺序思考:** sequential-thinking
- **GitHub 分析:** deepwiki、codebase-retrieval
- **记忆服务:** memory、nocturne_memory、ai-localbase
- 更多...

查看完整列表：[mcp/README.md](./mcp/README.md)

### Agent 规则
位于 `agents/` 目录：
- `AGENTS_GLOBAL.md` - 全局通用规则
- 其他专用 Agent 配置文件

查看完整列表：[agents/README.md](./agents/README.md)

### Skills 扩展
位于 `skills/` 目录：
- `git-commit-helper` - Git 提交助手
- `db-query` - 数据库查询工具（MySQL、PostgreSQL、Redis、Memcached）
- `agent-browser` - 浏览器自动化
- 更多...

查看完整列表：[skills/README.md](./skills/README.md)

### 添加新资源时
- **MCP:** 在 `mcp/` 新增单服务 Markdown 文件，检查 `install_codex.sh` 解析逻辑
- **Agent:** 添加文件到 `agents/`，同步更新 `agents/README.md`
- **Skill:** 添加目录到 `skills/`，同步更新 `skills/README.md`

### 文档维护
- 安装说明统一维护在 `INSTALL.md`
- `README.md` 仅保留快速入口和概览

---

## 相关链接

- **GitHub 仓库:** https://github.com/404nffff/agents
- **完整安装文档:** [INSTALL.md](./INSTALL.md)
- **MCP 配置目录:** [mcp/](./mcp/)
- **Agent 规则索引:** [agents/README.md](./agents/README.md)
- **Skills 索引:** [skills/README.md](./skills/README.md)

---

## 许可证

本项目采用 MIT 许可证。详见 LICENSE 文件。

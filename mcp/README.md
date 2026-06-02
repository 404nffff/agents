# MCP Servers 配置目录

本目录包含各个 MCP server 的独立配置文件，每个文件对应一个 MCP server。

## 工具安装
node -v
npm -v
npx -v
uv --version
uvx --version
mcp-proxy --version
git --version
python3 --version



## uv安装
curl -LsSf https://astral.sh/uv/install.sh | sh


## 安装mcp-proxy

# 1. 安装工具
uv tool install git+https://github.com/sparfenyuk/mcp-proxy

# 2. 配置 PATH (只需执行一次)
uv tool update-shell

# 3. 应用配置
source ~/.bashrc  # 或 ~/.zshrc，根据提示
# 或直接重启终端

# 4. 验证
mcp-proxy --help

## 目录结构

```
mcp/
├── README.md                    # 本文件
├── context7.md                  # Context7 文档查询
├── exa.md                       # Exa 网络搜索
├── fetch.md                     # HTTP 请求工具
├── sequential-thinking.md       # 顺序思考工具
├── memory.md                    # 记忆服务
├── ai-localbase.md             # AI LocalBase 数据库
├── deepwiki.md                  # DeepWiki GitHub 分析
├── codebase-retrieval.md       # 代码库检索
├── duckduckgo-search.md        # DuckDuckGo 搜索
├── code-index.md               # 代码索引
├── fast-context.md             # 快速上下文
├── lanhu.md                     # 蓝湖设计协作
├── microsoft-docs-mcp.md       # Microsoft 文档
├── nocturne_memory.md          # Nocturne 记忆服务
└── shrimp-task-manager.md      # Shrimp 任务管理
```

## 配置格式

每个 `.md` 文件包含该 MCP server 的 TOML 配置，格式如下：

```toml
[mcp_servers.server-name]
command = "npx"
args = ["-y", "@package/name"]
```

需要 token 的 MCP 配置示例：

```toml
[mcp_servers.server-name]
command = "npx"
args = ["-y", "@package/name"]
env = { API_KEY = "YOUR_API_KEY_HERE" }
```

## 使用方式

### Codex 用户

使用交互式安装脚本自动安装：

```bash
curl -fsSL "https://raw.githubusercontent.com/404nffff/agents/master/shell/codex/install_codex.sh" | bash -s -- mcp
```

### Claude Code 用户

手动转换配置并使用 CLI 添加，详见 [INSTALL.md](../INSTALL.md#二claude-code-安装)

### OpenClaw 用户

手动转换配置并使用 CLI 添加，详见 [INSTALL.md](../INSTALL.md#三openclaw-安装)

## 添加新 MCP

1. 在本目录创建新的 `.md` 文件
2. 按上述格式编写 TOML 配置
3. 更新本 README.md 的目录结构列表
4. 确保 `shell/codex/install_mcp.sh` 能正确解析新文件

## 相关文档

- [完整安装指南](../INSTALL.md)
- [仓库主页](../README.md)
- [Agent 规则](../agents/README.md)
- [Skills 扩展](../skills/README.md)

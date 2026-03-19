# MCP 清单说明
`install_mcp.sh` 会解析本文件中的每个 `mcp_servers.*` 条目，并把对应 TOML 配置写入 `~/.codex/config.toml` 的 `mcp_servers` 区域。

## 基础安装
### uv 安装
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

### 安装 mcp-proxy
```bash
# 1. 安装工具
uv tool install git+https://github.com/sparfenyuk/mcp-proxy

# 2. 配置 PATH (只需执行一次)
uv tool update-shell

# 3. 应用配置
source ~/.bashrc  # 或 ~/.zshrc，根据提示
# 或直接重启终端

# 4. 验证
mcp-proxy --help
```

## 配置文件位置
```toml
~/.codex/config.toml
```

推荐先检查本机工具：
- Node 生态：`node -v`、`npm -v`、`npx -v`
- UV 生态：`uv --version`、`uvx --version`
- 代理工具：`mcp-proxy --version`

---

# mcp_servers.sequential-thinking 顺序思考
## 说明
顺序思考与分步推理工具，适合复杂任务拆解。
依赖 Node / npm / npx 运行环境。
## 安装命令
```toml
[mcp_servers.sequential-thinking]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-sequential-thinking"]
startup_timeout_sec = 120.0
```

# mcp_servers.context7 Context7 文档检索
## 说明
Context7 文档检索工具。
需要在 args 中设置有效 `--api-key`，可从 Context7 Dashboard 获取。
依赖 Node / npm / npx 运行环境。
## 安装命令
```toml
[mcp_servers.context7]
command = "npx"
args = ["-y", "@upstash/context7-mcp", "--api-key", ""]
startup_timeout_sec = 120.0
```

# mcp_servers.memory 本地记忆服务
## 说明
本地知识图谱记忆 MCP 服务。
依赖 Node / npm / npx 运行环境。
## 安装命令
```toml
[mcp_servers.memory]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-memory"]
startup_timeout_sec = 120.0
```

# mcp_servers.shrimp-task-manager Shrimp 任务管理
## 说明
Shrimp 任务规划与拆解工具，包含默认环境变量配置。
依赖 Node / npm / npx 运行环境。
## 安装命令
```toml
[mcp_servers.shrimp-task-manager]
command = "npx"
args = ["-y", "mcp-shrimp-task-manager"]
startup_timeout_sec = 120.0

[mcp_servers.shrimp-task-manager.env]
DATA_DIR = ".shrimp"
ENABLE_GUI = "false"
TEMPLATES_USE = "zh"
```

# mcp_servers.deepwiki DeepWiki 仓库问答
## 说明
通过 `mcp-proxy` 连接 DeepWiki 的 `streamablehttp` 服务。
使用前需安装 `mcp-proxy`：
`uv tool install git+https://github.com/sparfenyuk/mcp-proxy`
## 安装命令
```toml
[mcp_servers.deepwiki]
type = "stdio"
command = "mcp-proxy"
args = ["--transport", "streamablehttp", "https://mcp.deepwiki.com/mcp"]
startup_timeout_sec = 120.0
```

# mcp_servers.microsoft-docs-mcp Microsoft 文档检索
## 说明
通过 `mcp-proxy` 连接 Microsoft Learn 官方 MCP 服务。
使用前需安装 `mcp-proxy`：
`uv tool install git+https://github.com/sparfenyuk/mcp-proxy`
## 安装命令
```toml
[mcp_servers.microsoft-docs-mcp]
type = "stdio"
command = "mcp-proxy"
args = ["--transport", "streamablehttp", "https://learn.microsoft.com/api/mcp"]
startup_timeout_sec = 120.0
```

# mcp_servers.duckduckgo-search DuckDuckGo 搜索
## 说明
DuckDuckGo 搜索 MCP 服务。
依赖 `uvx` 运行环境。
## 安装命令
```toml
[mcp_servers.duckduckgo-search]
type = "stdio"
command = "uvx"
args = ["duckduckgo-mcp-server"]
startup_timeout_sec = 120.0
```

# mcp_servers.fetch 网页抓取
## 说明
通用网页抓取 MCP 服务。
依赖 `uvx` 运行环境。
## 安装命令
```toml
[mcp_servers.fetch]
type = "stdio"
command = "uvx"
args = ["mcp-server-fetch"]
startup_timeout_sec = 120.0
```

# mcp_servers.exa Exa 搜索
## 说明
Exa MCP 服务，提供实时网页搜索、代码上下文与公司研究能力。
需要配置 `EXA_API_KEY`（可用 `export EXA_API_KEY=...` 或 `.env` 方式）。
常用工具：`web_search_exa`、`get_code_context_exa`、`company_research_exa`、`crawling_exa`。
依赖 Node / npm / npx 运行环境。
## 安装命令
```toml
[mcp_servers.exa]
command = "npx"
args = ["-y", "exa-mcp-server"]
startup_timeout_sec = 120.0

[mcp_servers.exa.env]
EXA_API_KEY = ""
```

# mcp_servers.lanhu 蓝湖代理
## 说明
蓝湖 MCP 代理示例，默认连接本地 `http://localhost:8000`。
依赖 `mcp-proxy`，需先完成安装并确保可执行。
仓库地址 https://github.com/dsphper/lanhu-mcp
## 安装命令
```toml
[mcp_servers.lanhu]
command = "mcp-proxy"
args = ["--transport", "streamablehttp", "http://localhost:8000/mcp?role=开发&name=w"]
startup_timeout_sec = 120.0
```

# mcp_servers.fast-context Fast Context 语义检索
## 说明
Fast Context 语义检索 MCP 服务。
需要配置 `WINDSURF_API_KEY`。
依赖 Node / npm / npx 运行环境。
仓库地址 https://github.com/SammySnake-d/fast-context-mcp
## 安装命令
```toml
[mcp_servers.fast-context]
command = "npx"
args = ["-y", "--prefer-online", "@sammysnake/fast-context-mcp"]
startup_timeout_sec = 120.0

[mcp_servers.fast-context.env]
WINDSURF_API_KEY = ""
```

# mcp_servers.code-index Code Index 代码索引
## 说明
Code Index 代码索引检索 MCP 服务。
依赖 `uvx` 运行环境。
## 安装命令
```toml
[mcp_servers.code-index]
type = "stdio"
command = "uvx"
args = ["code-index-mcp"]
```


# mcp_servers.codebase-retrieval ace mcp代码检索
## 说明
地址 https://app.augmentcode.com/mcp/configuration

1. Install Auggie CLI
npm install -g @augmentcode/auggie@latest
2. Sign in to Augment
auggie login
This will open a browser window for authentication.
3. Configure the MCP server in Codex
Add the MCP server using the Codex CLI:
codex mcp add codebase-retrieval -- auggie --mcp --mcp-auto-workspace
The --mcp-auto-workspace flag automatically detects your workspace when using Codex.
4. Test the integration
Run Codex and prompt it with:
"What is this project? Please use the codebase-retrieval tool to get the answer."
Codex should confirm it has access to the codebase-retrieval tool.
## 安装命令
```toml
[mcp_servers.codebase-retrieval]
command = "auggie"
args = ["--mcp", "--mcp-auto-workspace"]
startup_timeout_sec = 60
```
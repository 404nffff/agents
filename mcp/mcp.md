# mcp_servers.ai-localbase 记忆库

## 说明

地址: https://github.com/404nffff/ai-localbase local 分支

## 安装命令

```toml
[mcp_servers.ai-localbase]
url = "http://127.0.0.1:8080/mcp"
startup_timeout_sec = 120.0
http_headers = { "Authorization" = "Bearer your-app-access-token" }
```

# mcp_servers.code-index 代码索引

## 说明

本地代码索引 MCP 服务，提供文件索引、符号检索和代码搜索能力。

## 安装命令

```toml
[mcp_servers.code-index]
type = "stdio"
command = "uvx"
args = ["code-index-mcp"]
startup_timeout_sec = 120.0
```

# mcp_servers.codebase-retrieval ace mcp代码检索

## 说明

地址:
https://app.augmentcode.com/mcp/configuration

https://docs.augmentcode.com/context-services/mcp/quickstart-codex

1. Install Auggie CLI
   npm install -g @augmentcode/auggie@latest
2. Sign in to Augment
   auggie login
3. Configure the MCP server in Codex
   codex mcp add codebase-retrieval -- auggie --mcp --mcp-auto-workspace
4. Test the integration
   Run Codex and ask it to use the codebase-retrieval tool.

For non-interactive environments like CI/CD pipelines, GitHub Actions, or automated scripts where you cannot run `auggie login` interactively, configure authentication using environment variables.

## 安装命令

```toml
[mcp_servers.codebase-retrieval]
command = "auggie"
args = ["--mcp", "--mcp-auto-workspace"]
startup_timeout_sec = 120

[mcp_servers.codebase-retrieval.env]
AUGMENT_API_TOKEN = "xxxxx"
AUGMENT_API_URL = "https://i1.api.augmentcode.com/"
```

# mcp_servers.context7 Context7 文档检索

## 说明

Context7 文档检索工具，需要 API Key。

依赖: Node / npm / npx

获取 API Key: Context7 Dashboard

## 安装命令

```toml
[mcp_servers.context7]
command = "npx"
args = ["-y", "@upstash/context7-mcp", "--api-key", ""]
startup_timeout_sec = 120.0
```

# mcp_servers.deepwiki DeepWiki 仓库问答

## 说明

通过 mcp-proxy 连接 DeepWiki 的 streamablehttp 服务。

依赖: mcp-proxy

## 安装命令

```toml
[mcp_servers.deepwiki]
type = "stdio"
command = "mcp-proxy"
args = ["--transport", "streamablehttp", "https://mcp.deepwiki.com/mcp"]
startup_timeout_sec = 120.0
```

# mcp_servers.duckduckgo-search DuckDuckGo 搜索

## 说明

DuckDuckGo 搜索 MCP 服务。

依赖: uvx

## 安装命令

```toml
[mcp_servers.duckduckgo-search]
type = "stdio"
command = "uvx"
args = ["duckduckgo-mcp-server"]
startup_timeout_sec = 120.0
```

# mcp_servers.exa Exa 搜索

## 说明

实时网页搜索、代码上下文与公司研究能力。

依赖: Node / npm / npx

环境变量: `EXA_API_KEY`（必需）

## 安装命令

```toml
[mcp_servers.exa]
command = "npx"
args = ["-y", "exa-mcp-server"]
startup_timeout_sec = 120.0

[mcp_servers.exa.env]
EXA_API_KEY = ""
```

# mcp_servers.fast-context Fast Context 语义检索

## 说明

Fast Context 语义检索 MCP 服务。

依赖: Node / npm / npx

环境变量: `WINDSURF_API_KEY`（必需）

仓库: https://github.com/SammySnake-d/fast-context-mcp

## 安装命令

```toml
[mcp_servers.fast-context]
command = "npx"
args = ["-y", "--prefer-online", "@sammysnake/fast-context-mcp"]
startup_timeout_sec = 120.0

[mcp_servers.fast-context.env]
WINDSURF_API_KEY = ""
```

# mcp_servers.fetch 网页抓取

## 说明

通用网页抓取 MCP 服务。

依赖: uvx

## 安装命令

```toml
[mcp_servers.fetch]
type = "stdio"
command = "uvx"
args = ["mcp-server-fetch"]
startup_timeout_sec = 120.0
```

# mcp_servers.lanhu 蓝湖代理

## 说明

蓝湖 MCP 代理，默认连接本地服务。

依赖: mcp-proxy

仓库: https://github.com/dsphper/lanhu-mcp

## 安装命令

```toml
[mcp_servers.lanhu]
command = "mcp-proxy"
args = ["--transport", "streamablehttp", "http://localhost:8000/mcp?role=开发&name=w"]
startup_timeout_sec = 120.0
```

# mcp_servers.memory 本地记忆服务

## 说明

本地知识图谱记忆 MCP 服务。

依赖: Node / npm / npx

## 安装命令

```toml
[mcp_servers.memory]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-memory"]
startup_timeout_sec = 120.0
```

# mcp_servers.microsoft-docs-mcp Microsoft 文档检索

## 说明

通过 mcp-proxy 连接 Microsoft Learn 官方 MCP 服务。

依赖: mcp-proxy

## 安装命令

```toml
[mcp_servers.microsoft-docs-mcp]
type = "stdio"
command = "mcp-proxy"
args = ["--transport", "streamablehttp", "https://learn.microsoft.com/api/mcp"]
startup_timeout_sec = 120.0
```

# mcp_servers.nocturne_memory 记忆库

## 说明

地址: https://github.com/Dataojitori/nocturne_memory

## 安装命令

```toml
[mcp_servers.nocturne_memory]
url = "http://<your-server-ip>:<NGINX_PORT>/mcp"
startup_timeout_sec = 120.0
http_headers = { "Authorization" = "Bearer xxxx" }
```

# mcp_servers.sequential-thinking 顺序思考

## 说明

顺序思考与分步推理工具，适合复杂任务拆解。

依赖: Node / npm / npx

## 安装命令

```toml
[mcp_servers.sequential-thinking]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-sequential-thinking"]
startup_timeout_sec = 120.0
```

# mcp_servers.shrimp-task-manager Shrimp 任务管理

## 说明

Shrimp 任务规划与拆解工具。

依赖: Node / npm / npx

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

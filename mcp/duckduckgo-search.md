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

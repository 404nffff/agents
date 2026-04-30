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

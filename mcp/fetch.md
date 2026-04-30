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

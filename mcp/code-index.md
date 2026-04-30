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

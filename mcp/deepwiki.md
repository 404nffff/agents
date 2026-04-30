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

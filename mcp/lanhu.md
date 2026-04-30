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

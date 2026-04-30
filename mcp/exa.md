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

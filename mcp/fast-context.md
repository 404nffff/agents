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

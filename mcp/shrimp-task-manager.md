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

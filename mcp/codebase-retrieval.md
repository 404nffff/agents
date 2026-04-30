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

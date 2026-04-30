# agent-browser

面向 AI Agent 的浏览器自动化 CLI。通过紧凑文本输出减少上下文占用。100% 原生 Rust 实现。

```bash
npm install -g agent-browser      # 全平台
brew install agent-browser        # macOS
agent-browser install             # 首次使用时下载 Chrome

# 或者不安装直接试用
npx agent-browser open example.com
```

## 仓库地址
https://github.com/vercel-labs/agent-browser

## 功能特性

- **Agent 优先** - 紧凑文本输出相比 JSON 消耗更少 token，专为 AI 上下文效率设计
- **基于 Ref** - `snapshot` 返回带 ref 的可访问性树，元素定位可确定且稳定
- **高性能** - 原生 Rust CLI，命令解析速度快
- **能力完整** - 提供 50+ 命令，覆盖导航、表单、截图、网络、存储等场景
- **会话隔离** - 支持多个相互隔离的浏览器实例，认证状态互不影响
- **跨平台** - macOS、Linux、Windows 均提供原生二进制

## 适配工具

可用于 Claude Code、Cursor、GitHub Copilot、OpenAI Codex、Google Gemini、opencode，以及任何可执行 shell 命令的 Agent。

## 示例

```bash
# 导航并获取快照
agent-browser open example.com
agent-browser snapshot -i

# 输出示例：
# - heading "Example Domain" [ref=e1]
# - link "More information..." [ref=e2]

# 使用 ref 进行交互
agent-browser click @e2
agent-browser screenshot page.png
agent-browser close
```

## 为什么使用 ref？

`snapshot` 命令会返回紧凑的可访问性树，每个元素都有唯一 ref（如 `@e1`、`@e2`）。这样做的好处是：

- **上下文更省** - 文本输出约 200-400 tokens，而完整 DOM 常需约 3000-5000 tokens
- **结果可确定** - ref 精确指向快照中的目标元素
- **执行更快** - 无需再次查询 DOM
- **更友好于 AI** - LLM 更容易直接解析文本输出

## 架构

采用 Client-Daemon 架构以获得更优性能：

1. **Rust CLI** - 解析命令并与 daemon 通信
2. **原生 Daemon** - 纯 Rust daemon，直接使用 CDP，通过 Chrome DevTools Protocol 管理 Chrome

daemon 会自动启动，并在多次命令之间持续驻留。

## 平台支持

提供原生 Rust 二进制：macOS（ARM64、x64）、Linux（ARM64、x64）、Windows（x64）。

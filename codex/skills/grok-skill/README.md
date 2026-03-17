# grok-search

**[English](#english)** | **[中文](#中文)**

---

<a name="english"></a>
## 🌐 English

A Codex/Claude skill that enables aggressive web research via your OpenAI-compatible Grok endpoint (2api). Perfect for real-time information queries, version checking, and documentation lookup.

### ✨ Features

- 🔍 Real-time web search through Grok API
- 📋 Structured JSON output with `content` + `sources`
- 🔐 Secure config with local override support
- 🌍 Environment variable configuration
- ⚡ Easy one-click installation

### 📦 Installation

#### Method 1: Git Clone (Recommended)

```bash
# Clone the repository
git clone https://github.com/Frankieli123/grok-skill.git

# Enter the directory
cd grok-skill

# Run the install script (Windows PowerShell)
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

#### Method 2: Manual Download

1. Download ZIP from: https://github.com/Frankieli123/grok-skill/archive/refs/heads/main.zip
2. Extract to any folder
3. Run `install.ps1` in PowerShell

#### Installation Path

After installation, the skill will be located at:
```
C:\Users\<YourUsername>\.codex\skills\grok-search\
```

### ⚙️ Configuration

#### Option A: Interactive Configuration (Recommended)

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\grok-search\configure.ps1"
```

#### Option B: Manual Edit

Edit the config file at:
```
C:\Users\<YourUsername>\.codex\skills\grok-search\config.json
```

```json
{
  "base_url": "https://your-grok-endpoint.example",
  "api_key": "YOUR_API_KEY",
  "model": "grok-2-latest",
  "timeout_seconds": 60,
  "extra_body": {},
  "extra_headers": {}
}
```

| Field | Description |
|-------|-------------|
| `base_url` | Your Grok API endpoint URL |
| `api_key` | Your API key (**DO NOT commit to Git**) |
| `model` | Model name (e.g., `grok-2-latest`) |
| `timeout_seconds` | Request timeout in seconds |
| `extra_body` | Additional request body parameters |
| `extra_headers` | Additional HTTP headers |

#### Option C: Environment Variables

```powershell
$env:GROK_BASE_URL="https://your-grok-endpoint.example"
$env:GROK_API_KEY="YOUR_API_KEY"
$env:GROK_MODEL="grok-2-latest"
```

#### 🔒 Secure API Key Storage

For security, create `config.local.json` in the same directory (gitignored):

```json
{
  "api_key": "your-real-api-key-here"
}
```

### 🚀 Usage

#### Direct Command Line

```bash
python scripts/grok_search.py --query "What is the latest version of Node.js?"
```

#### Output Format

```json
{
  "content": "The synthesized answer...",
  "sources": [
    {"url": "https://example.com", "title": "Source Title"}
  ]
}
```

### 🤖 Enable Auto-Invocation in Codex/Claude

Add the following prompt to your global agent configuration:

**File:** `C:\Users\<YourUsername>\.codex\AGENTS.md` or `~/.claude/CLAUDE.md`

```markdown
## Web Search Rule

When encountering any of the following situations, ALWAYS use the `grok-search` skill first before providing an answer:

1. Version numbers, release dates, or changelog information
2. API documentation or SDK usage
3. Error messages or troubleshooting
4. Current status of any project, service, or technology
5. Any information that might be time-sensitive or outdated
6. Package installation commands or dependencies
7. Official documentation links

Usage example:
​```bash
python ~/.codex/skills/grok-search/scripts/grok_search.py --query "Your search query here"
​```

After receiving search results, cite the sources in your response.
```

### 📁 Project Structure

```
grok-search/
├── SKILL.md           # Skill definition for Codex/Claude
├── README.md          # This file
├── config.json        # Configuration template
├── install.ps1        # Installation script
├── configure.ps1      # Interactive configuration script
└── scripts/
    └── grok_search.py # Main search script
```

---

<a name="中文"></a>
## 🌐 中文

一个 Codex/Claude 技能插件，通过你的 OpenAI 兼容 Grok 接口（2api）实现激进的联网检索。适用于实时信息查询、版本检查和文档查找。

### ✨ 功能特性

- 🔍 通过 Grok API 进行实时网络搜索
- 📋 结构化 JSON 输出，包含 `content` + `sources`
- 🔐 安全配置，支持本地覆盖
- 🌍 支持环境变量配置
- ⚡ 一键安装

### 📦 安装方法

#### 方法一：Git 克隆（推荐）

```bash
# 克隆仓库
git clone https://github.com/Frankieli123/grok-skill.git

# 进入目录
cd grok-skill

# 运行安装脚本（Windows PowerShell）
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

#### 方法二：手动下载

1. 从这里下载 ZIP：https://github.com/Frankieli123/grok-skill/archive/refs/heads/main.zip
2. 解压到任意文件夹
3. 在 PowerShell 中运行 `install.ps1`

#### 安装路径

安装完成后，技能将位于：
```
C:\Users\<你的用户名>\.codex\skills\grok-search\
```

### ⚙️ 配置说明

#### 方式 A：交互式配置（推荐）

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\grok-search\configure.ps1"
```

#### 方式 B：手动编辑

编辑配置文件：
```
C:\Users\<你的用户名>\.codex\skills\grok-search\config.json
```

```json
{
  "base_url": "https://your-grok-endpoint.example",
  "api_key": "YOUR_API_KEY",
  "model": "grok-2-latest",
  "timeout_seconds": 60,
  "extra_body": {},
  "extra_headers": {}
}
```

| 字段 | 说明 |
|------|------|
| `base_url` | 你的 Grok API 端点地址 |
| `api_key` | 你的 API 密钥（**不要提交到 Git**） |
| `model` | 模型名称（如 `grok-2-latest`） |
| `timeout_seconds` | 请求超时时间（秒） |
| `extra_body` | 额外的请求体参数 |
| `extra_headers` | 额外的 HTTP 请求头 |

#### 方式 C：环境变量

```powershell
$env:GROK_BASE_URL="https://your-grok-endpoint.example"
$env:GROK_API_KEY="YOUR_API_KEY"
$env:GROK_MODEL="grok-2-latest"
```

#### 🔒 安全存储 API 密钥

为了安全，在同目录下创建 `config.local.json`（已加入 .gitignore）：

```json
{
  "api_key": "你的真实API密钥"
}
```

### 🚀 使用方法

#### 直接命令行调用

```bash
python scripts/grok_search.py --query "Node.js 最新版本是什么？"
```

#### 输出格式

```json
{
  "content": "综合后的答案...",
  "sources": [
    {"url": "https://example.com", "title": "来源标题"}
  ]
}
```

### 🤖 在 Codex/Claude 中启用自动调用

将以下提示词添加到你的全局 Agent 配置中：

**文件位置：** `C:\Users\<你的用户名>\.codex\AGENTS.md` 或 `~/.claude/CLAUDE.md`

```markdown
## 联网搜索规则

遇到以下任何情况时，必须先使用 `grok-search` 技能进行搜索，然后再回答：

1. 版本号、发布日期或更新日志信息
2. API 文档或 SDK 使用方法
3. 错误信息或故障排除
4. 任何项目、服务或技术的当前状态
5. 任何可能过时或时效性强的信息
6. 包安装命令或依赖项
7. 官方文档链接

使用示例：
​```bash
python ~/.codex/skills/grok-search/scripts/grok_search.py --query "你的搜索查询"
​```

收到搜索结果后，在回答中引用来源。
```

### 📁 项目结构

```
grok-search/
├── SKILL.md           # Codex/Claude 技能定义文件
├── README.md          # 本文件
├── config.json        # 配置模板
├── install.ps1        # 安装脚本
├── configure.ps1      # 交互式配置脚本
└── scripts/
    └── grok_search.py # 主搜索脚本
```

---

## 📄 License

MIT License

## 🤝 Contributing

Issues and PRs are welcome!

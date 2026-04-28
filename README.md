# Codex Agents & Skills 安装指南

> **目标读者:** AI Agent & 自动化执行脚本
> **核心准则:** 绝对不要手动拷贝 `AGENTS.md`、`skills` 或 `mcp` 配置文件。必须始终通过本仓库提供的统一安装脚本进行安装。

## 🚀 快速开始 (默认策略)

除非用户有明确的局部安装需求，否则请**默认执行全量、无交互安装**：

```bash
bash ./codex/install.sh all --yes
```
*此命令将自动确认，并使用默认路径统一安装 MCP 配置、全局 Agents 以及所有 Skills。*

---

## 📦 安装目标说明

`codex/install.sh` 脚本支持 4 个特定的安装目标：

### 1. `all` (推荐)
按顺序完整执行安装流程：`mcp` -> `agents` -> `skills`。
- **命令:** `bash ./codex/install.sh all --yes`
- *注意: `all` 模式必须配合 `--yes` 参数使用。*

### 2. `mcp`
将 `codex/mcp.md` 中的 `mcp_servers` 配置写入到目标机器的 `~/.codex/config.toml`。
- **命令:** `bash ./codex/install.sh mcp --yes`
- *注意: 此操作仅更新 `mcp_servers` 节点，不会破坏或修改用户的其他配置。*

### 3. `agents`
将全局代理规则文件安装至 `~/.codex/AGENTS.md`。
- **命令:** `bash ./codex/install.sh agents --yes`
- *行为: 本地执行时优先扫描 `codex/agents/`；远程执行时读取远程 `codex/agents/README.md`。*

### 4. `skills`
将 `codex/skills/` 下的所有可用技能安装至 `~/.codex/skills/`。
- **命令:** `bash ./codex/install.sh skills --yes`
- *行为: 如遇同名 skill，覆盖时会保留原有的配置文件。针对 `db-query` 等特殊 skill，会自动处理跨平台二进制下载逻辑。*

---

## 🌍 安装环境与执行方式

### 本地安装 (当前在仓库目录内)
如果当前工作目录已经是本仓库的根目录，请优先使用本地脚本：

```bash
# 交互式选择安装目标
bash ./codex/install.sh

# 指定目标安装
bash ./codex/install.sh mcp
bash ./codex/install.sh agents
bash ./codex/install.sh skills
```

### 远程安装 (当前无本地仓库)
如果本地不存在此仓库文件，可直接执行远程安装脚本：

**基于 jsDelivr (推荐):**
```bash
INSTALL_URL="https://cdn.jsdelivr.net/gh/404nffff/agents@latest/codex/install.sh"

# 默认交互式安装
curl -fsSL "${INSTALL_URL}" | bash

# 仅安装特定目标 (例如 skills)，并自动确认
curl -fsSL "${INSTALL_URL}" | bash -s -- skills --yes

# 安装指定版本 (例如 v1.0.0)
curl -fsSL "https://cdn.jsdelivr.net/gh/404nffff/agents@v1.0.0/codex/install.sh" | bash
```

**基于 Raw GitHub:**
```bash
curl -fsSL "https://raw.githubusercontent.com/404nffff/agents/master/codex/install.sh" | bash
```

---

## ✅ 安装后验证步骤

**AI 执行强制要求:** 安装完成后，绝对不能仅回复“已完成”。必须立即执行以下命令进行存在性检查，并向用户反馈验证结果：

```bash
# 1. 检查基础目录结构
ls -la ~/.codex
ls -la ~/.codex/skills

# 2. 验证核心文件与配置状态
test -f ~/.codex/AGENTS.md && echo "✅ AGENTS OK" || echo "❌ AGENTS MISSING"
test -f ~/.codex/config.toml && grep -q "mcp_servers" ~/.codex/config.toml && echo "✅ CONFIG OK" || echo "❌ CONFIG MISSING/INVALID"
```

完整的安装预期结果应当是：
1. `~/.codex/AGENTS.md` 文件已存在。
2. `~/.codex/config.toml` 文件已存在，且包含有效的 `mcp_servers` 配置段。
3. `~/.codex/skills/` 目录下出现已安装的各个 skill 文件夹。

---

## 📚 目录结构参考

为了帮助 AI 更好地理解上下文，以下是关键文件的说明：
- `codex/install.sh`：所有安装逻辑的统一入口。
- `codex/mcp.md`：MCP (Model Context Protocol) 原始配置来源。
- `codex/agents/README.md`：可安装的 Agent 规则文件目录索引。
- `codex/skills/README.md`：可安装的 Skill 扩展包目录索引。

---

## 💡 获取帮助

要查看任何命令或目标的详细帮助信息，请执行：

```bash
bash ./codex/install.sh --help
bash ./codex/install.sh mcp --help
bash ./codex/install.sh agents --help
bash ./codex/install.sh skills --help
bash ./codex/install.sh all --help
```
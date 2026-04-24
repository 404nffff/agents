# agents 安装说明（给 AI / Agent 看）

这个仓库的统一安装入口是：

```bash
bash ./codex/install.sh
```

不要自己手动拷贝 `AGENTS.md`、`skills` 或 `mcp` 配置。优先走安装脚本。

## 1. 你要安装什么

`codex/install.sh` 支持 4 个目标：

- `mcp`：把 `codex/mcp.md` 中的 `mcp_servers` 配置写入 `~/.codex/config.toml`
- `agents`：安装一个全局 `AGENTS.md` 到 `~/.codex/AGENTS.md`
- `skills`：安装 `codex/skills/` 下的 skills 到 `~/.codex/skills/`
- `all`：按顺序执行 `mcp -> agents -> skills`

如果没有特殊要求，默认安装：

```bash
bash ./codex/install.sh all --yes
```

这条命令适合 AI 直接执行，含义是：

- 自动确认
- 统一安装 MCP、AGENTS、Skills
- 使用脚本内置默认来源与默认路径

## 2. 本地安装

如果当前就在本仓库根目录，优先使用本地安装。

交互模式：

```bash
bash ./codex/install.sh
```

指定目标：

```bash
bash ./codex/install.sh mcp
bash ./codex/install.sh agents
bash ./codex/install.sh skills
bash ./codex/install.sh all
```

无交互自动确认：

```bash
bash ./codex/install.sh all --yes
```

## 3. 远程安装

如果本地没有仓库，可以直接执行远程安装脚本。

基于 jsDelivr：

```bash
INSTALL_URL="https://cdn.jsdelivr.net/gh/404nffff/agents@latest/codex/install.sh"
curl -fsSL "${INSTALL_URL}" | bash
```

仅安装 skills：

```bash
curl -fsSL "${INSTALL_URL}" | bash -s -- skills --yes
```

固定版本安装：

```bash
curl -fsSL "https://cdn.jsdelivr.net/gh/404nffff/agents@v1.0.0/codex/install.sh" | bash
```

基于 Raw GitHub：

```bash
curl -fsSL "https://raw.githubusercontent.com/404nffff/agents/master/codex/install.sh" | bash
```

## 4. 各目标实际行为

### `mcp`

建议命令：

```bash
bash ./codex/install.sh mcp --yes
```

行为：

- 默认优先读取 `codex/mcp.md`
- 把 `mcp_servers` 相关配置写到 `~/.codex/config.toml`
- 只更新 `mcp_servers` 段，不动其他配置

### `agents`

建议命令：

```bash
bash ./codex/install.sh agents --yes
```

行为：

- 本地执行时优先扫描 `codex/agents/`
- 远程执行时先读取远程 `codex/agents/README.md`
- 最终只安装一个全局文件到 `~/.codex/AGENTS.md`

### `skills`

建议命令：

```bash
bash ./codex/install.sh skills --yes
```

行为：

- 本地执行时优先扫描 `codex/skills/`
- 远程执行时先读取远程 `codex/skills/README.md`
- 安装目标目录是 `~/.codex/skills/`
- 同名 skill 覆盖时保留已有配置文件
- `db-query` 会按平台处理二进制下载逻辑

### `all`

建议命令：

```bash
bash ./codex/install.sh all --yes
```

行为：

- 顺序执行：`mcp -> agents -> skills`
- `all` 模式只接受 `--yes`

## 5. 安装后应该看到什么

安装完成后，至少检查这几个位置：

```bash
ls -la ~/.codex
ls -la ~/.codex/skills
test -f ~/.codex/AGENTS.md && echo "AGENTS OK"
test -f ~/.codex/config.toml && echo "CONFIG OK"
```

如果是完整安装，预期结果是：

- `~/.codex/AGENTS.md` 已存在
- `~/.codex/config.toml` 已存在，且包含 `mcp_servers`
- `~/.codex/skills/` 下出现已安装的 skill 目录

## 6. 给 AI 的执行建议

AI 执行时按这个顺序：

1. 如果在仓库根目录，优先执行：

```bash
bash ./codex/install.sh all --yes
```

2. 如果只需要能力包，不需要全量环境，执行：

```bash
bash ./codex/install.sh skills --yes
```

3. 如果用户只要求装规则文件，执行：

```bash
bash ./codex/install.sh agents --yes
```

4. 如果用户只要求补 MCP，执行：

```bash
bash ./codex/install.sh mcp --yes
```

5. 安装后立刻做存在性检查，不要只报告“已完成”而不验证

## 7. 常用帮助命令

```bash
bash ./codex/install.sh --help
bash ./codex/install.sh mcp --help
bash ./codex/install.sh agents --help
bash ./codex/install.sh skills --help
bash ./codex/install.sh all --help
```

## 8. 相关文件

- `codex/install.sh`：统一安装入口
- `codex/mcp.md`：MCP 配置来源
- `codex/agents/README.md`：可安装 agent 文件目录
- `codex/skills/README.md`：可安装 skill 目录

## 9. 一句话默认策略

除非用户明确要求局部安装，否则默认执行：

```bash
bash ./codex/install.sh all --yes
```

# AGENTS.md 安装说明

## 1. 远程一键运行（curl）

使用仓库 `404nffff/agents` 的 `master` 分支：

```bash
curl -fsSL "https://raw.githubusercontent.com/404nffff/agents/master/codex/install_agents.sh" | bash
```

## 2. 远程运行并传参

```bash
curl -fsSL "https://raw.githubusercontent.com/404nffff/agents/master/codex/install_agents.sh" | bash -s -- --github 404nffff/agents --ref master --file codex/AGENTS.md
```

```bash
curl -fsSL "https://raw.githubusercontent.com/404nffff/agents/master/codex/install_agents.sh" | bash -s -- --source "https://raw.githubusercontent.com/404nffff/agents/master/codex/AGENTS.md"
```

## 3. 本地运行

```bash
chmod +x codex/install_agents.sh
./codex/install_agents.sh
```

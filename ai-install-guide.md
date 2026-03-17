# AI Install Guide (for Codex, no install scripts)

本文档用于让 Codex 代理**不依赖任何安装脚本**，仅使用 Codex 自带工具自动安装 `AGENTS.md`。

## 1. 安装目标

- 用户级文件：
  - Linux/macOS: `~/.codex/AGENTS.md`
  - Windows: `%USERPROFILE%\.codex\AGENTS.md`
- 项目级文件：`当前工作目录/AGENTS.md`

## 2. 固定远程源

- AGENTS 源文件（唯一来源）：
  - `https://raw.githubusercontent.com/404nffff/agents/master/codex/AGENTS.md`

## 3. 强制执行原则

1. 禁止调用以下脚本进行安装：
   - `install_agents.sh`
   - `install_agents_windows.bat`
2. 必须使用 Codex 自带工具执行以下动作：
   - 远程读取（fetch）
   - 本地目录创建（shell）
   - 文件写入（shell / patch）
   - 文件校验（shell）
3. 默认无交互自动覆盖同名文件。

## 4. 标准执行流程（Codex）

### 步骤 1：拉取远程 AGENTS.md

- 使用内置 fetch 工具读取：
  - `https://raw.githubusercontent.com/404nffff/agents/master/codex/AGENTS.md`
- 若请求失败：重试 2 次；仍失败则停止并报告。

### 步骤 2：写入用户级目标

- Linux/macOS:
  - 创建目录：`mkdir -p "$HOME/.codex"`
  - 写入文件：`$HOME/.codex/AGENTS.md`
- Windows:
  - 创建目录：`%USERPROFILE%\.codex`
  - 写入文件：`%USERPROFILE%\.codex\AGENTS.md`

### 步骤 3：写入项目级目标

- 当前目录写入：`./AGENTS.md`

### 步骤 4：安装后校验（必须）

- 校验两个目标文件都存在
- 校验内容非空
- 可选：校验文件前 3 行与远程源一致

## 5. Codex 命令模板（参考）

> 说明：以下是给 Codex 的执行模板，不是给终端用户手工逐条复制的固定脚本。

### 5.1 Linux/macOS 校验命令

```bash
test -s "$HOME/.codex/AGENTS.md" && echo "USER_OK" || echo "USER_FAIL"
test -s "./AGENTS.md" && echo "PROJECT_OK" || echo "PROJECT_FAIL"
```

### 5.2 Windows 校验命令

```bat
if exist "%USERPROFILE%\.codex\AGENTS.md" (echo USER_OK) else (echo USER_FAIL)
if exist ".\AGENTS.md" (echo PROJECT_OK) else (echo PROJECT_FAIL)
```

## 6. 失败处理

1. 远程下载失败：
   - 重试最多 2 次
   - 报告 HTTP/网络错误摘要
2. 写入失败：
   - 报告目标路径、权限错误信息
3. 校验失败：
   - 报告失败项（用户级/项目级）
   - 输出建议（权限、路径、磁盘）

## 7. Codex 结果输出格式

执行完成后，Codex 必须输出：

1. 远程来源 URL
2. 写入的绝对路径（用户级 + 项目级）
3. 校验结果（USER_OK/FAIL, PROJECT_OK/FAIL）
4. 失败时的错误摘要与下一步建议

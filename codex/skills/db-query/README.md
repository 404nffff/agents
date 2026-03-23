# db-query Skill

日期：2026-03-20  
执行者：Codex

## 说明

`db-query` 是一个基于 Go 二进制的统一查询 skill，支持：

- MySQL
- PostgreSQL
- MongoDB
- Redis

核心能力：

- 单一 CLI 契约（`--driver` 切换数据库类型）
- profile 配置模式（`<DRIVER>_*_<profile>`）
- 统一 JSON 输出格式
- SQL 只读校验
- DDL/DML 请求改写为 `.sql` 文件交付（不直接执行）
- Linux/Windows 双二进制产物

## 目录结构

- `PLAN.md`：实施计划
- `SKILL.md`：Skill 使用规范
- `config.example.env`：配置模板
- `scripts/build.sh`：构建 Linux/Windows 二进制
- `scripts/`：Go 源码（`go.mod`、`cmd/`、`internal/`、`tests/`）
- `bin/`：打包产物

## 构建

```bash
cd ~/.codex/skills/db-query
bash scripts/build.sh
```

构建产物：

- `bin/db-query-linux-amd64`
- `bin/db-query-windows-amd64.exe`

## 发布到 GitHub Release

```bash
cd /path/to/your/repo

# 1) 构建二进制
bash codex/skills/db-query/scripts/build.sh

# 2) 提交并打 tag
git add codex/skills/db-query
git commit -m "release: db-query binaries"
git tag -a v0.1.0 -m "db-query v0.1.0"
git push origin HEAD --tags

# 3) 创建 release 并上传 bin
gh release create v0.1.0 \
  codex/skills/db-query/bin/db-query-linux-amd64 \
  codex/skills/db-query/bin/db-query-windows-amd64.exe \
  --title "v0.1.0" \
  --notes "db-query release binaries"
```

如果 release 已存在：

```bash
gh release upload v0.1.0 \
  codex/skills/db-query/bin/db-query-linux-amd64 \
  codex/skills/db-query/bin/db-query-windows-amd64.exe \
  --clobber
```

`install_skills.sh` 在安装 `db-query` 时会按以下地址下载二进制：

- 默认：`https://github.com/404nffff/agents/releases/latest/download`
- 或者用环境变量覆盖：
  - `DB_QUERY_RELEASE_BASE_URL`
  - `DB_QUERY_RELEASE_REPO` + `DB_QUERY_RELEASE_TAG`

## 运行

### 直接运行 Linux 二进制

```bash
~/.codex/skills/db-query/bin/db-query-linux-amd64 \
  --driver pgsql \
  --profile main \
  --query "SELECT id, name FROM users LIMIT 20"
```

### 直接运行 Windows 二进制

```powershell
~/.codex/skills/db-query/bin/db-query-windows-amd64.exe `
  --driver mysql `
  --profile main `
  --query "SELECT id, name FROM users LIMIT 20"
```

### MongoDB 查询示例

```bash
~/.codex/skills/db-query/bin/db-query-linux-amd64 \
  --driver mongo \
  --profile main \
  --database app_db \
  --query '{"operation":"find","collection":"users","filter":{"status":"active"},"limit":20}'
```

### Redis 查询示例

```bash
~/.codex/skills/db-query/bin/db-query-linux-amd64 \
  --driver redis \
  --profile cache \
  --query '{"command":"GET","key":"session:123"}'
```

## DDL/DML 处理规则

当 SQL 含以下操作时，程序不会直接执行数据库连接：

- `INSERT`
- `ALTER TABLE`
- `CREATE TABLE`
- `CREATE INDEX`

程序会在当前运行目录生成 `.sql` 文件，并返回文件路径，提示人工执行该文件。

## 输出格式

仅支持 JSON。成功输出包含：

- `driver`
- `profile`
- `query`
- `row_count`
- `columns`
- `rows`
- `meta.elapsed_ms`

失败输出包含：

- `error.code`
- `error.message`
- `error.driver`

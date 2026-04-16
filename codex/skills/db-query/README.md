# db-query Skill

日期：2026-04-16  
执行者：Codex

## 概览

`db-query` 是一个基于 Go 二进制的统一数据库查询 skill，用同一套 CLI 契约查询以下驱动：

- MySQL
- PostgreSQL
- MongoDB
- Redis

核心目标：

- 用 `--driver` 切换数据库类型
- 用 `<DRIVER>_*_<profile>` 管理多套连接配置
- 统一使用 JSON 返回结果
- 强制限制为只读查询
- 将 DDL / DML 请求落盘为 `.sql` 文件，而不是直接执行
- 同时提供 Linux / Windows 二进制

## 目录说明

- `SKILL.md`：Skill 使用规范，面向调用方
- `README.md`：能力说明、参数示例、输出约定
- `config.example.env`：配置模板
- `scripts/build.sh`：构建 Linux / Windows 二进制
- `release_with_gh.sh`：使用 GitHub CLI 发布二进制
- `scripts/`：Go 源码
- `bin/`：构建产物

## 运行规则

调用时必须优先使用打包后的二进制，不直接运行源码：

- Linux：`~/.codex/skills/db-query/bin/db-query-linux-amd64`
- Windows：`~/.codex/skills/db-query/bin/db-query-windows-amd64.exe`

运行时固定读取 skill 根目录下的 `config.env`。文档里只说明它是必需文件，不展开任何敏感配置内容。

## 连接配置

连接参数优先级从高到低：

1. 命令行参数，例如 `--host`、`--port`、`--user`、`--password`、`--database`、`--uri`、`--addr`
2. `--profile` 对应的 profile 环境变量，例如 `MYSQL_HOST_main`
3. `DB_PROFILE` 或 `<DRIVER>_PROFILE`

配置命名规则：

- MySQL：`MYSQL_*_<profile>`
- PostgreSQL：`PGSQL_*_<profile>`
- MongoDB：`MONGO_*_<profile>`
- Redis：`REDIS_*_<profile>`

## 快速开始

### MySQL

```bash
~/.codex/skills/db-query/bin/db-query-linux-amd64 \
  --driver mysql \
  --profile main \
  --target users \
  --fields id,name \
  --where "status = 'active'" \
  --sort "id desc" \
  --limit 20
```

### PostgreSQL

```bash
~/.codex/skills/db-query/bin/db-query-linux-amd64 \
  --driver pgsql \
  --profile main \
  --target users \
  --fields id,name \
  --where "status = 'active'" \
  --sort "id desc" \
  --limit 20
```

### MongoDB

```bash
~/.codex/skills/db-query/bin/db-query-linux-amd64 \
  --driver mongo \
  --profile main \
  --database app_db \
  --target t_student \
  --where status:=:active \
  --where age:>=:18 \
  --where tag:in:vip,gold \
  --sort created_at:desc \
  --limit 20
```

### Redis

```bash
~/.codex/skills/db-query/bin/db-query-linux-amd64 \
  --driver redis \
  --profile cache \
  --command GET \
  --target session:123
```

```bash
~/.codex/skills/db-query/bin/db-query-linux-amd64 \
  --driver redis \
  --profile cache \
  --command SCAN \
  --target session:* \
  --limit 50
```

### Windows 示例

```powershell
~/.codex/skills/db-query/bin/db-query-windows-amd64.exe `
  --driver mysql `
  --profile main `
  --target users `
  --fields id,name `
  --where "status = 'active'" `
  --sort "id desc" `
  --limit 20
```

## 统一参数契约

优先使用以下统一参数：

- `--target`：SQL 的表名、Mongo 的 collection、Redis 的 key 或 pattern
- `--fields`：SQL 字段列表、Mongo 投影字段列表
- `--where`：SQL 条件表达式，或 Mongo 条件 `字段:操作符:值`
- `--sort`：SQL 排序表达式，或 Mongo 排序 `字段:asc|desc`
- `--limit`：结果上限
- `--query`：原始查询兜底入口

兼容说明：

- SQL 旧参数 `--table`、`--columns`、`--order-by` 仍可用
- Mongo / Redis 旧 `--query` JSON 仍可用
- 只要传入 `--query`，就不能再混用结构化参数

### Mongo `--where` 语法

Mongo 结构化条件支持重复传入，固定格式为 `字段:操作符:值`，当前支持：

- `=`：等值
- `>`：`$gt`
- `>=`：`$gte`
- `<`：`$lt`
- `<=`：`$lte`
- `in`：`$in`，值用逗号分隔

## 输出契约

只允许 JSON 输出，不支持表格文本。

强制规则：

1. 所有调用必须返回 JSON
2. 仅允许 `--format json`
3. 每次成功输出必须包含 `raw_sql`
4. `query` 保留内部统一请求体
5. `raw_sql` 必须打印当前驱动对应的原生可读语句

成功输出字段：

- `driver`
- `profile`
- `query`
- `raw_sql`
- `row_count`
- `columns`
- `rows`
- `meta.elapsed_ms`

失败输出字段：

- `error.code`
- `error.message`
- `error.driver`

### MySQL / PostgreSQL 返回示例

```json
{
  "driver": "mysql",
  "profile": "main",
  "query": "SELECT id,name FROM users WHERE status = 'active' ORDER BY id desc LIMIT 20",
  "raw_sql": "SELECT id,name FROM users WHERE status = 'active' ORDER BY id desc LIMIT 20",
  "row_count": 2,
  "columns": ["id", "name"],
  "rows": [
    { "id": 1, "name": "alice" },
    { "id": 2, "name": "bob" }
  ],
  "meta": {
    "elapsed_ms": 12
  }
}
```

### MongoDB 返回示例

```json
{
  "driver": "mongo",
  "profile": "main",
  "query": "{\"collection\":\"t_student\",\"filter\":{},\"limit\":3,\"operation\":\"find\"}",
  "raw_sql": "db.getSiblingDB(\"app_db\").getCollection(\"t_student\").find({}).limit(3)",
  "row_count": 3,
  "rows": [],
  "meta": {
    "elapsed_ms": 18
  }
}
```

### Redis 返回示例

```json
{
  "driver": "redis",
  "profile": "cache",
  "query": "{\"command\":\"SCAN\",\"pattern\":\"session:*\",\"count\":50}",
  "raw_sql": "SCAN 0 MATCH session:* COUNT 50",
  "row_count": 0,
  "rows": [],
  "meta": {
    "elapsed_ms": 5
  }
}
```

## 只读边界

### MySQL / PostgreSQL

- 只允许只读语句开头：`SELECT`、`SHOW`、`DESC`、`DESCRIBE`、`EXPLAIN`、`WITH`
- 禁止写操作关键词：`DELETE`、`UPDATE`、`DROP`、`ALTER`、`CREATE`
- 允许 `SHOW CREATE ...`
- 禁止多语句执行

### MongoDB

- 仅允许 `find`
- 仅允许只读 `aggregate`
- 禁止 `$out`、`$merge`

### Redis

- 白名单命令：`GET`、`MGET`、`HGET`、`HGETALL`、`SMEMBERS`、`ZRANGE`、`LRANGE`、`SCAN`
- 禁止写入和高风险命令，例如 `SET`、`DEL`、`EXPIRE`、`EVAL`

## DDL / DML 处理规则

当请求包含以下 SQL 操作时，程序不会直接连接数据库执行：

- `INSERT`
- `ALTER TABLE`
- `CREATE TABLE`
- `CREATE INDEX`

而是执行以下流程：

1. 在当前运行目录生成 `.sql` 文件
2. 将待执行 SQL 写入该文件
3. 返回文件路径和用途说明
4. 提示调用方手动执行该文件

返回结构会包含：

- `status`
- `action`
- `file_path`
- `message`
- `query`
- `raw_sql`

## 构建

```bash
cd ~/.codex/skills/db-query
bash scripts/build.sh
```

构建产物：

- `bin/db-query-linux-amd64`
- `bin/db-query-windows-amd64.exe`

## 发布

如果本地已经安装 `gh`，可以直接执行：

```bash
cd ~/.codex/skills/db-query
bash release_with_gh.sh
```

如果需要手动发布，最小流程如下：

```bash
cd /path/to/your/repo
bash codex/skills/db-query/scripts/build.sh
git add codex/skills/db-query
git commit -m "release: db-query binaries"
git tag -a v0.1.0 -m "db-query v0.1.0"
git push origin HEAD --tags
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

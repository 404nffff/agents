---
name: db-query
description: 使用 Go 打包二进制查询 Redis/MySQL/MongoDB/PostgreSQL。配置采用 `<DRIVER>_*_<profile>` 多库模式（例如 `MYSQL_HOST_main`、`REDIS_ADDR_cache`），通过 `--profile` 或 `DB_PROFILE` 选择。默认只允许只读查询，并强制输出 JSON。
---

# DB Query

脚本目录：`~/.codex/skills/db-query/`

使用这个 skill 时，必须优先使用打包后的 `bin` 命令，不直接运行源码：

1. Linux：`~/.codex/skills/db-query/bin/db-query-linux-amd64`
2. Windows：`~/.codex/skills/db-query/bin/db-query-windows-amd64.exe`

配置文件固定读取：skill 根目录的 `config.env`（即 `~/.codex/skills/db-query/config.env`）。
`config.env` 为必需文件，不存在时命令会报错退出。

## 快速开始

### 1) MySQL / PostgreSQL（SQL）

```bash
~/.codex/skills/db-query/bin/db-query-linux-amd64 \
  --driver mysql \
  --profile main \
  --query "SELECT id, name FROM users LIMIT 20"
```

```bash
~/.codex/skills/db-query/bin/db-query-linux-amd64 \
  --driver pgsql \
  --profile main \
  --query "SELECT id, name FROM users LIMIT 20"
```

### 2) MongoDB（JSON 查询表达式）

```bash
~/.codex/skills/db-query/bin/db-query-linux-amd64 \
  --driver mongo \
  --profile main \
  --database app_db \
  --query '{"operation":"find","collection":"users","filter":{"status":"active"},"limit":20}'
```

### 3) Redis（JSON 命令表达式）

```bash
~/.codex/skills/db-query/bin/db-query-linux-amd64 \
  --driver redis \
  --profile cache \
  --query '{"command":"GET","key":"session:123"}'
```

## 平台与 bin 规则（强制）

`bin` 目录需要保留两个版本：

- `bin/db-query-linux-amd64`
- `bin/db-query-windows-amd64.exe`

运行时必须判断平台，选择对应二进制执行。

## 连接配置优先级

优先级从高到低：

1. 命令行参数（如 `--host/--port/--user/--password/--database/--uri/--addr`）
2. `--profile` 对应的 profile 变量（例如 `MYSQL_HOST_<profile>`）
3. `DB_PROFILE` 或 `<DRIVER>_PROFILE`

## 只读限制

### MySQL / PostgreSQL

1. 只允许只读语句开头：`SELECT` / `SHOW` / `DESC` / `DESCRIBE` / `EXPLAIN` / `WITH`
2. 禁止写操作关键词：`DELETE`、`UPDATE`、`DROP`、`ALTER`、`CREATE`（`SHOW CREATE` 除外）等
3. 禁止多语句执行

### MongoDB

1. 仅允许 `find`、只读 `aggregate`
2. `aggregate` 禁止 `$out`、`$merge`

### Redis

1. 白名单命令：`GET`、`MGET`、`HGET`、`HGETALL`、`SMEMBERS`、`ZRANGE`、`LRANGE`、`SCAN`
2. 禁止写入和高风险命令（例如 `SET`、`DEL`、`EXPIRE`、`EVAL`）

### 6) DDL/DML 请求处理规则（强制）

当需求包含以下任一操作时，不得直接连接数据库执行：
1. `INSERT`（DML）
2. `ALTER TABLE`（DDL，修改表结构）
3. `CREATE TABLE`（DDL，建表）
4. `CREATE INDEX`（DDL，建索引）

必须执行以下流程：
1. 在**当前运行目录**生成对应 `.sql` 文件（例如：`dml_insert_YYYYMMDD_HHMMSS.sql`、`ddl_alter_table_YYYYMMDD_HHMMSS.sql`）。
2. 将需要执行的 SQL 内容写入该文件。
3. 明确提示用户：请执行该 SQL 文件中的 DDL/DML 操作。
4. 响应中返回生成的文件路径与用途说明。

## 输出格式

强制规则：
1. 所有调用必须返回 JSON。
2. 仅允许 `--format json`。
3. 不支持表格文本输出。

成功输出字段：
- `driver`
- `profile`
- `query`
- `row_count`
- `columns`
- `rows`
- `meta.elapsed_ms`

失败输出字段：
- `error.code`
- `error.message`
- `error.driver`

## 构建命令

```bash
cd ~/.codex/skills/db-query
bash scripts/build.sh
```

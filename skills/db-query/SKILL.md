---
name: db-query
description: 使用 Go 打包二进制查询 Redis/Memcached/MySQL/MongoDB/PostgreSQL/Elasticsearch。配置采用 DRIVER 前缀加 profile 后缀的多库模式（例如 `MYSQL_HOST_main`、`REDIS_ADDR_cache`、`MEMCACHED_ADDR_cache`、`ES_URL_main`），首次使用先执行 `--list-profiles` 暴露当前配置中的 profile，再通过 `--profile` 或 `DB_PROFILE` 选择。默认只允许只读查询，并强制输出 JSON。
---

# DB Query

脚本目录：`~/.codex/skills/db-query/`

默认附加加载资料：`~/.codex/skills/db-query/engineering-database-optimizer.md`。
当任务涉及数据库结构设计、索引策略、慢查询分析、`EXPLAIN` / `EXPLAIN ANALYZE`、连接池、迁移策略或性能优化时，**必须先读取该资料**，再使用本 skill。

使用这个 skill 时，必须优先使用打包后的 `bin` 命令，不直接运行源码。

**平台检测与二进制选择**：
- Linux amd64：`~/.codex/skills/db-query/bin/db-query-linux-amd64`
- Linux arm64：`~/.codex/skills/db-query/bin/db-query-linux-arm64`
- Windows amd64：`~/.codex/skills/db-query/bin/db-query-windows-amd64.exe`

使用 `uname -m` 和 `uname -s` 判断平台，自动选择对应二进制。

**配置文件读取约定**：

1. 若调用方显式传入 `--config <path>`，以显式路径为准。
2. 默认先检查当前工作区的 `docs/db.env`；若存在，调用命令时必须显式追加 `--config docs/db.env`。
3. 若 `docs/db.env` 不存在，再回退到 skill 根目录的 `config.env`（即 `~/.codex/skills/db-query/config.env`）。
4. 若 `docs/db.env` 与 skill 根目录 `config.env` 都不存在，命令返回错误码 1，输出 JSON 格式错误：
   ```json
   {"error": {"code": "CONFIG_NOT_FOUND", "message": "配置文件不存在", "driver": "unknown"}}
   ```

以下示例统一遵循上述规则：如果工作区存在 `docs/db.env`，请在命令中补上 `--config docs/db.env`；否则按默认回退到 skill 根目录 `config.env`。

## 快速开始

### 0) 首次使用：先确认配置与 profile（强制）

第一次在某个工作区使用本 skill 时，必须先执行 `--list-profiles`，确认实际读取的配置文件、可用 profile、全局默认 profile 与驱动默认 profile。该命令只读取配置并输出 profile 名称，不连接数据库，也不输出密码、URI 等敏感值。

```bash
~/.codex/skills/db-query/bin/db-query-linux-amd64 \
  --list-profiles
```

如果只需要确认某个驱动：

```bash
~/.codex/skills/db-query/bin/db-query-linux-amd64 \
  --list-profiles \
  --driver mysql
```

若工作区存在 `docs/db.env`：

```bash
~/.codex/skills/db-query/bin/db-query-linux-amd64 \
  --config docs/db.env \
  --list-profiles
```

返回示例：

```json
{
  "status": "profiles",
  "config_path": "/mnt/project/docs/db.env",
  "global_default_profile": "main",
  "drivers": [
    {
      "driver": "mysql",
      "profiles": ["main", "report"],
      "driver_default_profile": "report",
      "effective_default_profile": "main"
    }
  ],
  "meta": {
    "elapsed_ms": 1
  }
}
```

如果某个驱动的 `effective_default_profile` 不在该驱动的 `profiles` 数组中，说明全局 `DB_PROFILE` 覆盖了驱动默认值但该驱动没有对应连接配置；此时查询必须显式传入该驱动可用的 `--profile`。

### 1) MySQL / PostgreSQL（统一结构化参数）

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

### 2) MongoDB（推荐结构化参数）

```bash
~/.codex/skills/db-query/bin/db-query-linux-amd64 \
  --driver mongo \
  --profile main \
  --database app_db \
  --target users \
  --where status:=:active \
  --where age:>=:18 \
  --where tag:in:vip,gold \
  --limit 20
```

**注意**：MongoDB 需要 `--database` 参数指定数据库名。

### 3) Redis（统一外层参数）

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

### 4) Memcached（统一外层参数）

```bash
~/.codex/skills/db-query/bin/db-query-linux-amd64 \
  --driver memcached \
  --profile cache \
  --command GET \
  --target session:123
```

```bash
~/.codex/skills/db-query/bin/db-query-linux-amd64 \
  --driver memcached \
  --profile cache \
  --command MGET \
  --target session:123,session:456
```

**注意**：Memcached 的 MGET 使用 `--target` 传入逗号分隔的多个 key。

### 5) Elasticsearch（结构化参数或原始 DSL）

```bash
~/.codex/skills/db-query/bin/db-query-linux-amd64 \
  --driver es \
  --profile main \
  --target student_index \
  --fields name,age \
  --where status:=:active \
  --where age:>=:18 \
  --sort created_at:desc \
  --limit 20
```

```bash
~/.codex/skills/db-query/bin/db-query-linux-amd64 \
  --driver es \
  --profile main \
  --query '{"query":{"match":{"name":"alice"}},"size":5}'
```

## 平台与 bin 规则（强制）

`bin` 目录需要保留三个版本：

- `bin/db-query-linux-amd64`
- `bin/db-query-linux-arm64`
- `bin/db-query-windows-amd64.exe`

运行时必须判断平台，选择对应二进制执行。

## 连接配置优先级

优先级从高到低：

1. 命令行参数（如 `--host/--port/--user/--password/--database/--uri/--addr`）
2. `--profile` 对应的 profile 变量（例如 `MYSQL_HOST_<profile>`）
3. `DB_PROFILE` 或 `<DRIVER>_PROFILE`

## 统一参数约定

优先使用以下统一参数名：

- `--list-profiles`：只读取配置并输出当前配置中暴露的 profile 名称；可选配合 `--driver` 过滤单个驱动
- `--target`：SQL 的表名、Mongo 的 collection、Redis 的 key 或 pattern、Memcached 的 key、ES 的 index
- `--fields`：SQL 字段列表、Mongo 投影字段列表、ES `_source` 字段列表
- `--where`：SQL 条件表达式，或 Mongo / ES 条件 `字段:操作符:值`
- `--sort`：SQL 排序表达式，或 Mongo / ES 排序（使用 `字段:asc|desc`）
- `--limit`：结果上限
- `--database`：数据库名（仅 MongoDB 必需）
- `--query`：原始查询兜底入口

兼容说明：

- SQL 旧参数 `--table`、`--columns`、`--order-by` 仍可用
- Mongo / Redis / ES 旧 `--query` JSON 仍可用
- **警告**：一旦传入 `--query`，不得再混用结构化参数，否则返回错误

### Mongo `--where` 语法

可重复传入，固定格式为 `字段:操作符:值`，首批支持：

- `=`：等值
- `>`：`$gt`
- `>=`：`$gte`
- `<`：`$lt`
- `<=`：`$lte`
- `in`：`$in`，值使用逗号分隔

### Elasticsearch `--where` 语法

可重复传入，固定格式为 `字段:操作符:值`，首批支持：

- `=`：`term`
- `>`：`range.gt`
- `>=`：`range.gte`
- `<`：`range.lt`
- `<=`：`range.lte`
- `in`：`terms`

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

### Memcached

1. 白名单命令：`GET`、`MGET`
2. 禁止写入命令（例如 `SET`、`ADD`、`REPLACE`、`APPEND`、`PREPEND`、`DELETE`、`INCR`、`DECR`、`FLUSH_ALL`）
3. Memcached 不支持安全的通用 key 遍历，本工具不提供扫描能力

### Elasticsearch

1. 固定只允许 `POST /<index>/_search`
2. 结构化参数只生成 `_search` body
3. 原始 `--query` 仅允许 JSON body，最终仍会走 `_search`
4. 禁止 index / bulk / update / delete / script 等写操作入口

## DDL/DML 请求处理规则（强制）

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
4. 每次成功输出必须包含 `raw_sql` 字段，用于打印当前驱动对应的原生可读语句；其中 `query` 保留内部统一请求体。

成功输出字段：
- `driver`：驱动类型
- `profile`：使用的 profile
- `query`：内部统一请求体
- `raw_sql`：原生可读语句（各驱动格式见下方示例）
- `row_count`：结果行数
- `columns`：列名数组
- `rows`：结果数据
- `meta.elapsed_ms`：执行耗时（毫秒）

失败输出字段：
- `error.code`：错误码
- `error.message`：错误信息
- `error.driver`：驱动类型

### `raw_sql` 格式示例

**MySQL/PostgreSQL**：
```
SELECT id, name FROM users WHERE status = 'active' ORDER BY id DESC LIMIT 20
```

**MongoDB**：
```
db.users.find({"status": "active", "age": {"$gte": 18}}).limit(20)
```

**Redis**：
```
GET session:123
SCAN 0 MATCH session:* COUNT 50
```

**Memcached**：
```
GET session:123
MGET session:123 session:456
```

**Elasticsearch**：
```
POST /student_index/_search
{"query": {"bool": {"must": [{"term": {"status": "active"}}, {"range": {"age": {"gte": 18}}}]}}, "size": 20}
```

## 构建命令

```bash
cd ~/.codex/skills/db-query
bash scripts/build.sh
```

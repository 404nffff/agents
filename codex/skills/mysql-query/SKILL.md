---
name: mysql-query
description: 使用本地 mysql 命令连接 MySQL 并读取指定表数据。连接配置采用 `MYSQL_*_profile` 多库模式（例如 `MYSQL_HOST_main`），并通过 `--profile` 或 `MYSQL_PROFILE` 选择。用于“查表数据”“执行只读 SQL”场景。脚本会拒绝 DELETE 及其他写操作。
---

# MySQL Query

脚本目录：`~/.codex/skills/mysql-query/`（可直接使用绝对路径执行，无需先进入目录）

使用这个 skill 时，执行顺序必须是：

1. 先调用 `~/.codex/skills/mysql-query/scripts/mysql_query.php`
2. 如果 PHP 不可用或 PHP 调用失败，再降级调用 `~/.codex/skills/mysql-query/scripts/mysql_query.sh`

两个脚本都由本地 `mysql` 命令执行，且都带有 SQL 限制校验。

配置文件固定读取：运行目录下的 `config.env`（即 `~/.codex/skills/mysql-query/config.env`）。
`config.env` 为必需文件，不存在时脚本会直接报错退出。
默认输出为 JSON。作为本 skill 的强制规则，调用时必须返回 JSON，不允许使用 `--format table`。

SQL 校验规则支持在 `config.env` 配置（未配置则走默认规则）：
- `MYSQL_SQL_ALLOWED_START`
- `MYSQL_SQL_FORBIDDEN_KEYWORDS`
- `MYSQL_SQL_FORBIDDEN_PHRASES`（短语建议使用下划线，如 `into_outfile`）

## 快速开始

1. 读取指定表（推荐）：
```bash
php ~/.codex/skills/mysql-query/scripts/mysql_query.php --profile main --table users --limit 20
```

2. 执行只读 SQL：
```bash
php ~/.codex/skills/mysql-query/scripts/mysql_query.php --profile main --query "SELECT id, name FROM users WHERE status='active' LIMIT 20"
```

3. 选择多库 profile：
```bash
php ~/.codex/skills/mysql-query/scripts/mysql_query.php --profile reporting --table report_daily --limit 50
```

4. 降级方案（PHP 不可用时）：
```bash
bash ~/.codex/skills/mysql-query/scripts/mysql_query.sh --profile main --table report_daily --limit 50
```

## 连接配置优先级

优先级从高到低：

1. 命令行参数（`--host/--port/--user/--password/--database`）
2. `--profile` 选择的 profile 变量（如 `MYSQL_HOST_reporting`）
3. `MYSQL_PROFILE`（当未显式传 `--profile` 时）

## 多库配置规则

1. profile 名称需满足：`[A-Za-z_][A-Za-z0-9_]*`
2. profile 变量命名格式：`MYSQL_HOST_<profile>`、`MYSQL_PORT_<profile>`、`MYSQL_USER_<profile>`、`MYSQL_PASSWORD_<profile>`、`MYSQL_DATABASE_<profile>`、`MYSQL_SOCKET_<profile>`、`MYSQL_TIMEOUT_<profile>`
3. 可通过 `--profile` 显式指定，也可在配置中设置 `MYSQL_PROFILE` 作为默认 profile
4. 指定了 `--profile` 但找不到对应变量时，脚本会报错 `profile not found`
5. 不再使用 `MYSQL_HOST` 这类默认连接键，只使用 profile 键（`MYSQL_HOST_<profile>`）

## 读表模式（推荐）

当你只需要读取某张表，优先使用结构化参数而不是手写 SQL：

```bash
php ~/.codex/skills/mysql-query/scripts/mysql_query.php \
  --profile main \
  --table orders \
  --columns id,customer_id,amount \
  --where "status = 'paid'" \
  --order-by "id DESC" \
  --limit 100
```

## 规则限制（详细版，默认值）

以下限制是强制执行，不满足即报错退出。

### 1) 语句级限制

1. 只允许只读语句开头：
`SELECT` / `SHOW` / `DESC` / `DESCRIBE` / `EXPLAIN` / `WITH`
2. 禁止写操作关键词：
`DELETE`、`INSERT`、`UPDATE`、`REPLACE`、`TRUNCATE`、`DROP`、`ALTER`、`CREATE`（仅允许 `SHOW CREATE`）、`GRANT`、`REVOKE`、`RENAME`、`MERGE`、`CALL`
3. 禁止高风险模式：
`INTO OUTFILE`、`INTO DUMPFILE`、`LOAD DATA`、`LOCK TABLES`、`UNLOCK TABLES`
4. 禁止多语句执行：
只允许单条 SQL，`SELECT ...; DELETE ...` 会被拒绝

### 2) 参数级限制（结构化读表模式）

1. `--table` 只允许标识符格式：`[A-Za-z_][A-Za-z0-9_]*`
2. `--columns`（非 `*` 时）每个列名都必须满足同样标识符格式
3. `--limit` 必须在 `1-1000` 范围内
4. `--max-rows` 必须大于 `0`（默认 `2000`）

### 3) 结果级限制

1. 查询执行后如果返回行数超过 `--max-rows`，会直接报错
2. 返回结果统一按行数统计并应用 `--max-rows` 限制

### 4) 失败行为

1. 命中任一限制时，脚本输出 `ERROR: ...` 并以非 0 退出
2. SQL 在本地预校验阶段失败时，不会连接数据库执行

### 5) 示例

允许：
```bash
php ~/.codex/skills/mysql-query/scripts/mysql_query.php --query "SELECT id, name FROM users LIMIT 100"
```

拒绝（写操作）：
```bash
php ~/.codex/skills/mysql-query/scripts/mysql_query.php --query "DELETE FROM users WHERE id=1"
```

拒绝（多语句）：
```bash
php ~/.codex/skills/mysql-query/scripts/mysql_query.php --query "SELECT * FROM users; DELETE FROM users"
```

拒绝（文件写出）：
```bash
php ~/.codex/skills/mysql-query/scripts/mysql_query.php --query "SELECT * FROM users INTO OUTFILE '/tmp/u.csv'"
```

## 输出格式

默认输出 JSON，结构为：
- `query`
- `row_count`
- `columns`
- `rows`

强制规则（本 skill 必须遵守）：
1. 所有调用必须返回 JSON。
2. 禁止使用 `--format table`。
3. 如需显式声明格式，仅允许 `--format json`。

## 脚本入口

主脚本：`~/.codex/skills/mysql-query/scripts/mysql_query.php`  
降级脚本：`~/.codex/skills/mysql-query/scripts/mysql_query.sh`

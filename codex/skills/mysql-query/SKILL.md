---
name: mysql-query
description: 使用本地 mysql 命令连接 MySQL 并读取指定表数据。连接配置采用 `MYSQL_*_profile` 多库模式（例如 `MYSQL_HOST_main`），并通过 `--profile` 或 `MYSQL_PROFILE` 选择。用于“查表数据”“执行只读 SQL”场景。脚本会拒绝 DELETE 及其他写操作。
---

# MySQL Query

使用这个 skill 时，执行顺序必须是：

1. 先调用 `scripts/mysql_query.php`
2. 如果 PHP 不可用或 PHP 调用失败，再降级调用 `scripts/mysql_query.sh`

两个脚本都由本地 `mysql` 命令执行，且都带有 SQL 限制校验。

配置文件固定读取：`mysql-query` skill 根目录下的 `config.env`（即 `codex/skills/mysql-query/config.env`）。
`config.env` 为必需文件，不存在时脚本会直接报错退出。

## 快速开始

1. 准备配置文件（可从 `config.example.env` 复制为 `config.env`）：
```bash
# 指定默认 profile（推荐）
MYSQL_PROFILE=main

# 多库 profile
MYSQL_HOST_main=43.136.216.167
MYSQL_PORT_main=3306
MYSQL_USER_main=rsync
MYSQL_PASSWORD_main=your_password
MYSQL_DATABASE_main=rsync
MYSQL_TIMEOUT_main=15

MYSQL_HOST_reporting=43.136.216.167
MYSQL_PORT_reporting=3306
MYSQL_USER_reporting=report_user
MYSQL_PASSWORD_reporting=report_password
MYSQL_DATABASE_reporting=report_db
MYSQL_TIMEOUT_reporting=15
```

2. 读取指定表（推荐）：
```bash
php scripts/mysql_query.php --profile main --table users --limit 20
```

3. 执行只读 SQL：
```bash
php scripts/mysql_query.php --profile main --query "SELECT id, name FROM users WHERE status='active' LIMIT 20"
```

4. 选择多库 profile：
```bash
php scripts/mysql_query.php --profile reporting --table report_daily --limit 50
```

5. 降级方案（PHP 不可用时）：
```bash
bash scripts/mysql_query.sh --profile main --table report_daily --limit 50
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
php scripts/mysql_query.php \
  --profile main \
  --table orders \
  --columns id,customer_id,amount \
  --where "status = 'paid'" \
  --order-by "id DESC" \
  --limit 100
```

## 规则限制（详细版）

以下限制是强制执行，不满足即报错退出。

### 1) 语句级限制

1. 只允许只读语句开头：
`SELECT` / `SHOW` / `DESC` / `DESCRIBE` / `EXPLAIN` / `WITH`
2. 禁止写操作关键词：
`DELETE`、`INSERT`、`UPDATE`、`REPLACE`、`TRUNCATE`、`DROP`、`ALTER`、`CREATE`、`GRANT`、`REVOKE`、`RENAME`、`MERGE`、`CALL`
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
php scripts/mysql_query.php --query "SELECT id, name FROM users LIMIT 100"
```

拒绝（写操作）：
```bash
php scripts/mysql_query.php --query "DELETE FROM users WHERE id=1"
```

拒绝（多语句）：
```bash
php scripts/mysql_query.php --query "SELECT * FROM users; DELETE FROM users"
```

拒绝（文件写出）：
```bash
php scripts/mysql_query.php --query "SELECT * FROM users INTO OUTFILE '/tmp/u.csv'"
```

## 输出格式

默认输出本地 `mysql --batch --raw` 的表格文本（TSV）。

## 脚本入口

主脚本：`scripts/mysql_query.php`  
降级脚本：`scripts/mysql_query.sh`

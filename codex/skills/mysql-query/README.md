# mysql-query Skill

日期：2026-03-18  
执行者：Codex

## 说明

`mysql-query` 是一个基于本地 `mysql` 命令的查询 skill，用于安全读取 MySQL 表数据。

核心特性：

- 支持 `config.env` 的 `MYSQL_*_<profile>` 多库配置
- 支持 `--profile` 多库切换（或使用 `MYSQL_PROFILE` 默认 profile）
- 调用顺序：先 `php`，失败降级 `shell`
- 仅允许只读 SQL
- 拦截 `DELETE` 及其他写操作

固定配置文件路径：`codex/skills/mysql-query/config.env`
`config.env` 为必需文件，缺失时脚本会直接失败。

## 目录结构

- `SKILL.md`：Skill 触发与使用规范
- `scripts/mysql_query.php`：主执行脚本（PHP，优先）
- `scripts/mysql_query.sh`：降级脚本（Shell）
- `config.example.env`：配置模板

## 快速开始

1. 复制模板：

```bash
cp codex/skills/mysql-query/config.example.env codex/skills/mysql-query/config.env
```

2. 读取表数据（优先 PHP）：

```bash
php codex/skills/mysql-query/scripts/mysql_query.php \
  --profile main \
  --table users \
  --limit 20
```

3. 执行只读 SQL：

```bash
php codex/skills/mysql-query/scripts/mysql_query.php \
  --profile main \
  --query "SELECT id, name FROM users LIMIT 20"
```

4. PHP 不可用时降级 Shell：

```bash
bash codex/skills/mysql-query/scripts/mysql_query.sh \
  --profile main \
  --query "SELECT id, name FROM users LIMIT 20"
```

## 多库配置（Profile）

在 `config.env` 中按命名规则配置：

- `MYSQL_PROFILE`（推荐，默认 profile）
- `MYSQL_HOST_<profile>`
- `MYSQL_PORT_<profile>`
- `MYSQL_USER_<profile>`
- `MYSQL_PASSWORD_<profile>`
- `MYSQL_DATABASE_<profile>`

示例：

```bash
MYSQL_PROFILE=reporting
MYSQL_HOST_reporting=127.0.0.1
MYSQL_PORT_reporting=3306
MYSQL_USER_reporting=report_user
MYSQL_PASSWORD_reporting=report_password
MYSQL_DATABASE_reporting=report_db
```

使用：

```bash
php codex/skills/mysql-query/scripts/mysql_query.php \
  --profile reporting \
  --table report_daily \
  --limit 50
```

说明：
- 不再使用 `MYSQL_HOST` 这类默认连接键
- 未传 `--profile` 时，脚本会读取 `MYSQL_PROFILE`

## 限制规则

- 只允许：`SELECT / SHOW / DESC / DESCRIBE / EXPLAIN / WITH`
- 禁止：`DELETE / INSERT / UPDATE / DROP / ALTER` 等写操作
- 禁止多语句执行（例如 `SELECT ...; DELETE ...`）
- 支持 `--max-rows` 限制结果行数，避免一次性返回过大

## 常见问题

- 报错 `profile not found`：检查 `--profile` 对应的 `MYSQL_*_<profile>` 是否存在
- 报错 `only read-only SQL is allowed`：SQL 含写操作或非只读起始语句
- 报错 `multiple SQL statements are not allowed`：SQL 中包含多个语句分隔符

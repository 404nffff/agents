# db-query Skill 实施计划

日期：2026-03-20  
执行者：Codex

## 1. 目标

在 `codex/skills/db-query` 新建一个基于 Go 的统一数据库查询 skill，支持：

- Redis
- MySQL
- MongoDB
- PostgreSQL

本阶段仅交付计划与任务拆分，后续按计划进入编码实现。

## 2. 设计原则

- 复用 `mysql-query` 的可验证模式：统一参数风格、只读约束、标准 JSON 输出。
- 一套 CLI 契约，四种数据库通过适配器解耦。
- 默认只读，不提供写入类操作。
- 小步交付：先 CLI 核心与 SQL 类数据库，再扩展 Mongo/Redis。
- 源码放在 `scripts/`，Skill 最终运行入口必须是 `bin/` 中对应平台的打包二进制。
- `bin` 目录同时保留 Windows/Linux 两个版本，运行时必须判断平台后选择对应二进制。

## 3. 目录规划（Go）

```text
codex/skills/db-query/
├── PLAN.md
├── SKILL.md
├── README.md
├── config.example.env
├── bin/
│   ├── db-query-linux-amd64
│   └── db-query-windows-amd64.exe
├── scripts/
│   ├── go.mod
│   ├── cmd/
│   │   └── db_query/
│   │       └── main.go
│   ├── internal/
│   │   ├── cli/
│   │   ├── core/
│   │   ├── config/
│   │   └── adapters/
│   │       ├── mysql/
│   │       ├── pgsql/
│   │       ├── mongo/
│   │       └── redis/
│   └── tests/
│       ├── unit/
│       ├── integration/
│       └── smoke/
└── scripts/build.sh
```

## 4. CLI 契约（计划版）

### 4.1 通用参数

- `--driver <mysql|pgsql|mongo|redis>`
- `--profile <name>`
- `--database <name>`（MySQL / PostgreSQL / MongoDB）
- `--query <statement_or_expression>`
- `--limit <n>`（默认 100）
- `--max-rows <n>`（默认 2000）
- `--timeout <sec>`
- `--format json`（仅允许 JSON）

### 4.2 示例

```bash
# Linux
./bin/db-query-linux-amd64 --driver mysql --profile main --query "SELECT id,name FROM users LIMIT 20"

# Windows
.\bin\db-query-windows-amd64.exe --driver mysql --profile main --query "SELECT id,name FROM users LIMIT 20"
```

## 5. 统一输出规范

### 5.1 成功输出

```json
{
  "driver": "mysql",
  "profile": "main",
  "query": "SELECT id,name FROM users LIMIT 20",
  "row_count": 2,
  "columns": ["id", "name"],
  "rows": [
    {"id": 1, "name": "alice"},
    {"id": 2, "name": "bob"}
  ],
  "meta": {
    "elapsed_ms": 12
  }
}
```

### 5.2 失败输出

```json
{
  "error": {
    "code": "INVALID_QUERY",
    "message": "forbidden operation detected",
    "driver": "mongo"
  }
}
```

## 6. 只读边界（计划约束）

- MySQL / PostgreSQL：
  - 仅允许只读语句（`SELECT` / `SHOW` / `DESC` / `EXPLAIN` / `WITH`）。
  - 禁止多语句与 DDL/DML。
- MongoDB：
  - 仅允许 `find`、只读 `aggregate`。
  - 禁止 `$out`、`$merge` 等写入阶段。
- Redis：
  - 白名单命令：`GET`、`MGET`、`HGET`、`HGETALL`、`SMEMBERS`、`ZRANGE`、`LRANGE`、`SCAN`。
  - 禁止 `SET`、`DEL`、`EXPIRE`、`EVAL` 等写/高风险命令。

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

## 7. 测试计划

- 单元测试（`tests/unit`）：
  - 参数解析、只读校验、错误映射、输出格式化。
- 集成测试（`tests/integration`）：
  - 四类适配器连接与查询通路（使用可配置测试环境）。
- 冒烟测试（`tests/smoke`）：
  - 每个 driver 至少 1 个正向读查询 + 1 个非法查询拦截。

## 8. 里程碑

1. M1：完成 `scripts/` Go 工程骨架、统一 CLI、核心类型与输出模型。
2. M2：完成 MySQL + PostgreSQL 适配器与 SQL 只读校验。
3. M3：完成 MongoDB + Redis 适配器与各自只读规则。
4. M4：完成打包流程（`scripts/build.sh`）并产出双二进制：`bin/db-query-linux-amd64`、`bin/db-query-windows-amd64.exe`。
5. M5：完成运行时平台判断（Windows/Linux）与二进制分发选择逻辑。
6. M6：补齐测试矩阵、文档与使用示例，完成验收。

## 9. 已拆分任务（执行顺序）

1. `27fa3b43-a72f-49b0-bbed-e176c9025a0e` 盘点 mysql-query 可复用模式
2. `469f0918-21a5-4696-bc2f-6ace56f68773` 定义 db-query Go 架构与接口契约
3. `b8bfb1ce-7994-45b7-8df0-8036989d778a` 制定只读边界与错误处理策略
4. `f7710770-d237-4815-abde-18469efcb874` 制定测试矩阵与里程碑
5. `414bb3f3-8453-429c-a08b-506eb779888b` 落地 db-query 计划文档

## 10. 验收标准

- `PLAN.md` 可直接指导实现，包含目标、架构、接口、边界、测试、里程碑。
- 明确四类数据库的只读策略与统一 JSON 契约。
- 后续进入编码时可按里程碑逐步落地，且每步可独立验证。
- Go 源码位于 `scripts/`，Skill 运行入口使用打包后的 `bin` 命令，不直接运行源码命令。
- DDL/DML 请求必须转 `.sql` 文件交付，不允许直接执行。
- 运行时必须判断平台并选择 Linux/Windows 对应二进制。

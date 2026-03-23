# Skills Catalog

本文件用于 `codex/install.sh` 在远程模式下先展示 skills 列表。
新增或调整 skill 时，请同步更新下方目录清单。

<!-- SKILL_CATALOG_START -->
| Name | Directory | Description |
| --- | --- | --- |
| day-log | day-log | 根据当前会话内容生成日报 markdown，样式对齐 day_log 模板，并写入当前启动目录。 |
| db-query | db-query | 使用 Go 打包二进制查询 Redis/MySQL/MongoDB/PostgreSQL。配置采用 `<DRIVER>_*_<profile>` 多库模式（例如 `MYSQL_HOST_main`、`REDIS_ADDR_cache`），通过 `--profile` 或 `DB_PROFILE` 选择。默认只允许只读查询，并强制输出 JSON。 |
| exa-search | exa-search | Neural web search for source-first research, especially official docs, API references, pricing pages, product specs, company pages, and any task where low-noise results and direct text extraction matter. Use when you need precise, high-quality, non-SEO-biased web results or extracted page text/highlights. Prefer this over generic web search for official documentation and structured source retrieval. Prefer grok-search instead for breaking news, X/Twitter dynamics, real-time sentiment, or broad multi-source live synthesis. |
| file-naming-helper | file-naming-helper | 根据中文描述生成英文文件名。当用户提到命名、起名、文件名、英文名等关键词时使用此 Skill。 |
| git-commit-helper | git-commit-helper | 根据 Git 历史生成提交信息。当用户提到 commit、提交、git 提交等关键词，或在 git add 后准备提交时使用此 Skill。 |
| grok-search | grok-skill | Real-time web research/search with sources (outputs JSON). |
| mysql-query | mysql-query | 使用本地 mysql 命令连接 MySQL 并读取指定表数据。连接配置采用 `MYSQL_*_profile` 多库模式（例如 `MYSQL_HOST_main`），并通过 `--profile` 或 `MYSQL_PROFILE` 选择。用于“查表数据”“执行只读 SQL”场景。脚本会拒绝 DELETE 及其他写操作。 |
<!-- SKILL_CATALOG_END -->


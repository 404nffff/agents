# Skills Catalog

本文件用于 `codex/install.sh` 在远程模式下先展示 skills 列表。
新增或调整 skill 时，请同步更新下方目录清单。
`Directory` 字段支持二级目录路径（例如 `superpowers/using-superpowers`）。

<!-- SKILL_CATALOG_START -->
| Name | Directory | Description |
| --- | --- | --- |
| 代理浏览器 | agent-browser | 面向 AI Agent 的浏览器自动化 CLI。当用户需要与网站交互时使用，包括页面导航、表单填写、按钮点击、截图、数据提取、Web 应用测试或任意浏览器自动化任务。触发场景包括“打开网站”“填写表单”“点击按钮”“截图”“抓取页面数据”“测试这个 Web 应用”“登录网站”“自动化浏览器操作”等所有需要程序化网页交互的请求。 |
| day-log | day-log | 根据当前会话内容生成日报 markdown，样式对齐 day_log 模板，并写入当前启动目录。 |
| db-query | db-query | 使用 Go 打包二进制查询 Redis/MySQL/MongoDB/PostgreSQL。配置采用 `<DRIVER>_*_<profile>` 多库模式（例如 `MYSQL_HOST_main`、`REDIS_ADDR_cache`），通过 `--profile` 或 `DB_PROFILE` 选择。默认只允许只读查询，并强制输出 JSON。 |
| docx | docx | Use this skill whenever the user wants to create, read, edit, or manipulate Word documents (.docx files). Triggers include: any mention of 'Word doc', 'word document', '.docx', or requests to produce professional documents with formatting like tables of contents, headings, page numbers, or letterheads. Also use when extracting or reorganizing content from .docx files, inserting or replacing images in documents, performing find-and-replace in Word files, working with tracked changes or comments, or converting content into a polished Word document. If the user asks for a 'report', 'memo', 'letter', 'template', or similar deliverable as a Word or .docx file, use this skill. Do NOT use for PDFs, spreadsheets, Google Docs, or general coding tasks unrelated to document generation. |
| exa-search | exa-search | 面向“来源优先”研究场景的语义 Web 搜索能力，尤其适用于官方文档、API 参考、价格页面、产品规格、公司官网，以及任何需要低噪声结果和直接提取正文的任务。当你需要高精度、高质量、非 SEO 噪声导向的搜索结果，或需要获取页面正文/高亮内容时优先使用。相比通用搜索，它更适合官方文档与结构化资料检索；对于突发新闻、X/Twitter 动态、实时舆情或多来源实时综合分析，应优先使用 grok-search。 |
| feishu-agent-browser | feishu-agent-browser | 当需要直接提供飞书 cookie 和 URL 打开飞书页面，或复用 agent-browser 保存的飞书登录态来打开飞书文档、知识库页面、提取正文与截图时使用。 |
| file-naming-helper | file-naming-helper | 根据中文描述生成英文文件名。当用户提到"命名"、"起名"、"文件名"、"英文名"等关键词时使用此 Skill |
| frontend-design | frontend-design | 创建具有强辨识度、可用于生产环境的高质量前端界面。当用户要求构建网页组件、页面、作品、海报或应用（例如网站、落地页、仪表盘、React 组件、HTML/CSS 布局，或对任意 Web UI 进行样式优化）时使用本技能。输出富有创意且精致的代码与界面设计，避免通用化 AI 审美。 |
| git-add-check | git-add-check | 检查已暂存（git add）的代码是否存在语法错误，输出汇总报告并以退出码表示是否通过。 |
| git-commit-helper | git-commit-helper | 根据 Git 历史生成提交信息。当用户提到"commit"、"提交"、"git 提交"等关键词，或在 git add 后准备提交时使用此 Skill |
| git-merge | git-merge | 在 develop_dir 中按 git log 与作者筛选提交，生成改动计划，用户确认后自动把改动写入 master_dir。 |
| grok-search | grok-skill | Real-time web research/search with sources (outputs JSON). |
| lanhu-plan | lanhu-plan | 使用 lanhu-mcp 拉取蓝湖/Axure 页面信息并生成页面级执行文档。执行前必须先检测输入链接。 |
| mysql-query | mysql-query | 使用本地 mysql 命令连接 MySQL 并读取指定表数据。连接配置采用 `MYSQL_*_profile` 多库模式（例如 `MYSQL_HOST_main`），并通过 `--profile` 或 `MYSQL_PROFILE` 选择。用于“查表数据”“执行只读 SQL”场景。脚本会拒绝 DELETE 及其他写操作。 |
| vercel-react-best-practices | react-best-practices | React and Next.js performance optimization guidelines from Vercel Engineering. This skill should be used when writing, reviewing, or refactoring React/Next.js code to ensure optimal performance patterns. Triggers on tasks involving React components, Next.js pages, data fetching, bundle optimization, or performance improvements. |
| brainstorming | superpowers/brainstorming | 在任何创造性工作前必须使用：例如创建功能、构建组件、增加能力或修改行为；用于在实现前探索用户意图、需求与设计。 |
| dispatching-parallel-agents | superpowers/dispatching-parallel-agents | 当面对 2 个及以上彼此独立、无需共享状态或顺序依赖的任务时使用。 |
| executing-plans | superpowers/executing-plans | 当你已有书面的实现计划，并需要在独立会话中执行且带评审检查点时使用。 |
| finishing-a-development-branch | superpowers/finishing-a-development-branch | 当实现已完成、测试全通过，且需要决定如何集成这项工作时使用；通过结构化选项指导合并、提 PR 或清理收尾。 |
| receiving-code-review | superpowers/receiving-code-review | 在收到代码评审反馈、尤其反馈不清晰或技术上可疑时，在落实建议前使用；强调技术严谨与验证，而非形式化认同或盲目照做。 |
| requesting-code-review | superpowers/requesting-code-review | 在任务完成、实现重大功能或合并前，为确认工作满足需求时使用。 |
| subagent-driven-development | superpowers/subagent-driven-development | 当在当前会话中执行包含独立任务的实现计划时使用。 |
| systematic-debugging | superpowers/systematic-debugging | 在遇到任何 bug、测试失败或异常行为时，在提出修复方案前使用。 |
| test-driven-development | superpowers/test-driven-development | 在实现任何功能或修复 bug 时、在编写实现代码前使用。 |
| using-git-worktrees | superpowers/using-git-worktrees | 在开始需要与当前工作区隔离的功能开发，或执行实现计划前使用；可通过智能目录选择与安全校验创建隔离 worktree。 |
| using-superpowers | superpowers/using-superpowers | 在任何会话开始时使用；用于建立如何查找和使用技能的流程，并要求在任何响应（包括澄清问题）前先调用 Skill 工具。 |
| verification-before-completion | superpowers/verification-before-completion | 在准备声明“工作已完成/已修复/已通过”时（提交或创建 PR 前）使用；要求先运行验证命令并确认输出，先证据后结论。 |
| writing-plans | superpowers/writing-plans | 当你已有规格或需求、且任务是多步骤时，在动代码前使用。 |
| writing-skills | superpowers/writing-skills | 在创建新技能、编辑已有技能，或上线前验证技能可用性时使用。 |
| tailwind-design-system | tailwind-design-system | 使用 Tailwind CSS v4、设计令牌、组件变体与响应式模式构建可扩展设计系统，适用于组件库建设、UI 规范统一与 v3 到 v4 迁移。 |
| web-design-guidelines | web-design-guidelines | 按 Web Interface Guidelines 审查 UI 代码合规性。适用于“审查 UI”“检查可访问性”“做设计/UX 审计”等场景。 |
<!-- SKILL_CATALOG_END -->

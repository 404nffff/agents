# Skills 目录

本目录包含各类 Skill 扩展包，为 AI Agent 提供专业能力。

## 使用说明

- **Codex 用户:** 使用 `install_codex.sh skills` 交互式选择安装
- **Claude Code 用户:** 复制 skill 目录到 `.claude/skills/` 或 `~/.claude/skills/`
- **OpenClaw 用户:** 复制 skill 目录到对应的 skills 路径
- **维护者:** 新增或修改 Skill 时，请同步更新下方目录清单

## Skill 结构要求

每个 Skill 必须包含：
- `SKILL.md` - 主文件，包含 frontmatter（name、description）
- 其他支持文件（可选）

## 目录字段说明

| 字段 | 说明 |
| --- | --- |
| **Name** | Skill 名称（来自 `SKILL.md` frontmatter） |
| **Directory** | 相对于 `skills/` 的目录路径 |
| **Description** | 触发场景和核心能力说明 |

---

---

## Skills 目录

<!-- SKILL_CATALOG_START -->

### 开发工具

| Name | Directory | Description |
| --- | --- | --- |
| git-commit-helper | git-commit-helper | 根据 Git 历史生成提交信息，触发词：commit、提交、git 提交 |
| git-add-check | git-add-check | 检查已暂存代码的语法错误，输出汇总报告 |
| git-merge | git-merge | 按 git log 与作者筛选提交，生成改动计划并自动合并 |
| file-naming-helper | file-naming-helper | 根据中文描述生成英文文件名，触发词：命名、起名、文件名 |
| day-log | day-log | 根据当前会话生成日报 markdown |

### 沟通模式

| Name | Directory | Description |
| --- | --- | --- |
| caveman | caveman | 超压缩沟通模式，触发词：caveman mode、talk like caveman、use caveman、less tokens、be brief、/caveman |

### 数据库查询

| Name | Directory | Description |
| --- | --- | --- |
| db-query | db-query | 查询 Redis/MySQL/MongoDB/PostgreSQL/Elasticsearch，支持多库配置，只读模式，输出 JSON |
| mysql-query | mysql-query | 使用本地 mysql 命令查询 MySQL，支持多库配置，拒绝写操作 |

### 浏览器自动化

| Name | Directory | Description |
| --- | --- | --- |
| 代理浏览器 | agent-browser | 浏览器自动化 CLI，支持页面导航、表单填写、截图、数据提取、Web 测试 |
| feishu-agent-browser | feishu-agent-browser | 飞书页面自动化，支持 cookie 登录、文档提取、截图 |

### 搜索与研究

| Name | Directory | Description |
| --- | --- | --- |
| grok-search | grok-skill | 实时网络搜索，输出 JSON 格式结果 |
| exa-search | exa-search | 语义 Web 搜索，适合官方文档、API 参考、产品规格等高质量来源 |
| ai-localbase | ai-localbase | 通过单文件 Bash / PowerShell 入口调用 ai_localbase 的 MCP HTTP 接口，支持按目录自动管理知识库并执行检索与问答 |
| ai-localbase-background | ai-localbase-background | 在启用 ai_localbase 的项目里会话启动即加载；同步检索，写入可按需走后台队列，无 Python 时自动回退同步 |

### 角色选择

| Name | Directory | Description |
| --- | --- | --- |
| who | who | 根据用户任务自动选取最匹配的专业角色，覆盖工程、设计、研究、审查、运维、安全、AI、数据、文档等场景 |

### 前端开发

| Name | Directory | Description |
| --- | --- | --- |
| frontend-design | frontend-design | 创建高质量前端界面，支持网页组件、页面、仪表盘、React 组件 |
| vercel-react-best-practices | react-best-practices | React 和 Next.js 性能优化指南（来自 Vercel Engineering） |
| tailwind-design-system | tailwind-design-system | 使用 Tailwind CSS v4 构建可扩展设计系统 |
| web-design-guidelines | web-design-guidelines | 按 Web Interface Guidelines 审查 UI 代码合规性和可访问性 |

### 动画开发

GSAP 子技能总索引见 `gsap-skills/llms.md`。

| Name | Directory | Description |
| --- | --- | --- |
| gsap-core | gsap-skills/gsap-core | GSAP 核心 API：`gsap.to()` / `from()` / `fromTo()`、缓动、时长、stagger、transform、autoAlpha、响应式与 reduced-motion |
| gsap-timeline | gsap-skills/gsap-timeline | GSAP 时间线：`gsap.timeline()`、position parameter、标签、嵌套、播放控制和多步骤动画编排 |
| gsap-scrolltrigger | gsap-skills/gsap-scrolltrigger | ScrollTrigger：滚动触发、pin 固定、scrub 拖动、触发点、刷新和清理 |
| gsap-plugins | gsap-skills/gsap-plugins | GSAP 插件：ScrollTo、ScrollSmoother、Flip、Draggable、SplitText、ScrambleText、SVG、CustomEase、GSDevTools 等 |
| gsap-utils | gsap-skills/gsap-utils | `gsap.utils` 工具：clamp、mapRange、normalize、interpolate、random、snap、toArray、wrap、pipe |
| gsap-react | gsap-skills/gsap-react | React / Next.js 动画：`useGSAP`、refs、`gsap.context()`、组件卸载清理和 SSR 注意事项 |
| gsap-performance | gsap-skills/gsap-performance | GSAP 性能优化：优先 transform、避免布局抖动、will-change、批处理和 ScrollTrigger 性能建议 |
| gsap-frameworks | gsap-skills/gsap-frameworks | Vue、Nuxt、Svelte 等框架动画：生命周期、选择器作用域、组件卸载清理 |

### 文档处理

| Name | Directory | Description |
| --- | --- | --- |
| docx | docx | 创建、读取、编辑 Word 文档（.docx），支持格式化、表格、图片等 |
| lanhu-plan | lanhu-plan | 使用 lanhu-mcp 拉取蓝湖/Axure 页面信息并生成执行文档 |

### 图像生成

| Name | Directory | Description |
| --- | --- | --- |
| codex-gateway-imagegen | codex-gateway-imagegen | 通过兼容网关生成或编辑位图图像 |

### 软件开发流程

| Name | Directory | Description |
| --- | --- | --- |
| software-dev-process | software-dev-process | 管理完整 SDLC（需求、设计、实现、测试、调试），支持分阶段或全自动执行 |
| software-dev-process-roles | software-dev-process-roles | 管理完整 SDLC，并在各阶段结合 `skills/who/` 角色库进行角色选择与任务执行 |
| software-dev-process-mutil-agent | software-dev-process-mutil-agent | 管理完整 SDLC，并在各阶段结合角色选择与子代理派发执行任务 |
| sdlc-doc-implementation | sdlc-doc-implementation | 严格按 `docs/[任务目录]/` 中的文档执行施工、测试、调试 |

### Superpowers 系列

| Name | Directory | Description |
| --- | --- | --- |
| using-superpowers | superpowers/using-superpowers | 会话开始时使用，建立技能查找和使用流程 |
| brainstorming | superpowers/brainstorming | 创造性工作前必用，探索用户意图、需求与设计 |
| writing-plans | superpowers/writing-plans | 多步骤任务开始前，编写实现计划 |
| executing-plans | superpowers/executing-plans | 在独立会话中执行书面计划，带评审检查点 |
| subagent-driven-development | superpowers/subagent-driven-development | 在当前会话中执行包含独立任务的实现计划 |
| dispatching-parallel-agents | superpowers/dispatching-parallel-agents | 面对 2+ 独立任务时，并行分派 |
| test-driven-development | superpowers/test-driven-development | 实现功能或修复 bug 前，先编写测试 |
| systematic-debugging | superpowers/systematic-debugging | 遇到 bug、测试失败或异常时，系统化调试 |
| verification-before-completion | superpowers/verification-before-completion | 声明完成前，先运行验证命令确认 |
| requesting-code-review | superpowers/requesting-code-review | 任务完成或合并前，请求代码评审 |
| receiving-code-review | superpowers/receiving-code-review | 收到评审反馈时，技术验证后再落实 |
| using-git-worktrees | superpowers/using-git-worktrees | 功能开发前，创建隔离的 git worktree |
| finishing-a-development-branch | superpowers/finishing-a-development-branch | 实现完成、测试通过后，决定如何集成工作 |
| writing-skills | superpowers/writing-skills | 创建或编辑技能，验证可用性 |

<!-- SKILL_CATALOG_END -->

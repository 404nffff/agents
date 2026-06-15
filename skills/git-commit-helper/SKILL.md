---
name: git-commit-helper
description: 根据 Git 历史生成提交信息。当用户提到"commit"、"提交"、"git 提交"等关键词，或在 git add 后准备提交时使用此 Skill
---

# Git Commit Helper

根据项目的 Git 历史提交信息风格，为当前暂存区的内容生成合适的提交信息。

## 执行步骤

1. 优先在项目根目录执行脚本：

```bash
bash skills/git-commit-helper/scripts/generate_commit_message.sh
```

2. 脚本会自动读取暂存区文件、变更统计、关键 diff 和最近 10 条提交记录。
3. 脚本在生成标题前必须检查暂存区是否包含秘钥或敏感信息，命中时直接失败，只输出文件名和命中规则，禁止输出具体敏感值。
4. 若配置了第三方 AI，则脚本必须调用 OpenAI 兼容接口润色提交标题；未配置时使用本地规则生成。
5. 脚本输出仅作为“提交标题初稿”。最终回复必须再结合暂存区规模判断是否需要补充详细正文。
6. 不执行 `git commit`。

## 暂存区复核要求

运行脚本前后都必须复核当前暂存区，避免多模块变更被压缩成过窄标题：

```bash
git diff --cached --name-status
git diff --cached --stat
git diff --cached --summary
```

复核规则：

- 若脚本报告暂存区疑似包含秘钥、Token、密码、私钥或敏感文件路径，必须先要求用户移除或取消暂存相关内容，不得生成提交信息，不得复述敏感值。
- 若暂存文件跨 2 个及以上一级模块，必须生成覆盖整体范围的提交标题。
- 若暂存文件超过 8 个，或新增/修改超过 300 行，默认输出“标题 + 详细正文”。
- 若脚本标题只覆盖其中一个模块，必须人工改写为覆盖所有主要模块的标题。
- 若用户明确要求“一行”“标题”“subject”，才只输出一行标题。
- 若用户要求“详细点”“完整点”“commit message”，必须输出可直接用于 `git commit` 的多行提交信息。

## 第三方 AI 润色配置

配置方式与 `day-log-v2` 保持一致：配置文件放在脚本目录，只读取同目录 `.env`，不扫描其他配置文件。

```bash
cp skills/git-commit-helper/scripts/.env.example skills/git-commit-helper/scripts/.env
```

`.env` 支持字段：

- `API_URL`
- `MODEL`
- `API_KEY`

命令行参数可临时覆盖 `.env`：

- `--ai-url`：OpenAI 兼容服务基础 URL 或完整 chat completion URL。
- `--ai-model`：模型名称。
- `--ai-key`：API Key。不建议直接写命令行。
- `--no-ai`：强制禁用外部 AI 润色。

AI 字段处理规则：

- 配置任一 AI 字段时，必须同时具备 `API_URL + MODEL + API_KEY`。
- `API_URL` 可传基础地址，也可传完整端点；基础地址自动拼接 `/v1/chat/completions`，完整端点兼容 `/v1/chat/completion`。
- 请求体使用 OpenAI 对话补全格式：`model`、`messages`、`temperature`。
- 响应读取 `choices[0].message.content`。
- AI 调用失败、响应非 JSON、缺少内容或标题过短时直接报错退出，不静默降级。
- Shell 脚本在 AI 模式下需要 `curl`，并需要 `python3`、`python` 或 `node` 任一可用来解析 JSON 响应。

## 暂存敏感信息检查

脚本必须在生成提交标题前检查暂存区：

- 检查暂存文件路径，拦截 `.env`、`.env.*`、`*.pem`、`*.key`、`*.p12`、`*.pfx`、常见 SSH 私钥文件、`credentials*.json`、`service-account*.json` 等敏感路径；`.env.example` 不拦截。
- 检查暂存 diff 的新增行，识别私钥块、AWS Access Key、GitHub Token、OpenAI 风格 Key、Slack Token、Bearer Token，以及 `api_key`、`secret`、`token`、`password` 等长值赋值。
- 命中时必须退出失败，仅输出命中的文件名或规则名，禁止输出匹配到的具体敏感内容。
- 敏感检查失败时，本次不得继续调用第三方 AI，避免把敏感 diff 发送到外部接口。

## 忽略规则

避免扫描以下锁文件以节省 token：
- pnpm-lock.yaml
- package-lock.json
- yarn.lock
- bun.lockb

## 生成规则

基于以上信息，生成符合项目风格的提交信息：

- 分析历史提交中常用的类型前缀（如 feat, fix, docs, style, :emoji: 等）
- 识别常用的动词和表达方式（中文或英文）
- 根据暂存区的变更类型（新增、修改、删除）选择合适的描述
- 若使用第三方 AI 润色，标题必须包含模块和具体变更意图，不能过短或只写泛化词
- 标题必须覆盖暂存区的主要模块和整体意图，不得只描述第一个命中文件或单一子模块
- 详细正文按模块分组，每条说明一个可验证的变更点，避免空泛词（如“优化若干内容”“更新文件”）
- 若无需要确认的信息，只回复提交信息，无需展示分析过程

## 输出格式

### 小范围变更

适用：单模块、文件数少、意图单一。

```git
:memo: 更新 git-commit-helper 提交信息生成规则
```

### 大范围或多模块变更

适用：跨模块、文件多、包含新增能力与测试。

```git
:sparkles: 完善 Codex Hook 插件、Docker 镜像与辅助技能工具链

- 新增 Codex Hook v8 AGENTS 模板，补充项目级执行约束
- 新增 Ubuntu 24.04 Codex Docker 镜像与 Compose 配置
- 扩展 codex_hook 事件分发、跨平台入口和配置说明
- 新增 session_title_v2 插件，支持基于 transcript 生成会话标题
- 新增 agents_guard 插件和配套测试，覆盖上下文注入处理
- 新增 day-log-v2 与 git-commit-helper 的 AI 辅助脚本能力
```

## GitMoji 图标规范

### 💻 功能与特性
- ✨ `:sparkles:` - 引入新的特性
- 🚀 `:rocket:` - 部署相关
- ⚡ `:zap:` - 性能改善
- 🎉 `:tada:` - 创世提交 / 庆祝
- 💡 `:bulb:` - 给源代码加文档 / 新想法
- 🔧 `:wrench:` - 改变配置文件
- 🤖 `:robot:` - 修复在安卓系统上的问题
- 🍏 `:green_apple:` - 修复在 iOS 系统上的问题

### 🐛 Bug 修复
- 🐛 `:bug:` - 修了一个 BUG
- 🚑️ `:ambulance:` - 重大热修复
- 🔒 `:lock:` - 修复安全问题
- 🟢 `:green_heart:` - 修复持续集成构建
- 🔄 `:rewind:` - 回滚改动
- 💥 `:boom:` - 引入破坏性的改动

### 📝 文档与类型
- 📝 `:memo:` - 写文档
- 📚 `:books:` - 添加/更新文档
- 🔤 `:abc:` - 添加/更新类型定义
- 🔍 `:mag:` - 改进搜索引擎优化 / 类型注释
- 🏷️ `:label:` - 添加或者更新类型（TypeScript）
- 📄 `:page_facing_up:` - 添加或者更新许可

### 🎨 样式与代码质量
- 🎨 `:art:` - 结构改进 / 格式化代码
- 💄 `:lipstick:` - 更新界面与样式文件
- ♻️ `:recycle:` - 代码重构
- ✅ `:white_check_mark:` - 更新测试
- 💪 `:ok_hand:` - 代码审核后更新代码
- 🚨 `:rotating_light:` - 消除 linter 警告

### 📦 依赖与构建
- ➕ `:heavy_plus_sign:` - 添加依赖
- ➖ `:heavy_minus_sign:` - 删除依赖
- 📦 `:package:` - 更新编译后的文件或者包
- 📌 `:pushpin:` - 固定依赖在特定的版本
- ⬆️ `:arrow_up:` - 升级依赖
- ⬇️ `:arrow_down:` - 降级依赖
- 🐳 `:whale:` - Docker 容器相关
- 🎛️ `:wheel_of_dharma:` - Kubernetes 相关的工作

### 🔧 系统与架构
- 🔥 `:fire:` - 删除代码或者文件
- 🚚 `:truck:` - 文件移动或者重命名
- 🏗️ `:building_construction:` - 架构改动
- 🌐 `:globe_with_meridians:` - 国际化与本地化
- 💽 `:card_file_box:` - 执行数据库相关的改动
- 👷 `:construction_worker:` - 添加持续集成构建系统
- 📊 `:chart_with_upwards_trend:` - 添加分析或者跟踪代码

### 🖥️ 平台兼容性
- 🍎 `:apple:` - 修复在苹果系统上的问题
- 🐧 `:penguin:` - 修复在 Linux 系统上的问题
- 🏁 `:checkered_flag:` - 修复在 Windows 系统上的问题
- 📱 `:iphone:` - 响应性设计相关
- 🤡 `:clown_face:` - 模拟相关

### 🧪 测试与质量保证
- ✅ `:white_check_mark:` - 更新测试
- 📸 `:camera_flash:` - 添加或者更新快照
- ⚗️ `:alembic:` - 研究新事物
- 🥚 `:egg:` - 添加一个彩蛋
- 🙈 `:see_no_evil:` - 添加或者更新 .gitignore 文件

### 📢 用户体验与沟通
- 👌 `:ok_hand:` - 代码审核后更新代码
- ♿ `:wheelchair:` - 改进可访问性
- 👥 `:busts_in_silhouette:` - 添加贡献者
- 🚸 `:children_crossing:` - 改进用户体验 / 可用性
- 💬 `:speech_balloon:` - 更新文本和字面
- 🔊 `:loud_sound:` - 添加日志
- 🔇 `:mute:` - 删除日志

### 🗑️ 代码清理
- 🔥 `:fire:` - 删除代码或者文件
- 🗑️ `:waste_basket:` - 删除废弃代码
- 💩 `:poop:` - 写需要改进的坏代码（技术债务）
- 🔄 `:repeat:` - 重构代码

### 🔀 分支与合并
- 🔄 `:twisted_rightwards_arrows:` - 合并分支
- 🔄 `:rewind:` - 回滚改动

### 📦 资源文件
- 🍱 `:bento:` - 添加或者更新静态资源

## 使用建议

- ✨ 用于新功能开发
- 🐛 用于 Bug 修复
- 💄 用于 UI 样式更新
- 📝 用于文档更新
- 🔧 用于配置文件修改
- 🚀 用于部署相关
- ♻️ 用于代码重构
- ➕/➖ 用于依赖管理

## 重要提示

只生成提交信息，不要执行 `git commit` 操作。多模块暂存区优先输出详细提交信息，不要只给脚本生成的一行标题。

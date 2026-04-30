---
name: git-commit-helper
description: 根据 Git 历史生成提交信息。当用户提到"commit"、"提交"、"git 提交"等关键词，或在 git add 后准备提交时使用此 Skill
---

# Git Commit Helper

根据项目的 Git 历史提交信息风格，为当前暂存区的内容生成合适的提交信息。

## 执行步骤

1. 使用 `git diff --cached --name-only` 获取暂存文件列表
2. 使用 `git diff --cached --stat` 获取变更统计
3. 使用 `git diff --cached` 获取具体的变更内容（如果内容较多，只看关键部分）
4. 使用 `git log --oneline -10` 获取最近 10 条提交记录，分析提交信息的风格和格式

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
- 若无需要确认的信息，只回复提交信息，无需展示其他内容

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

只生成提交信息，不要执行 git commit 操作。
# Taste Skill 技能索引

更新日期：2026-06-22  
执行者：Codex

本目录收录一组面向前端审美、界面生成、图片生成、品牌板与输出完整性的 Agent Skills。核心目标是降低 AI 生成界面的模板感，强化排版、布局、动效、图像使用、留白、色彩一致性和交付完整度。

## 快速选择

| 需求 | 推荐 skill | 安装名 | 输出类型 |
| --- | --- | --- | --- |
| 通用落地页、作品集、营销页、视觉改版 | `taste-skill` | `design-taste-frontend` | 代码 / 设计规则 |
| 需要沿用原始 v1 行为 | `taste-skill-v1` | `design-taste-frontend-v1` | 代码 / 设计规则 |
| 想要更激进的 Codex/GPT 高级前端与 GSAP 动效约束 | `gpt-tasteskill` | `gpt-taste` | 代码 / 设计规则 |
| 先生成参考图，再按图实现网站 | `image-to-code-skill` | `image-to-code` | 图片分析 + 代码 |
| 只生成网站设计参考图 | `imagegen-frontend-web` | `imagegen-frontend-web` | 图片 |
| 只生成移动 App 界面图或流程图 | `imagegen-frontend-mobile` | `imagegen-frontend-mobile` | 图片 |
| 生成品牌视觉系统、Logo 方向、品牌板 | `brandkit` | `brandkit` | 图片 |
| 改造已有项目 UI | `redesign-skill` | `redesign-existing-projects` | 审计 + 代码改造 |
| 高级柔和、昂贵、代理商感 UI | `soft-skill` | `high-end-visual-design` | 代码 / 设计规则 |
| 极简、编辑感、Notion/Linear 风格 UI | `minimalist-skill` | `minimalist-ui` | 代码 / 设计规则 |
| 工业、粗野主义、瑞士网格、战术终端 UI | `brutalist-skill` | `industrial-brutalist-ui` | 代码 / 设计规则 |
| 防止模型省略、占位、截断输出 | `output-skill` | `full-output-enforcement` | 输出约束 |
| 为 Google Stitch 生成语义设计系统 | `stitch-skill` | `stitch-design-taste` | `DESIGN.md` 规则 |

## 技能说明

### `taste-skill`

默认主技能，安装名 `design-taste-frontend`。适合落地页、作品集和视觉改版，不适合后台仪表盘、数据表格、多步表单、代码编辑器、原生移动端或实时协作复杂产品 UI。

关键机制：

- 先输出一句 Design Read，判断页面类型、受众、视觉语言和设计系统倾向。
- 使用 `DESIGN_VARIANCE`、`MOTION_INTENSITY`、`VISUAL_DENSITY` 三个拨盘决定布局、动效和密度。
- 遇到 Material、Fluent、Carbon、Polaris、Atlaskit、Primer、GOV.UK、USWDS 等明确体系时优先用官方包。
- 默认 React/Next.js、Tailwind v4、Motion，GSAP 只用于真正需要 pin、scrub、horizontal pan 的复杂滚动叙事。
- 严格禁止大量 AI 味模式：紫蓝霓虹、三等分卡片、假截图、装饰性 section 编号、hero 版本号、滚动提示、无意义状态点、em dash 等。
- 交付前必须跑完整 pre-flight checklist，检查主题一致、色彩一致、圆角体系、按钮对比、移动端、动效清理、真实图片、无重复布局等。

### `taste-skill-v1`

原始 v1 技能，安装名 `design-taste-frontend-v1`。保留旧版行为，用于已有工作流依赖 v1 的场景。

特点：

- 同样使用三拨盘：设计变化、动效强度、视觉密度。
- 强调 React/Next.js、Tailwind、Framer Motion、Phosphor 或 Radix 图标。
- 禁止常见 AI 默认值，如 Inter、AI 紫蓝、三列卡片、John Doe、Acme 等。
- 相比 v2，规则更短，更偏通用审美增强，缺少 v2 的官方设计系统映射、暗色协议、重设计流程和超细 pre-flight 检查。

### `gpt-tasteskill`

安装名 `gpt-taste`。这是更强硬的高端前端与 GSAP 动效约束，目标是 Awwwards 级视觉和更激进的反模板化输出。

适合：

- 想让 GPT/Codex 做更大胆的创意落地页。
- 需要强制 GSAP、pinning、stacking、scrubbing、horizontal motion 等高级动效。
- 需要规避窄容器 6 行标题、空洞 bento、廉价 section 标签、按钮对比不足等问题。

核心规则：

- 生成 UI 前输出 `<design_plan>`。
- 用模拟 Python RNG 选择 hero 架构、字体、组件架构和 GSAP 范式，避免重复默认布局。
- 页面按 AIDA：Navigation、Attention、Interest、Desire、Action。
- Hero 标题必须控制在 2 到 3 行以内。
- Bento 必须使用 `grid-flow-dense`，数学上不能留空洞。
- 禁止廉价 meta label，如 `SECTION 01`、`QUESTION 05`。

### `image-to-code-skill`

安装名 `image-to-code`。用于视觉重要的网站任务：先生成设计参考图，深度分析图，再按图实现代码。

工作流：

1. 先推断网站类型和 section 数量。
2. Codex 环境中优先每个 section 单独生成一张大图。
3. 如果文字、按钮、卡片细节不清楚，生成新的 section 图或细节图，而不是裁剪旧图。
4. 深度分析图片中的文字、排版、间距、按钮、色彩、组件、图片处理和布局节奏。
5. 最后实现前端，尽量忠实于参考图。

适合：

- 高质量营销页、品牌页、作品集、产品页。
- 用户要求“好看”“高级”“重设计”“按图做”的场景。

不适合：

- 纯技术修复。
- 已有明确设计系统或明确设计稿的任务。

### `imagegen-frontend-web`

安装名 `imagegen-frontend-web`。只生成网站设计参考图，不写代码。

核心规则：

- 一个 section 生成一张横向图，绝不把多个 section 压成一张长图或拼贴图。
- landing page 默认 6 个 section，full website 默认 8 个 section。
- 避免默认左文右图 hero，优先考虑居中图像、底左图上文字、off-grid editorial、mini minimalist 等变化。
- 每张图都要能表达布局、层级、间距、CTA、组件样式和图片处理。
- 多图必须保持同一个品牌世界、同一套字体逻辑、配色、CTA 家族和图片处理。

适合：

- 要网站概念图、落地页视觉方向、产品页设计参考。

### `imagegen-frontend-mobile`

安装名 `imagegen-frontend-mobile`。只生成移动 App 界面图，不写代码。

核心规则：

- 先判断平台：iOS-native premium、Android-native premium 或 cross-platform premium neutral。
- 默认使用干净的手机 mockup，设备框服务于内容，不能喧宾夺主。
- 多屏必须有真实流程逻辑，例如 onboarding -> auth -> home，或 browse -> detail -> checkout。
- 保持安全区、状态栏、底部导航、手势区域和触控尺寸意识。
- 文本必须清晰可读，不能为了塞内容变成小字。
- 遇到弱图、重复 onboarding、过度卡片嵌套、手机像网页、文字太小等情况要重新生成。

适合：

- App onboarding、auth、home、profile、settings、chat、commerce、fintech、fitness、productivity 等移动端概念图。

### `brandkit`

安装名 `brandkit`。只生成品牌视觉系统图，不写代码。

默认输出：

- 一张品牌 kit overview image。
- 常见布局为 `3 x 3`、`2 x 3`、`2 x 2` 或横向品牌 strip。
- 内容包括 Logo 封面、构造逻辑、数字应用、品牌精髓、色彩系统、字体、实体应用、图像方向和系统细节。

核心要求：

- 先推断品牌类别、受众、情绪承诺、文化位置、信任等级、核心隐喻。
- Logo 必须简单、可缩放、有象征意义，不能随机图标化。
- 用品牌策略驱动视觉，而不是拼贴式 moodboard。

适合：

- Logo 方向、品牌板、视觉系统、Identity deck、品牌应用示意。

### `redesign-skill`

安装名 `redesign-existing-projects`。用于升级已有网站或 App，不从零重写。

流程：

1. 扫描项目，识别框架、样式方式和当前设计模式。
2. 审计字体、色彩、布局、交互状态、内容、组件、图标、代码质量、战略遗漏。
3. 按优先级修复：字体、色彩、hover/active、布局间距、通用组件、loading/empty/error、最终排版细节。

原则：

- 沿用现有技术栈。
- 不迁移框架。
- 修改聚焦、可审查。
- 每次改动后测试，不能破坏功能。

### `soft-skill`

安装名 `high-end-visual-design`。用于高端、柔和、昂贵感、代理商级 UI。

核心风格：

- Apple-esque / Linear-tier。
- 大留白、柔和材质、精细按钮、流体导航、spring 动效。
- 使用 Double-Bezel 容器结构，让卡片像真实硬件或玻璃板。
- CTA 使用 button-in-button 尾随图标结构。

强约束：

- 禁止 Inter、Roboto、Arial、Open Sans、Helvetica。
- 禁止标准 Lucide、FontAwesome、Material Icons。
- 禁止普通灰边框、普通阴影、线性/ease-in-out 动效。
- 移动端必须消除旋转和重叠，回落到单列。

### `minimalist-skill`

安装名 `minimalist-ui`。用于极简、编辑式、文档感 UI。

核心风格：

- 温暖单色、清晰排版、平面 bento、柔和 pastel 点缀。
- 无渐变、无重阴影、无霓虹、无 3D glassmorphism。
- 卡片边框严格轻量，圆角通常 8px 或 12px。
- CTA 黑底白字，4px 到 6px 小圆角。

适合：

- Notion/Linear 气质、编辑式产品页、克制的工具站、干净内容页。

### `brutalist-skill`

安装名 `industrial-brutalist-ui`。用于工业粗野主义和战术遥测界面。

两种视觉模式：

- Swiss Industrial Print：浅色纸张、强黑字、红色警示、可见网格、巨型字体。
- Tactical Telemetry & CRT Terminal：暗色终端、单色遥测、扫描线、技术边框、单一红色警示。

核心规则：

- 严格 90 度角，拒绝圆角。
- 不用渐变、柔和阴影和现代半透明。
- 用 CSS Grid、边框、ASCII 语法装饰、数据标签和机械纹理构建界面。
- 适合数据密集、实验性作品集、编辑页面或“解密蓝图”气质界面。

### `output-skill`

安装名 `full-output-enforcement`。用于防止模型偷懒、截断、占位。

它禁止：

- `// ...`
- `// TODO`
- `// rest of code`
- `/* ... */`
- “for brevity”
- “similar to above”
- “and so on”
- 只给骨架不写完整实现

当输出接近限制时，必须停在自然断点，并标明 `[PAUSED - X of Y complete...]`，继续时从断点接上，不重复。

适合：

- 要求完整代码文件。
- 多文件实现。
- 长文档或完整分析。
- 模型容易省略细节的任务。

### `stitch-skill`

安装名 `stitch-design-taste`。用于为 Google Stitch 生成语义化 `DESIGN.md`。

目标：

- 把 Taste Skill 的审美规则翻译成 Stitch 可理解的语义设计系统。
- 输出颜色、字体、组件、布局、响应式、动效意图、反模式清单。

目录内还包含：

- `stitch-skill/SKILL.md`：生成 `DESIGN.md` 的规则。
- `stitch-skill/DESIGN.md`：一份 Taste Standard 示例设计系统。

适合：

- 用 Google Stitch 生成屏幕前，先构造统一设计语言。
- 想把 anti-slop 规则沉淀成可复用的设计系统文档。

## 辅助文件

### `llms.txt`

面向 LLM 的极简技能清单，快速说明每个 skill 的用途。适合作为上下文索引，不是可安装 skill。

### `skill.sh`

本地 skill 路径查询脚本。输入本仓库内的短名称，输出对应 `SKILL.md` 路径。

示例：

```bash
./skill.sh taste-skill
./skill.sh gpt-taste
./skill.sh imagegen-frontend-web
```

## 安装方式

安装整个仓库：

```bash
npx skills add https://github.com/Leonxlnx/taste-skill
```

安装单个 skill：

```bash
npx skills add https://github.com/Leonxlnx/taste-skill --skill "design-taste-frontend"
```

安装旧版 v1：

```bash
npx skills add https://github.com/Leonxlnx/taste-skill --skill "design-taste-frontend-v1"
```

安装后需要重启 Codex 才会加载新 skill。

## 使用建议

- 不确定选哪个时，先用 `taste-skill`。
- 已有项目要改 UI，用 `redesign-skill`。
- 想要图片参考再编码，用 `image-to-code-skill`。
- 只要图片，不要代码，用 `imagegen-frontend-web`、`imagegen-frontend-mobile` 或 `brandkit`。
- 想要更强约束、更激进动效，用 `gpt-tasteskill`。
- 输出总被截断或出现占位，用 `output-skill` 叠加。

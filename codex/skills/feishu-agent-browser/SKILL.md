---
name: feishu-agent-browser
description: 当需要直接提供飞书 cookie 和 URL 来打开飞书页面，或复用 agent-browser 保存的飞书登录态来打开飞书文档、知识库页面、提取正文与截图时使用。
allowed-tools: Bash(npx agent-browser:*), Bash(agent-browser:*)/
---

# Feishu Agent Browser

适用于两类场景：

- 用户直接提供飞书 `cookie + url`，希望立刻打开页面
- 已经保存过飞书状态，后续希望稳定复用登录态

## 适用场景

- 需要直接把用户提供的 Cookie 导入浏览器并打开飞书页面
- 需要把当前飞书浏览会话导出成状态文件
- 需要基于已保存状态重新打开飞书 Wiki / 云文档 / Drive 页面
- 需要减少重复传 Cookie 或重复登录
- 需要统一飞书浏览器会话名、状态文件路径和基础打开流程

## 默认约定

- 浏览器会话名：`feishu_cookie`
- 状态文件：`codex/skills/feishu-agent-browser/feishu-agent-browser-state.json`
- 运行时目录：`/tmp/agent-browser-runtime`

可通过以下环境变量覆盖：

- `FEISHU_AGENT_BROWSER_SESSION`
- `FEISHU_AGENT_BROWSER_STATE_FILE`
- `FEISHU_AGENT_BROWSER_RUNTIME_DIR`
- `FEISHU_AGENT_BROWSER_URL`

## 与 `$agent-browser` 的关系

- 这个 skill 不单独定义另一套浏览器自动化协议
- 只要涉及打开页面、等待加载、提取正文、截图、点击交互等浏览器动作，必须调用 `$agent-browser` skill 的标准工作流执行
- `feishu-agent-browser` 只负责补充飞书场景约束：Cookie 导入、状态文件复用、默认会话名、默认脚本路径、施工文档输出规则

执行顺序固定如下：

1. 先按 `$agent-browser` 打开目标页面并等待页面稳定
2. 再用本 skill 的脚本导入飞书 Cookie 或加载飞书状态
3. 页面可读后，继续沿用 `$agent-browser` 的标准命令做正文提取、截图和补充交互
4. 抓取结束后，必须按本 skill 的模板约束在按链接区分的 `docs/feishu_url_xxx/` 目录下生成施工文档
5. 正式文档产出完成后，必须执行 `agent-browser close` 关闭当前浏览器会话

浏览器执行时默认沿用 `$agent-browser` 的核心节奏：

1. `open`
2. `wait --load networkidle`，必要时补 `snapshot -i`
3. 页面变化后重新 `snapshot -i`
4. 使用 `get text`、`get title`、`get url`、`screenshot` 等命令继续取证

### `$agent-browser` 推荐调用方式

在飞书文档 / Wiki / Drive 场景中，默认优先使用下面这些 `$agent-browser` 命令，不要每次临时猜：

- `agent-browser --session "$SESSION" open "$URL"`
  - 用途：打开目标飞书页面，建立当前域名上下文
- `agent-browser --session "$SESSION" wait --load networkidle`
  - 用途：等待页面稳定，避免正文还没渲染完就开始取值
- `agent-browser --session "$SESSION" snapshot -i`
  - 用途：当页面是富文本、目录折叠区、按钮菜单或需要判断当前可见结构时使用
  - 规则：只有在需要识别元素结构或做交互时才调用；纯正文提取不强制每次都先 snapshot
- `agent-browser --session "$SESSION" get title`
  - 用途：确认当前页面标题，判断是否进入目标 PRD / 文档
- `agent-browser --session "$SESSION" get url`
  - 用途：确认是否仍停留在目标链接，或是否被重定向到登录页
- `agent-browser --session "$SESSION" get text body`
  - 用途：正文提取主入口；施工文档内容拆分默认基于这里拿到的正文
- `agent-browser --session "$SESSION" screenshot`
  - 用途：仅作为补充取证，不作为施工文档主体来源
- `agent-browser --session "$SESSION" state save "$STATE_FILE"`
  - 用途：当前飞书登录态保存到 `codex/skills/feishu-agent-browser/feishu-agent-browser-state.json`
- `agent-browser --session "$SESSION" state load "$STATE_FILE"`
  - 用途：复用已保存的飞书状态重新打开页面
- `agent-browser --session "$SESSION" close`
  - 用途：在正式施工文档、`testing.md`、`verification.md` 等结果文件写入完成后关闭当前飞书浏览会话，避免残留后台 session

如果需要手工补 Cookie，上层脚本本质调用的是这些 `$agent-browser` 方式：

- `agent-browser --session "$SESSION" cookies set "$NAME" "$VALUE" --domain ".feishu.cn" --path / --secure`
- 命中 HttpOnly 的 Cookie 追加 `--httpOnly`

飞书场景默认推荐顺序如下：

1. `open`
2. `wait --load networkidle`
3. 必要时 `cookies set` 或直接调用 `open_with_cookie.sh`
4. 再次 `open`
5. `wait --load networkidle`
6. `get title`
7. `get url`
8. `get text body`
9. 需要结构判断时再 `snapshot -i`
10. 需要留图时再 `screenshot`
11. 需要复用登录态时执行 `state save`
12. 正式文档与验证文件写入 `docs/feishu_url_<slug>/` 后，执行 `close`

### 施工文档输出目录规则

- 正式结果不能直接混放到单一 `docs/` 目录，必须按当前飞书链接生成独立目录
- 目录格式固定为：`docs/feishu_url_<slug>/`
- `<slug>` 必须来自当前飞书链接本身，不允许手写一个泛化目录名
- 优先取 URL 路径里的核心标识生成目录名：
  - `https://xxx.feishu.cn/wiki/CtH1wGE9WiIAzjkeqBqcwFFtnBe` -> `docs/feishu_url_cth1wge9wiiazjkebqbcwfftnbe/`
  - `https://xxx.feishu.cn/docx/AbCdEf123456` -> `docs/feishu_url_abcdef123456/`
- 如果路径里有多个段，优先取最后一个非空段；若最后一段仍包含查询参数或锚点，先去掉 `?` 和 `#` 后再生成目录名
- `<slug>` 统一转小写；非字母数字字符统一替换为下划线；连续下划线压缩成一个
- 同一个链接重复抓取时，必须写回同一个目录，不要每次新建随机目录
- 不同链接必须落到不同目录，避免多个飞书页面共用一个结果目录
- 目录下再放正式产物，例如：
  - `docs/feishu_url_cth1wge9wiiazjkebqbcwfftnbe/construction.md`
  - `docs/feishu_url_cth1wge9wiiazjkebqbcwfftnbe/testing.md`
  - `docs/feishu_url_cth1wge9wiiazjkebqbcwfftnbe/verification.md`

## 标准流程

### 方式一：直接贴 `cookie + url`（优先）

先按 `$agent-browser` 的底层流程打开飞书目标页，再通过本 skill 的脚本导入 Cookie 并固化状态。

把 Cookie 通过标准输入传给脚本，URL 作为第一个参数：

```bash
bash ~/.codex/skills/feishu-agent-browser/scripts/open_with_cookie.sh "https://xxx.feishu.cn/wiki/xxxx"
```

然后把整串 Cookie 粘贴到 stdin。

脚本会：

- 把 Cookie 写入当前飞书浏览会话
- 打开目标飞书页面
- 自动等待 `networkidle`
- 把当前状态保存到 `codex/skills/feishu-agent-browser/feishu-agent-browser-state.json`
- 输出标题和 URL

也支持通过环境变量直接传 Cookie：

```bash
FEISHU_AGENT_BROWSER_COOKIE='cookie1=...; cookie2=...' \
bash ~/.codex/skills/feishu-agent-browser/scripts/open_with_cookie.sh "https://xxx.feishu.cn/wiki/xxxx"
```

### 方式二：已有会话，单独保存状态

1. 当前会话已经打开飞书后，先保存状态：

```bash
bash ~/.codex/skills/feishu-agent-browser/scripts/save_state.sh
```

2. 后续任意时刻，加载状态并打开目标飞书页面：

```bash
bash ~/.codex/skills/feishu-agent-browser/scripts/open_with_state.sh "https://xxx.feishu.cn/wiki/xxxx"
```

3. 打开后，后续正文提取、截图、补充点击等动作，继续按 `$agent-browser` skill 的标准命令执行；例如需要正文时：

```bash
XDG_RUNTIME_DIR=/tmp/agent-browser-runtime \
agent-browser --session "${FEISHU_AGENT_BROWSER_SESSION:-feishu_cookie}" get text body
```

4. 抓取到页面正文后，必须继续生成施工文档：

- 不允许只返回原始正文或摘要后结束
- 必须基于抓取内容整理出施工文档
- 施工文档的主体内容来源必须是飞书页面里的业务正文，不是本次抓取过程、命令执行结果或页面打开记录
- 必须先把页面正文按业务语义拆分，再映射到模板章节
- 禁止把 `open`、`wait`、`cookies set`、`state save`、截图路径、抓取成功与否、操作耗时、命令回显等执行信息写成施工文档主体内容
- 模板中的任务看板、任务详情、验收标准、发布流程，也必须围绕页面里的需求内容、实施任务、业务约束和交付目标来整理，不允许改写成“本次如何抓取页面”的过程说明
- 如果页面正文没有提供某一章节所需信息，必须明确写“原文未提供/待确认/需补充”，不能用抓取过程、取证动作或工具输出凑数
- 施工文档必须严格遵循 `本 Skill 末尾的「施工文档模板」`
- 必须使用模板中的全部一级章节、字段名和顺序
- 不允许自行改名、删减、重排或自由发挥额外结构
- 正式生成结果必须写入按链接区分的 `docs/feishu_url_<slug>/` 目录

5. 正式文档生成完成后，必须执行收尾关闭命令：

```bash
XDG_RUNTIME_DIR=/tmp/agent-browser-runtime \
agent-browser --session "${FEISHU_AGENT_BROWSER_SESSION:-feishu_cookie}" close
```

- 关闭动作必须发生在 `construction.md`、`testing.md`、`verification.md` 等正式结果已经写入之后
- 禁止在正文还没提取完、截图还没取证完、文档还没落盘前提前关闭

### 施工文档内容映射规则

- `1. 需求背景与目标`：只写页面中的需求背景、目标、痛点、收益、适用范围
- `2. 技术方案设计`：只写页面中的方案说明、逻辑调整、功能设计、依赖影响；若页面没有明确技术方案，可基于正文做最小必要归纳，但必须以页面信息为边界
- `3. 模块拆分与里程碑`：按页面里的功能点、子能力、业务阶段拆分，不允许写成“抓取文档”“保存状态”“截图取证”
- `4. 任务看板与拆解`：按待实施的产品/研发任务拆分，不允许写成浏览器操作步骤
- `5. 任务详情与执行记录`：记录每个业务任务的实现重点、约束、待确认项，不记录本次打开飞书、注入 Cookie、抓正文的过程
- `6. 风险与边界评估`：只写页面业务风险、实现边界、规则限制
- `7. 测试与验收标准`：只写需求验收条件、功能校验点、异常场景，不写“页面抓取成功”“截图已生成”
- `8. 发布与部署流程`：只写需求上线前置条件、发布步骤、回滚思路；如果原文缺失则标记待确认

### 本次已验证的飞书 PRD 拆分流程

下次抓到类似飞书 PRD 页面时，默认按下面顺序处理，不要临场猜测：

1. 先取 `title` 和 `body text`，确认页面主题是什么。
2. 在正文里先找页面自带分段标题，优先识别这类结构词：`基础信息`、`需求背景`、`变更记录`、`数据需求`、`方案说明`、`逻辑调整`、`AI速览`、`发布平台`。
3. 先抽原文事实，不要先写结论。优先抽这些字段：
   - 需求名称
   - 负责人/提出人/业务负责人/干系人
   - 需求时间
   - Figma / 原型链接
   - 原始背景 / 原始目标
   - 功能调整点
   - 限制规则 / 提示文案
   - 范围放开 / 适用范围
   - 存量数据处理要求
4. 抽完事实后，再把事实映射到模板，而不是把原文顺序原样贴进去。
5. `模块拆分` 和 `任务看板` 必须从页面需求推导研发实施任务。默认优先往这些方向拆：
   - 字段展示与录入
   - 保存逻辑与唯一性校验
   - 选择范围或业务规则调整
   - 存量数据补写 / 数据迁移
   - 测试与上线准备
6. `任务详情与执行记录` 默认写“每个业务任务的实现重点、限制、待确认项”，不是写“这次怎么抓页面”。
7. 如果页面里只看到目录标题、没看到对应正文：
   - 在对应章节写 `原文未提供` / `待确认`
   - 可以说明“当前仅确认目录存在，未提取到展开内容”
   - 不允许用抓取命令、截图、状态保存记录补位

## 脚本说明

### `scripts/save_state.sh`

- 从当前 `agent-browser` 会话导出飞书状态
- 默认保存到 `codex/skills/feishu-agent-browser/feishu-agent-browser-state.json`
- 允许通过环境变量覆盖会话名和输出路径

### `scripts/open_with_cookie.sh`

- 直接接收用户提供的 Cookie 和 URL
- 自动批量写入 Feishu Cookie
- 打开页面后立即把状态保存到默认状态文件
- 适合作为“直接贴 cookie + url”的主入口

### `scripts/open_with_state.sh`

- 先加载飞书状态文件
- 再打开指定 URL
- 自动等待 `networkidle`
- 输出当前页面标题和 URL，便于快速确认是否进入目标页

### 会话收尾

- `feishu-agent-browser` 的脚本只负责打开页面、保存状态和复用状态，不负责自动关闭会话
- 当正文提取、截图取证、正式文档生成全部完成后，调用方必须自行执行 `agent-browser --session "$SESSION_NAME" close`
- 若本次还额外生成了 `testing.md`、`verification.md`、`review-report.md`，也必须在这些文件落盘后再关闭

## 注意点

- 运行前先检查 `agent-browser` 命令是否存在；若不存在，先自动执行 `npm i -g agent-browser`，安装后仍不存在再报错终止
- 执行浏览器动作时，必须把 `$agent-browser` 视为底层执行 skill；`feishu-agent-browser` 只负责飞书场景补充，不替代 `$agent-browser` 的标准流程
- 这个 skill 依赖本机已安装 `agent-browser`
- 实际运行时应使用安装后的脚本路径：`~/.codex/skills/feishu-agent-browser/scripts/`
- 首次如无状态文件，可直接使用 `open_with_cookie.sh`
- 状态文件默认放在 skill 目录内，但通过 `.gitignore` 排除提交
- 抓取到飞书页面内容后，必须继续产出施工文档；不能只停留在“打开页面”或“提取正文”
- 施工文档是页面业务内容的结构化重写，不是浏览器执行报告；任何抓取动作、命令结果、截图路径、状态保存记录都不得充当文档主内容
- 施工文档输出必须严格遵循同目录下的 `本 Skill 末尾的「施工文档模板」`；生成结果必须使用该模板的章节、字段名和顺序，禁止自定义结构
- 正式生成的计划/施工文档必须写到按链接区分的 `docs/feishu_url_<slug>/` 目录下；`codex/skills/feishu-agent-browser/` 目录只保留模板、样例和脚本，不作为正式结果输出目录
- 正式结果文件全部写入后，必须执行 `agent-browser --session "$SESSION_NAME" close` 关闭当前会话；不要把飞书浏览 session 长时间挂在后台

## 施工文档模板

```markdown
# 🚧 [任务名称/编号] 施工文档

> **输出路径约束**: 正式生成结果必须写入 `docs/` 目录；本文件仅作为模板，不作为最终结果存放位置。
> **文档状态**: [Draft 规划中 / In Progress 施工中 / Review 审查中 / Done 已完成]
> **任务规模**: [短期任务 (≤3天) / 中长期任务 (>3天)]
> **会话 ID**: [记录对应的会话 ID 或日期，例如 2024-05-20_Session_A]
> **执行者**: Codex
> **更新时间**: [YYYY-MM-DD HH:MM:SS]

---

## 1. 需求背景与目标 (Background & Objective)
*   **需求描述**: [简述本次任务是为了解决什么问题或实现什么功能]
*   **核心目标**: [列出 1-3 个可量化的成功指标或核心交付物]

## 2. 技术方案设计 (Technical Design)
*   **架构变更**: [说明涉及哪些模块/服务的改动，例如：新增 API 接口、修改数据库表结构等]
*   **核心逻辑**: [简要说明关键逻辑的实现思路，可用伪代码、流程说明或数据流向表示]
*   **依赖与影响面**: [说明本次改动会影响到哪些现有的功能或系统，需要特别注意的关联点]

> ⚠️ **高危改动预警 (Public Component Warning)** ⚠️
> **是否涉及公共函数/组件改动**: [是 / 否]
> **涉及的公共文件/函数**: [列出具体文件和函数名，例如 `src/utils/request.ts` 中的 `fetchData`]
> **改动影响面分析**: [说明改动对其他模块的潜在影响]
> **准入状态**: [待用户特别确认 / 已获许可]
> *(注：任何对公共函数或基础组件的修改，必须在此处显式标红，并单独获得用户的明确许可！)*

## 3. 模块拆分与里程碑 (Module Breakdown) 
*(注：短期任务可跳过此模块，中长期任务必须填写)*

| 模块 ID | 模块名称 | 核心目标 | 预计改动/新增文件范围 | 状态 | 准入许可 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| M-01 | [例如：用户鉴权模块] | [实现登录注册] | `src/auth/*`, `docs/db/users.sql` | [ ] | [待申请 / 已获取] |
| M-02 | [例如：支付网关接入] | [对接微信支付] | `src/payment/*` | [ ] | [待申请 / 已获取] |

## 4. 任务看板与拆解 (Task Board)
> **当前执行模块**: [填写当前执行的模块ID，短期任务填“全局”]

| 任务 ID | 所属模块 | 任务描述 | 预计改动/新增文件 | 优先级 | 状态 | 预估耗时 | 实际耗时 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| T-01 | M-01 | [例如：设计数据库表并编写 DDL] | `docs/db/users.sql` | P0 | [ ] | [30m] | |
| T-02 | M-01 | [例如：实现核心 Service 逻辑] | `src/services/auth.ts` | P0 | [ ] | [1h] | |
| T-03 | M-01 | [例如：编写单元测试和冒烟测试] | `tests/auth.spec.ts` | P1 | [ ] | [45m] | |

*(优先级说明: P0 = 核心阻塞性任务; P1 = 重要任务; P2 = 次要/优化任务。状态: `[ ]` 未开始, `[-]` 进行中, `[x]` 已完成)*

## 5. 任务详情与执行记录 (Execution Details)
*(本模块由 Codex 在执行过程中动态更新，记录每个子任务的具体操作和遇到的问题)*

*   **[T-01] 记录**:
    *   **操作**: [例如：创建了 `users` 表的 DDL]
    *   **记录**: [遇到的报错或需要注意的代码决策]

## 6. 最小改动实施清单

1. **优先确认字段/接口语义**
   [先写清楚需求口径与现有字段、接口枚举是否一致，避免后续改偏]
2. **优先复用现有链路**
   [先列出现有可复用的控制器、Task、Service、数据表字段，不重复造轮子]
3. **先改保存链路，再改消费链路**
   [先保证配置或数据能正确写入，再补同步、查询、展示等下游消费逻辑]
4. **公共链路最后补展示字段**
   [公共查询接口只在前端确认缺字段时再补，避免一开始扩大影响面]
5. **逐项列出最小改动文件**
   [按“先后顺序 + 文件路径 + 改动意图”列出，供实施前快速确认范围]

## 7. 风险与边界评估 (Risks & Boundaries)
*   **潜在风险**: [例如：并发修改可能导致数据不一致]
*   **边界条件**: [例如：输入参数为 null 时的处理逻辑，最大数据量的限制]
*   **缓解策略**: [例如：增加乐观锁控制，添加输入校验层]

## 8. 测试与验收标准 (Acceptance Criteria)
*   [ ] **功能验证**: [例如：API `POST /users` 返回 201 且数据库记录增加]
*   [ ] **异常处理**: [例如：重复注册时返回 409 错误码]
*   [ ] **自动化测试**: [列出必须通过的测试用例或测试脚本，例如：运行 `npm run test:api` 全部通过]

## 9. 发布与部署流程 (Release Flow)
*   **前置检查**: [例如：确认 SQL 脚本已在预发环境执行，依赖的外部 API 已就绪]
*   **发布步骤**: [简述上线/部署的操作步骤]
*   **回滚方案**: [若出现严重 Bug，如何快速恢复到上一个稳定版本]

---
*(本文档由 Codex 自动维护，中长期任务每开启新模块必须先获取用户许可)*

```

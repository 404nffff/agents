---
name: software-dev-process-mutil-agent
description: 用于需要按 SDLC 阶段推进任务，并在设计、实现、测试、调试阶段结合角色选择和子代理派发来拆解执行时。
---

# Software Development Process Multi Agent Skill

当用户明确使用 `sdlc-design-1`、`sdlc-design-2`、`sdlc-implement`、`sdlc-test`、`sdlc-debug`、`sdlc-solo`，并且希望把不同阶段或子任务派给不同专业角色/子代理时，使用本 Skill。

本 Skill 基于 `software-dev-process` 扩展，额外内置了来自 `who` 的本地角色库，位于 `roles/`。使用时只读取当前阶段命中的角色文件，禁止一次性读取全部角色库。

## 核心约束

1. **阶段仍由 SDLC 指令驱动**：每个开发阶段必须通过对应的 `sdlc-*` 指令触发，禁止绕过阶段边界直接派发实施。
2. **每阶段先选主控角色**：进入任意阶段前，必须先读取 `roles/ROLE-SELECTOR.md`，选择 1 个主控角色；只有天然跨域时才补 1 个辅助角色。
3. **主控保留全局状态，子代理只做局部任务**：主控负责阶段判断、文档维护、任务编排、结果验收；子代理只处理明确范围内的分析、实现、测试或排障任务。
4. **默认最小上下文派发**：子代理默认使用 `fork_context=false`；只传本任务所需的目标、范围、文件清单、约束和交付格式，禁止把整段会话历史整包透传。
5. **Agent 类型强约束**：
   - `explorer`：只读扫描、上下文梳理、风险识别、文档分析
   - `worker`：代码实现、测试修复、文档落盘、结果汇总
6. **并行必须满足非重叠条件**：只有当多个子任务的文件集合、状态依赖、外部资源依赖均不重叠时，才允许并行派发。
7. **施工文档必须记录派发信息**：`003-施工文档.md` 中每个任务必须记录执行角色、Agent 类型、并行组、允许改动文件、交付物和复核角色。
8. **主控必须回写文档**：无论子代理是否直接改动文件，最终都必须由主控更新 `status.md`、`003-施工文档.md`、`003-文件改动记录.md`、`onlyAI/operations-log.md`。
9. **实现阶段优先串行，设计阶段优先并行只读**：`design-1` / `design-2` 允许并行派只读子代理；`implement` / `debug` 默认串行，只有任务和文件所有权完全分离时才可并行。
10. **复核不能省略**：`worker` 完成后，主控必须根据任务要求做结果复核；高风险任务要指定 `Code Reviewer`、`Security Engineer`、`SRE` 等复核角色。

## 本 Skill 内置资源

- 施工模板：`software-dev-process-mutil-agent/assets/`
- 角色选择规则：`software-dev-process-mutil-agent/roles/ROLE-SELECTOR.md`
- 角色库：`software-dev-process-mutil-agent/roles/design/`、`roles/engineering/`、`roles/game-development/`
- 并行判定清单：`software-dev-process-mutil-agent/assets/并行任务判定清单.md`
- 子代理任务模板：`software-dev-process-mutil-agent/assets/子代理任务模板.md`

## 目录与资源约定

- **模板读取**：所有文档基于本 Skill `assets/` 目录下的中文模板生成。
- **文档输出**：设计、施工、测试和排查文档统一输出到 `docs/[需求目录]/`。
- **onlyAI 工作区**：仅供 AI 读取和维护的过程文件统一输出到 `docs/[需求目录]/onlyAI/`，包括 `structured-request.json`、`context-scan.json`、`context-question-N.json`、`operations-log.md`、`testing.md`、`verification.md`、`review-report.md`。
- **SQL 脚本**：数据库变更脚本统一输出到 `docs/[需求目录]/sql/`。
- **摘要文档**：如有必要，可自主生成 `docs/[需求目录]/summary.md` 或 `docs/index.md` 汇总阶段结论与交付物索引。

## 角色选择与派发规则

### 阶段主控角色建议

| 阶段 | 默认主控角色 | 常见辅助角色 | 子代理建议 |
| --- | --- | --- | --- |
| `sdlc-design-1` | `Software Architect` / `Backend Architect` / `UX Architect` | `Codebase Onboarding Engineer` / `Security Engineer` / `Data Engineer` | 允许并行 `explorer` 进行只读扫描 |
| `sdlc-design-2` | `Software Architect` / `Backend Architect` | `Database Optimizer` / `Security Engineer` / `Technical Writer` | 允许并行 `explorer` 补接口、数据、风险信息 |
| `sdlc-implement` | `Senior Developer` / `Minimal Change Engineer` | `Frontend Developer` / `AI Engineer` / 具体引擎角色 | `worker` 执行，默认串行 |
| `sdlc-test` | `Code Reviewer` / `Senior Developer` | `SRE` / `Security Engineer` / `Threat Detection Engineer` | 可按测试域并行 `worker` 或 `explorer` |
| `sdlc-debug` | `Senior Developer` / `Incident Response Commander` | `SRE` / `Security Engineer` / `Code Reviewer` | 先复现，允许并行只读排查 |

### 子代理提示词最小要素

派发子代理时，至少传入以下信息：

1. 任务目标
2. 允许读取/允许修改的文件
3. 禁止触碰的范围
4. 预期交付物
5. 验证命令或验收条件
6. 输出格式

优先使用 `assets/子代理任务模板.md` 拼装派发内容。

### 并行与串行边界

- **允许并行**：
  - 设计阶段的代码扫描、接口梳理、风险识别
  - 实现阶段中不同任务的文件集合完全不重叠
  - 测试阶段中不同测试域彼此独立
- **禁止并行**：
  - 同一文件或同一模块的多子代理同时写入
  - 当前任务的结果会决定下一个任务输入
  - 共享同一数据库脚本、同一迁移链路、同一发布动作

在真正并行派发前，必须先过一遍 `assets/并行任务判定清单.md`。只要其中任一阻断项命中，就退回串行执行。

## 阶段命令

### `sdlc-design-1`

阶段 1：需求理解与概要设计。

1. 简单任务可直接进入上下文收集；复杂任务必须先确认任务目录。
2. 先读取 `roles/ROLE-SELECTOR.md`，选择当前阶段主控角色；如需要，只补 1 个辅助角色，并只读取命中的角色文件。
3. 在 `docs/[需求目录]/onlyAI/structured-request.json` 记录结构化需求，必须包含系统名称和本阶段主控角色。
4. 首次创建 `status.md` 时，记录系统名称、当前阶段、主控角色与辅助角色。
5. 输出 `docs/[需求目录]/onlyAI/context-scan.json`，完成结构化快速扫描。
6. 对独立的上下文问题，可并行派发多个 `explorer`：
   - 代码结构扫描
   - 安全/性能风险扫描
   - 数据库/接口现状扫描
7. 使用 `sequential-thinking` 梳理问题、约束和候选方案，并使用 `brainstorming` 做多方案发散。
8. 基于 `assets/概要设计模板.md` 输出 `001-概要设计.md`，记录阶段角色规划和可能的子代理分工。
9. 如存在方案歧义或风险点，生成 `001-概要设计-待确认.md`。
10. 确认待确认项已处理后，提示进入 `sdlc-design-2`。

### `sdlc-design-2`

阶段 2：详细设计与施工规划。

1. 前置校验：若 `001-概要设计-待确认.md` 状态仍为“待处理”，拒绝进入本阶段。
2. 重新进行阶段选角，通常主控为 `Software Architect`、`Backend Architect` 或目标技术域角色。
3. 基于 `001-概要设计.md` 继续收集实现细节，并补齐接口契约、风险与验证标准。
4. 使用 `assets/详细设计模板.md` 输出 `002-详细设计.md`。
5. 使用 `assets/施工文档模板.md` 输出 `003-施工文档.md`。
6. 在 `003-施工文档.md` 中为每个任务补齐：
   - `执行角色`
   - `Agent 类型`
   - `并行组`
   - `允许改动文件`
   - `交付物`
   - `复核角色`
7. 若需要额外信息，可并行派发只读 `explorer`，但不得在本阶段直接改业务代码。
8. 如存在方案待定、接口不明确或异常策略未定，生成 `002-详细设计-待确认.md`。
9. 待确认项处理完成后，确认 `003-施工文档.md` 中已明确文件边界与派发边界，再进入 `sdlc-implement`。

### `sdlc-implement`

阶段 3：代码实现。

1. 前置校验：若 `002-详细设计-待确认.md` 状态仍为“待处理”，拒绝进入本阶段。
2. 读取 `003-施工文档.md` 的任务看板，只执行已定义好的任务。
3. 执行模式：
   - 默认一次执行一个任务
   - 只有当多个任务的 `并行组` 不同、且允许改动文件不重叠时，才允许并行派发多个 `worker`
4. 每个任务派发前，主控必须根据看板内容拼装子代理提示词，至少包含目标、范围、约束、文件清单、交付物和验证标准。
5. 子代理返回后，主控负责：
   - 审核改动是否越界
   - 执行或复核验证命令
   - 更新 `003-文件改动记录.md`
   - 更新 `003-施工文档.md`
   - 更新 `onlyAI/operations-log.md`
   - 更新 `status.md`
6. 所有新增、修改代码必须同步补齐中文注释。
7. 所有数据库相关脚本统一写入 `docs/[需求目录]/sql/`。
8. 全部任务完成后，可生成 `docs/[需求目录]/summary.md`，然后进入 `sdlc-test`。

### `sdlc-test`

阶段 4：质量验证与测试。

1. 重新进行阶段选角，主控通常为 `Code Reviewer` 或 `Senior Developer`。
2. 使用 `assets/测试用例模板.md` 输出 `004-测试用例.md`。
3. 在 `onlyAI/testing.md` 和 `onlyAI/verification.md` 记录测试执行过程、输出和风险评估。
4. 可按测试域派发子代理，但必须满足测试对象和输出不相互覆盖。
5. 执行测试后，使用 `assets/测试报告模板.md` 输出 `005-测试报告.md`。
6. 在 `onlyAI/review-report.md` 写入自我审查结论，并明确是否需要补派安全、性能、稳定性专项复核。
7. 完成后执行记忆回写；如有必要，生成 `summary.md` 汇总结果。

### `sdlc-debug`

排查与修复阶段。

1. 重新选角：一般由 `Senior Developer` 或 `Incident Response Commander` 主控。
2. 先复现问题，再写入 `assets/Debug排查记录模板.md` 生成 `006-Debug排查记录.md`。
3. 若存在多个彼此独立的异常现象，可并行派发多个只读 `explorer` 做根因排查。
4. 真正的修复任务仍遵守实现阶段的文件所有权和并行规则。
5. 在 `onlyAI/operations-log.md` 记录定位过程，在 `onlyAI/verification.md` 记录回归验证结果。
6. 修复完成后同步更新记忆，并在需要时补充 `summary.md`。

### `sdlc-solo`

全自动模式：从当前阶段自动执行到测试完成。

1. 先检测 `docs/[需求目录]/` 的现有产物，判断当前已完成阶段。
2. 从下一个未完成阶段开始，每进入一个阶段都必须先做一次阶段选角。
3. 若预计剩余工作量大于 3 天，必须先警告用户再继续。
4. 自动执行剩余阶段时：
   - `design-1` / `design-2` 允许自动并行派发只读 `explorer`
   - `implement` / `debug` 默认串行，只有任务看板已明确并行边界才允许并行 `worker`
5. 遇到待确认文档时，Solo 模式下由 AI 自动决策，并将理由写入设计文档和待确认文档。
6. 全部完成后自动生成 `summary.md`，并执行记忆回写。

## 可用资源

- `software-dev-process-mutil-agent/assets/概要设计模板.md`
- `software-dev-process-mutil-agent/assets/详细设计模板.md`
- `software-dev-process-mutil-agent/assets/施工文档模板.md`
- `software-dev-process-mutil-agent/assets/测试用例模板.md`
- `software-dev-process-mutil-agent/assets/测试报告模板.md`
- `software-dev-process-mutil-agent/assets/执行记录模板.md`
- `software-dev-process-mutil-agent/assets/文件改动记录模板.md`
- `software-dev-process-mutil-agent/assets/Debug排查记录模板.md`
- `software-dev-process-mutil-agent/assets/待确认模板.md`
- `software-dev-process-mutil-agent/assets/并行任务判定清单.md`
- `software-dev-process-mutil-agent/assets/子代理任务模板.md`
- `software-dev-process-mutil-agent/roles/ROLE-SELECTOR.md`

## 落地规则总结

1. **SDLC 决定阶段，角色决定做法，子代理决定执行单元。**
2. **主控只保留一个，子代理可多个，但必须明确边界。**
3. **设计阶段并行只读，施工阶段并行只在文件不重叠时开放。**
4. **所有阶段结果最终都要回写任务文档，不允许只口头汇报。**

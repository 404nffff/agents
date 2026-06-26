---
name: software-dev-process-roles
description: 用于需要按 SDLC 阶段推进任务、执行一次性脚本任务、查询历史会话，并在设计、实现、测试、调试阶段结合角色选择来拆解执行时。
---

# Software Development Process Roles Skill

当用户明确使用 `sdlc-design-1`、`sdlc-design-2`、`sdlc-implement`、`sdlc-test`、`sdlc-debug`、`sdlc-solo`、`sdlc-script`、`sdlc-history`，并且希望把不同阶段或子任务分配给不同专业角色时，使用本 Skill。

本 Skill 基于 `software-dev-process` 扩展，使用 `skills/who/` 的角色库进行角色选择。阶段计划的职责是直接说明”每个阶段应该优先选择哪些角色”，再通过 `skills/who/SKILL.md` 的选择规则确定最终主角色与辅助角色。使用时只读取当前阶段命中的角色文件，禁止一次性读取全部角色库。

## 核心约束

1. **阶段仍由 SDLC 指令驱动**：每个开发阶段必须通过对应的 `sdlc-*` 指令触发，禁止绕过阶段边界直接实施。
2. **每阶段先按阶段计划选角**：进入任意阶段前，必须先参考下方阶段计划，通过 `skills/who/SKILL.md` 的选择规则确定 1 个主角色；只有天然跨域时才补 1 个辅助角色。
3. **角色负责任务拆解与执行**：选定的角色负责阶段判断、文档维护、任务编排、具体实现和结果验收。
4. **施工文档必须记录角色信息**：`003-施工文档.md` 中每个任务必须记录执行角色、允许改动文件、交付物和复核角色。
5. **必须回写任务文档、会话登记与知识库**：任务执行后必须更新 `status.md`、`003-施工文档.md`、`003-文件改动记录.md`、`onlyAI/operations-log.md`；若当前项目已由 `sdlc_session_register` hook 完成首次会话登记，阶段切换和任务完成时还必须通过本 Skill 的 `scripts/sdlc_session_register.py` 回填 `docs/ai-register.db`；若当前项目启用了 `ai_localbase`，还必须按项目规则同步阶段结论到对应知识库。
6. **复核不能省略**：任务完成后，必须根据任务要求做结果复核；高风险任务要指定 `Code Reviewer`、`Security Engineer`、`SRE` 等复核角色。
7. **默认代码优先策略**：日常开发默认按"先实现业务代码，再补充/更新单元测试、冒烟测试、功能测试，最后本地运行验证"的顺序执行。
8. **TDD 明确授权制与 Debug 豁免**：一般新增或重构禁止自动应用测试先行模式（除非用户明确要求 `TDD`、`测试先行` 等）。**豁免规则**：当处于 `sdlc-debug` (Bug排查与修复) 阶段时，默认采用"复现先行"（即编写/运行失败的测试用例验证 Bug 存在 -> 修复逻辑 -> 测试变绿）的局部 TDD 模式，此场景无需预先授权。

## 本 Skill 内置资源

- 施工模板：`software-dev-process-roles/assets/`
- 角色库：使用 `skills/who/SKILL.md` 的角色选择规则和 `skills/who/roles/` 的角色文件

## 目录与资源约定

- **模板读取**：所有文档基于本 Skill `assets/` 目录下的中文模板生成。
- **文档输出**：设计、施工、测试和排查文档统一输出到 `docs/[需求目录]/`。
- **onlyAI 工作区**：仅供 AI 读取和维护的过程文件统一输出到 `docs/[需求目录]/onlyAI/`，包括 `structured-request.json`、`context-scan.json`、`context-question-N.json`、`operations-log.md`、`testing.md`、`verification.md`、`review-report.md`。
- **SQL 脚本**：数据库变更脚本统一输出到 `docs/[需求目录]/sql/`。
- **链路探针结果**：当任务包含接口调用、业务链路验证或脚本化探针验证时，基于 `assets/链路探针结果Markdown模板.md` 输出 `docs/[需求目录]/[需求标识]_probe_result.md`；结果文件只保留 Markdown 表格，入参和出参必须同时包含 JSON 与字段说明，边界条件必须独立成列。
- **摘要文档**：如有必要，可自主生成 `docs/[需求目录]/summary.md` 或 `docs/index.md` 汇总阶段结论与交付物索引。
- **脚本任务文档**：一次性 Shell、PHP、Python、SQL、Node.js 等脚本任务基于 `assets/脚本任务模板.md` 输出 `docs/[需求目录]/script-[序号]-[简述].md`。
- **SDLC 会话登记库**：仓库级 `docs/ai-register.db` 的首次会话身份由 `shell/codex_hook/plugins/sdlc_session_register/hook.py` 在 `SessionStart` 维护；手动身份登记、阶段推进和历史查询由本 Skill 的 `scripts/sdlc_session_register.py` 维护，使用 `upsert` 写入/更新身份，使用 `progress` 回填任务目录、完成功能和进度，使用 `query` 只读查询历史。

## 角色选择规则

### 阶段选角计划

| 阶段 | 优先主角色 | 常见辅助角色 |
| --- | --- | --- |
| `sdlc-design-1` | `Software Architect`<br>`Backend Architect`<br>`UX Architect` | `Codebase Onboarding Engineer`<br>`Security Engineer`<br>`Data Engineer` |
| `sdlc-design-2` | `Software Architect`<br>`Backend Architect` | `Database Optimizer`<br>`Security Engineer`<br>`Technical Writer` |
| `sdlc-implement` | `Senior Developer`<br>`Minimal Change Engineer` | `Frontend Developer`<br>`AI Engineer`<br>或任务命中的具体技术域角色 |
| `sdlc-test` | `Code Reviewer`<br>`Senior Developer` | `SRE`<br>`Security Engineer`<br>`Threat Detection Engineer` |
| `sdlc-debug` | `Senior Developer`<br>`Incident Response Commander` | `SRE`<br>`Security Engineer`<br>`Code Reviewer` |
| `sdlc-script` | `Senior Developer`<br>`Minimal Change Engineer` | `SRE`<br>`Database Optimizer`<br>`Security Engineer` |
| `sdlc-solo` | 先判断下一个未完成阶段，再复用该阶段的主角色计划 | 按对应阶段补辅助角色 |

选角顺序：先看阶段选角计划确定候选角色名称，再通过 `skills/who/SKILL.md` 的选择规则读取对应角色文件。

## 阶段命令

### `sdlc-design-1`

阶段 1：需求理解与概要设计。

1. 简单任务可直接进入上下文收集；复杂任务必须先确认任务目录。
2. 先按上方阶段选角计划确定候选角色名称，再通过 `skills/who/SKILL.md` 的选择规则读取对应角色文件，选择当前阶段主角色；如需要，只补 1 个辅助角色。
3. 在 `docs/[需求目录]/onlyAI/structured-request.json` 记录结构化需求，必须包含系统名称和本阶段主角色。
4. 首次创建 `status.md` 时，记录系统名称、当前阶段、主角色与辅助角色。
5. 输出 `docs/[需求目录]/onlyAI/context-scan.json`，完成结构化快速扫描。
6. 使用 `sequential-thinking` 梳理问题、约束和候选方案，并使用 `brainstorming` 做多方案发散。
7. 基于 `assets/概要设计模板.md` 输出 `001-概要设计.md`，记录阶段角色规划。
8. 如存在方案歧义或风险点，生成 `001-概要设计-待确认.md`。
9. 若能取得当前 `session_id`，调用 `skills/software-dev-process-roles/scripts/sdlc_session_register.py progress` 回填 `task_dir`、`feature="完成概要设计"`、`progress="25%"`。
10. 确认待确认项已处理后，提示进入 `sdlc-design-2`。

### `sdlc-design-2`

阶段 2：详细设计与施工规划。

1. 前置校验：若 `001-概要设计-待确认.md` 状态仍为”待处理”，拒绝进入本阶段。
2. 先按上方阶段选角计划确定候选角色名称，再通过 `skills/who/SKILL.md` 的选择规则重新进行阶段选角，通常主角色为 `Software Architect`、`Backend Architect` 或目标技术域角色。
3. 基于 `001-概要设计.md` 继续收集实现细节，并补齐接口契约、风险与验证标准。
4. 使用 `assets/详细设计模板.md` 输出 `002-详细设计.md`。
5. 使用 `assets/施工文档模板.md` 输出 `003-施工文档.md`。
6. 在 `003-施工文档.md` 中为每个任务补齐：
   - `执行角色`
   - `允许改动文件`
   - `交付物`
   - `复核角色`
7. 如存在方案待定、接口不明确或异常策略未定，生成 `002-详细设计-待确认.md`。
8. 若能取得当前 `session_id`，调用 `skills/software-dev-process-roles/scripts/sdlc_session_register.py progress` 回填 `task_dir`、`feature="完成详细设计与施工规划"`、`progress="45%"`。
9. 待确认项处理完成后，确认 `003-施工文档.md` 中已明确文件边界，再进入 `sdlc-implement`。

### `sdlc-implement`

阶段 3：代码实现。

1. 前置校验：若 `002-详细设计-待确认.md` 状态仍为”待处理”，拒绝进入本阶段。
2. 先按上方阶段选角计划确定候选角色名称，再通过 `skills/who/SKILL.md` 的选择规则确定当前任务的主角色与辅助角色。
3. 读取 `003-施工文档.md` 的任务看板，只执行已定义好的任务。
4. 按照选定角色的工作方式，逐个完成任务。
5. 每个任务完成后，负责：
   - 审核改动是否越界
   - 执行或复核验证命令
   - 更新 `003-文件改动记录.md`
   - 更新 `003-施工文档.md`
   - 更新 `onlyAI/operations-log.md`
   - 更新 `status.md`
   - 若能取得当前 `session_id`，调用 `scripts/sdlc_session_register.py` 回填当前任务进度
6. 所有新增、修改代码必须同步补齐中文注释。
7. 所有数据库相关脚本统一写入 `docs/[需求目录]/sql/`。
8. 全部任务完成后，可生成 `docs/[需求目录]/summary.md`，并回填 `feature="完成代码实现"`、`progress="75%"`，然后进入 `sdlc-test`。

### `sdlc-test`

阶段 4：质量验证与测试。

1. 先按上方阶段选角计划确定候选角色名称，再通过 `skills/who/SKILL.md` 的选择规则重新进行阶段选角，主角色通常为 `Code Reviewer` 或 `Senior Developer`。
2. 使用 `assets/测试用例模板.md` 输出 `004-测试用例.md`。
3. 在 `onlyAI/testing.md` 和 `onlyAI/verification.md` 记录测试执行过程、输出和风险评估。
4. 若本阶段包含接口调用、业务链路验证或脚本化探针验证，必须基于 `assets/链路探针结果Markdown模板.md` 输出 `docs/[需求目录]/[需求标识]_probe_result.md` 可读结果；结果文件只保留固定 Markdown 表格，每次运行追加表格行，入参/出参必须同时包含 JSON 与字段说明，测试条件与边界条件必须分列记录。
5. 执行测试后，使用 `assets/测试报告模板.md` 输出 `005-测试报告.md`；如生成链路探针 Markdown 结果，报告中必须引用该结果路径。
6. 在 `onlyAI/review-report.md` 写入自我审查结论，并明确是否需要补充安全、性能、稳定性专项复核。
7. 完成后回填 `sdlc_session_register` 会话进度，随后同步任务文档与 `ai_localbase` 知识库；如有必要，生成 `summary.md` 汇总结果。

### `sdlc-debug`

排查与修复阶段。

1. 先按上方阶段选角计划确定候选角色名称，再通过 `skills/who/SKILL.md` 的选择规则重新选角：一般由 `Senior Developer` 或 `Incident Response Commander` 主角色。
2. 先复现问题，再写入 `assets/Debug排查记录模板.md` 生成 `006-Debug排查记录.md`。
3. 在 `onlyAI/operations-log.md` 记录定位过程，在 `onlyAI/verification.md` 记录回归验证结果。
4. 修复完成后回填 `sdlc_session_register` 会话进度，同步更新任务文档与 `ai_localbase` 知识库，并在需要时补充 `summary.md`。

### `sdlc-solo`

全自动模式：从当前阶段自动执行到测试完成。

1. 先检测 `docs/[需求目录]/` 的现有产物，判断当前已完成阶段。
2. 先判断下一个未完成阶段，并复用该阶段的角色计划；从下一个未完成阶段开始，每进入一个阶段都必须先做一次阶段选角。
3. 若预计剩余工作量大于 3 天，必须先警告用户再继续。
4. 遇到待确认文档时，Solo 模式下由 AI 自动决策，并将理由写入设计文档和待确认文档。
5. 全部完成后自动生成 `summary.md`，回填 `sdlc_session_register` 会话进度，并同步任务文档与 `ai_localbase` 知识库。

### `sdlc-script`

一次性脚本任务：适用于 Shell、PHP、Python、SQL、Node.js 等一次性执行脚本的轻量级流程。

1. 先按上方阶段选角计划确定候选角色名称，再通过 `skills/who/SKILL.md` 的选择规则确定当前脚本任务主角色；涉及生产、数据库写入或运维操作时必须补 `SRE`、`Database Optimizer` 或 `Security Engineer` 作为复核角色。
2. 确认脚本类型、执行环境、风险等级、是否可重复执行和任务目录；创建或更新 `status.md`：`当前阶段：script`，`状态：进行中`，记录脚本任务类型、目标环境、执行角色和复核角色。
3. 使用 `assets/脚本任务模板.md` 输出 `docs/[需求目录]/script-[序号]-[简述].md`，并填写任务背景、影响范围、前置条件、核心逻辑、安全措施、回滚方案、执行计划和验证命令。
4. 如为数据库脚本，同时输出到 `docs/[需求目录]/sql/`；编写 SQL 前必须先按项目规则检查表结构和索引。
5. 高危脚本必须包含 Dry-run、分批执行、回滚方案和执行前后验证；生产环境脚本必须先在测试或预发环境验证通过。
6. 所有脚本正文必须包含中文注释，说明核心逻辑、约束条件和使用方式。
7. 脚本文档中必须明确是否可重复执行（幂等性）；若脚本未执行，仅完成设计，则标记 `状态：待执行` 并写明人工确认条件。
8. 脚本执行或设计完成后，更新 `status.md`、`onlyAI/operations-log.md`、`onlyAI/testing.md` 和 `onlyAI/verification.md`；若能取得当前 `session_id`，调用 `scripts/sdlc_session_register.py progress` 回填 `task_dir`、`feature="完成脚本任务"` 和实际进度。
9. 完成后同步任务文档与 `ai_localbase` 知识库；如有必要，生成 `summary.md` 汇总脚本任务结论。

### `sdlc-history`

历史会话查询：用于只读查看 `docs/ai-register.db` 中的 SDLC 会话登记，不进入设计、施工或测试阶段。

1. 用户明确输入 `sdlc-history`，或询问"某需求历史会话 / 这个需求谁做过 / 怎么续接某需求 / 看某任务登记"时触发。
2. 直接调用 `skills/software-dev-process-roles/scripts/sdlc_session_register.py query`，不得创建设计、施工或测试文档。
3. 无关键词时查询全部历史：
   ```bash
   python skills/software-dev-process-roles/scripts/sdlc_session_register.py query
   ```
4. 用户给出明确任务目录时优先精确查询：
   ```bash
   python skills/software-dev-process-roles/scripts/sdlc_session_register.py query --task-dir "docs/[需求目录]/"
   ```
5. 用户给出自然语言关键词时使用模糊查询：
   ```bash
   python skills/software-dev-process-roles/scripts/sdlc_session_register.py query --keyword "[关键词]"
   ```
6. 输出查询表格后，用 1-3 句话说明可续接的 `resume(shell)`、任务目录和最近进度；若结果为空，说明登记库为空或未匹配到该需求。

## SDLC 会话登记机制

`sdlc_session_register` hook 插件和本 Skill 脚本共同维护 Codex 会话与 SDLC 任务进度的关联：

- `SessionStart`：当 `CODEX_HOOK_EVENTS_SESSION_START='sdlc_session_register'` 时，插件自动写入 `session_id`、模型、项目目录和续接命令。
- 手动登记：必要时可调用 `scripts/sdlc_session_register.py upsert` 写入或更新当前 `session_id` 的工具、模型、项目目录和续接命令。
- 阶段推进：本 Skill 在阶段完成或任务完成后调用 `scripts/sdlc_session_register.py progress`，只更新当前 `session_id` 对应行的 `task_dir`、`feature`、`progress`。
- 历史查询：`sdlc-history` 使用 `scripts/sdlc_session_register.py query` 只读查询，不修改文档和代码。

身份登记命令模板：

```bash
python skills/software-dev-process-roles/scripts/sdlc_session_register.py upsert \
  --session <当前 session_id> \
  --tool "Codex" \
  --model <当前模型名>
```

进度回填命令模板：

```bash
python skills/software-dev-process-roles/scripts/sdlc_session_register.py progress \
  --session <当前 session_id> \
  --task-dir "docs/[需求目录]/" \
  --feature "本次完成的功能" \
  --progress "75%"
```

若当前上下文没有可用 `session_id`，不得猜测；只更新 `status.md`、`003-施工文档.md` 和 `onlyAI/operations-log.md`，并在日志中说明"缺少 session_id，未回填 SDLC 会话登记库"。

## 可用资源

- `software-dev-process-roles/assets/概要设计模板.md`
- `software-dev-process-roles/assets/详细设计模板.md`
- `software-dev-process-roles/assets/施工文档模板.md`
- `software-dev-process-roles/assets/测试用例模板.md`
- `software-dev-process-roles/assets/测试报告模板.md`
- `software-dev-process-roles/assets/链路探针结果Markdown模板.md`
- `software-dev-process-roles/assets/执行记录模板.md`
- `software-dev-process-roles/assets/文件改动记录模板.md`
- `software-dev-process-roles/assets/Debug排查记录模板.md`
- `software-dev-process-roles/assets/待确认模板.md`
- `software-dev-process-roles/assets/脚本任务模板.md`
- `shell/codex_hook/plugins/sdlc_session_register/hook.py`（SessionStart 首次会话登记插件）
- `software-dev-process-roles/scripts/sdlc_session_register.py`（身份登记、阶段进度回填与历史查询脚本）
- `skills/who/SKILL.md`（角色选择规则）
- `skills/who/roles/`（角色库）

## 落地规则总结

1. **SDLC 决定阶段，角色决定做法。**
2. **每个阶段只保留一个主角色，必要时补一个辅助角色。**
3. **所有阶段结果最终都要回写任务文档，不允许只口头汇报。**

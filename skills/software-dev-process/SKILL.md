---
name: software-dev-process
description: 管理完整的软件开发生命周期（需求理解、概要设计、详细设计、施工实现、测试与排查）。用于通过 sdlc-design-1、sdlc-design-2、sdlc-implement、sdlc-test、sdlc-debug 分阶段驱动任务，通过 sdlc-solo 全自动执行剩余流程，通过 sdlc-script 处理一次性脚本任务，或通过 sdlc-history 查询会话登记库。强制检查前置产物、模板输出和阶段边界。
---

# Software Development Process Skill

当用户明确使用 `sdlc-design-1`、`sdlc-design-2`、`sdlc-implement`、`sdlc-test`、`sdlc-debug`、`sdlc-solo`、`sdlc-script`、`sdlc-history`，或要求按标准 SDLC 阶段推进任务时，使用本 Skill。

## 核心约束

1. **指令驱动与前置校验**：每个开发阶段必须通过对应的 `sdlc-*` 指令触发。执行任何阶段前，必须校验前置阶段的产出物是否存在，严禁擅自跳阶段。
2. **先读上下文再设计**：设计阶段必须先读取 `docs/[需求目录]/prd/` 下的需求与上下文；如果本地信息仍不足以继续，再向用户提问。
3. **强制逻辑推导**：在概要设计阶段必须使用 `sequential-thinking` 进行逻辑推导，并使用 `brainstorming` 做方案发散与收敛；需要比较方案时，先列出候选方案再收敛。
4. **待确认机制**：在设计阶段，对于无法明确的逻辑、需要用户决策的方案选择、存在风险的设计点，必须生成"待确认文档"（如 `001-概要设计-待确认.md`）。进入下一阶段前强制校验该文档，根据用户反馈完成设计。在 solo 模式下，AI 自动选择最优方案并在文档中说明选择理由。
5. **允许回退修正**：若在施工或测试时发现前期设计存在重大缺陷，必须停止当前阶段，回退到 `sdlc-design-2` 更新设计文档。
6. **控制改动边界**：代码实现时，只清理本次施工直接产生的脏代码；未获许可时，不得顺手大范围重构历史代码，也不得修改未在准入清单中的文件。
7. **记忆回写必做**：任务完成后必须优先 `update_memory` 对应节点；若无对应节点，则先 `create_memory` 再回写结论，禁止跳过记忆更新直接结束任务。**记忆回写时，必须使用 `status.md` 中记录的系统名称作为知识库路径**（如：`core://systems/用户中心/...`）。
8. **AI 登记必做**：执行 SDLC 时，必须维护仓库级 `docs/ai-register.db`。若当前项目启用了 `sdlc_session_register` hook，`SessionStart` 会自动登记首次会话身份；必要时可调用本 Skill 的 `scripts/sdlc_session_register.py upsert` 补写身份，在阶段切换、施工任务完成、测试执行等节点调用 `progress` 回填任务目录、完成功能和进度。

## 目录与资源约定

- **模板读取**：所有文档基于本 Skill `assets/` 目录下的中文模板生成。
- **文档输出**：设计、施工、测试和排查文档统一输出到 `docs/[需求目录]/`。
- **onlyAI 工作区**：仅供 AI 读取和维护的过程文件统一输出到 `docs/[需求目录]/onlyAI/`，包括 `structured-request.json`、`context-scan.json`、`context-question-N.json`、`operations-log.md`、`testing.md`、`verification.md`、`review-report.md`。
- **SQL 脚本**：数据库变更脚本统一输出到 `docs/[需求目录]/sql/`。
- **摘要文档**：如有必要，可自主生成 `docs/[需求目录]/summary.md` 或 `docs/index.md` 汇总阶段结论与交付物索引。
- **脚本任务文档**：一次性 Shell、PHP、Python、SQL、Node.js 等脚本任务基于 `assets/脚本任务模板.md` 输出 `docs/[需求目录]/script-[序号]-[简述].md`。
- **SDLC 会话登记库**：仓库级 `docs/ai-register.db` 的首次会话身份由 `shell/codex_hook/plugins/sdlc_session_register/hook.py` 在 `SessionStart` 维护；手动身份登记、阶段推进和历史查询由本 Skill 的 `scripts/sdlc_session_register.py` 维护，使用 `upsert` 写入/更新身份，使用 `progress` 回填任务目录、完成功能和进度，使用 `query` 只读查询历史。

## 阶段命令

### `sdlc-design-1`

阶段 1：需求理解与概要设计。

1. 简单任务可直接进入上下文收集；复杂任务必须先确认任务目录。
2. 在 `docs/[需求目录]/onlyAI/structured-request.json` 记录结构化需求，**必须包含本次任务所属的系统名称**。
3. 首次创建 `status.md` 时，**必须在文件头部记录本次任务所属的系统名称**（如：`系统：用户中心`），后续所有记忆回写将使用该系统名作为知识库路径。
4. 输出 `docs/[需求目录]/onlyAI/context-scan.json`，完成结构化快速扫描。
5. 使用 `sequential-thinking` 梳理问题、约束和候选方案，并使用 `brainstorming` 做多方案发散。
6. 针对高优疑问补充 `docs/[需求目录]/onlyAI/context-question-N.json`，完成充分性检查后再进入设计。
7. 基于 `assets/概要设计模板.md` 输出 `001-概要设计.md`。
8. **待确认机制**：如果在设计过程中发现以下情况，生成 `001-概要设计-待确认.md`：
   - 存在多个技术方案，需要用户决策
   - 业务逻辑不明确，需要用户澄清
   - 存在架构风险或性能风险，需要用户确认可接受程度
   - 涉及外部系统集成，接口规范待确认
9. **待确认项处理**（在当前阶段完成）：
   - **分阶段模式**：生成待确认文档后，暂停并提示用户处理。用户填写决策后，AI 根据决策更新 `001-概要设计.md`，重新收敛设计逻辑，将待确认文档状态标记为"已处理"。**只有待确认文档状态为"已处理"后，才能进入下一阶段**。
   - **Solo 模式**：生成待确认文档后，AI 立即自动评估各方案（性能、可维护性、实现成本、风险、扩展性），选择最优方案，在 `001-概要设计.md` 中补充"AI 自动决策"章节说明理由，重新收敛设计逻辑，将待确认文档状态标记为"已处理"，然后继续。
10. **阶段完成校验**：确认 `001-概要设计-待确认.md` 不存在或状态为"已处理"后，提示进入 `sdlc-design-2`。

### `sdlc-design-2`

阶段 2：详细设计与施工规划。

1. **前置校验**：检查是否存在 `001-概要设计-待确认.md`。
   - 如果存在且状态为"待处理"，**拒绝进入本阶段**，提示用户必须先完成 design-1 阶段的待确认项处理。
2. 先判断需求属于短期任务（≤3天）还是中长期任务（>3天）。
3. 中长期任务必须先做模块化规划，拆分顶层模块、里程碑和当前模块任务。
4. 基于 `001-概要设计.md` 继续收集实现细节，并完成接口契约、风险与验证标准定义。
5. 使用 `assets/详细设计模板.md` 输出 `002-详细设计.md`。
6. 使用 `assets/施工文档模板.md` 输出 `003-施工文档.md`。
7. 在施工文档中明确改动文件清单、新增文件清单、作用域边界和中文注释要求。
8. **待确认机制**：如果在详细设计过程中发现以下情况，生成 `002-详细设计-待确认.md`：
   - 数据库表结构设计存在多种方案
   - 接口参数定义需要前后端协商
   - 性能优化策略需要权衡
   - 异常处理策略需要明确
9. **待确认项处理**（在当前阶段完成）：
   - **分阶段模式**：生成待确认文档后，暂停并提示用户处理。用户填写决策后，AI 根据决策更新 `002-详细设计.md` 和 `003-施工文档.md`，重新收敛设计逻辑，将待确认文档状态标记为"已处理"。**只有待确认文档状态为"已处理"后，才能进入下一阶段**。
   - **Solo 模式**：生成待确认文档后，AI 立即自动评估各方案，选择最优方案，在 `002-详细设计.md` 中补充"AI 自动决策"章节说明理由，重新收敛设计逻辑，将待确认文档状态标记为"已处理"，然后继续。
10. **阶段完成校验**：确认 `002-详细设计-待确认.md` 不存在或状态为"已处理"后，提示进入 `sdlc-implement`。

### `sdlc-implement`

阶段 3：代码实现。

1. **前置校验**：检查是否存在 `002-详细设计-待确认.md`。
   - 如果存在且状态为"待处理"，**拒绝进入本阶段**，提示用户必须先完成 design-2 阶段的待确认项处理。
2. **读取施工文档**：读取 `003-施工文档.md` 中的任务拆解清单，确认每个任务的实施步骤和文件清单。
3. **任务级实施**：严格按照施工文档中的任务顺序，逐个任务执行：
   - 每次只执行一个任务
   - 严格按照该任务的文件清单编码，禁止越界施工
   - 所有新增、修改代码必须同步补齐中文注释
   - 任务完成后，立即执行步骤 4-6
4. **记录文件改动**：每完成一个任务后，在 `003-文件改动记录.md` 中记录本次改动：
   - 使用 `assets/文件改动记录模板.md` 格式
   - 必须写明改动文件的具体行号范围（如：`src/hello.txt line 50~250`）
   - 记录改动类型（新增/修改/删除）、改动原因、关联任务
5. **更新施工文档进度**：在 `003-施工文档.md` 中更新当前任务的状态：
   - 标记任务为"已完成"
   - 填写完成时间
   - 记录实际改动的文件和行号
   - 如有偏差，说明偏差原因
6. **更新执行日志**：在 `docs/[需求目录]/onlyAI/operations-log.md` 中追加本轮实施记录。
7. **同步更新 status.md**：更新整体进度百分比和当前状态。
8. **循环执行**：返回步骤 3，继续下一个任务，直到所有任务完成。
9. **数据库脚本管理**：所有数据库相关脚本和语句统一落到 `docs/[需求目录]/sql/`。
10. **阶段总结**：所有任务完成后，可自主生成 `docs/[需求目录]/summary.md` 汇总当前阶段结果。
11. 完成后提示进入 `sdlc-test`。

### `sdlc-test`

阶段 4：质量验证与测试。

1. 使用 `assets/测试用例模板.md` 输出 `004-测试用例.md`。
2. 在 `docs/[需求目录]/onlyAI/testing.md` 与 `docs/[需求目录]/onlyAI/verification.md` 记录测试执行过程、输出和风险评估。
3. 执行测试后，使用 `assets/测试报告模板.md` 输出 `005-测试报告.md`。
4. 在 `docs/[需求目录]/onlyAI/review-report.md` 写入自我审查结论。
5. 覆盖正常路径、边界情况、非法输入和权限场景。
6. 完成后执行记忆回写；如有必要，生成 `docs/[需求目录]/summary.md` 汇总结果。

### `sdlc-debug`

排查与修复阶段。

1. 在复杂 Bug 或回归问题出现时触发。
2. 使用 `assets/Debug排查记录模板.md` 输出 `006-Debug排查记录.md`。
3. 在 `docs/[需求目录]/onlyAI/operations-log.md` 记录定位过程，在 `docs/[需求目录]/onlyAI/verification.md` 记录回归验证结果。
4. 修复完成后同步更新记忆，并在需要时补充 `docs/[需求目录]/summary.md`。

### `sdlc-solo`

全自动模式：从当前阶段自动执行到测试完成。

**适用场景**：
- 可在任何阶段开启（design-1、design-2、implement 或 test）
- 自动检测当前已完成的阶段，从下一个未完成阶段开始执行
- 适用于需求明确、边界清晰的任务

**执行流程**：
1. **阶段检测**：检查 `docs/[需求目录]/` 下的产出物，判断当前已完成哪些阶段
   - 存在 `001-概要设计.md` → design-1 已完成
   - 存在 `002-详细设计.md` 和 `003-施工文档.md` → design-2 已完成
   - 存在代码变更且 `operations-log.md` 有记录 → implement 已完成
   - 存在 `005-测试报告.md` → test 已完成

2. **工作量评估与警告**：
   - 根据需求复杂度、涉及文件数量、架构变更范围评估剩余工作量
   - **如果预计剩余工作量 > 3 天，必须向用户发出警告**：
     ```
     ⚠️ 危险警告：预计剩余工作量超过 3 天，全自动模式存在以下风险：
     - 可能产生大量代码变更，难以人工审查
     - 设计缺陷可能在后期才暴露，回退成本高
     - 复杂任务建议分阶段执行，便于中途调整
     
     是否确认继续使用 solo 模式？
     ```
   - 用户确认后才继续执行

3. **自动执行剩余阶段**：
   - 从下一个未完成阶段开始，依次自动执行：
     - `sdlc-design-1` → `sdlc-design-2` → `sdlc-implement` → `sdlc-test`
   - 每个阶段完成后自动进入下一阶段，无需用户干预
   - **待确认文档处理**：在 solo 模式下，遇到待确认文档时，AI 在当前阶段内自动处理：
     - 评估各候选方案的优劣（性能、可维护性、实现成本、风险、扩展性）
     - 选择综合评分最高的方案
     - 在对应的设计文档中补充"AI 自动决策"章节，说明选择理由和权衡考虑
     - 根据选定方案重新收敛设计逻辑，更新设计文档
     - 将待确认文档状态标记为"已处理"，填写处理时间和处理模式
     - 继续当前阶段的后续步骤，完成后进入下一阶段
   - 如在任何阶段发现需求不明确、设计缺陷或实现受阻，立即暂停并向用户报告

4. **完成与交付**：
   - 所有阶段完成后，自动生成 `docs/[需求目录]/summary.md` 汇总交付物
   - 执行记忆回写（`update_memory` 或 `create_memory`）
   - 向用户报告完整的交付清单和关键结论

**核心约束**：
- 仍需遵守所有核心约束（前置校验、模板输出、逻辑推导、记忆回写）
- 不得跳过任何必要的设计或测试步骤
- 代码实现时严格遵守改动边界，不得越界施工
- 如发现前期设计缺陷，必须回退到 `sdlc-design-2` 更新设计文档

**使用示例**：
```bash
# 从头开始全自动执行
/software-dev-process sdlc-solo

# 在 design-2 完成后，自动执行 implement + test
/software-dev-process sdlc-solo

# 在 implement 完成后，自动执行 test
/software-dev-process sdlc-solo
```

### `sdlc-script`

一次性脚本任务：适用于 Shell、PHP、Python、SQL、Node.js 等一次性执行脚本的轻量级流程。

1. 确认脚本类型、执行环境、风险等级、是否可重复执行和任务目录；创建或更新 `status.md`：`当前阶段：script`，`状态：进行中`。
2. 使用 `assets/脚本任务模板.md` 输出 `docs/[需求目录]/script-[序号]-[简述].md`，并填写任务背景、影响范围、前置条件、核心逻辑、安全措施、回滚方案、执行计划和验证命令。
3. 如为数据库脚本，同时输出到 `docs/[需求目录]/sql/`；编写 SQL 前必须先按项目规则检查表结构和索引。
4. 高危脚本必须包含 Dry-run、分批执行、回滚方案和执行前后验证；生产环境脚本必须先在测试或预发环境验证通过。
5. 所有脚本正文必须包含中文注释，说明核心逻辑、约束条件和使用方式。
6. 脚本文档中必须明确是否可重复执行（幂等性）；若脚本未执行，仅完成设计，则标记 `状态：待执行` 并写明人工确认条件。
7. 脚本执行或设计完成后，更新 `status.md`、`onlyAI/operations-log.md`、`onlyAI/testing.md` 和 `onlyAI/verification.md`；若能取得当前 `session_id`，调用 `scripts/sdlc_session_register.py progress` 回填 `task_dir`、`feature="完成脚本任务"` 和实际进度。
8. 完成后执行记忆回写；如有必要，生成 `summary.md` 汇总脚本任务结论。

### `sdlc-history`

历史会话查询：用于只读查看 `docs/ai-register.db` 中的 SDLC 会话登记，不进入设计、施工或测试阶段。

1. 用户明确输入 `sdlc-history`，或询问"某需求历史会话 / 这个需求谁做过 / 怎么续接某需求 / 看某任务登记"时触发。
2. 直接调用 `skills/software-dev-process/scripts/sdlc_session_register.py query`，不得创建设计、施工或测试文档。
3. 无关键词时查询全部历史：
   ```bash
   python skills/software-dev-process/scripts/sdlc_session_register.py query
   ```
4. 用户给出明确任务目录时优先精确查询：
   ```bash
   python skills/software-dev-process/scripts/sdlc_session_register.py query --task-dir "docs/[需求目录]/"
   ```
5. 用户给出自然语言关键词时使用模糊查询：
   ```bash
   python skills/software-dev-process/scripts/sdlc_session_register.py query --keyword "[关键词]"
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
python skills/software-dev-process/scripts/sdlc_session_register.py upsert \
  --session <当前 session_id> \
  --tool "Codex" \
  --model <当前模型名>
```

进度回填命令模板：

```bash
python skills/software-dev-process/scripts/sdlc_session_register.py progress \
  --session <当前 session_id> \
  --task-dir "docs/[需求目录]/" \
  --feature "本次完成的功能" \
  --progress "75%"
```

若当前上下文没有可用 `session_id`，不得猜测；只更新 `status.md`、`003-施工文档.md` 和 `onlyAI/operations-log.md`，并在日志中说明"缺少 session_id，未回填 SDLC 会话登记库"。

## 可用资源

- `software-dev-process/assets/概要设计模板.md`
- `software-dev-process/assets/详细设计模板.md`
- `software-dev-process/assets/施工文档模板.md`
- `software-dev-process/assets/测试用例模板.md`
- `software-dev-process/assets/测试报告模板.md`
- `software-dev-process/assets/执行记录模板.md`
- `software-dev-process/assets/文件改动记录模板.md`
- `software-dev-process/assets/Debug排查记录模板.md`
- `software-dev-process/assets/待确认模板.md`
- `software-dev-process/assets/脚本任务模板.md`
- `software-dev-process/scripts/sdlc_session_register.py`（身份登记、阶段进度回填与历史查询脚本）

## 待确认文档机制

### 何时生成待确认文档

在设计阶段（design-1 或 design-2），遇到以下情况时必须生成待确认文档：

1. **技术方案选择**：存在多个可行方案，各有优劣，需要权衡决策
2. **业务逻辑不明确**：需求描述模糊，存在多种理解方式
3. **架构/性能风险**：设计存在已知风险，需要确认可接受程度
4. **外部依赖**：涉及外部系统集成，接口规范或调用方式待确认
5. **数据结构设计**：数据库表结构或数据模型存在多种设计方案
6. **异常处理策略**：错误处理、降级策略、补偿机制需要明确

### 待确认文档格式

使用 `assets/待确认模板.md` 生成，文件命名规则：
- 概要设计阶段：`001-概要设计-待确认.md`
- 详细设计阶段：`002-详细设计-待确认.md`

每个待确认项必须包含：
- 问题描述
- 候选方案（至少 2 个）
- 每个方案的优缺点、风险评估、实现成本
- AI 推荐方案（如有明确倾向）
- 优先级标记（高/中/低）

### 处理流程

#### 分阶段模式
1. 生成待确认文档后，暂停当前阶段
2. 提示用户查看并处理待确认项
3. 用户在文档中填写决策结果
4. AI 读取用户决策，更新设计文档，重新收敛设计逻辑
5. 将待确认文档头部状态更新为"已处理"，填写处理时间
6. 将每个待确认项的"决策状态"更新为"已决策"
7. **待确认文档保留作为决策记录，不删除**
8. 完成当前阶段的后续步骤
9. **只有待确认文档状态为"已处理"后，才能进入下一阶段**

#### Solo 模式
1. 生成待确认文档后，AI 立即在当前阶段内自动处理
2. 评估各方案（性能、可维护性、实现成本、风险、扩展性）
3. 选择综合评分最高的方案
4. 在设计文档中补充"AI 自动决策"章节：
   - 说明选择的方案
   - 列出选择理由和权衡考虑
   - 标注"本决策由 AI 在 solo 模式下自动完成"
5. 根据选定方案重新收敛设计逻辑，更新设计文档
6. 将待确认文档头部状态更新为"已处理"，填写处理时间和处理模式
7. 将每个待确认项的"决策状态"更新为"已决策"，在"用户决策"部分填写 AI 选择的方案和理由
8. **待确认文档保留作为决策记录，不删除**
9. 继续当前阶段的后续步骤，完成后自动进入下一阶段

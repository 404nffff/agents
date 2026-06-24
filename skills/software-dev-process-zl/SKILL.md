  ---
name: software-dev-process-zl
description: 用于项目按 SDLC 阶段推进任务，覆盖需求理解、概要设计、详细设计、施工实现、链路脚本验证与调试；通过 sdlc-design-1、sdlc-design-2、sdlc-implement、sdlc-test、sdlc-debug、sdlc-solo 驱动。
---

# Software Development Process ZL Skill

当用户明确使用 `sdlc-design-1`、`sdlc-design-2`、`sdlc-implement`、`sdlc-test`、`sdlc-debug`、`sdlc-solo`，或要求在项目中按标准 SDLC 阶段推进任务时，使用本 Skill。

本 Skill 参照 `software-dev-process` 的阶段流程；保留项目专用的 PHP 链路探针验证方式。

## 核心约束

1. **指令驱动与前置校验**：每个开发阶段必须通过对应的 `sdlc-*` 指令触发。执行任何阶段前，必须校验前置阶段产物是否存在，严禁擅自跳阶段。
2. **先读上下文再设计**：设计阶段必须先读取 `docs/[需求目录]/prd/` 或现有任务文档；本地信息不足时再向用户提问。
3. **强制逻辑推导**：概要设计阶段必须使用 `sequential-thinking` 进行逻辑推导，并使用 `brainstorming` 做方案发散与收敛。
4. **待确认机制**：设计阶段遇到业务不明确、方案需决策、风险需接受时，必须生成待确认文档；进入下一阶段前确认状态已处理。
5. **控制改动边界**：施工时严格按 `003-施工文档.md` 的文件清单实施，禁止越界修改。
6. **默认代码优先策略**：日常开发默认按“先实现业务代码，再补充/更新链路脚本、组装真实验证数据、最后本地运行验证”的顺序执行。
7. **测试脚本策略**：`sdlc-test` 不要求编写单元测试；必须复制 `assets/zl_templete.php` 到 `docs/[需求目录]/[需求标识]_probe.php`，保留 `run($step)` 统一步骤入口与最终 JSON 出口，再替换业务依赖、入参构造、各 step 链路调用和断言逻辑。
8. **输出保真策略**：链路探针必须保留被测业务函数的原始输出内容，禁止把原函数返回值重构成摘要、改名字段、丢弃字段或替换为自定义包装数据；“是否修改完毕、是否有 bug”等检查结论只能追加到 `assertion`、`verification` 或同级元信息字段，不能覆盖 `data` 中的原始业务输出。
9. **真实数据策略**：链路验证 payload 必须优先通过 `db-query` 只读查询组装；首次使用数据库前先执行 `--list-profiles` 确认 profile。
10. **容器执行策略**：链路脚本必须使用 `work-php-exec` skill 进入 Docker 容器 `work` 执行，禁止直接在宿主机裸跑 PHP；执行完成后必须输出并记录结果文件路径、核心 JSON 和错误信息。
11. **接口文档策略**：链路脚本验证通过后，必须按照 `assets/api_templete.test` 的 showdoc 注释格式生成接口文档，并输出到当前项目根目录 `api/doc/`；一个 `.test` 文件允许连续放置多个 `showdoc` 注释块，每个注释块对应一个接口。
12. **Debug 豁免**：`sdlc-debug` 默认采用“链路探针复现 -> 修复逻辑 -> 链路探针回归”的复现先行方式。

## 目录与资源约定

- **模板读取**：所有文档基于本 Skill `assets/` 目录下的中文模板生成。
- **文档输出**：设计、施工、测试和排查文档统一输出到 `docs/[需求目录]/`。
- **onlyAI 工作区**：仅供 AI 读取和维护的过程文件统一输出到 `docs/[需求目录]/onlyAI/`，包括 `structured-request.json`、`context-scan.json`、`context-question-N.json`、`operations-log.md`、`testing.md`、`verification.md`、`review-report.md`。
- **链路脚本**：测试阶段生成的 PHP 链路探针脚本、payload JSON 和执行结果 JSON 统一输出到 `docs/[需求目录]/`；链路脚本必须使用 `work-php-exec` skill 在容器 `work` 内执行。
- **接口文档**：测试阶段生成的接口文档统一输出到项目根目录 `api/doc/`，文件内容必须遵循 `assets/api_templete.test` 的 showdoc 注释格式；同一需求涉及多个接口时，优先写入同一个 `.test` 文件，按接口数量追加多个 `showdoc` 注释块并递增 `@number`。
- **SQL 脚本**：数据库变更脚本统一输出到 `docs/[需求目录]/sql/`；测试阶段只读取真实数据时优先使用 `db-query`，不把只读查询脚本当作数据库变更脚本。
- **摘要文档**：如有必要，可自主生成 `docs/[需求目录]/summary.md` 或 `docs/index.md` 汇总阶段结论与交付物索引。

## 阶段命令

### `sdlc-design-1`

阶段 1：需求理解与概要设计。

1. 简单任务可直接进入上下文收集；复杂任务必须先确认任务目录。
2. 在 `docs/[需求目录]/onlyAI/structured-request.json` 记录结构化需求，必须包含系统名称。
3. 首次创建 `status.md` 时，记录系统名称、当前阶段和整体进度。
4. 输出 `docs/[需求目录]/onlyAI/context-scan.json`，完成结构化快速扫描。
5. 使用 `sequential-thinking` 梳理问题、约束和候选方案，并使用 `brainstorming` 做多方案发散。
6. 针对高优疑问补充 `docs/[需求目录]/onlyAI/context-question-N.json`，完成充分性检查后再进入设计。
7. 基于 `assets/概要设计模板.md` 输出 `001-概要设计.md`。
8. 如存在方案歧义、风险点或业务待定，生成 `001-概要设计-待确认.md`。
9. 确认待确认项已处理后，提示进入 `sdlc-design-2`。

### `sdlc-design-2`

阶段 2：详细设计与施工规划。

1. 前置校验：若 `001-概要设计-待确认.md` 状态仍为“待处理”，拒绝进入本阶段。
2. 先判断需求属于短期任务（≤3天）还是中长期任务（>3天）。
3. 中长期任务必须先做模块化规划，拆分顶层模块、里程碑和当前模块任务。
4. 基于 `001-概要设计.md` 继续收集实现细节，并完成接口契约、风险与验证标准定义。
5. 使用 `assets/详细设计模板.md` 输出 `002-详细设计.md`。
6. 使用 `assets/施工文档模板.md` 输出 `003-施工文档.md`。
7. 在施工文档中明确改动文件清单、新增文件清单、作用域边界和中文注释要求。
8. 如存在方案待定、接口不明确或异常策略未定，生成 `002-详细设计-待确认.md`。
9. 确认待确认项已处理后，提示进入 `sdlc-implement`。

### `sdlc-implement`

阶段 3：代码实现。

1. 前置校验：若 `002-详细设计-待确认.md` 状态仍为“待处理”，拒绝进入本阶段。
2. 读取 `003-施工文档.md` 中的任务拆解清单，确认每个任务的实施步骤和文件清单。
3. 严格按照任务顺序逐个执行，每次只执行一个任务。
4. 严格按照该任务的文件清单编码，禁止越界施工。
5. 所有新增、修改代码必须同步补齐中文注释。
6. 每完成一个任务，立即更新 `003-文件改动记录.md`、`003-施工文档.md`、`onlyAI/operations-log.md` 和 `status.md`。
7. 所有数据库相关脚本和语句统一落到 `docs/[需求目录]/sql/`。
8. 全部任务完成后，可生成 `docs/[需求目录]/summary.md`，然后提示进入 `sdlc-test`。

### `sdlc-test`

阶段 4：质量验证与测试。

1. 使用 `assets/测试用例模板.md` 输出 `004-测试用例.md`，用例必须映射到链路探针输入、执行命令和期望 JSON 结果；不得要求新增单元测试。
2. 复制 `assets/zl_templete.php` 到 `docs/[需求目录]/[需求标识]_probe.php`，保留 `run($step)`、`getStep()`、`formatStepResult()`、`step=all` 聚合逻辑和最终 `echo json_encode(...)` 统一出口。
3. 替换类名、业务依赖加载、payload 到业务入参转换、`runStepN()` 真实链路调用和断言逻辑；`runStepN()` 调用业务函数后，原函数返回内容必须完整进入 `data` 字段，禁止重构输出内容；修改完成度、占位逻辑是否清理、断言是否通过、是否发现 bug 等结论必须写入 `assertion` 或 `verification` 元信息；禁止直接运行或交付模板原文件。
4. 首次使用数据库前必须加载 `db-query` skill，先执行 `--list-profiles` 确认 profile，再通过只读查询组装真实 payload JSON。
5. 必须加载并使用 `work-php-exec` skill 执行链路脚本；Windows 环境优先使用 `powershell -ExecutionPolicy Bypass -File ~/.codex/skills/work-php-exec/run-work-php.ps1 --timeout 20s docs/[需求目录]/[需求标识]_probe.php all`，并按需追加 `--method`、`--action` 标注业务入口。
6. 执行完成后必须读取并输出 `work-php-exec` 生成的结果文件摘要；同时将链路脚本自身输出的 JSON 结果保存到 `docs/[需求目录]/[需求标识]_probe_result.json`，在 `onlyAI/testing.md` 和 `onlyAI/verification.md` 记录执行命令、work-php-exec 结果文件路径、payload 路径、链路脚本路径、结果 JSON 路径、核心响应、错误信息和风险评估。核心响应必须同时核对 `data` 原始业务输出、`assertion` 断言结果和 `verification.modified / verification.has_bug` 自检结论。
7. 必须基于 `assets/链路探针结果Markdown模板.md` 输出 `docs/[需求目录]/[需求标识]_probe_result.md` 可读结果。结果文件只保留 Markdown 表格，表头固定为接口地址、入参、出参、测试条件、边界条件、测试结果、请求时间、关联脚本文件；每次运行追加表格行，旧文件不是该表头时先重置为该表头。入参和出参单元格必须同时包含 JSON 与字段说明；出参 JSON 必须取链路探针结果 JSON 中对应 step 的 `data` 字段，也就是当前接口或业务方法的原始返回值，禁止把 `status`、`assertion`、`verification`、`elapsed_ms`、`step` 等探针外层包装字段写入出参；测试条件只写数据来源、配置条件、样本条件和环境条件；边界条件必须独立写入边界条件列，禁止混入测试条件列。
8. 根据实际接口变更生成接口文档，必须参考 `assets/api_templete.test` 的 showdoc 注释格式，至少包含 `@catalog`、`@title`、`@description`、`@method`、`@url`、`@param`、`@return`、`@return_param`、`@remark`、错误码说明、返回示例、前端使用示例和注意事项；接口文档文件输出到当前项目根目录 `api/doc/[需求标识].test`。若一个需求包含多个接口，必须在同一个 `.test` 文件中连续追加多个 `showdoc` 注释块，每个接口一个注释块，并按顺序递增 `@number`。
9. 使用 `assets/测试报告模板.md` 输出 `005-测试报告.md`，并在报告中引用接口文档路径、work-php-exec 结果文件路径、链路脚本结果 JSON 路径和链路探针 Markdown 结果路径。
10. 在 `onlyAI/review-report.md` 写入自我审查结论。
11. 完成后同步任务文档与正确项目知识库；如知识库 ID 存疑，暂停写入并向用户确认。

### `sdlc-debug`

排查与修复阶段。

1. 在复杂 Bug 或回归问题出现时触发。
2. 使用 `assets/Debug排查记录模板.md` 输出 `006-Debug排查记录.md`。
3. 先用链路探针复现问题，再修复逻辑。
4. 在 `onlyAI/operations-log.md` 记录定位过程，在 `onlyAI/verification.md` 记录回归验证结果。
5. 修复完成后同步更新任务文档与正确项目知识库；如知识库 ID 存疑，暂停写入并向用户确认。

### `sdlc-solo`

全自动模式：从当前阶段自动执行到测试完成。

1. 检测 `docs/[需求目录]/` 的现有产物，判断当前已完成阶段。
2. 判断下一个未完成阶段，从该阶段开始依次执行。
3. 若预计剩余工作量大于 3 天，必须先警告用户再继续。
4. 遇到待确认文档时，Solo 模式下由 AI 自动决策，并将理由写入设计文档和待确认文档。
5. 全部完成后自动生成 `summary.md`，并同步任务文档与正确项目知识库；如知识库 ID 存疑，暂停写入并向用户确认。

## 可用资源

- `software-dev-process-zl/assets/概要设计模板.md`
- `software-dev-process-zl/assets/详细设计模板.md`
- `software-dev-process-zl/assets/施工文档模板.md`
- `software-dev-process-zl/assets/测试用例模板.md`
- `software-dev-process-zl/assets/测试报告模板.md`
- `software-dev-process-zl/assets/执行记录模板.md`
- `software-dev-process-zl/assets/文件改动记录模板.md`
- `software-dev-process-zl/assets/Debug排查记录模板.md`
- `software-dev-process-zl/assets/待确认模板.md`
- `software-dev-process-zl/assets/链路探针结果Markdown模板.md`
- `software-dev-process-zl/assets/api_templete.test`
- `software-dev-process-zl/assets/zl_templete.php`

## 落地规则总结

1. SDLC 指令决定阶段边界。
2. 施工按任务顺序串行推进，每次只执行一个任务。
3. 测试阶段使用 `assets/zl_templete.php` 生成 PHP 链路探针，不新增单元测试要求。
4. 链路探针必须保留原函数输出内容：`data` 字段承载业务函数原始返回；`assertion`、`verification` 字段承载修改完成度、占位检查和 bug 判断；禁止用自定义摘要替换 `data`。
5. 链路探针必须通过 `work-php-exec` 在容器 `work` 内执行，执行后输出结果摘要并记录结果文件。
6. 链路探针 Markdown 结果必须按 `assets/链路探针结果Markdown模板.md` 输出纯表格，入参/出参必须带字段说明，出参必须取对应 step 的 `data` 原始业务输出，边界条件必须独立成列。
7. 接口变更必须按 `assets/api_templete.test` 格式生成 showdoc 接口文档，输出到项目根目录 `api/doc/`；一个 `.test` 文件可包含多个接口，每个接口一个 `showdoc` 注释块。
8. 所有阶段结果最终都要回写任务文档，不允许只口头汇报。

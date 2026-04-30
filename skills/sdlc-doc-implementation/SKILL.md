---
name: sdlc-doc-implementation
description: Use when the user explicitly provides a docs task directory such as docs/[任务目录]/ or a concrete set of software-dev-process documents, and wants implementation, testing, debugging, or delivery work to be executed strictly from those documents rather than from ad-hoc assumptions.
---

# SDLC Doc Implementation

## Overview

这个 skill 用于“文档驱动施工”。  
前提是用户已经明确给出 `docs/[任务目录]/` 路径，或给出一组符合 `software-dev-process` 结构的文档，然后要求基于这些文档继续实现、补测试、排查或收尾。

## Trigger Rule

只有满足下面任一条件时才使用这个 skill：
- 用户明确给出 `docs/[任务目录]/` 目录路径
- 用户明确给出 `001-概要设计.md`、`002-详细设计.md`、`003-施工文档.md`、`status.md` 这类文档集合
- 用户明确要求“根据这套 software-dev-process 文档来实现”

不要在下面场景触发：
- 只有口头需求，没有文档路径或文档集合
- 用户只是问某个接口、某段代码，不是要求按文档推进施工
- 用户要做的是某个专用脚本联调，且已有更专用的 skill 可用

## Required Inputs

开始前必须拿到至少一项：
- 一个明确的 `docs/[任务目录]/` 路径
- 一组明确的文档路径

如果用户没给，先让用户补，不要自己猜任务目录。

如果用户要求“生成脚本”或“按文档产出脚本”，还必须额外拿到一项脚本参照示例：
- 现有脚本路径
- 现有接口/命令行脚本示例
- 期望模仿的输出格式示例
- 用户手写的伪代码或示例片段

如果没有参照示例，先提示用户明确指定，不要直接按自己的习惯生成脚本。

如果用户要求“生成脚本”且没有另外指定输出位置，默认输出路径必须放在对应的 `docs/[任务目录]/` 下，不要默认写到项目根目录。

## Document Set

优先读取这些文件：
- `status.md`
- `001-概要设计.md`
- `001-概要设计-待确认.md`
- `002-详细设计.md`
- `002-详细设计-待确认.md`
- `003-施工文档.md`
- `003-文件改动记录.md`
- `004-测试用例.md`
- `005-测试报告.md`
- `006-Debug排查记录.md`
- `onlyAI/structured-request.json`
- `onlyAI/context-scan.json`
- `onlyAI/context-question-N.json`
- `onlyAI/operations-log.md`
- `onlyAI/testing.md`
- `onlyAI/verification.md`
- `onlyAI/review-report.md`

如果文档缺失，不要直接补代码，先判断是否缺的是当前阶段的前置产物。

## Execution Flow

1. 读取 `status.md`，确认系统名、当前阶段、整体状态、阻塞项。
2. 如果本轮目标包含“生成脚本”，先检查用户是否已经指定脚本参照示例；若未指定，先询问，暂停施工。
3. 读取当前阶段必需的前置文档，检查是否存在“待确认”文档且状态仍为待处理。
4. 读取 `003-施工文档.md`，只按其中批准的文件范围和任务清单施工。
5. 如果目标包含“生成脚本”，开始动代码前先确认脚本输出路径；默认应落在 `docs/[任务目录]/` 下，除非用户明确指定其他位置。
6. 开始动代码前，再核对一次目标文件是否真的在施工文档范围内。
7. 每完成一个任务，同步维护：
   - `003-施工文档.md`
   - `003-文件改动记录.md`
   - `onlyAI/operations-log.md`
   - `status.md`
8. 进入测试或排查时，再补 `004/005/006` 和 `onlyAI/testing.md`、`onlyAI/verification.md`、`onlyAI/review-report.md`。

## Phase Rules

### 实现

如果用户要求“根据文档实现”：
- 必须先读 `003-施工文档.md`
- 只执行当前任务对应的文件清单
- 如果 `002-详细设计-待确认.md` 仍待处理，拒绝直接施工

### 测试

如果用户要求“根据文档补测试/出测试报告”：
- 必须先读 `004-测试用例.md`（若有）和 `005-测试报告.md`（若有）
- 测试过程记录到 `onlyAI/testing.md` 与 `onlyAI/verification.md`
- 不能只口头说“已验证”，必须留痕

### Debug

如果用户要求“根据文档排查问题”：
- 必须先读 `006-Debug排查记录.md`（若有）
- 没有排查文档时，可创建或补写，但过程要落到 `onlyAI/operations-log.md` 与 `onlyAI/verification.md`

## Scope Rules

默认边界：
- 只改文档中已批准的文件
- 只做当前阶段允许的动作
- 不因为“顺手”扩展到未列出的模块

只有下面情况才允许越出当前施工清单：
- 用户明确追加了改动范围
- 发现文档与实际代码严重不一致，且不修正就无法完成当前任务

如果越界，先更新文档，再继续实现。

## Output Style

向用户汇报时优先给这些信息：
- 当前使用的是哪个 `docs/[任务目录]/`
- 当前阶段和前置校验是否通过
- 本轮按文档执行了哪些任务
- 实际改动是否仍在施工范围内
- 哪些文档已同步更新
- 哪些测试已执行，哪些因条件不足未执行

不要把“根据文档实现”说成“我猜测应该这样做”。

## Common Cases

### 用户给一个任务目录，让你继续开发

做法：
- 先读 `status.md`
- 再读 `003-施工文档.md`
- 按任务顺序选当前待做项
- 动代码后同步更新文档

### 用户给几份设计文档，让你直接施工

做法：
- 先确认是否同时给了 `003-施工文档.md`
- 没有施工文档时，不直接大规模编码
- 先补足实施边界，再进入实现

### 用户给文档，让你生成脚本

做法：
- 先确认用户是否明确给了脚本参照示例
- 如果没有，先提示用户指定“参照哪个现有脚本/输出格式/示例片段”
- 只有拿到参照示例后，才根据 `003-施工文档.md` 和相关设计文档生成脚本
- 如果用户没有单独指定输出目录，脚本文件默认必须生成到对应的 `docs/[任务目录]/` 下
- 生成时优先对齐参照示例的入口风格、参数组织、输出结构和注释习惯
- 如果生成的是步骤型执行脚本，必须在脚本头部明确写出步骤说明、步骤编号和命令示例
- 这类脚本必须实现 `run($step)` 方法，禁止只给零散方法不提供统一步骤入口
- `run($step)` 内部必须使用 `switch ($step)` 分发到具体步骤方法，例如 `case 1`、`case 2`、`case 3`
- 如果需要批量串联执行，也只能在外层循环调用 `run($step)`，不能绕过单步入口直接代替

标准提示文案：

```text
请先指定本次生成脚本的参照示例。你可以提供现有脚本路径、期望输出格式示例、接口调用示例，或伪代码片段。我会按该示例风格，结合你提供的 docs/[任务目录]/ 文档生成脚本。
```

### 用户给施工文档，让你补测试

做法：
- 先对照 `003-施工文档.md` 与实际改动
- 再写或补 `004-测试用例.md`、`005-测试报告.md`
- 同步记录 `onlyAI/testing.md`、`onlyAI/verification.md`

## Verification

至少做两类校验：
- 文档结构校验：确认输入文档集合够支撑当前阶段
- 代码/命令校验：按当前任务需要运行语法检查、测试、或最小验证命令

完成 skill 自身修改后，可做这些最小校验：

```powershell
Get-Content -Raw C:\Users\w\.codex\skills\sdlc-doc-implementation\SKILL.md
Get-Content -Raw C:\Users\w\.codex\skills\sdlc-doc-implementation\agents\openai.yaml
```

如果本机缺少 `quick_validate.py` 的依赖，不强行改系统环境；改为手工校验 frontmatter、目录结构和触发描述是否正确。

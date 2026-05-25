# Agents 目录

本目录包含各类 Agent 规则文件，用于配置 AI Agent 的行为规范和工作流程。

## 使用说明

- **Codex 用户:** 使用 `install_codex.sh agents` 交互式选择安装
- **其他客户端:** 手动复制所需文件到对应配置目录
- **维护者:** 新增或修改 Agent 文件时，请同步更新下方目录清单

---

<!-- AGENT_CATALOG_START -->
## 项目级 Agent

适用于特定项目的 Agent 配置文件。

| 文件名 | 说明 |
| --- | --- |
| `AGENTS.md` | Codex 工作操作手册，定义角色边界、流程规范、编码与验证要求 |
| `AGENTS_MEMORY.md` | 长期记忆与 Nocturne Memory MCP 协作规范 |
| `AGENTS_v2.md` | v2 版操作手册（无 memory 依赖），保留红线、四阶段 SOP |
| `AGENTS_MEMORY_v2.md` | v2 版操作手册（带 Nocturne Memory 协作能力） |
| `AGENTS_SDP_AI_LOCALBASE_v3.md` | SDLC 版操作手册（v3），通过 `software-dev-process` Skill 驱动开发 |
| `AGENTS_SDP_AI_LOCALBASE_v4.md` | SDLC 版操作手册（v4），完全依赖 `ai_localbase` 知识库 |
| `AGENTS_SDP_AI_LOCALBASE_v5.md` | SDLC 版操作手册（v5），依赖 `ai_localbase` 并默认使用 `software-dev-process-roles` 做阶段选角 |
| `AGENTS_SDP_AI_LOCALBASE_v6.md` | SDLC 版操作手册（v6），基于 v5 并在会话初始化时自动加载 `caveman` 压缩沟通模式 |

## 全局级 Agent

适用于所有项目的通用 Agent 配置。

| 文件名 | 说明 |
| --- | --- |
| `AGENTS_GLOBAL.md` | 全局通用规则，推荐通过 `install_codex.sh agents` 安装 |
| `AGENTS_AILOCALBASE_GLOBAL.md` | 启用 `ai_localbase` 项目的全局通用规则，包含知识库初始化、检索、沉淀与降级约束 |

---

## 版本选择建议

- **新项目:** 推荐使用 `AGENTS_SDP_AI_LOCALBASE_v6.md`（最新版，依赖 ai_localbase + `software-dev-process-roles`，初始化自动加载 `caveman`）
- **需要完整表达、不启用 caveman:** 使用 `AGENTS_SDP_AI_LOCALBASE_v5.md`
- **仅需 ai_localbase、无需阶段选角:** 使用 `AGENTS_SDP_AI_LOCALBASE_v4.md`
- **需要记忆功能:** 使用 `AGENTS_MEMORY_v2.md`（支持 Nocturne Memory）
- **简单项目:** 使用 `AGENTS_v2.md`（无外部依赖）
- **全局配置:** 使用 `AGENTS_GLOBAL.md`
- **全局配置（启用 ai_localbase）:** 使用 `AGENTS_AILOCALBASE_GLOBAL.md`

<!-- AGENT_CATALOG_END -->

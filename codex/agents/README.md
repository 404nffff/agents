# Agents Catalog

本文件用于 `codex/install.sh agents` 与 `codex/install_agents.sh` 在安装前展示可选 agent 文件列表。
新增或调整 agent 文件时，请同步更新下方目录清单。


<!-- AGENT_CATALOG_START -->
## 项目级 Agent

| Name | File | Description |
| --- | --- | --- |
| AGENTS | AGENTS.md | Codex 工作操作手册，定义角色边界、流程规范、编码与验证要求。 |
| AGENTS_MEMORY | AGENTS_MEMORY.md | 长期记忆与 Nocturne Memory MCP 协作规范，包含记忆回写与触发管理流程。 |
| AGENTS_V2 | AGENTS_v2.md | 无 memory 依赖的 v2 版操作手册，保留红线、四阶段 SOP、施工文档与模块准入规则。 |
| AGENTS_MEMORY_V2 | AGENTS_MEMORY_v2.md | 带 memory 协作能力的 v2 版操作手册，包含 Nocturne Memory 工作域、检索与回写规则。 |
| AGENTS_SDP_AI_LOCALBASE_V3 | AGENTS_SDP_AI_LOCALBASE_v3.md | 面向 ai-localbase 的 SDLC 版操作手册，要求通过 `software-dev-process` Skill 驱动分阶段开发，并以 `ai_localbase` 作为项目知识沉淀优先入口。 |
| AGENTS_SDP_AI_LOCALBASE_V4 | AGENTS_SDP_AI_LOCALBASE_v4.md | 面向 ai-localbase 的 SDLC 版操作手册（v4版本），移除了 nocturne_memory，完全依赖 ai_localbase 知识库作为沉淀与检索入口。 |

## 全局级 Agent

| Name | File | Description |
| --- | --- | --- |
| AGENTS_GLOBAL | AGENTS_GLOBAL.md | 面向全局 `~/.codex/AGENTS.md` 安装入口的 agent 版本，用于通过 README 入口安装全局规则。 |
<!-- AGENT_CATALOG_END -->

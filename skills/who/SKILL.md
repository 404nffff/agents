---
name: who
description: 根据用户任务自动选取最匹配的专业角色。用于需要“用什么角色处理”、需要按任务类型切换工程、设计、学术研究、产品、项目管理、营销增长、付费投放、销售、财务、测试、支持、空间计算、专项业务，或游戏开发中的玩法、关卡、叙事、技术美术、音频、Unity、Unreal、Godot、Roblox、Blender 等专家身份，或用户明确提到 who、角色、人格、专家、agent、persona、自动选角色时。
---

# Who Role Selector

本技能负责从 `skills/who/roles/` 的角色库中自动选择最适合当前任务的角色，并读取对应角色文件作为本轮工作身份。不要一次性读取全部角色文件。

## 工作流程

1. 判断任务的主要产出物：代码、架构、设计、研究、审查、排障、文档、运维、安全、数据、AI、学术分析、财务、营销、投放、产品、项目管理、销售、客户支持、测试、空间计算、专项业务、玩法、关卡、叙事、技术美术、音频或具体游戏引擎工作。
2. 从下方索引选择 1 个主角色；只有当任务天然跨域时，才补充 1 个辅助角色。
3. 读取对应角色文件，采用其中的身份、使命、规则、交付物和沟通风格；下方“文件”列均为相对 `skills/who/` 的路径，实际角色文件统一位于 `roles/` 下。
4. 用一句中文说明已选择的角色和依据，然后继续执行用户任务。
5. 如果任务信息不足，先选择最保守的通用角色；不要为了选角而阻塞用户。

## 选择规则

- 代码实现默认选 `Senior Developer`，前端界面选 `Frontend Developer`，系统/API/数据库架构选 `Backend Architect` 或 `Software Architect`。
- UI 视觉与设计系统选 `UI Designer`；UX 结构、信息架构、CSS 基础和开发交付结构选 `UX Architect`。
- 代码审查选 `Code Reviewer`；只做最小范围修改选 `Minimal Change Engineer`；熟悉陌生代码库选 `Codebase Onboarding Engineer`。
- 生产事故选 `Incident Response Commander`；可靠性、SLO、监控和容量选 `SRE`；CI/CD、云资源和自动化选 `DevOps Automator`。
- 安全开发和威胁建模选 `Security Engineer`；SIEM、检测规则、威胁狩猎选 `Threat Detection Engineer`。
- AI/ML/RAG/模型集成选 `AI Engineer`；数据管道和仓湖选 `Data Engineer`；坏数据修复选 `AI Data Remediation Engineer`。
- 文档、README、API 文档和教程选 `Technical Writer`；Git 流程选 `Git Workflow Master`。
- 图片生成提示词选 `Image Prompt Engineer`；包容性视觉表达选 `Inclusive Visuals Specialist`；品牌体系选 `Brand Guardian`。
- 学术世界观、文化系统、历史脉络、地理气候、叙事理论、角色心理分析，分别选 `Anthropologist`、`Historian`、`Geographer`、`Narratologist`、`Psychologist`。
- 财务核算、财务分析、预算滚动预测、投资研究、税务筹划，分别选 `Bookkeeper & Controller`、`Financial Analyst`、`FP&A Analyst`、`Investment Researcher`、`Tax Strategist`。
- 营销增长、SEO、AI 引用、内容运营、社媒渠道、中国平台、电商本地化、直播带货选 `Agentic Search Optimizer`、`AI Citation Strategist`、`SEO Specialist`、`Content Creator`、`Social Media Strategist`、`Douyin Strategist`、`Xiaohongshu Specialist`、`China E-Commerce Operator`、`Livestream Commerce Coach` 等营销角色。
- 付费投放、创意策略、PPC、Paid Social、程序化广告、归因与追踪选 `Paid Media Auditor`、`Ad Creative Strategist`、`PPC Campaign Strategist`、`Paid Social Strategist`、`Programmatic & Display Buyer`、`Tracking & Measurement Specialist`。
- 产品定义、反馈归纳、行为设计、迭代优先级、趋势判断选 `Product Manager`、`Feedback Synthesizer`、`Behavioral Nudge Engine`、`Sprint Prioritizer`、`Trend Researcher`。
- 项目拆解、Jira 流程、实验跟踪、Studio 运营/制片与总体推进选 `Senior Project Manager`、`Jira Workflow Steward`、`Experiment Tracker`、`Project Shepherd`、`Studio Operations`、`Studio Producer`。
- 销售发现、售前方案、账户策略、外呼、提案、管道分析选 `Sales Engineer`、`Discovery Coach`、`Account Strategist`、`Outbound Strategist`、`Proposal Strategist`、`Pipeline Analyst`。
- visionOS、XR、空间界面、Metal 图形、沉浸式交互和终端集成选 `visionOS Spatial Engineer`、`XR Interface Architect`、`XR Immersive Developer`、`XR Cockpit Interaction Specialist`、`macOS Spatial/Metal Engineer`、`Terminal Integration Specialist`。
- 多代理编排、身份信任、自动化治理、MCP/LSP、Salesforce、开发者关系、法务合规、招聘培训、行业顾问、语言翻译、业务支持等专项问题，从 `roles/specialized/` 下选择最贴近的角色。
- 客服支持、运营报表、摘要生成、基础设施维护、合规检查选 `Support Responder`、`Analytics Reporter`、`Executive Summary Generator`、`Infrastructure Maintainer`、`Legal Compliance Checker`。
- 无障碍、API、性能、证据收集、结果分析、现实校验、工具评估、流程调优选 `Accessibility Auditor`、`API Tester`、`Performance Benchmarker`、`Evidence Collector`、`Reality Checker`、`Tool Evaluator`、`Workflow Optimizer`。
- 需要带长期记忆上下文的后端架构与数据建模时，选 `Backend Architect`（`roles/integrations/mcp-memory/backend-architect-with-memory.md`）。
- 玩法机制、核心循环、GDD 选 `Game Designer`；关卡流线与空间叙事选 `Level Designer`；剧情、分支对话、Lore 选 `Narrative Designer`。
- 技术美术、Shader、VFX、资产规范与性能预算选 `Technical Artist`；交互音频、FMOD、Wwise、空间音频选 `Game Audio Engineer`。
- Blender 工具、导出器、校验器与 DCC 自动化选 `Blender Add-on Engineer`。
- Godot 通用玩法脚本选 `Godot Gameplay Scripter`；Godot 联机选 `Godot Multiplayer Engineer`；Godot Shader 和后处理选 `Godot Shader Developer`。
- Unity 架构和数据驱动系统选 `Unity Architect`；Unity 编辑器工具链选 `Unity Editor Tool Developer`；Unity 联机选 `Unity Multiplayer Engineer`；Unity Shader Graph/HLSL 选 `Unity Shader Graph Artist`。
- Unreal C++/Blueprint/GAS/性能架构选 `Unreal Systems Engineer`；Unreal 联机复制与专服选 `Unreal Multiplayer Architect`；Unreal 材质/Niagara/PCG 选 `Unreal Technical Artist`；开放世界、Landscape、World Partition 选 `Unreal World Builder`。
- Roblox 玩法和留存/变现设计选 `Roblox Experience Designer`；Roblox Luau/RemoteEvent/DataStore 选 `Roblox Systems Scripter`；Roblox UGC、Avatar、Marketplace 流水线选 `Roblox Avatar Creator`。

## 角色索引

### 设计角色

| 角色 | 适用场景 | 文件 |
| --- | --- | --- |
| Brand Guardian | 品牌战略、品牌一致性、品牌指南、品牌资产保护 | `roles/design/design-brand-guardian.md` |
| Image Prompt Engineer | AI 图片/摄影提示词、构图、光线、镜头语言、负面提示词 | `roles/design/design-image-prompt-engineer.md` |
| Inclusive Visuals Specialist | 多元包容视觉、避免刻板印象、文化真实性、人像/视频偏差审查 | `roles/design/design-inclusive-visuals-specialist.md` |
| UI Designer | UI 视觉、组件库、设计系统、像素级界面、可访问性视觉规范 | `roles/design/design-ui-designer.md` |
| UX Architect | UX 信息架构、CSS 架构、布局基础、主题系统、开发交付结构 | `roles/design/design-ux-architect.md` |
| UX Researcher | 用户研究、可用性测试、用户旅程、行为分析、数据驱动设计洞察 | `roles/design/design-ux-researcher.md` |
| Visual Storyteller | 视觉叙事、故事板、多媒体内容、信息可视化、品牌故事 | `roles/design/design-visual-storyteller.md` |
| Whimsy Injector | 趣味微交互、品牌人格、惊喜体验、错误/加载状态文案与动效 | `roles/design/design-whimsy-injector.md` |

### 工程角色

| 角色 | 适用场景 | 文件 |
| --- | --- | --- |
| AI Data Remediation Engineer | 异常数据聚类、坏数据修复、离线 SLM 修复逻辑、零数据丢失 | `roles/engineering/engineering-ai-data-remediation-engineer.md` |
| AI Engineer | AI/ML、RAG、模型部署、智能功能、MLOps、向量数据库 | `roles/engineering/engineering-ai-engineer.md` |
| Autonomous Optimization Architect | LLM 路由、影子测试、成本/延迟优化、熔断、AI FinOps | `roles/engineering/engineering-autonomous-optimization-architect.md` |
| Backend Architect | 后端架构、API、数据库、微服务、缓存、服务端安全和性能 | `roles/engineering/engineering-backend-architect.md` |
| CMS Developer | WordPress、Drupal、主题、插件/模块、内容模型、编辑工作流 | `roles/engineering/engineering-cms-developer.md` |
| Code Reviewer | 代码审查、正确性、安全、性能、可维护性、测试缺口 | `roles/engineering/engineering-code-reviewer.md` |
| Codebase Onboarding Engineer | 陌生代码库导览、架构梳理、模块边界、开发上手路径 | `roles/engineering/engineering-codebase-onboarding-engineer.md` |
| Data Engineer | 数据管道、ETL/ELT、湖仓、批流处理、数据质量和血缘 | `roles/engineering/engineering-data-engineer.md` |
| Database Optimizer | SQL 优化、索引、Schema、查询计划、数据库性能调优 | `roles/engineering/engineering-database-optimizer.md` |
| DevOps Automator | CI/CD、IaC、部署流水线、云运维、自动化脚本 | `roles/engineering/engineering-devops-automator.md` |
| Email Intelligence Engineer | 邮件线程解析、结构化抽取、邮件自动化、AI 可推理数据 | `roles/engineering/engineering-email-intelligence-engineer.md` |
| Embedded Firmware Engineer | ESP32、STM32、RTOS、裸机、固件、硬件接口和低功耗 | `roles/engineering/engineering-embedded-firmware-engineer.md` |
| Feishu Integration Developer | 飞书/Lark 机器人、开放平台、审批、表格、文档和集成 | `roles/engineering/engineering-feishu-integration-developer.md` |
| Filament Optimization Specialist | Filament PHP 后台、资源页、表单、表格、管理界面效率优化 | `roles/engineering/engineering-filament-optimization-specialist.md` |
| Frontend Developer | React/Vue/Angular、Web UI 实现、状态管理、前端性能和可访问性 | `roles/engineering/engineering-frontend-developer.md` |
| Git Workflow Master | Git 分支、rebase、merge、提交整理、发布和版本控制策略 | `roles/engineering/engineering-git-workflow-master.md` |
| Incident Response Commander | 生产事故响应、分级、战情室、沟通、缓解和复盘 | `roles/engineering/engineering-incident-response-commander.md` |
| Minimal Change Engineer | 精准小改、低风险修复、严格控制 diff、避免范围蔓延 | `roles/engineering/engineering-minimal-change-engineer.md` |
| Mobile App Builder | iOS、Android、React Native、Flutter、移动端架构和发布 | `roles/engineering/engineering-mobile-app-builder.md` |
| Rapid Prototyper | 快速原型、概念验证、MVP、短周期可运行演示 | `roles/engineering/engineering-rapid-prototyper.md` |
| Security Engineer | 应用安全、威胁建模、漏洞修复、安全评审、合规控制 | `roles/engineering/engineering-security-engineer.md` |
| Senior Developer | 通用高级实现、Laravel/Livewire/FluxUI、复杂功能落地、代码质量 | `roles/engineering/engineering-senior-developer.md` |
| Software Architect | 系统设计、DDD、架构模式、边界划分、技术决策和演进路线 | `roles/engineering/engineering-software-architect.md` |
| Solidity Smart Contract Engineer | Solidity、EVM、智能合约、安全审计、Gas 优化、代理升级 | `roles/engineering/engineering-solidity-smart-contract-engineer.md` |
| SRE | SLO、错误预算、可观测性、容量规划、混沌工程、降噪自动化 | `roles/engineering/engineering-sre.md` |
| Technical Writer | README、API 文档、教程、开发者文档、迁移指南、文档体系 | `roles/engineering/engineering-technical-writer.md` |
| Threat Detection Engineer | SIEM、Sigma、MITRE ATT&CK、威胁狩猎、检测即代码、告警调优 | `roles/engineering/engineering-threat-detection-engineer.md` |
| Voice AI Integration Engineer | 语音转写、Whisper、ASR、字幕、说话人分离、音频管道 | `roles/engineering/engineering-voice-ai-integration-engineer.md` |
| WeChat Mini Program Developer | 微信小程序、WXML/WXSS/WXS、微信支付、订阅消息、小程序审核 | `roles/engineering/engineering-wechat-mini-program-developer.md` |

### 游戏开发角色

#### 通用游戏开发

| 角色 | 适用场景 | 文件 |
| --- | --- | --- |
| Game Designer | 核心玩法、机制设计、GDD、经济与循环设计、玩家动机 | `roles/game-development/game-designer.md` |
| Level Designer | 关卡布局、空间节奏、遭遇设计、环境叙事、路线引导 | `roles/game-development/level-designer.md` |
| Narrative Designer | 剧情系统、分支对话、世界观、角色语气、叙事与玩法融合 | `roles/game-development/narrative-designer.md` |
| Technical Artist | 技术美术、Shader、VFX、LOD、资产规范、渲染与性能预算 | `roles/game-development/technical-artist.md` |
| Game Audio Engineer | 交互音频、FMOD、Wwise、自适应音乐、空间音频、音频预算 | `roles/game-development/game-audio-engineer.md` |

#### Blender

| 角色 | 适用场景 | 文件 |
| --- | --- | --- |
| Blender Add-on Engineer | Blender Python 插件、校验器、导出器、批处理和资产流水线自动化 | `roles/game-development/blender/blender-addon-engineer.md` |

#### Godot

| 角色 | 适用场景 | 文件 |
| --- | --- | --- |
| Godot Gameplay Scripter | Godot 4、GDScript 2.0、C#、节点组合、信号设计、通用玩法脚本 | `roles/game-development/godot/godot-gameplay-scripter.md` |
| Godot Multiplayer Engineer | Godot 4 联机、MultiplayerAPI、ENet/WebRTC、RPC、场景复制、Authority | `roles/game-development/godot/godot-multiplayer-engineer.md` |
| Godot Shader Developer | Godot Shader、CanvasItem/Spatial、VisualShader、后处理、2D/3D 特效 | `roles/game-development/godot/godot-shader-developer.md` |

#### Roblox Studio

| 角色 | 适用场景 | 文件 |
| --- | --- | --- |
| Roblox Avatar Creator | Roblox UGC、Avatar、Accessory Rigging、服装、Marketplace 提交流程 | `roles/game-development/roblox-studio/roblox-avatar-creator.md` |
| Roblox Experience Designer | Roblox 体验设计、留存、变现、DataStore 驱动进度、平台 UX | `roles/game-development/roblox-studio/roblox-experience-designer.md` |
| Roblox Systems Scripter | Roblox Luau、RemoteEvents、RemoteFunctions、DataStore、模块架构与安全边界 | `roles/game-development/roblox-studio/roblox-systems-scripter.md` |

#### Unity

| 角色 | 适用场景 | 文件 |
| --- | --- | --- |
| Unity Architect | ScriptableObject、模块化组件、数据驱动架构、可扩展 Unity 项目 | `roles/game-development/unity/unity-architect.md` |
| Unity Editor Tool Developer | EditorWindow、PropertyDrawer、AssetPostprocessor、导入和校验自动化 | `roles/game-development/unity/unity-editor-tool-developer.md` |
| Unity Multiplayer Engineer | NGO、UGS Relay/Lobby、状态同步、延迟补偿、服务端权威 | `roles/game-development/unity/unity-multiplayer-engineer.md` |
| Unity Shader Graph Artist | Shader Graph、HLSL、URP/HDRP、自定义 Render Pass、实时视觉效果 | `roles/game-development/unity/unity-shader-graph-artist.md` |

#### Unreal Engine

| 角色 | 适用场景 | 文件 |
| --- | --- | --- |
| Unreal Multiplayer Architect | Unreal 联机、Actor Replication、GameMode/GameState、专服、预测与同步 | `roles/game-development/unreal-engine/unreal-multiplayer-architect.md` |
| Unreal Systems Engineer | UE5 C++/Blueprint、GAS、Nanite、Lumen、AAA 级系统架构与性能 | `roles/game-development/unreal-engine/unreal-systems-engineer.md` |
| Unreal Technical Artist | UE5 材质、Niagara、PCG、视觉管线、渲染优化 | `roles/game-development/unreal-engine/unreal-technical-artist.md` |
| Unreal World Builder | UE5 开放世界、World Partition、Landscape、HLOD、流式加载 | `roles/game-development/unreal-engine/unreal-world-builder.md` |

### 学术研究角色

| 角色 | 适用场景 | 文件 |
| --- | --- | --- |
| Anthropologist | 文化系统、仪式、亲属关系、民族志式社会与世界观构建 | `roles/academic/academic-anthropologist.md` |
| Geographer | 地形、气候、水文、资源分布、地图逻辑与聚落布局 | `roles/academic/academic-geographer.md` |
| Historian | 历史脉络、时代考据、制度演化、物质文化与史学方法 | `roles/academic/academic-historian.md` |
| Narratologist | 叙事结构、角色弧线、节奏控制、理论化故事分析 | `roles/academic/academic-narratologist.md` |
| Psychologist | 角色动机、创伤反应、人格机制、群体互动与关系分析 | `roles/academic/academic-psychologist.md` |

### 财务与金融角色

| 角色 | 适用场景 | 文件 |
| --- | --- | --- |
| Bookkeeper & Controller | 日常会计、对账、月结、内控、审计准备 | `roles/finance/finance-bookkeeper-controller.md` |
| Financial Analyst | 财务建模、经营分析、预测、敏感性分析与决策支持 | `roles/finance/finance-financial-analyst.md` |
| FP&A Analyst | 预算编制、滚动预测、资源配置、经营计划与差异分析 | `roles/finance/finance-fpa-analyst.md` |
| Investment Researcher | 行业与公司研究、估值、投资备忘录、投研判断 | `roles/finance/finance-investment-researcher.md` |
| Tax Strategist | 税务结构、税务筹划、合规申报与跨地区税务考量 | `roles/finance/finance-tax-strategist.md` |

### 营销与增长角色

- 搜索与 SEO：`Agentic Search Optimizer`、`AI Citation Strategist`、`SEO Specialist`、`Baidu SEO Specialist`。文件：`roles/marketing/marketing-agentic-search-optimizer.md`、`roles/marketing/marketing-ai-citation-strategist.md`、`roles/marketing/marketing-seo-specialist.md`、`roles/marketing/marketing-baidu-seo-specialist.md`。
- 内容与社媒内容生产：`Content Creator`、`Social Media Strategist`、`Book Co-Author`、`Podcast Strategist`、`Carousel Growth Engine`、`Short-Video Editing Coach`、`Video Optimization Specialist`。文件：`roles/marketing/marketing-content-creator.md`、`roles/marketing/marketing-social-media-strategist.md`、`roles/marketing/marketing-book-co-author.md`、`roles/marketing/marketing-podcast-strategist.md`、`roles/marketing/marketing-carousel-growth-engine.md`、`roles/marketing/marketing-short-video-editing-coach.md`、`roles/marketing/marketing-video-optimization-specialist.md`。
- 国际社媒渠道：`Instagram Curator`、`LinkedIn Content Creator`、`Reddit Community Builder`、`Twitter Engager`、`TikTok Strategist`。文件：`roles/marketing/marketing-instagram-curator.md`、`roles/marketing/marketing-linkedin-content-creator.md`、`roles/marketing/marketing-reddit-community-builder.md`、`roles/marketing/marketing-twitter-engager.md`、`roles/marketing/marketing-tiktok-strategist.md`。
- 中国平台与私域：`Bilibili Content Strategist`、`Douyin Strategist`、`Kuaishou Strategist`、`WeChat Official Account Manager`、`Weibo Strategist`、`Xiaohongshu Specialist`、`Zhihu Strategist`、`Private Domain Operator`。文件：`roles/marketing/marketing-bilibili-content-strategist.md`、`roles/marketing/marketing-douyin-strategist.md`、`roles/marketing/marketing-kuaishou-strategist.md`、`roles/marketing/marketing-wechat-official-account.md`、`roles/marketing/marketing-weibo-strategist.md`、`roles/marketing/marketing-xiaohongshu-specialist.md`、`roles/marketing/marketing-zhihu-strategist.md`、`roles/marketing/marketing-private-domain-operator.md`。
- 电商、本地化与增长：`China E-Commerce Operator`、`China Market Localization Strategist`、`Cross-Border E-Commerce Specialist`、`Livestream Commerce Coach`、`App Store Optimizer`、`Growth Hacker`。文件：`roles/marketing/marketing-china-ecommerce-operator.md`、`roles/marketing/marketing-china-market-localization-strategist.md`、`roles/marketing/marketing-cross-border-ecommerce.md`、`roles/marketing/marketing-livestream-commerce-coach.md`、`roles/marketing/marketing-app-store-optimizer.md`、`roles/marketing/marketing-growth-hacker.md`。

### 付费投放角色

| 角色 | 适用场景 | 文件 |
| --- | --- | --- |
| Paid Media Auditor | 广告账户审计、预算浪费识别、投放结构诊断 | `roles/paid-media/paid-media-auditor.md` |
| Ad Creative Strategist | 广告创意策略、素材方向、受众与创意匹配 | `roles/paid-media/paid-media-creative-strategist.md` |
| Paid Social Strategist | Meta/TikTok 等社媒广告投放与优化 | `roles/paid-media/paid-media-paid-social-strategist.md` |
| PPC Campaign Strategist | 搜索广告、关键词体系、出价与落地页协同 | `roles/paid-media/paid-media-ppc-strategist.md` |
| Programmatic & Display Buyer | 程序化投放、展示广告、媒体采买与频控 | `roles/paid-media/paid-media-programmatic-buyer.md` |
| Search Query Analyst | 搜索词报告、否词、意图分层与查询洞察 | `roles/paid-media/paid-media-search-query-analyst.md` |
| Tracking & Measurement Specialist | 归因链路、像素埋点、转化追踪与测量修复 | `roles/paid-media/paid-media-tracking-specialist.md` |

### 产品角色

| 角色 | 适用场景 | 文件 |
| --- | --- | --- |
| Behavioral Nudge Engine | 行为设计、转化 nudges、留存触发与行为路径优化 | `roles/product/product-behavioral-nudge-engine.md` |
| Feedback Synthesizer | 用户反馈归纳、需求模式提炼、反馈到行动项映射 | `roles/product/product-feedback-synthesizer.md` |
| Product Manager | 问题定义、需求优先级、路线图、成功指标与跨团队对齐 | `roles/product/product-manager.md` |
| Sprint Prioritizer | Sprint 排序、范围裁剪、任务依赖与容量取舍 | `roles/product/product-sprint-prioritizer.md` |
| Trend Researcher | 产品趋势、竞品动向、市场信号与机会判断 | `roles/product/product-trend-researcher.md` |

### 项目管理角色

| 角色 | 适用场景 | 文件 |
| --- | --- | --- |
| Experiment Tracker | 实验设计跟踪、指标回收、实验台账与复盘 | `roles/project-management/project-management-experiment-tracker.md` |
| Jira Workflow Steward | Jira 流程治理、工单状态设计、协作规范 | `roles/project-management/project-management-jira-workflow-steward.md` |
| Project Shepherd | 需求到交付推进、跨团队对齐、阻塞清理 | `roles/project-management/project-management-project-shepherd.md` |
| Studio Operations | 工作室运营、资源协调、节奏管理与执行支撑 | `roles/project-management/project-management-studio-operations.md` |
| Studio Producer | 产能调度、里程碑推进、制作协同与风险管理 | `roles/project-management/project-management-studio-producer.md` |
| Senior Project Manager | 规格拆解、任务细化、验收标准与范围控制 | `roles/project-management/project-manager-senior.md` |

### 销售角色

| 角色 | 适用场景 | 文件 |
| --- | --- | --- |
| Account Strategist | 大客户经营、账户规划、关系图谱与机会推进 | `roles/sales/sales-account-strategist.md` |
| Sales Coach | 销售训练、话术纠偏、方法复盘与团队辅导 | `roles/sales/sales-coach.md` |
| Deal Strategist | 复杂交易策略、关键节点推进、风险识别与赢单路径 | `roles/sales/sales-deal-strategist.md` |
| Discovery Coach | 需求访谈、BANT/MEDDICC 类发现流程与问题设计 | `roles/sales/sales-discovery-coach.md` |
| Sales Engineer | 售前技术发现、POC、Demo 工程、技术异议处理 | `roles/sales/sales-engineer.md` |
| Outbound Strategist | 外呼、外联、冷启动触达与序列设计 | `roles/sales/sales-outbound-strategist.md` |
| Pipeline Analyst | 销售漏斗分析、阶段转化、预测与机会健康度 | `roles/sales/sales-pipeline-analyst.md` |
| Proposal Strategist | 商务提案、方案包装、投标文本与价值叙事 | `roles/sales/sales-proposal-strategist.md` |

### 空间计算角色

| 角色 | 适用场景 | 文件 |
| --- | --- | --- |
| macOS Spatial/Metal Engineer | macOS 空间界面、Metal 图形、桌面与空间体验桥接 | `roles/spatial-computing/macos-spatial-metal-engineer.md` |
| Terminal Integration Specialist | 终端与空间工作流衔接、CLI 集成、工具桥接 | `roles/spatial-computing/terminal-integration-specialist.md` |
| visionOS Spatial Engineer | visionOS 原生空间界面、Volumetric UI、Liquid Glass | `roles/spatial-computing/visionos-spatial-engineer.md` |
| XR Cockpit Interaction Specialist | XR 控制台、复杂操作界面、空间交互流程设计 | `roles/spatial-computing/xr-cockpit-interaction-specialist.md` |
| XR Immersive Developer | 沉浸式 XR 内容、3D 体验与交互场景实现 | `roles/spatial-computing/xr-immersive-developer.md` |
| XR Interface Architect | XR 信息架构、交互模式、空间布局和界面系统 | `roles/spatial-computing/xr-interface-architect.md` |

### 专项业务角色

- 编排与平台工程：`Agentic Identity & Trust Architect`、`Agents Orchestrator`、`Automation Governance Architect`、`Identity Graph Operator`、`LSP/Index Engineer`、`MCP Builder`、`Model QA Specialist`、`Workflow Architect`、`ZK Steward`。文件：`roles/specialized/agentic-identity-trust.md`、`roles/specialized/agents-orchestrator.md`、`roles/specialized/automation-governance-architect.md`、`roles/specialized/identity-graph-operator.md`、`roles/specialized/lsp-index-engineer.md`、`roles/specialized/specialized-mcp-builder.md`、`roles/specialized/specialized-model-qa.md`、`roles/specialized/specialized-workflow-architect.md`、`roles/specialized/zk-steward.md`。
- 法务、审计与合规：`Blockchain Security Auditor`、`Compliance Auditor`、`Healthcare Marketing Compliance Specialist`、`Legal Billing & Time Tracking`、`Legal Client Intake`、`Legal Document Review`。文件：`roles/specialized/blockchain-security-auditor.md`、`roles/specialized/compliance-auditor.md`、`roles/specialized/healthcare-marketing-compliance.md`、`roles/specialized/legal-billing-time-tracking.md`、`roles/specialized/legal-client-intake.md`、`roles/specialized/legal-document-review.md`。
- 组织、招聘与培训：`Chief of Staff`、`Corporate Training Designer`、`HR Onboarding`、`Recruitment Specialist`、`Study Abroad Advisor`。文件：`roles/specialized/specialized-chief-of-staff.md`、`roles/specialized/corporate-training-designer.md`、`roles/specialized/hr-onboarding.md`、`roles/specialized/recruitment-specialist.md`、`roles/specialized/study-abroad-advisor.md`。
- 通用业务支持：`Accounts Payable Agent`、`Customer Service`、`Data Consolidation Agent`、`Document Generator`、`Report Distribution Agent`、`Sales Data Extraction Agent`。文件：`roles/specialized/accounts-payable-agent.md`、`roles/specialized/customer-service.md`、`roles/specialized/data-consolidation-agent.md`、`roles/specialized/specialized-document-generator.md`、`roles/specialized/report-distribution-agent.md`、`roles/specialized/sales-data-extraction-agent.md`。
- 行业顾问与前台业务：`Government Digital Presales Consultant`、`Loan Officer Assistant`、`Real Estate Buyer & Seller`、`Retail Customer Returns`、`Supply Chain Strategist`、`Sales Outreach`。文件：`roles/specialized/government-digital-presales-consultant.md`、`roles/specialized/loan-officer-assistant.md`、`roles/specialized/real-estate-buyer-seller.md`、`roles/specialized/retail-customer-returns.md`、`roles/specialized/supply-chain-strategist.md`、`roles/specialized/sales-outreach.md`。
- 区域、文化与专业顾问：`Cultural Intelligence Strategist`、`French Consulting Market Navigator`、`Korean Business Navigator`、`Language Translator`、`Civil Engineer`、`Developer Advocate`、`Salesforce Architect`。文件：`roles/specialized/specialized-cultural-intelligence-strategist.md`、`roles/specialized/specialized-french-consulting-market.md`、`roles/specialized/specialized-korean-business-navigator.md`、`roles/specialized/language-translator.md`、`roles/specialized/specialized-civil-engineer.md`、`roles/specialized/specialized-developer-advocate.md`、`roles/specialized/specialized-salesforce-architect.md`。
- 垂直行业服务：`Healthcare Customer Service`、`Hospitality Guest Services`。文件：`roles/specialized/healthcare-customer-service.md`、`roles/specialized/hospitality-guest-services.md`。

### 支持与运营角色

| 角色 | 适用场景 | 文件 |
| --- | --- | --- |
| Analytics Reporter | 支持/运营分析报表、数据可视化、周期性汇报 | `roles/support/support-analytics-reporter.md` |
| Executive Summary Generator | 高层摘要、会议纪要提炼、简报压缩与管理层汇报 | `roles/support/support-executive-summary-generator.md` |
| Finance Tracker | 运营侧财务跟踪、支出台账、预算跟进与对账辅助 | `roles/support/support-finance-tracker.md` |
| Infrastructure Maintainer | 运行维护、环境健康巡检、基础设施日常保障 | `roles/support/support-infrastructure-maintainer.md` |
| Legal Compliance Checker | 文案/流程/交付物合规检查与风险提示 | `roles/support/support-legal-compliance-checker.md` |
| Support Responder | 客服响应、问题分流、体验修复与多渠道支持 | `roles/support/support-support-responder.md` |

### 测试与质量角色

| 角色 | 适用场景 | 文件 |
| --- | --- | --- |
| Accessibility Auditor | 无障碍审计、ARIA/键盘流、可用性与合规性检查 | `roles/testing/testing-accessibility-auditor.md` |
| API Tester | API 功能、性能、安全、契约与第三方集成测试 | `roles/testing/testing-api-tester.md` |
| Evidence Collector | 缺陷复现证据、日志、截图、回归证据归档 | `roles/testing/testing-evidence-collector.md` |
| Performance Benchmarker | 性能基准、压测、吞吐/延迟对比与瓶颈定位 | `roles/testing/testing-performance-benchmarker.md` |
| Reality Checker | 现实性校验、集成落地检查、风险和伪完成识别 | `roles/testing/testing-reality-checker.md` |
| Test Results Analyzer | 测试结果分析、失败聚类、原因归纳与结论提炼 | `roles/testing/testing-test-results-analyzer.md` |
| Tool Evaluator | 测试/研发工具评估、选型、试用验证与比较 | `roles/testing/testing-tool-evaluator.md` |
| Workflow Optimizer | QA/测试流程优化、自动化覆盖率提升与效率改进 | `roles/testing/testing-workflow-optimizer.md` |

### 记忆增强角色

| 角色 | 适用场景 | 文件 |
| --- | --- | --- |
| Backend Architect | 带记忆的后端架构、Schema 设计、图谱/实体数据建模 | `roles/integrations/mcp-memory/backend-architect-with-memory.md` |

## 配套资料边界

- `roles/strategy/` 下的 `EXECUTIVE-BRIEF`、`QUICKSTART`、`playbooks/`、`runbooks/`、`coordination/` 属策略手册和执行剧本，不作为直接角色索引。
- `roles/integrations/*/README.md` 属各客户端集成说明，不作为直接角色索引。
- 如任务需要“怎么组织多角色推进”而不是“选哪个专家角色”，优先读取相应 strategy 文档或其他流程型 Skill。

## 冲突处理

- 同时涉及设计和实现：先选定义产出物的角色；例如“实现一个漂亮页面”选 `Frontend Developer`，并可辅以 `UI Designer`。
- 同时涉及架构和实现：规划阶段选 `Software Architect` 或 `Backend Architect`，施工阶段选 `Senior Developer`。
- 同时涉及安全和功能：安全风险高时选 `Security Engineer` 为主，否则把它作为辅助约束。
- 同时涉及学术考据与世界构建：以 `Historian`、`Geographer`、`Anthropologist`、`Psychologist`、`Narratologist` 中最贴近当前核心约束的一位为主，避免并行读取整组学术角色。
- 同时涉及营销自然增长与广告投放：自然流量、内容与渠道运营优先 `roles/marketing/`；预算消耗、素材、归因与广告账户优先 `roles/paid-media/`。
- 同时涉及产品规划与项目推进：问题定义、路线图和优先级优先 `Product Manager`；任务编排、交付跟踪和流程治理优先 `Senior Project Manager` 或 `Project Shepherd`。
- 同时涉及销售与售前：商业推进、账户和提案优先 `roles/sales/`；如果核心问题是技术发现、POC、Demo 或集成可行性，优先 `Sales Engineer`。
- 同时涉及支持、专项业务与测试：用户响应和内部运营支持优先 `roles/support/`；行业/合规/法务/编排等专门场景优先 `roles/specialized/`；验证、证据、性能和无障碍优先 `roles/testing/`。
- 同时涉及玩法设计和引擎实现：方案/GDD/数值阶段优先 `Game Designer`，具体引擎落地阶段切到对应引擎角色。
- 同时涉及技术美术和具体引擎渲染：通用资产规范、跨引擎预算优先 `Technical Artist`，引擎专属材质/Shader/VFX 交给对应 Unity、Godot、Unreal 角色。
- 用户明确指定角色时，以用户指定为准；若指定角色不存在，选择最接近角色并说明映射关系。

## 输出格式

```markdown
角色：<角色名>
依据：<一句话说明匹配原因>
```

随后按该角色继续完成用户任务，不要输出冗长选角过程。

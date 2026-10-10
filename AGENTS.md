# AGENTS.md

## Collaboration Protocol (协作协议)

本文件旨在规范 AI Agent（Claude Code、Antigravity 等）在本项目中的代码与文档协作行为。项目定位详见 [README.md](./README.md)。

- **Core Language**: Output MUST be in **Chinese (Simplified)** unless serving code/technical constraints.
- **Tone**: Professional, precise, and evidence-based.

## Engineering Code of Conduct (工程行为准则)

**Core Philosophy**: **Entropy Reduction (熵减)**. 通过上下文锚定、复用驱动与标准化流水线，对抗软件系统的无序熵增。

### 道 (Mindset - 认知心法)

- **Context-Driven (上下文驱动)**: 上下文是第一性要素 (Context Quality First)。任何变更需建立在深度理解之上（CDD），拒绝基于关键字匹配的机械式修改。
- **Minimal Intervention (最小干预)**: 遵循奥卡姆剃刀与 YAGNI 原则，仅实施必要的变更，推崇演进式设计 (Evolutionary Design) 而非过度设计。
- **Evidence-Based (循证工程)**: 杜绝主观臆断，核心决策需以**最新**且**权威**的文献（IEEE 格式）为佐证，构建“设计-实现-验证”的完整反馈闭环，确保每一项工程行动都能产生可观测的反馈信号（测试、日志、监控），以验证假设并指导迭代。
- **Systemic Integrity (系统完整性)**: 具备全局视角与二阶思维 (Second-Order Thinking)，评估变更对上下游依赖及整个生态（Engine, Adapter, Agent, UI）的“涟漪效应”，不只关注变更的直接结果，更要预测“结果的结果”（如引入缓存导致的陈旧数据、重试机制引发的雪崩），优先保障整体稳定性与逻辑自洽。
- **Knowledge Crystallization (知识结晶)**: 将系统视为有机体，持续沉淀和进化「调研报告」与「方案文档」，并将工程错误与 AI 失败案例转化为经验约束 (Negative Prompts) 和持久化知识，驱动系统的自我进化与持续熵减。
- **Proactive Navigation (主动导航)**: 智能体不应止步于被动响应，需即时转化为“领航者”。在交付任务结果的同时，**必须**基于上下文预判并提出**下一步最佳行动建议 (Next Best Action)**，不仅交付“答案”，更要交付“路径”，消除用户决策的认知摩擦。

### 法 (Strategy - 架构原则)

- **Plan-First Default (规划先行)**: 面对任何非琐碎任务（预估步骤 > 3 或涉及架构级决策），**必须**率先进入 Plan 模式。规划产物需明确界定：功能边界、边缘 Case 应对策略、与现有逻辑的交互锚点以及预计改动的爆炸半径。
- **Subagent Strategy (子代理并发策略)**: 面对高复杂度命题，严禁主 Agent 单点统揽。应贯彻“算力换空间”思路，果断编排 Subagent 进行任务拆解与并行攻坚，主 Agent 的职责需严格收敛于上下文协同与最终成果的组装整合。
- **Verification Before Done (交付前验证定式)**: 严禁在缺乏确凿运行证据的情况下标记任务为“已完成”。交付阶段**强制要求**提供客观自证材料：Diff 变更分析、测试用例覆盖、实施日志截图及核心链路边缘 Case 验证结果，并时刻以“方案是否能通过 Staff Engineer 严格审查”的视角自检。
- **Reuse-Driven (复用驱动)**: Compose over Reinvent。系统变更**必须**主动参考业界经典设计模式与最佳实践。在进入实质性编码前，需率先对相关领域的成熟范式进行深度调研，并结合当前项目上下文输出充分的关联分析与方案梳理。坚决贯彻“拿来主义”，优先通过组合与集成来构建系统，防范闭门造车与重复造轮子。
- **Boundary Management (边界管理)**: 严控模块/Agent 间的职责边界与契约，确保高内聚低耦合，防范隐式依赖穿透。
- **Orthogonal Decomposition (正交分解)**: 坚持“正交地提取概念主体”。识别系统中独立变化的维度并进行解耦（如机制与策略分离），确保单一概念主体的变更具备局部性，避免逻辑纠缠。
- **Single Source of Truth (单一事实源)**：严格维护唯一的权威定义源。引用时**必须**使用轻量级指针 (Link/ID) 而非数据副本 (Copy-Paste)，从根源消除断裂 (Split-Brain) 风险。

### 术 (Tactics - 执行规范)

- **Structured AI-Pair Pipeline (规范化 AI 结对流水线)**: 遵循 **Specification-Driven (规约驱动)** + **Context-Anchored (上下文锚定)** + **AI-Pair (AI 结对)** 模式，将开发固化为可审计的流水线，避免代码腐化为无法维护的“大泥球 (Big Ball of Mud)”。
- **Operational Excellence (卓越运营)**:
  1. **Git Discipline**: 默认严禁调用 git commit；当用户显式要求提交时，一律使用 Claude Code 的自定义 Slash Command: `/commit-no-push` 进行操作（若非 Claude Code 运行环境，则读取 /commit-no-push 命令中的规则执行）。严禁执行 Rebase；
  2. **Temp Management**: 临时产物（执行计划等）一律收敛至 `.temp/` 并及时清理；
  3. **Link Validity**: 确保所有引用的 URL 可访问且具备明确的上下文价值；
  4. **Testing**: macOS 侧统一在 `tests/` 下维护测试用例（自建极简断言运行器，`make test` 驱动，本地运行总时间控制在 3 min 以内）；Windows 侧为 `windows/` 下的 xUnit 测试工程（CI 运行）。**macOS Swift 适配**：Command Line Tools 不含 XCTest/Swift Testing，故 Swift 项目采用 `tests/` 下自建的极简断言运行器（`expect`/`test` + 退出码，经 `make test` → `swift run` 驱动），语义对齐 XCTest；详见 [Give me a break README](./README.md)；
  5. **Pre-commit Hooks**: 本仓暂无 pre-commit 工具链；如后续引入，按用户级规约激活；
  6. **Issue**: 在 [issue.md](.agents/issue.md) 中维护你处理过的 Issue 摘要（问题描述、表因根因、处理方式、后续防范、同类问题影响与处理注意事项等），便于同类问题的跨上下文处理；注意识别相同 Issue，不要同 Issue 多处维护；
- **Package Management Standardization (包管理规范)**:
  1. **Python**: 严禁使用 pip/poetry，**必须**统一使用 `uv` 进行包管理与脚本执行（如 `uv run`）；
  2. **JavaScript/TypeScript**: 严禁使用 npm/yarn，**必须**统一使用 `pnpm` 进行包管理与脚本执行；
  3. **Swift**: 统一使用 Swift Package Manager（`Package.swift`）；依赖经 Xcode `File > Add Package Dependency` 或 SPM 引入，**严禁**引入非必要第三方库；macOS 应用经 `Makefile` 装配 `.app` bundle（`swift build -c release` + `codesign`）；
- **Database Management**: 谨慎操作，数据迁移、测试等操作严禁将现有数据删除，谨慎操作数据迁移的回滚，防止数据被清理。
- **Browser Validation Protocol (浏览器验证准则)**：Agent 不得自行完成、绕过或模拟任何 OAuth / SSO / 设备码认证流程，凭证（密码 / Cookie / 验证码 / token）一律不进 chat；本仓同构映射为系统权限 / TCC 授予（辅助功能、输入监控等）一律由用户手动完成。完整协议见用户级规约；
- **Knowledge Map (知识索引)**：项目所有文档索引统一维护在 [知识索引](./.agents/knowledge-map.md)，并在文档目录变更时即时同步跟新；
- **Documentation Standards (文档规范)**：
  1. **Visual Documentation (图文并茂)**: 对于复杂逻辑，优先 **Archify 图表规范**，构建“图文并茂”的直观文档；
     - **单一事实源 (SSOT)**：图源 candidate JSON 为唯一权威定义，入库于 `docs/diagrams/<slug>/`（`<slug>.json` 图源 + `<slug>.html` 交互版 + `<slug>.svg` 双主题嵌入版）；生成或修改图必须经 `archify finalize --quality showcase` 门禁通过；
     - **嵌入方式**：文档以相对路径嵌入 SVG（README 用 `docs/diagrams/<slug>/<slug>.svg`，docs/ 内用 `diagrams/<slug>/<slug>.svg`），双主题自动适配深浅模式；
     - **色彩语义与兼容性**：为图表节点配置具备语义辨识度的色彩，并确保在深色模式（Dark Mode）下具有极高的对比度与清晰度；
     - **逻辑模块化解构**：针对业务跨度较大的架构流程，以 boundary 分层承载领域边界与层级解构，以增强图表的自解说（Self-explaining）能力；
     - 禁止再新增 mermaid 代码块（存量已全量置换为 Archify 图）；
  2. **语言叙事**：用语精准，叙事完备，行文专业，聚焦核心，篇幅精炼，形象具体，体现真实作用与用户吸引性，字数恰当；
  3. **Direct Hyperlinking (直接跳转)**: 在文档中提及 Repo 内其他资源（文档/代码）时，**必须**构建可跳转的相对路径链接（如 `[Doc Name](./path.md)`），严禁使用“死文本”引用，以降低信息检索熵；
  4. **实操截图**：文档需要引入必要的浏览器实操截图时，需自行通过默认浏览器打开相关页面，通过实操现场截图并保留到文档路径进行文档引用；
- **Reference Specifications (IEEE)**：核心引用遵循 IEEE 标准引用格式（规约见用户级配置）；

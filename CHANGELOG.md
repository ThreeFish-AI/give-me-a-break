# CHANGELOG

本文件记录 Give me a break 的版本变更事件。

## Unreleased

### 新增

- **工作日志（休息前记录 + 周期报告）**：自然休息前弹一个轻量输入框，花 30 秒写下「刚刚完成了什么 + 可选下一步」，让大脑真正放下再休息（循证：Leroy 注意力残留 / Stubblebine 插值日记 / Fogg 行为模型 / JITAI）。
  - 提示钉死在唯一 FSM 转换边界（`.working → .resting`），在遮罩升起**之前**渲染独立窗口，规避「对话框被遮罩遮挡」陷阱；永不阻塞休息（回车提交 / Esc / 跳过 / 60s 自动放行）。
  - 记录按时间段落盘 `work-log.json`；菜单「工作日志…」生成今日/本周/月报 Markdown，支持复制与导出 `.md`（确定性幂等）。
  - 仅自然休息触发，「立即休息」不弹；默认开启、可在设置关闭；连续跳过自动衰减抗疲劳。
  - 纯 FSM 零改动，仅在接线层 `tick()` 副作用分发处最小拦截 + 新增 `completeDeferredRest(now:)`（严格对齐 issue #6 不变量，配回归测试）。
  - 单测 30 → 47（新增 WorkLogStore/报告渲染/引擎延迟/容错解码 17 例，既有零回归）。
- 跨平台 schema SSOT：新增 [shared/work-log.schema.json](./shared/work-log.schema.json) 定义工作日志条目结构。

### 变更

- 配置 schema 升级 `schemaVersion` 2 → 3：`DayPlanConfig` 新增 `workLogEnabled`（默认 `true`），容错解码保证旧配置平滑迁移不丢失；[shared/config.schema.json](./shared/config.schema.json) 同步。
- [README.md](./README.md) 新增工作日志核心能力、配置示例与验证说明；[docs/give-me-a-break-design.md](./docs/give-me-a-break-design.md) 新增 §7 工作日志设计章节与 IEEE 引用（[7]-[13]）；[.agents/knowledge-map.md](./.agents/knowledge-map.md) 索引 WorkLog 代码位置。

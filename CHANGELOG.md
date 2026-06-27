# CHANGELOG

本文件记录 Give me a break 的版本变更事件。

## Unreleased

### 新增

- **补录工作日志**：菜单栏新增「补录工作日志…」，可补录漏掉的时段——选择起止时段（默认自上一条日志结束起算，结束默认当前）、写下完成了什么与可选「下一步」，保存后按时间排序并入工作日志报告。复用既有小结输入视觉语言（leaf 标题 / summary TextEditor + 软字符计数 / 可选下一步），独立窗口、无超时、不触发休息、不冻结心跳。

### 优化

- **设置页签细分**：将「休息」页签拆分为「休息音效」与「工作日志」两个独立页签，分类更聚焦（现四页签：通用 / 作息 / 休息音效 / 工作日志）。

## v0.1.2-rc.3 — 2026-06-27

### 优化

- **设置界面页签化与交互优化**：将原本单页堆叠的全部设置项按域分类为三个页签——**通用**（开机自启 + 关于）、**作息**（工作时段 + 节律）、**休息**（休息音效 + 工作日志），降低单页认知负荷。底部「应用 / 取消 / 恢复默认」改为跨页签全局生效（一次提交所有页签草稿）；「恢复默认」增加二次确认防误操作；「应用」作为唯一主按钮（`.borderedProminent`）。新增「关于」段展示版本号。沿用原生 macOS 控件 + SF Symbols + 语义色（自适应深浅色），并按页签布局调整窗口初始尺寸。

## v0.1.2-rc.2 — 2026-06-27

### 新增

- **休息模式自定义音频（取代内置粉噪音）**：设置 →「休息音效」新增「休息音乐」文件选择。选择本地 DRM-free 音频（mp3/m4a/aac/wav/flac/aiff 等 `AVAudioPlayer` 支持格式）后，休息时循环播放该文件取代内置粉噪音；文件**不打包、不分发**，仅以本地绝对路径引用（App 非沙盒，路径即引用）。文件缺失或格式不支持时自动回退粉噪音，保证休息必有舒缓音效。
  - `DayPlanConfig` 新增 `restMusicPath: String?`（默认 nil=用粉噪音）；配置 schema 升级 `schemaVersion` 4 → 5，容错解码保证旧配置平滑迁移；[shared/config.schema.json](./shared/config.schema.json) 同步。
  - `LiveMusicController` 新增 `AVAudioPlayer` 文件播放分支（无限循环、0.8 舒适响度、加载失败回退粉噪音 + 诊断日志），与既有粉噪音/QQ 音乐联动正交。
  - 单测 50 → 53（新增 restMusicPath 默认 nil / round-trip / v4→v5 迁移 3 例，既有零回归）。

## v0.1.2-rc.1 — 2026-06-27

### 新增

- **工作日志小结等待时长可配置**：设置 →「工作日志」新增等待时长控制。原硬编码 60s 自动放行改为可配置（默认 **3 分钟**）；新增「永久等待」开关——开启后小结窗不自动跳过、不自动进入休息，须手动「记录并休息」/「跳过」/关闭窗口；关闭整个环节仍由既有开关承担（直接进入休息）。
  - 永久模式安全性：提示窗红色关闭按钮经 `NSWindowDelegate.windowWillClose` 等同「跳过」，保证始终有手动出口；系统唤醒时若小结窗仍开启则不抢恢复心跳，避免延迟休息被静默判定结束（`suspend`/`resume` 严格配对）。
  - 配置 schema 升级 `schemaVersion` 3 → 4：`DayPlanConfig` 新增 `workLogPromptTimeoutSeconds`（默认 `180`，哨兵 `0`=永久等待），容错解码保证旧配置平滑迁移；[shared/config.schema.json](./shared/config.schema.json) 同步。
  - 单测 47 → 50（新增等待时长 round-trip、永久哨兵 0 保留、v3→v4 迁移补默认 3 例，既有零回归）。

## v0.1.1 — 2026-06-26

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

## v0.1.0

### 新增

- 首个发布版本：macOS 菜单栏强制作息应用。
- **强制排版作息**：工作窗口内累计 N 分钟（默认 50）触发强制休息 M 分钟（默认 10）。
- **全屏遮罩**：休息时遮罩所有显示器（`CGShieldingWindowLevel`），Esc 二次确认方可提前结束（软强制）。
- **休息音效**：内置粉噪音（AVAudioEngine 实时合成），可选联动 QQ 音乐媒体键。
- **Google 日历门控**：会议计为工作时间，休息推迟至会议结束（EventKit 复用 OS 登录态，无 OAuth 代码）。
- **健壮性**：AFK/睡眠暂停累加、崩溃恢复 fast-forward、多屏热插拔、状态持久化。
- 设置窗口图形化编辑（即时保存 + 引擎热更新）；开机自启。

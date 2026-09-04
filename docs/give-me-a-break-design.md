# Give me a break 设计文档

> macOS 强制作息应用的工程设计与循证依据。协作规约见 [AGENTS.md](../AGENTS.md)，快速上手见 [README](../README.md)。

## 1. 设计目标

在用户自定义工作时段内执行「工作 / 强制休息」节律；休息时遮罩全部显示器并控制 QQ 音乐；Google 日历会议计为工作但推迟休息。核心是**单调 wall-clock 工作累加器 + 反应式 FSM**，对抗「会议/睡眠/AFK」等非确定性输入对静态日程的扰动。

## 2. 调度引擎

### 2.1 状态机（5 态）

```mermaid
stateDiagram-v2
    direction LR
    [*] --> OFF_DUTY: 冷启动/fast-forward
    OFF_DUTY --> WORKING: 进入工作窗口
    WORKING --> RESTING: workAccum≥interval && meeting==nil
    WORKING --> IN_MEETING: 会议开始
    WORKING --> IDLE: AFK/睡眠
    WORKING --> OFF_DUTY: 离开工作窗口
    IN_MEETING --> RESTING: 会议结束 && 阈值已满足
    IN_MEETING --> WORKING: 会议结束 && 阈值未满足
    IN_MEETING --> OFF_DUTY: 离开工作窗口
    IDLE --> WORKING: 输入恢复(对账 lastTickAt)
    RESTING --> WORKING: 自然结束/Esc 二次确认
    RESTING --> IN_MEETING: 会议打断(abort-and-reset)
    RESTING --> OFF_DUTY: 窗口结束(abort-and-reset)
    classDef off fill:#3a4a5a,color:#fff,stroke:#7fa8c9
    classDef work fill:#2d5a3a,color:#fff,stroke:#7fc98a
    classDef meet fill:#5a4a2d,color:#fff,stroke:#c9b27f
    classDef rest fill:#5a2d3a,color:#fff,stroke:#c97f9a
    classDef idle fill:#4a4a4a,color:#fff,stroke:#b0b0b0
    class OFF_DUTY off
    class WORKING work
    class IN_MEETING meet
    class RESTING rest
    class IDLE idle
```

色彩语义：蓝灰=下班、绿=工作、琥珀=会议、品红=休息、中性灰=空闲；前景 `#fff` + 深色填充，深/浅模式对比度均 > 7:1（WCAG AAA）。

### 2.2 谓词优先级（`evaluate` 纯函数）

```
evaluate(now) 按顺序短路求值，首个匹配决定目标态：
  (1) NOT inAnyWorkWindow(now)  → OFF_DUTY      [最高，压过会议]
  (2) isAFK(now) OR isAsleep    → IDLE
  (3) activeMeeting(now) != nil → IN_MEETING    [会议压过休息]
  (4) workAccum >= workInterval → RESTING
  (5) otherwise                 → WORKING
触发休息的不变量：workAccum >= workInterval AND activeMeeting == nil
```

`evaluate` 是**零时间依赖纯函数**<sup>[[1]](#ref1)</sup>：所有时间经注入的 `Clock` 进入快照，可用 `VirtualClock` 单元测试。

### 2.3 累加器推进规则（防跨睡眠回灌）

每 tick：`delta = now - lastTickAt`（限幅 ≤ 60s 防异常 tick）→ **第一步即更新 `lastTickAt = now`** → 仅当 `active && phase ∈ {working, inMeeting}` 才 `workAccum += delta`。睡眠/AFK 期间 `active=false`，delta 不计入；`handleWake()` 强制 `lastTickAt = now`，使首个唤醒 tick 的 delta≈0，**不回灌睡眠时长**<sup>[[2]](#ref2)</sup>。

### 2.4 工作示例验证（30 + 30 会议 → 60 工作 → 10 休息）

`workInterval=3000s`（50min）。t=0 WORKING 累加至 30min → t=30 会议开始 IN_MEETING，累加器续推 → t=50 穿越阈值但谓词 3 压过谓词 4，**不触发休息** → t=60 会议结束，`workAccum=3600≥3000` 且 meeting=nil → **RESTING**，reset，休息 60→70 → t=70 WORKING。✓ 已由单元测试 `U1` 断言。

## 3. 三大集成契约

| 契约 | 实现 | 关键 API | 权限 |
|---|---|---|---|
| **遮罩** | `LiveOverlayController` | 每 `NSScreen` 一个 borderless `NSPanel`，`level=CGShieldingWindowLevel()`<sup>[[3]](#ref3)</sup>（⚠️ 该 C 函数 Apple 已弃用，现代等价 `.screenSaver` / `CGWindowLevelForKey(.shieldingWindowLevelKey)`，同屏蔽层级；`LiveOverlayController.swift:73` 待平滑替换为 `.screenSaver`），`collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.canJoinAllApplications]`；Esc 经本地事件监听→`NSAlert` 二次确认 | 无（遮罩本身不需 TCC） |
| **音乐** | `LiveMusicController` | `NSWorkspace` 拉起 QQ 音乐 + CGEvent 合成 `NX_KEYTYPE_PLAY`(=16) 媒体键（`subtype=8` NX_SUBTYPE_AUX_CONTROL_BUTTONS）<sup>[[4]](#ref4)</sup>，OS 路由到 Now Playing 应用 | **Accessibility（必需）** |
| **日历** | `LiveCalendarProvider` | 单一 `EKEventStore`<sup>[[5]](#ref5)</sup>，`requestFullAccessToEvents()`，过滤 `sourceType==.calDAV`<sup>[[6]](#ref6)</sup> + busy，`EKEventStoreChanged` 推送 + 限流回退 | **完全日历访问** |

## 4. 数据模型

```swift
struct EngineState { phase; workAccumulatedSeconds; lastTickAt; restStartedAt; modelVersion }  // 单一事实源，Codable 持久化
struct DayPlanConfig { workWindows; workIntervalSeconds; restDurationSeconds; afkThresholdSeconds; …; agent: AgentSettings; schemaVersion }
struct AgentSettings { claudeExecutablePath: String?; claudeSettingsEditorBundleId: String? }  // v8 · Agentic AI 正交子结构
struct MeetingTimeline { busyIntervals: [DateRange]; generatedAt }  // 合并后的不相交忙碌区间
func mergeBusyIntervals(_:) -> [DateRange]  // 纯函数，端点相接合并（背靠背会议视为连续）
```

> **Agentic AI 配置（v8，groundwork）**：`AgentSettings` 为「Agentic AI」功能域预留的正交子结构，随 `DayPlanConfig` 落于同一 `config.json`（单一事实源），经容错解码平滑迁移。仅承载纯 Foundation 的 `String?` 字段——引擎不消费（携带即忽略，同 `restMusicPath`）；编辑器探测/打开等 AppKit 逻辑位于集成层 `ClaudeSettingsLauncher`，与本模型正交解耦。当前仅持久化 + 设置 UI，未接入实际 Claude Code 调用。

崩溃恢复：启动加载持久化 `EngineState`，`fastForward(sanityLimit:)` 依间隔决策——短中断（≤300s）按工作态推进计入累加；长中断仅对账基点不回灌（`U11` 断言）。

## 5. 测试矩阵

`make test` → 自建运行器（CLT 无 XCTest/Swift Testing，见 [issue #1](../.agents/issue.md)）。

- **谓词优先级** P1-P5：offDuty 压过一切；idle 压过会议/阈值；会议压过阈值；阈值触发休息；默认 working。
- **工作示例** U1：30+30 会议→60 工作→10 休息（纯函数 + 引擎接线双重断言）。
- **边缘 case**：U2 会议恰在阈值点不触发瞬间休息；U3 背靠背会议跨接缝；U4 会议跨窗口边界→offDuty 优先；U7 休息被会议打断→abort-and-reset；U9 同态幂等（showOverlay 仅一次）。
- **健壮性**：U10 advance 限幅；U5 AFK 冻结累加器；U6 睡眠不回灌；U11 fast-forward 短推进/长冻结。
- **持久化**：config/state round-trip、缺失文件回退默认、损坏 JSON 不崩溃、schema 迁移（含 v7→v8 `agent`/AgentSettings 缺字段补默认、子字段容错、往返一致）。

## 6. 已验证 / 待实机核实

✅ 已无头验证：编译链接、87 单元测试、`.app` 装配签名、引擎启动与 phase 判定、DEBUG 周期遮罩 show/dismiss、持久化落盘、工作日志提示拦截 + `completeDeferredRest` rebase + 报告渲染幂等、优雅降级（权限未授时）；`LockShortcutMonitor`/`ScreenMaskController` 新代码编译链接通过、`.app` 签名后二进制内含相应符号、Info.plist 新增 `NSInputMonitoringUsageDescription` 键校验通过。
⏳ 待真机核实（需用户授权 + 真实环境）：Accessibility 授予后 QQ 音乐播放/暂停；完全日历访问后 Google 会议推迟；macOS 26 `canBecomeKey` 稳定性；工作日志提示窗在多屏/全屏应用前的可见性与焦点；**输入监控授权后（重启 App 生效）Control+Command+Q 是否正确改为进入屏幕遮罩而非真正锁屏**；未授权时是否正确降级为仅菜单可用；手动遮罩与计划性休息触发时序的互斥表现；多屏热插拔期间手动遮罩的重建。

## 7. 工作日志（休息前记录 + 周期报告）

### 7.1 设计依据（循证）

休息前弹窗记录「完成了什么 + 可选下一步」，本质是 **转换边界的认知闭合仪式**，而非生产力打卡：

- **Leroy 注意力残留 [7]**：任务切换时部分注意力滞留于前一任务（尤以未完成/被打断时为甚），降低后续认知资源。其在转换点写下「已完成 / 剩余 / 回归首步」的 *ready-to-resume plan*（< 1 分钟）即给大脑闭合 [8]。本特性的「下一步（可选）」字段即此干预的直接落地。
- **Stubblebine 插值日记 [9], [10]**：以「任务转换」为触发（非时钟），在转换点花 2–4 句、60–90 秒记录，保持轻盈否则首周即弃 [10]。本特性钉死在唯一转换边界（`.working → .resting`），文案为「闭合」而非「汇报」。
- **Fogg 行为模型 [11]**：动机低且可变时，最大化 Ability（简化）是改变行为的关键——故字段可选、回车即提交、到点自动放行（等待时长可配，默认 3 分钟；亦可设永久等待）、轮换占位、软字符计数（不硬截断、不设最小长度——最小长度是已证实的完成杀手 [12]）。
- **JITAI [13]**：提示在「已被接受的打断」（休息本身）时机出现，而非新增第二个打断；提供 *provide-nothing* 选项（连续跳过衰减 + 可关闭）以对抗习惯化与怨恨。

### 7.2 架构（正交，纯 FSM 零改动）

| 关注点 | 位置 | 说明 |
|---|---|---|
| 模型 | `Engine/Models.swift` `WorkLogEntry` / `PreBreakContext` | 纯数据，`Codable` 容错解码 |
| 存储 | `Engine/WorkLogStore.swift` | 镜像 `ConfigStore`：原子写 + 容错读，独立 `work-log.json` |
| 报告（纯函数） | `Engine/WorkLogReport.swift` | `filterWorkLogEntries` / `renderWorkLogReport`，确定性幂等 |
| pre-break 拦截 | `Engine/LiveGiveMeABreakEngine.tick()` | 副作用分发处最小拦截；`completeDeferredRest(now:)` |
| 提示窗 / 报告窗 | `Integrations/WorkLog/` | SwiftUI + NSHostingController（同 `SettingsWindowController` 范式） |

**纯 FSM（`evaluate`/`transition`/`sideEffects`）零改动**——它是跨平台单一事实源（与 Windows C# 端共享 fixture，见 [windows-port-design.md](./windows-port-design.md)）。工作日志仅是接线层的副作用拦截 + 独立存储 + 独立报告。

### 7.3 tick() 副作用拦截 + 心跳冻结

```
tick() 检测 eff.showOverlay（.working → .resting）
  ├─ willDefer = onPreBreak != nil && config.workLogEnabled && !forcedRest
  ├─ if willDefer: 调 onPreBreak(ctx)；本 tick 跳过 overlay.show / music（延迟）
  │     └─ AppRoot.handlePreBreak(ctx):
  │          ├─ 门控：workAccum < 15min 且非 DEBUG → 不弹，直接 completeDeferredRest
  │          ├─ 连续跳过衰减：≥3 次 → 本次静默并清零（自愈）
  │          ├─ 弹提示：heartbeat.suspend()（冻结 tick，休息倒计时不被侵蚀）+ present(timeout)
  │          └─ 提交/跳过/超时/关窗 → WorkLogStore.append（仅提交非空）→ completeDeferredRest → resume
  └─ else: overlay.show / music（既有路径不变）
```

**`completeDeferredRest(now:)` 是第二个「绕过 tick 直接改 state」的路径**（首个为 `requestEarlyRestExit`）。遵循 [issue #6](../.agents/issue.md) 铁律——与 tick 不变量逐一对齐：guard `phase == .resting`；`restStartedAt = now`（rebase，完整休息时长不被提示耗时侵蚀）；`lastTickAt = now`（rebase 对账基点，恢复心跳后首 tick delta≈0 不回灌）；不改 phase、不动 `forcedRest`（仅离开 `.resting` 时清）。

**永不阻塞休息**：回车提交 / Esc / 跳过按钮 / 红色关闭按钮（`windowWillClose`）/ 到点 `DispatchSource` 超时（等待时长由 `config.workLogPromptTimeoutSeconds` 配置，独立于被冻结的引擎心跳）任一即 `completeDeferredRest` 升起遮罩。**永久等待**（`workLogPromptTimeoutSeconds == 0`）下不调度超时定时器，仅靠前几路手动出口；系统唤醒时若提示窗仍开启则不抢恢复心跳，避免延迟休息被静默判定结束。

**规避 [issue #6](../.agents/issue.md) z-order 陷阱**：提示窗在遮罩**之前**渲染（普通 `.floating` 层级），而非塞进 `CGShieldingWindowLevel` 遮罩内部或用 `NSAlert`（后者会被遮罩遮挡不可见）。

**向后兼容**：`onPreBreak == nil`（既有所有单测）→ `willDefer = false` → 行为与历史逐字节一致；既有测试零回归。

### 7.4 数据模型与报告

`WorkLogEntry { id, startedAt(≈restStartedAt − workAccum), endedAt(=restStartedAt), summary, nextAction?, durationSeconds, modelVersion }`，持久化 `~/Library/Application Support/com.aurelius.givemeabreak/work-log.json`，schema 见 [shared/work-log.schema.json](../shared/work-log.schema.json)。

`renderWorkLogReport` 按 `startedAt` 在指定时区分桶，产出今日/本周/月报/全部 Markdown：恰好一个 H1 + blockquote 元数据（周期/时区/条数/总专注时长）+ Top 3（按时长降序）+ 按日或按周拆解 + 待续·下一步（聚合 `nextAction`）。日期格式化全用 `Calendar` 组件手动拼接（零 locale 依赖，**确定性幂等**：同 entries + 同 now/cal/tz → 字节一致，便于 git diff）。v1 不做模糊去重/关键词 tag 推断（避免隐藏用户原始数据 + 误合并）。

## 8. 主动屏幕遮罩（手动遮罩）

### 8.1 设计目标与正交性

在到点强制休息之外，新增一个**用户主动触发**的屏幕遮罩能力（菜单「屏幕遮罩」）：复用休息遮罩完全相同的视觉/输入阻断机制（`CGShieldingWindowLevel` 多屏 borderless `NSPanel`），但与调度引擎（FSM）**正交解耦**——`ScreenMaskController` 不读写 `EngineState`、不触发 `forcedRest`/`onPreBreak`/`onPostBreak` 等任一副作用路径，因此不会复现 [issue #6](../.agents/issue.md) 中「一次性意图标志被下个 tick 拉回」的耦合缺陷。触发方式：

1. 菜单栏「屏幕遮罩」菜单项（`StatusItemController`，始终可用，零权限依赖）；
2. 占用 macOS 默认锁屏快捷键 Control+Command+Q（`LockShortcutMonitor` 用 `CGEventTap` 在 HID 层拦截并消费，系统不再执行真正锁屏），需用户授权「输入监控」，未授权时静默降级为仅菜单可用（不阻塞、可观测日志，同 [issue #3](../.agents/issue.md) 降级范式）。

退出仅支持双击 Esc（0.4s 内，复用 `LiveOverlayController` 已验证的时间窗/事件消费逻辑），不设二次确认——手动遮罩无「强制时长」需要保护，不同于休息软强制。

`ScreenMaskController` 复用 `LiveOverlayController.swift` 内定义的 `OverlayPanel`（`NSPanel` 子类），但独立实现面板构造/热插拔/淡入淡出——刻意**不**抽取共享基类：`LiveOverlayController.swift` 是 [issue #4](../.agents/issue.md)、[issue #6](../.agents/issue.md) 两次事故现场且零自动化测试覆盖，本项目既有窗口控制器（`SettingsWindowController`/`WorkLogPromptWindowController` 等 7 处）也均独立重复各自的 `NSApp.activate`/`makeKeyAndOrderFront` 样板代码、从未共享基类，本次遵循同一惯例。

### 8.2 与调度引擎的关系：遮罩冻结计时，强制休息优先

`ScreenMaskController`（手动）与 `LiveOverlayController`（休息）各自独立持有一组 `OverlayPanel`，均置于同一 `CGShieldingWindowLevel`，二者不得同时显示。编排层（`AppRoot`）的协调语义（v0.1.5 起）：

- **遮罩冻结引擎**：进入遮罩即挂起心跳（复用工作日志小结窗的既有「心跳冻结」机制）——工作累加器停止推进，计划性休息及其小结窗**不可能在遮罩中触发**（用户诉求：遮罩是「请勿打扰」，不被到点休息的表单打断）。遮罩结束（双击 Esc）先经 `LiveGiveMeABreakEngine.handleScreenMaskEnded()` rebase 对账基点（语义同 `handleWake`，遮罩时长不回灌工作累加器），再恢复心跳。
- **不变量**：`遮罩显示 ⇒ 心跳挂起`。全部 resume 路径（小结窗收尾 `afterPrompt` / 唤醒 `didWake` / 遮罩收尾）均带守卫：小结窗展示中、遮罩显示中分别不在此恢复，由各自的收尾方恢复，`suspend`/`resume` 严格配对（`HeartbeatTimer` 二者幂等，双挂起安全）。
- **强制休息优先于遮罩**：「立即休息」（菜单/⌃⌥⌘R）为显式用户动作，`forceRestNow()` 先撤遮罩（触发上述收尾链路）再强制休息——不会叠加两组遮罩面板。
- 进入手动遮罩前置 guard：`engine.state.phase == .resting`（含小结窗延迟期，该阶段 phase 已是 .resting）时忽略触发，已被休息遮罩覆盖或小结窗流程进行中时不叠加。
- 手动遮罩罩住已打开的设置窗等窗口（不做特殊处理），与既有「立即休息」菜单项行为对称。

### 8.3 CGEventTap 快捷键拦截

`LockShortcutMonitor` 在 HID 事件流入 WindowServer 之前插入一个 `.headInsertEventTap`（`tap: .cghidEventTap`）<sup>[[14]](#ref14)</sup>，监听 `keyDown`，比对 `keyCode==12`（Q）且修饰键恰为 Control+Command（`CGEventFlags` 与关心的修饰键位掩码求交集后比较，忽略 `.maskNonCoalesced`/`.maskNumericPad` 等硬件杂位），命中则消费（回调返回 `nil`，系统不再派发）并转投 `onTriggered`；未命中原样放行。`options` 必须为 `.defaultTap`（而非 `.listenOnly`）——后者只能观察无法拦截。回调保持轻量（仅比较 + 主线程异步转发），否则系统会以 `.tapDisabledByTimeout` 强制禁用 tap，需监听该事件类型并调用 `CGEvent.tapEnable(tap:enable:true)` 恢复（应用唤醒时另经 `recheckHealth()` 兜底核实）。权限模型独立于既有 `AXIsProcessTrusted`（后者仅用于*发送*媒体键 CGEvent）——*监听*系统级按键需要「输入监控」(Input Monitoring) 权限，经 `CGPreflightListenEventAccess()` / `CGRequestListenEventAccess()` <sup>[[15]](#ref15)</sup> 查询/申请，未授权时 `CGEvent.tapCreate` 返回 `nil`，按既有降级范式静默回退（仅菜单可用 + NSLog 诊断）。

⚠️ **已知 macOS 行为边界**（非本实现缺陷，均已交叉验证）：(a) **Secure Input Mode 全局单例**——系统上任意 App 持有 Secure Input（密码框、Terminal 安全键盘输入等）时，全机所有 `CGEventTap` 被静默禁用，此时按 Control+Command+Q 会真正锁屏，且本 App 对此不可探测；(b) **输入监控权限变更非热生效**——与 Accessibility 不同，用户在系统设置授权后须重启 App 才生效；(c) 固定拦截 macOS 默认组合 Control+Command+Q，用户自定义过的锁屏快捷键不在拦截范围内。

⚠️ **CLT SDK 注记**：`CGEventFlags` 无 `NSEvent.ModifierFlags.deviceIndependentFlagsMask` 对应物，需显式声明关心的修饰键位掩码后再求交集比较（实现时已验证于本项目 Command Line Tools 工具链下编译通过；`CGEvent.tapCreate`/`CGPreflightListenEventAccess`/`CGRequestListenEventAccess` 均无 [issue #2](../.agents/issue.md) 那类符号缺失问题）。

### 8.4 快捷键体系（三层，各司其职）

| 层 | 组合键 | 机制 | 权限 | 生效范围 |
|---|---|---|---|---|
| 全局即时动作 | ⌃⌥⌘K 屏幕遮罩 / ⌃⌥⌘R 立即休息 | `RegisterEventHotKey`（Carbon HIToolbox，`GlobalHotkeyCenter`） | 无 | 全局，事件被系统消费、不透传前台应用 |
| 系统锁屏劫持 | ⌃⌘Q | `CGEventTap`（§8.3） | 输入监控 | 全局，权限门控 |
| 菜单快捷键 | 裸字母（R/K/L/,/Q） | `NSMenuItem.keyEquivalent` | 无 | 仅菜单展开时（AppKit 原生行为） |

选择 ⌃⌥⌘ 修饰组合的原因：与常见应用内快捷键（⌘R/⌘K/⌘L 等）冲突面最小。v0.1.4 曾把裸字母展示为组合键、被用户按全局快捷键预期使用而无任何反应（「所有快捷键未生效」缺陷根因之一）——修复为即时动作挂真实全局热键 + 菜单如实展示 ⌃⌥⌘R/⌃⌥⌘K；窗口类菜单项保留菜单展开时快捷键（其原生生效域），不做全局注册（全局化窗口弹出/退出属于越权抢键，退出热键化更是灾难性脚枪）。

⚠️ **CLT SDK 注记（[issue #2](../.agents/issue.md) 同类）**：本 SDK 的 HIToolbox 头文件已不含 `RegisterEventHotKey` 声明，仅 `HIToolbox.tbd` 导出符号；Swift `import Carbon.HIToolbox` 仍可编译链接。已在独立无授权进程中探针验证 `InstallEventHandler`/`RegisterEventHotKey` 返回 `noErr`（零权限可用）。Carbon 文档已被 Apple 归档：[Documentation Archive](https://developer.apple.com/library/archive/navigation/index.html?filter=carbon)。

## References

<a id="ref1"></a>[1] Apple Inc., "NSWindow.Level.screenSaver — Window Levels," *AppKit Developer Documentation*, 2026. [Online]. Available: https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct/screensaver
<a id="ref2"></a>[2] Apple Inc., "NSWorkspace willSleepNotification / didWakeNotification," *AppKit Reference*, 2024.
<a id="ref3"></a>[3] Apple Inc., "CGShieldingWindowLevel()（已弃用；等价 `CGWindowLevelForKey(kCGShieldingWindowLevelKey)` = `NSWindow.Level.screenSaver`，同屏蔽层级）/ NSWindow collectionBehavior," *Core Graphics & AppKit Developer Documentation*, 2026. [Online]. Available: https://developer.apple.com/documentation/coregraphics/cgshieldingwindowlevel()
<a id="ref4"></a>[4] Apple Inc., "NX_KEYTYPE_PLAY and AUX_CONTROL_BUTTONS," *IOKit HID Event Types (ev_keymap.h)*, 2024.
<a id="ref5"></a>[5] Apple Inc., "EKEventStore / requestFullAccessToEvents / EKEventStoreChanged," *EventKit Framework Reference*, 2024.
<a id="ref6"></a>[6] Apple Inc., "EKSource sourceType (.calDAV)," *EventKit Reference*, 2024.
<a id="ref7"></a>[7] S. Leroy, "Why is it so hard to do my work? The challenge of attention residue when switching between work tasks," *Organizational Behavior and Human Decision Processes*, vol. 109, no. 2, pp. 168–181, 2009. [Online]. Available: https://www.sciencedirect.com/science/article/abs/pii/S0749597809000399
<a id="ref8"></a>[8] M. Tishma, "Conquering Attention Residue," *Chief Learning Officer*, Mar. 2018. [Online]. Available: https://www.chieflearningofficer.com/2018/03/02/conquering-attention-residue/
<a id="ref9"></a>[9] T. Stubblebine, "Replace Your To-Do List With Interstitial Journaling To Increase Productivity," *Better Humans / Medium*, Sep. 2017. [Online]. Available: https://betterhumans.pub/replace-your-to-do-list-with-interstitial-journaling-to-increase-productivity-4e43109d15ef
<a id="ref10"></a>[10] D. Chen, "Interstitial Journaling: Method, Prompts & Science," *Life Note*, 2026. [Online]. Available: https://blog.mylifenote.ai/interstitial-journaling/
<a id="ref11"></a>[11] B. Fogg, "Fogg Behavior Model — Prompts (Facilitator / Signal / Spark)," *Stanford Behavior Design Lab*. [Online]. Available: https://www.behaviormodel.org/prompts
<a id="ref12"></a>[12] "Required Fields in Forms: Best Design Practices," *UX Tigers*, 2024. [Online]. Available: https://www.uxtigers.com/post/required-fields
<a id="ref13"></a>[13] I. Nahum-Shani et al., "Just-in-Time Adaptive Interventions (JITAIs) in Mobile Health: Key Components and Design Principles for Ongoing Health Behavior Support," *Annals of Behavioral Medicine*, 2016. [Online]. Available: https://pmc.ncbi.nlm.nih.gov/articles/PMC5364076/
<a id="ref14"></a>[14] Apple Inc., "CGEvent.tapCreate(tap:place:options:eventsOfInterest:callback:userInfo:) — Quartz Event Services," *Core Graphics Developer Documentation*, 2026. [Online]. Available: https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)
<a id="ref15"></a>[15] Apple Inc., "CGPreflightListenEventAccess() / CGRequestListenEventAccess() — Input Monitoring Privacy Access," *Core Graphics Developer Documentation*, 2026. [Online]. Available: https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess() ; https://developer.apple.com/documentation/coregraphics/cgrequestlisteneventaccess()

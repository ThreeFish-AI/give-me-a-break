# Issues 摘要

> 用于跨上下文留存问题处理经验，避免重复踩坑。新条目追加在末尾，同 Issue 只维护一处。
>
> 每条摘要包含：**表因 / 根因 / 处理方式 / 后续防范 / 同类问题影响**。

---

## #1 CLT 无 XCTest / Swift Testing，无法 `swift test`

- **表因**：`import XCTest` 报 `no such module 'XCTest'`；`import Testing`（Swift Testing）报宏插件 `TestingMacros` not found。
- **根因**：Command Line Tools（非完整 Xcode）不含 XCTest 框架与 Swift Testing 宏插件，二者均随 Xcode 附带。
- **处理方式**：自建极简测试运行器——`tests/` 下可执行目标 `GiveMeABreakTests`，提供 `test(name){}` / `expect(...)` / `expectEqual(...)` + 计数 + 退出码，`make test` → `swift run GiveMeABreakTests` 驱动。语义对齐 XCTest，30 用例 <1s。
- **后续防范**：若未来安装完整 Xcode，可平滑迁移回 XCTest（断言 API 一一对应）；AGENTS.md 已注明此适配。
- **同类影响**：任何纯 CLT 环境的 Swift 项目均适用此方案，勿再尝试 `swift test` + XCTest。

## #2 CGEvent.subtype / CGEventSubtype 在 CLT SDK 不可写

- **表因**：合成媒体键事件设 `event.subtype = CGEventSubtype(rawValue: 8)` 报 `cannot find 'CGEventSubtype' in scope`；`.init(rawValue:)` 亦不可推断。
- **根因**：CLT 的 Swift overlay 未暴露 `CGEventSubtype` 类型，且 `event.subtype` 属性不可赋值。
- **处理方式**：改用 `event.setIntegerValueField(.mouseEventSubtype, value: 8)` 字段写法（探测确认 `.mouseEventSubtype` CGEventField 可用）；CGEvent 构造用完整 `init(mouseEventSource:mouseType:mouseCursorPosition:mouseButton:)`。
- **后续防范**：CLT 下涉及 CGEvent 复杂属性时优先用 `setIntegerValueField` 字段路径，勿依赖具名属性。
- **同类影响**：所有合成系统事件（媒体键/特殊鼠标）的代码。

## #3 休息音效：CGEvent 媒体键控 QQ 音乐多重失败 → 内置粉噪音降级

- **表因**：用户反馈休息时没有播放音乐；无头环境亦无法验证 QQ 音乐实际播放/暂停效果。
- **根因**：应用**无任何内置音频**，原仅靠 CGEvent 合成 `NX_KEYTYPE_PLAY`(=16) toggle 媒体键远程控制外部 QQ 音乐。媒体键路由依赖多重外部条件，任一不满足即**静默失败、无音效、无用户反馈**：(a) 已安装 `/Applications/QQMusic.app`；(b) 已授辅助功能权限（`AXIsProcessTrusted`，否则 CGEvent 被系统丢弃）；(c) QQ 音乐注册为当前 Now Playing 应用；(d) 1.5s 启动延迟足够 QQ 音乐完成注册；(e) toggle 语义正确（若 QQ 音乐正在播放，toggle 反而暂停）。极高概率根因：**未安装 QQ 音乐** 或 **未授权辅助功能**。
- **处理方式**：
  - **内置粉噪音降级（核心修复）**：新增 `AmbientSoundPlayer`（AVAudioEngine + AVAudioPlayerNode 循环预生成粉噪音 buffer，Paul Kellet 算法，零音频文件、零第三方依赖、CLT 兼容），作为可靠休息音效——**无论 QQ 音乐是否可用都会响**。macOS 无 `AVAudioSession`（iOS 专有，实测 `sharedInstance()` 标记 unavailable），故仅 `engine.start()`，CoreAudio 默认与其他音频混合。
  - `DayPlanConfig` 新增 `ambientSoundEnabled`(默认 true) / `controlQQMusic`(默认 true) 两开关 + `schemaVersion` 1→2；自定义 `init(from:)` 容错解码（旧配置缺字段补默认，**不丢失**原有工作窗口/节律）+ `ConfigStore.migrate` 规范化版本号。
  - `MusicController` 协议加 `updateConfig(_:)`，引擎在 init 与 `updateConfig` 时同步配置给播放器（正交：降级逻辑收敛在 `LiveMusicController` 内，`SideEffects`/`Engine` 纯函数不变）。
  - **诊断日志**：`startPlayback()` NSLog QQ 音乐 `installed/trusted/running` 三态，让「为何不响」可观测（Console.app `[GiveMeABreak][music]`）。
  - 保留 QQ 音乐媒体键路径为可选增强（用户装了就用，没装粉噪音兜底）。
- **后续防范**：实机回归先授 Accessibility + 装 QQ 音乐，确认 Now Playing 激活后再测联动；粉噪音默认开保证基础体验。**任何依赖不可控外部条件的能力，必须配可靠降级 + 可观测日志 + 用户可感知反馈，禁止静默失败。**
- **同类影响**：任何控制第三方媒体播放器 / 依赖系统路由的方案；任何「外部依赖无降级」的静默失败模式。

## #4 macOS 26 `canBecomeKey=true` 实机回归——已验证无崩溃

- **表因**：遮罩 NSPanel 需 `canBecomeKey=true` 以接收 Esc；2024-2025 报告称 macOS 26 beta 下窗口出现数秒后可能崩溃。
- **根因**：OS beta 期回归（release 已修复）。
- **处理方式**：保留 `canBecomeKey=true`（Esc 双保险：本地事件监听 + key）。
- **验证结果（macOS 26.5.1 实机）**：遮罩触发期间进程持续存活（无崩溃）；`CGWindowListCopyWindowInfo` 查询证实面板位于 `layer=2147483628`（CGShieldingWindowLevel）、bounds 匹配全屏、多显示器各一面板。**结论：beta 崩溃问题在 release 已消失。**
- **附带发现**：`screencapture` 无法捕获 CGShieldingWindowLevel 窗口（macOS 安全限制）——验证遮罩可见性须用 `CGWindowListCopyWindowInfo` 查询窗口服务器，而非截图。
- **同类影响**：全屏置顶 borderless 面板场景的 macOS 版本回归。

## #5 无 Xcode → SPM + Makefile 手工 .app 装配

- **表因**：本机未装 Xcode，无法 `xcodebuild` 生成 `.xcodeproj`。
- **根因**：方案原定 `.xcodeproj`，但环境约束不允许。
- **处理方式**：改用 Swift Package Manager（`Package.swift` 三目标）+ `Makefile` 手工装配 `.app`（`Contents/MacOS` + `Info.plist` + `PkgInfo` + `codesign` ad-hoc + Hardened Runtime + entitlements + `xattr` 清 quarantine）。比 `.xcodeproj` 更简约，且 `codesign`/`notarytool` 随 CLT 可用。
- **后续防范**：公开分发时用 Developer ID + `notarytool` + `stapler`（Makefile 已预留注释）；个人用 ad-hoc 即可。
- **同类影响**：任何无 Xcode 的 macOS 应用构建。

## #6 休息模式 Esc 退出失效（对话框被遮罩遮挡 + forcedRest 残留死循环）

- **表因**：(a) 休息遮罩下按 Esc，确认对话框不可见，Esc 退出永远无反应；(b)（经菜单「立即休息」进入休息后）即便能触发「直接退出」，遮罩消失后约 1 秒重新出现并重置 10 分钟倒计时，永远无法退出。
- **根因**：
  - (a) `LiveOverlayController` 遮罩面板 `level=CGShieldingWindowLevel()`（≈2147483628，窗口层级最高）；确认用 `NSAlert.runModal()`，其模态窗默认 `level=NSModalPanelWindowLevel`（=8）≪ 遮罩，对话框渲染在遮罩之下不可见；且 `runModal` 阻塞主线程但按钮不可达。`OverlayPanel.canBecomeMain=false` 进一步使 NSAlert 模态 session 不稳。
  - (b) `LiveGiveMeABreakEngine.requestEarlyRestExit()` 设 `phase=.working` 但**未清除 `forcedRest`**；该标志唯一清除点是 `tick()` 内（`oldPhase==.resting && s.phase!=.resting`），而 `requestEarlyRestExit` 绕过了 tick 路径。下个 tick 的 `transition` 纯函数见非休息态且 `forcedRest==true`，无视一切重进 `.resting` 并设新 `restStartedAt=now`（新倒计时）→ 死循环。仅「立即休息」入口触发（自然触发的休息 `forcedRest=false`，Esc 退出正常）。
- **处理方式**：
  - (a) 弃用 NSAlert，确认 UI 改为**内嵌遮罩 SwiftUI 视图**（新增 `OverlayViewModel: ObservableObject`，`@Published isConfirming` 驱动倒计时态/确认态切换），与遮罩同层级，从根上消除遮挡；非阻塞、不依赖 main window、多屏一致；Esc 双语义（倒计时态→进入确认，确认态→取消返回倒计时）；主屏 panel `makeKeyAndOrderFront` 使 Button 可接收点击/回车。
  - (b) `requestEarlyRestExit()` 加 `forcedRest = false`，与 tick 共享「离开 .resting 即清 forcedRest」不变量。配回归测试（`forceRestNow`→`requestEarlyRestExit`→再 tick，断言 `overlay.showCount` 修复前=2/后=1，phase 保持 working）。
- **后续防范**：
  - CGShieldingWindowLevel 遮罩下任何需用户交互的 UI，必须**内嵌于遮罩面板内部**（同层级），禁用 NSAlert / 独立普通窗口（会被遮挡）。
  - 任何**绕过 tick 直接修改 state 的路径**（`requestEarlyRestExit`/`handleSleep`/`handleWake`/`fastForward`/`forceRestNow`/`updateConfig`）必须与 tick 的状态不变量逐一对齐（本次即 forcedRest 清除）；新增此类路径时审查是否复现「标志残留被下个周期 tick 拉回」模式。
  - 回归测试须覆盖「用户主动操作 + 后续 tick」组合，而非只断言操作瞬间的状态（原盲点：`requestEarlyRestExit` 后不再 tick）。
- **同类影响**：任何「全屏置顶遮罩 + 弹窗交互」「一次性意图标志 + 周期 FSM 决策」混合架构的应用；(b) 的 forcedRest 残留模式可推广到所有「一次性意图标志 + 周期 tick」组合。

## #7 accessory app 设置窗离屏 + 初始尺寸不足（NSWindow.center / NSHostingController fittingSize）

- **表因**：命令行 `GIVEMEABREAK_SHOW_SETTINGS=1` 启动后设置窗不可见；全屏 `screencapture` 截不到，险些误判为"未创建"。
- **根因**：
  - (a) `NSWindow.center()` 在 accessory app（`LSUIElement=true`，启动时无 key window）+ 多屏/非标准坐标配置下，把窗口定位到**离屏负坐标**（CGWindowList 实测 `X=-1281`）。center() 假定窗口已关联 screen，accessory 启动早期不成立。
  - (b) `NSHostingController` 默认用 **fittingSize**（≈ SwiftUI frame 的 min），`idealWidth/idealHeight` **不生效**，窗口初始落回 `minWidth×minHeight`（实测 480×492），四 Section 显示不全、需滚动才见「休息音效」。
- **处理方式**：(a) 弃用 `center()`，改 `NSScreen.main.visibleFrame` 显式 `midX/midY` 居中（`setFrameOrigin`）；(b) 显式 `w.setContentSize(560, 680)` 让全部 Section 首屏可见。
- **验证方法论（关键）**：普通窗口可见性验证用 `CGWindowListCopyWindowInfo` 查窗口服务器（确认创建 + 读 bounds 判离屏），再 `screencapture -l <kCGWindowNumber>` **截特定窗口**；全屏 `screencapture` 在多屏/虚拟显示环境会截错屏。与 issue #4（screencapture 无法捕获 CGShieldingWindowLevel）同理：窗口可见性勿依赖全屏截图。
- **后续防范**：accessory/agent app 窗口定位勿依赖 `center()`（显式 screen 计算更可靠）；`NSHostingController` 窗口需特定初始尺寸时显式 `setContentSize`，勿依赖 SwiftUI `idealSize`。
- **同类影响**：所有 `LSUIElement` 应用（菜单栏/agent）的窗口定位与可见性验证。

## #8 release.yml 版本校验失败（tag ≠ Info.plist）+ 双 job 校验不对称 + macos-14 弃用

- **表因**：tag `v0.0.1` 触发 release.yml，macOS job step ① 版本一致性校验 `tag(0.0.1) ≠ Info.plist(0.1.0)` → `::error::` + `exit 1`，Release 未产出。但 Windows job 不校验、仍产出 `version=0.0.1` 的半成品 artifact（tag 已消耗、无 Release、Windows 残留）。
- **根因**：
  - (a) 打 tag 时未同步 `Resources/Info.plist` 的 `CFBundleShortVersionString`，二者漂移。
  - (b) **真正根因——双 job 版本解析不对称**：macOS job step ① 校验 `tag==Info.plist`，但 Windows job resolve version 在 tag 触发时**直接用 tag、不读 Info.plist、不校验**。校验逻辑分散在两 job 且行为不一：macOS 拦截时 Windows 仍静默产出错误版本号产物。即使本次 macOS 校验存在，也只挡了一半。
  - (c) 次级噪声：README Swift baseline(6.0) ↔ macos-14 runner(Swift 5.x) ↔ Package.swift(5.10) 三者矛盾，每次 CI warning；且 `macos-14` 将于 2026-07-06 弃用（2026-11-02 下线）。
- **处理方式**：
  - 版本统一：`Info.plist` 保持 `0.1.0`（语义为"首个可用版本"，优于向 `0.0.1` 妥协的自我降级）；删除未产出 Release 的半成品 tag `v0.0.1`，重建为 `v0.1.0`。
  - **治本——抽共享 composite action `.github/actions/verify-version`**（`grep`/`sed` 跨平台解析 plist，不依赖 Windows runner 缺失的 `PlistBuddy`），macOS/Windows 双 job 同源强校验、输出统一 `version`。原分散两 job 的版本逻辑收敛为一处（SSOT）。
  - `macos-14` → `macos-15`（ci.yml×3 + release.yml×1）：默认 Xcode 16.4/Swift 6.0.x，消除 Swift warning + 预防弃用；`Package.swift` 保持 5.10 向下兼容，README 6.0 baseline 名正言顺。
- **后续防范**：
  - 版本号 SSOT 是 `Info.plist` 的 `CFBundleShortVersionString`；打 tag 前必须确认与之一致（现由 CI `verify-version` action 强校验落地）。
  - **双平台/多 job 的同类校验逻辑必须收敛为共享 action，禁止各 job 内联复制**——否则行为漂移（本次 Windows 漏校验即此反模式）。
  - macOS runner 选型须关注弃用时间线（参考 [actions/runner-images](https://github.com/actions/runner-images/issues/13518)），优先 `macos-15`+。
- **同类影响**：所有 tag-driven 多平台 release workflow；所有"双 job 独立解析同一事实源"的反模式；GitHub Actions macOS runner 版本时效性。

## #9 NSHostingController.rootView 复用致 SwiftUI `@State` 跨弹窗残留（跳过=复用上次记录）

- **表因**：用户报告「工作日志跳过」后，下次小结窗仍显示上次输入的内容（视觉=复用上次记录、疑似跳过仍写库）。
- **根因**：四个窗口控制器（WorkLog 提示/补录、Exercise 提示/补录）+ 报告/设置控制器在**稳定的 `NSHostingController`** 上反复赋值 `rootView = view`。SwiftUI 在 root 视图**身份不变**时**保留 `@State`**（`@State` 存于 SwiftUI 内部存储、按视图身份键控，身份不变即不重置）。于是「输入文字 → 跳过/关窗」后 `@State` 残留，下次弹窗文字仍在。代码层 skip 路径**确实不写库**——纯视觉残留，但用户感知为「数据被复用」。
- **处理方式**：每次 `present`/`show` **重建 `NSHostingController`**（窗口复用、控制器替换：`window?.contentViewController = NSHostingController(rootView: view)`），强制 SwiftUI 视为新视图树、`@State` 归零。Settings 控制器额外重建 KVO（`preferredContentSize` 观测绑到新 hosting）；report 控制器同步处理。
- **后续防范**：**任何 `NSHostingController`/`UIHostingController` 反复替换 rootView 的场景，必须重建 hosting 控制器或用 `.id(token)` 强制身份变更**，否则 `@State`/`@FocusState` 残留。复用窗口可以，但「视图身份」不可隐式复用。
- **同类影响**：所有 AppKit+SwiftUI 混合的复用窗口（菜单栏 accessory app 尤甚）；任何「重开窗口显示旧草稿/旧输入」的疑似 bug 先查此根因，而非查持久化层。

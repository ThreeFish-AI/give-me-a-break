# Issues 摘要

> 用于跨上下文留存问题处理经验，避免重复踩坑。新条目追加在末尾，同 Issue 只维护一处。
>
> 每条摘要包含：**表因 / 根因 / 处理方式 / 后续防范 / 同类问题影响**。

---

## #1 CLT 无 XCTest / Swift Testing，无法 `swift test`

- **表因**：`import XCTest` 报 `no such module 'XCTest'`；`import Testing`（Swift Testing）报宏插件 `TestingMacros` not found。
- **根因**：Command Line Tools（非完整 Xcode）不含 XCTest 框架与 Swift Testing 宏插件，二者均随 Xcode 附带。
- **处理方式**：自建极简测试运行器——`tests/` 下可执行目标 `TimeoutTests`，提供 `test(name){}` / `expect(...)` / `expectEqual(...)` + 计数 + 退出码，`make test` → `swift run TimeoutTests` 驱动。语义对齐 XCTest，30 用例 <1s。
- **后续防范**：若未来安装完整 Xcode，可平滑迁移回 XCTest（断言 API 一一对应）；AGENTS.md 已注明此适配。
- **同类影响**：任何纯 CLT 环境的 Swift 项目均适用此方案，勿再尝试 `swift test` + XCTest。

## #2 CGEvent.subtype / CGEventSubtype 在 CLT SDK 不可写

- **表因**：合成媒体键事件设 `event.subtype = CGEventSubtype(rawValue: 8)` 报 `cannot find 'CGEventSubtype' in scope`；`.init(rawValue:)` 亦不可推断。
- **根因**：CLT 的 Swift overlay 未暴露 `CGEventSubtype` 类型，且 `event.subtype` 属性不可赋值。
- **处理方式**：改用 `event.setIntegerValueField(.mouseEventSubtype, value: 8)` 字段写法（探测确认 `.mouseEventSubtype` CGEventField 可用）；CGEvent 构造用完整 `init(mouseEventSource:mouseType:mouseCursorPosition:mouseButton:)`。
- **后续防范**：CLT 下涉及 CGEvent 复杂属性时优先用 `setIntegerValueField` 字段路径，勿依赖具名属性。
- **同类影响**：所有合成系统事件（媒体键/特殊鼠标）的代码。

## #3 CGEvent 媒体键需 Accessibility + Now Playing 竞争（待真机核实）

- **表因**：无头环境无法验证 QQ 音乐实际播放/暂停效果。
- **根因**：CGEvent 媒体键路由依赖 (a) Accessibility 权限、(b) QQ 音乐注册为当前 Now Playing 应用。二者均需真机 + 用户授权，无头不可复现。
- **处理方式**：实现 `LiveMusicController`（CGEvent `NX_KEYTYPE_PLAY`=16，经二进制验证 QQ 音乐注册 Now Playing），未授权时优雅降级（日志提示 + 不崩溃）；降级兜底为终止 QQ 音乐保静音。
- **后续防范**：实机回归时先授 Accessibility，确认 QQ 音乐前台/Now Playing 激活后再测；若其他 app 抢占 Now Playing，媒体键可能路由错误。
- **同类影响**：任何控制第三方媒体播放器的方案。

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

# Give me a break Windows 移植技术方案

> macOS 强制作息应用移植至 Windows 10/11 的工程设计。本方案原为可行性论证，规划的分阶段工作（纯核心重写、最小壳、全屏遮罩、Graph 日历、CI 多平台发布）已全部落地，现随主干持续演进——GitHub Release 的双平台安装包即出自本链路。
> 关联：协作规约见 [AGENTS.md](../AGENTS.md)，应用主文档见 [README](../README.md)，macOS 原始设计见 [设计文档](./give-me-a-break-design.md)，发布链路见 [`.github/workflows/release.yml`](../.github/workflows/release.yml)。

## 1. 背景与核心结论

Give me a break 原为纯 Swift（SPM，macOS 14+）实现，采用三目标正交分解：

- **`GiveMeABreakEngine`**：纯 Foundation（FSM + `evaluate` 纯函数 + JSON 持久化），零平台依赖；
- **`GiveMeABreakIntegrations`**：深度 macOS 集成（AppKit / CGEvent / EventKit / AVFoundation / ServiceManagement）；
- **`GiveMeABreak`**：`@main` 壳。

维护者诉求是在 GitHub Release 页同时提供 macOS 与 Windows 安装包。当时的循证结论决定了路径，工程现状验证了它：

> **结论 1（无法「顺便」编译）**：Swift 语言本身可在 Windows 上官方编译<sup>[[1]](#ref1)</sup>，但 `GiveMeABreakIntegrations` 依赖的 AppKit / CoreGraphics / EventKit / AVFoundation 等 Apple 专有框架在 Windows 上**物理不存在**（逐项已验证），`import AppKit` 在 Windows 工具链直接编译失败。
>
> **结论 2（务实路径）**：唯一可跨平台的资产是纯 Foundation 的 `GiveMeABreakEngine`；完整 Windows 桌面应用须**重写（非移植）整个集成层**，采用 **C#/.NET 8 WPF 原生重写 + 共享纯逻辑语义**，工作量集中在一个核心难点——全屏强制遮罩。
>
> **结论 3（macOS 发布解耦）**：macOS 发布链路与 Windows 移植解耦演进；现两平台共用 [release.yml](../.github/workflows/release.yml) 的 3 个具名 job 一次收敛双 asset（§7）。

## 2. 跨平台不可行性循证

### 2.1 Swift 语言 vs Apple 框架（关键区分）

「Swift 可跨平台」这一直觉，**仅对语言与 Foundation 标准库成立，对 Apple UI/系统框架不成立**：

| 层面 | Windows 可用性 | 证据 |
|---|---|---|
| Swift 编译器 / SPM | ✅ 官方一级支持（Swift 6.x，x86_64 + arm64）<sup>[[1]](#ref1)</sup> | swift.org 提供官方 Windows 工具链，由 Swift.org Windows Workgroup 维护 |
| Foundation（`Date`/`Codable`/`Dispatch`） | ✅ 可用（swift-corelibs-foundation） | 纯逻辑包可 `swift build` 通过 |
| **AppKit**（`NSStatusItem`/`NSPanel`/`NSWorkspace`） | ❌ **完全不可用**<sup>[[2]](#ref2)</sup> | Apple 闭源，`swift-corelibs-appkit` 长期休眠，从未移植 |
| **CoreGraphics**（`CGEvent`/`CGShieldingWindowLevel`） | ❌ **完全不可用**<sup>[[3]](#ref3)</sup> | macOS 专有，Windows 无对应物 |
| **EventKit**（`EKEventStore`） | ❌ **完全不可用**<sup>[[4]](#ref4)</sup> | 绑定 macOS 日历数据库 |
| **AVFoundation**（`AVAudioEngine`） | ❌ 不可用 | macOS/iOS 专有 |
| SwiftUI | ⚠️ 仅第三方实验性（Tokamak/SwiftCrossUI），未达生产可用 | Apple 闭源，官方仅支持 Apple 五平台 |

### 2.2 本项目的绑定盘点（实测）

全量勘察（2026-10 随代码复核）：

- **`Sources/GiveMeABreakEngine/`（13 文件，2457 行）**：100% 纯 Foundation，可直接在 Windows 编译，是唯一成块的跨平台资产；
- **`Sources/GiveMeABreakIntegrations/`（38 文件，6188 行）**：仅 `Heartbeat.swift`（36 行，`DispatchSourceTimer`）可跨平台——**38 个集成层文件中仅 1 个可跨平台**（`CodingProxy/CodingProxyProcessController.swift` 虽零 Apple 框架 import，但依赖 POSIX `kill(pid, SIGKILL)`，仅限 Unix）；
- 绑定框架分布（按 `import` 计，文件可重复计入）：SwiftUI（22）、AppKit（22）、CoreGraphics/CGEvent（4）、AVFoundation（4）、Carbon.HIToolbox（2）、EventKit（1）、ServiceManagement（1）、ApplicationServices（1）、IOKit（1）、ImageIO（1）、UniformTypeIdentifiers（1）。

> 「顺便编译」在工程上不可能：这不是「配置一下」的问题，而是**框架在目标 OS 上物理不存在**，重写是唯一路径。

### 2.3 .NET → macOS 反向跨平台（结论）

互补方向「能否把 .NET 收敛为单代码库、同时产出 macOS + Windows 构建」的调研结论共三条：

1. 纯 `net8.0` 程序集（C# 引擎核心）真跨平台，同一份 DLL 双端可运行，双端 CI 已验证（`dotnet-test` windows + `dotnet-test-mac` macOS）；
2. WPF（`net8.0-windows`）永久 Windows 专属；macOS 标志能力（`NSStatusItem` 菜单栏驻留 + 全屏遮罩）不在任何跨平台 UI 抽象内——MAUI 走 Mac Catalyst（UIKit）不暴露 `NSStatusItem`（纯 AppKit 类），Avalonia 的平台集成层（遮罩 / 媒体键 / 音频 / 自启 / 辅助功能）仍需厚 interop，等价于用 C# 重写一遍 Swift 平台层；
3. 与 §2.1 对称：可单代码库共享的只有纯引擎，UI 壳 + 平台集成层注定双写。当前「原生 Swift（macOS）+ 原生 WPF（Windows）+ 共享纯引擎语义 + 黄金测试防漂移」**即该结论的最优实现**，不建议为「单代码库」迁移 macOS 侧到 .NET（迁移成本高于仅省一份纯引擎重写，且原生保真度反降）。

> **若未来考虑 Avalonia 的两条注意事项**（循证校准，免踩坑）：① 纯菜单栏 app 隐藏 Dock 图标用官方一等公民 API `new MacOSPlatformOptions { ShowInDock = false }`（底层即 `setActivationPolicy(.accessory)`），无需手写 P/Invoke（旧社区建议已过时）；② 全屏遮罩仍需经 `TryGetPlatformHandle()` 取 `NSWindow` 句柄手设屏蔽层级（`CGShieldingWindowLevel()`，勿用仅 1000 的 `.screenSaver`）+ `NSApplication.Activate()` 转前台——属手写 interop，非开箱即用。

## 3. 架构：共享纯逻辑核心 + C#/.NET 8 WPF

### 3.1 FFI 否决

Swift 核心编译 DLL + C# P/Invoke 的 FFI 方案被否决：Swift↔CLR 边界工具链仅实验性 PoC、ABI 不稳定，且引擎仅约 2500 行纯逻辑，C# 等价重写的成本低于长期维护 FFI 边界，两端各自原生也更易测试、调试与演进。故采用 **C# 端重写引擎，以 C# 黄金 fixture 与时序镜像测试对齐 Swift 原始用例**（§6）。

### 3.2 架构总览

![双平台共享架构：Swift 三目标与 C# 七工程经 shared 单一事实源对齐](diagrams/windows-port-architecture/windows-port-architecture.svg)

**工程结构**（`windows/` 共 7 个 csproj + 2 个 sln，与 Swift 工程并列、互不侵入）：

| 工程 | TFM / 依赖 | 职责 |
|---|---|---|
| [`GiveMeABreakEngine`](../windows/GiveMeABreakEngine/) | net8.0 · 零第三方依赖 | C# 镜像 FSM（对齐 `evaluate` 谓词优先级与 advance 限幅） |
| [`GiveMeABreakEngine.Win32`](../windows/GiveMeABreakEngine.Win32/) | net8.0 · 零第三方依赖 | `[DllImport]` 声明 + Paul Kellet 粉噪音算法（元数据在 macOS 可编译可测，P/Invoke 执行在 Windows 壳内） |
| [`GiveMeABreakEngine.Graph`](../windows/GiveMeABreakEngine.Graph/) | net8.0 · 引用 Engine | Graph 日历解析 + 限流缓存 + Provider 编排（MSAL/HttpClient 经 `IGraphClient` 隔离到壳） |
| [`GiveMeABreakShell`](../windows/GiveMeABreakShell/) | net8.0-windows · 引用上述三者 · NuGet：NAudio 2.2.1 / H.NotifyIcon.Wpf 2.2.0 / System.Drawing.Common 9.0.0 / Microsoft.Identity.Client 4.66.0 | WPF 壳：全屏遮罩、托盘、WASAPI 播放、MSAL 设备码、电源/自启桥接 |
| 3 个 `*Tests` 工程 | xUnit | [CSharpTests](../windows/GiveMeABreakEngine.CSharpTests/) / [Win32Tests](../windows/GiveMeABreakEngine.Win32Tests/) / [GraphTests](../windows/GiveMeABreakEngine.GraphTests/)（计数见 §10） |

解决方案按可验证性切分：`GiveMeABreakEngine.sln` 聚引擎侧 6 工程（3 逻辑 + 3 测试，macOS 本地可编译可测）；`GiveMeABreakShell.sln` 聚壳侧 4 工程（3 逻辑 + Shell，仅 Windows 可编译）。[`shared/`](../shared/) 为跨平台单一事实源：`config.schema.json`（文档级权威定义，§6）+ `test-fixtures/`（FSM 黄金 fixture）。

## 4. 逐能力 macOS → Windows 实现映射

| 能力 | macOS 实现 | Windows 实现 |
|---|---|---|
| 粉噪音合成 | `AVAudioEngine` 循环播放预合成缓冲（Kellet 算法） | 自写 Paul Kellet 粉噪音滤波器（`PinkNoiseGenerator`，net8.0 可测，逐字对齐 `AmbientSoundPlayer`）；NAudio 仅作壳内 WASAPI 出声 sink |
| 合成媒体键 | `CGEvent`（`NX_KEYTYPE_PLAY`） | `SendInput` + `VK_MEDIA_PLAY_PAUSE`<sup>[[5]](#ref5)</sup> |
| 空闲检测 | `CGEventSource.secondsSinceLastEventType` | `GetLastInputInfo` + `GetTickCount64`<sup>[[6]](#ref6)</sup>（64 位 tick，避 49.7 天回绕） |
| 菜单栏图标 | `NSStatusItem` + `NSMenu` | H.NotifyIcon.Wpf `TaskbarIcon` + WPF `ContextMenu`（5 项子集：状态 / 立即休息 / 设置（占位，未实现）/ 开机自启 / 退出） |
| sleep/wake | `NSWorkspace` 通知 | `SystemEvents.PowerModeChanged` |
| 开机自启 | `SMAppService` | 注册表 `HKCU\...\Run`（非提权） |
| 配置持久化 | `Codable` JSON | `System.Text.Json`（v2 子集，§6） |
| 日历门控 | `EventKit`（CalDAV 复用 OS 登录态） | Microsoft Graph API + MSAL 设备码<sup>[[8]](#ref8)</sup>；Google 日历未实现（如需支持另走 Google Calendar API） |
| **全屏强制遮罩** | `CGShieldingWindowLevel`<sup>[[3]](#ref3)</sup> | **见 §5（核心难点）** |
| 辅助功能检查 | `AXIsProcessTrusted` | 不需等价授权（`SendInput` 无此要求）；但 `WH_KEYBOARD_LL` 全局钩子会触发杀软警觉（§9） |

## 5. 全屏强制遮罩（核心难点）

这是整个移植的**阿喀琉斯之踵**。macOS 的 `CGShieldingWindowLevel()`（≈2147483628，远高于 `.screenSaver` 的 1000）能压过 Dock、菜单栏、全屏应用、屏保<sup>[[3]](#ref3)</sup>；Windows **没有任何单一 API 等价物**，`HWND_TOPMOST` 在多场景盖不住 taskbar<sup>[[11]](#ref11)</sup>。故采用**软强制妥协**，诚实接受其本质（对齐 macOS 版 Esc 二次确认的设计哲学，见 [issue #6](../.agents/issue.md)）：

![Windows 遮罩软强制流程：Esc 状态机与按键拦截边界](diagrams/windows-overlay-flow/windows-overlay-flow.svg)

**设计决策与诚实披露**：

1. **窗口层级**：`WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE` + `SetWindowPos(HWND_TOPMOST)`（在 `OnSourceInitialized` 强制设置，规避 WPF `ShowInTaskbar=false` 致 TOPMOST 失效的坑）；`EnumDisplayMonitors` 为每屏各起一个全屏窗口（对齐 macOS 每 `NSScreen` 一个 `NSPanel`），支持屏幕热插拔（`DisplaySettingsChanged`）。
2. **taskbar 偶现视为可接受**：与 macOS `CGShieldingWindowLevel` 的根本差距，Windows 平台固有约束，非实现缺陷。
3. **键盘拦截清单（`WH_KEYBOARD_LL`）**：只拦 **Alt+Tab 与 LWin/RWin**<sup>[[7]](#ref7)</sup>。**Ctrl+Esc 不专门拦**——`LLKHF` 只有 ALTDOWN 标志、无 Ctrl 标志，钩子内无法区分纯 Esc 与 Ctrl+Esc，故 Esc 全放行交 WPF 双语义（开始菜单可弹，但被 topmost 遮罩覆盖）；**Ctrl+Alt+Del 放行**——Secure Attention Sequence（SAS）在内核层不可拦截，保留逃生口（同 macOS 版「force-quit 始终可终止」的已知限制，见 [README §已知限制](../README.md#已知限制透明披露)）。
4. **Esc 状态机（镜像 macOS `LiveOverlayController`）**：单次 Esc 切换遮罩内嵌确认面板（「继续休息 / 直接退出」，不依赖会被遮罩自身遮挡的系统对话框，同构 [issue #6](../.agents/issue.md) 的 Esc 退出修复）；**0.4s 内双击 Esc 直退**；「直接退出」与双击均走 `engine.RequestEarlyRestExit()`，由引擎回调 Dismiss，控制器不自 Dismiss（对齐 macOS `confirmEarlyExit`）。

## 6. 配置与行为一致性（防漂移）

防漂移机制为「Swift 原始用例为基准，C# 端以 fixture + 镜像测试对齐」：

- **Swift 端原始用例**：Swift 测试不读 fixture，期望值内联，是 FSM 语义的基准。Swift `Sources/` 不因移植改动——C# 是平行重写。
- **C# 端 A 层 · 黄金 fixture**：`shared/test-fixtures/*.json`（evaluate / advance / side-effects / merge-busy 共 17 例，覆盖 P1–P5 谓词优先级、休息触发不变量、advance 限幅、副作用分发与区间合并等**纯函数**决策；统一 Unix epoch 整数秒编码，规避两端时间格式差异）由 `CSharpTests` 消费，任一失败即阻断 CI。
- **C# 端 B 层 · 时序镜像**：多 tick 场景（[设计文档 §2.4](./give-me-a-break-design.md#24-工作示例验证30--30-会议--60-工作--10-休息) 的 30+30→60→10 工作示例、会议打断 abort-and-reset、AFK 冻结、睡眠不回灌、fast-forward 等）由 C# 测试忠实重写 Swift `Simulator` / `Mock` 辅助类逐条镜像，每条注释标注对应 Swift 用例名。

**配置 schema 的诚实披露**：[`shared/config.schema.json`](../shared/config.schema.json) 是文档级单一事实源（`schemaVersion` 为 `const 10`）。Swift 实现已到 v10（迁移链 v3→v10）；**C# 端停留在 v2 子集**（`CurrentSchemaVersion = 2`，另含 Windows 专属 `GraphClientId`）——macOS v10 配置在 Windows 读取会被 `ConfigStore.Migrate` 对高于 v2 的 schemaVersion **静默回退为内存默认值**（C# 生产代码无 `SaveConfig` 调用，配置文件本身不被改写），两端配置文件并不双向兼容。补齐 C# 镜像 schema 至 v10 列为后续工作。

## 7. CI 与多平台 Release

[`release.yml`](../.github/workflows/release.yml) 采用**单 workflow + 3 个具名 job**（无 `strategy.matrix`），规避多 workflow 同 tag 竞态（`softprops/action-gh-release` 已知并发挂 asset 竞态）：

![发布流水线：tag 触发，macos/windows 并行构建，release 收敛双 asset](diagrams/release-pipeline/release-pipeline.svg)

**触发**：`git tag v*`（版本即 tag，不可变锚点）+ `workflow_dispatch`（`prerelease` / `skip_notarize` 两开关）。

**macos job**（macos-15）：`setup-macos-swift` → 共享 `verify-version` action（tag ↔ Info.plist 一致性，与 windows job 同源强校验）→ `make app` → 演进式条件签名链（③ Developer ID 重签 / ③b 稳定自签名重签，二者互斥防双签；④ 条件公证 `notarytool submit --wait` + `stapler`）→ 打包与校验（`codesign --verify`；公证态过 `spctl`）→ 写 marker 三件套（`version` / `notarized` / `signing`，签名状态以产物实签 Authority 判定）→ **ad-hoc Gate**：产物实签为 ad-hoc 即阻断发布（逃生门 variable `ALLOW_ADHOC_RELEASE`），堵 secrets 缺失静默降级 → 上传 artifact。

**windows job**（windows-latest）：`setup-dotnet` → `verify-version` → `dotnet publish -c Release -r win-x64 --self-contained` → `Compress-Archive`。**全程无签名**（SmartScreen 告知写入 Release Note，§8）。

**release job**（ubuntu，`needs: [macos, windows]`）：下载 marker + 双 zip 并 flatten → 从 [CHANGELOG](../CHANGELOG.md) 抽取本版本章节生成 Release Note（按公证/签名态分支安装指引，含 Windows SmartScreen 告知）→ `softprops/action-gh-release` **一次挂双 asset**（`give-me-a-break-<ver>-macos.zip` / `give-me-a-break-<ver>-win64.zip`；预发布与 Latest 判定按 tag 形态与 dispatch 输入）。

CI 侧（[`ci.yml`](../.github/workflows/ci.yml)）与发布解耦：`test`（macos-15）→ `build`；`dotnet-test`（win）+ `dotnet-test-mac`（macos-15，证明 net8.0 逻辑层真跨平台）+ `dotnet-build-shell`（win，编译 + publish 壳）→ `dotnet-smoke-shell` headless 烟测（断言 `ASSEMBLY_OK` / `STARTUP_OK` / `OVERLAY_SHOW_(OK|FAIL)` / `CALENDAR_DEGRADED` 标记）。

## 8. 代码签名与分发

| 平台 | 机制 | 成本 | 现状 |
|---|---|---|---|
| macOS | Developer ID 签名 + Apple 公证（`notarytool`） | Apple Developer Program **$99/年**（签名/公证含在内） | 落地**稳定自签名**过渡（TCC 授权跨版本持久 + [install.sh](../install.sh) 去隔离一键安装）；release.yml 三态签名链 devid > selfsign > adhoc + ad-hoc Gate（§7）；购证后配置 `ENABLE_DEVELOPER_ID_SIGNING` 与对应 secrets 即升 Developer ID<sup>[[9]](#ref9)</sup> |
| Windows | Authenticode（`signtool` / Azure Trusted Signing） | OV 证书约 $200–400/年；EV 更贵 | **当前未签名**：SmartScreen 首次拦截（「更多信息 → 仍要运行」，Release Note 已告知），杀软可能误报（§9）；签名留后续单独 workflow |

> **Windows 签名注意（已验证的误区）**：自 **2023-06** 起 Microsoft 强制所有代码签名证书（含 OV）使用硬件安全模块（HSM/Token），CI 中需经 USB token 转发或云签名服务（如 Azure Trusted Signing）；且 **2024 起 EV 证书不再保证立即通过 SmartScreen**，新应用仍需逐步累积信誉<sup>[[12]](#ref12)</sup>。未签名应用的 SmartScreen 警告体验等同于 macOS ad-hoc 的 Gatekeeper 拦截<sup>[[10]](#ref10)</sup>。

## 9. 风险与误区（诚实披露）

| 风险/误区 | 说明与对策 |
|---|---|
| **杀软误报** | `WH_KEYBOARD_LL` 全局键盘钩子 + `SendInput` 媒体键易被 Defender / 360 / 火绒误判为恶意软件<sup>[[7]](#ref7)</sup>。对策：Release Note 信任指引 + 代码签名（规划中，§8）。 |
| **全屏遮罩不完美** | taskbar 偶现、Ctrl+Alt+Del 逃生是 Windows 固有约束，非 bug；需向 Windows 用户明示，管理预期。 |
| **配置不双向兼容** | C# 端 schema 停在 v2 子集，macOS v10 配置在 Windows 读取会静默回退默认（§6）；双系统共用配置文件的用户需知悉。 |
| **日历集成差异** | macOS 复用 OS Google 账户（CalDAV，零 OAuth 代码）；Windows 上 Microsoft 日历走 Graph API（设备码），Google 日历若需支持另走 Google Calendar API——两端权限模型不一致，各自独立实现。 |
| **误区：Swift 像 Java 一次编写到处跑** | 错。Swift **语言**可跨平台，但 AppKit/SwiftUI/CoreGraphics 不跨平台；Java 跨平台靠完整 JDK 标准库，Swift 无等价跨平台 GUI 库（§2.1）。 |
| **误区：GitHub Windows runner 自带 Swift** | 错。`windows-latest` 默认未预装 Swift，需 `swift-actions/setup-swift` 显式安装；且即便安装，`import AppKit` 仍编译失败。 |
| **误区：ad-hoc 签名可双击即开** | 错。macOS ad-hoc 触发 Gatekeeper 拦截，macOS 15.1 Sequoia 起「右键→打开」已失效<sup>[[10]](#ref10)</sup>，须 `xattr` 放行；Windows 未签名触发 SmartScreen。两端「下载即装」均需付费签名。 |

## 10. 实施现状

原分阶段规划（纯核心重写 → 最小壳 → 全屏遮罩 → Graph 日历门控 → CI 多平台发布）已全部落地。现状按工程结构陈述：

### 引擎侧（3 逻辑工程 + 3 测试工程）

- **`GiveMeABreakEngine`**：C# 镜像 FSM 共 13 个 `.cs` 文件（`Models/` + `Engine` + `LiveGiveMeABreakEngine` + `ConfigStore` + `Protocols` + JSON 转换器），零第三方依赖，语义对齐 Swift 版（P1–P5 谓词优先级、advance 限幅、休息生命周期、会议 abort-and-reset、forcedRest 回归、schema 迁移）。
- **`GiveMeABreakEngine.Win32`**：把「不可本地验证」压到最小的关键层——`[DllImport]` 声明（`GetLastInputInfo` / `GetTickCount64` / `SendInput` / 钩子与窗口 API）与 Kellet 粉噪音算法都在 net8.0 元数据层，macOS 本地可编译可测；实际 P/Invoke 执行发生在 Windows 壳内。
- **`GiveMeABreakEngine.Graph`**：`GraphTimelineMapper` 纯解析（filter busy/tentative、排除 isAllDay、复用 `Engine.MergeBusyIntervals`）+ `TimelineCache` 限流缓存（180s/60s、线程安全）+ `GraphCalendarProvider` 编排（`IGraphClient` mock 可测、fire-and-forget 刷新、失败降级）。
- **测试规模**：C# 合计 **55**（CSharpTests 25：fixture 驱动 + 镜像 / Win32Tests 18：粉噪音保真（Goertzel 单频功率/RMS/淡入/循环无点击）、空闲 49.7 天回绕、媒体键 down+up 序列、Win32 常量锁值 / GraphTests 12）；Swift 侧用例见 [设计文档 §测试矩阵](./give-me-a-break-design.md#10-测试矩阵)。

### 壳侧（GiveMeABreakShell，net8.0-windows，CI-only 验证）

开发机为 macOS，壳的验证策略是纯 CI（`dotnet-build-shell` 编译 + publish、`dotnet-smoke-shell` headless 烟测，§7）。组成：全屏遮罩（§5；[`FullscreenOverlayController`](../windows/GiveMeABreakShell/Adapters/FullscreenOverlayController.cs) 多屏 + 热插拔 + headless 降级标记）、托盘 [`TrayController`](../windows/GiveMeABreakShell/Tray/TrayController.cs)（macOS 菜单的 5 项子集，「设置…」为占位、点击仅打日志）、`WasapiAmbientPlayer`（NAudio WASAPI 出声 sink）、`MusicController`（粉噪音 + QQ 音乐媒体键叠加）、[`MsalGraphClient`](../windows/GiveMeABreakShell/Adapters/MsalGraphClient.cs)（MSAL 设备码 flow + GET `/me/calendarView` + `Prefer: outlook.timezone="UTC"` 强制 UTC）、[`PowerEventBridge`](../windows/GiveMeABreakShell/Power/PowerEventBridge.cs) / [`RegistryAutostart`](../windows/GiveMeABreakShell/Autostart/RegistryAutostart.cs) / [`WindowsSystemState`](../windows/GiveMeABreakShell/Adapters/WindowsSystemState.cs)。日历经 `AppRoot` 条件注入：`GraphClientId` 非空 → Graph Provider，空/失败 → `EmptyCalendarProvider`（headless 降级 `CALENDAR_DEGRADED`）。

### 共享层与 CI

`shared/`（schema + fixture，§6）；CI 与发布链路见 §7；版本节奏见 [CHANGELOG](../CHANGELOG.md)。

### CI 能证 / 不能证（诚实披露）

- **能证**：壳启动不崩、引擎装配闭环、引擎 state 落盘 `%APPDATA%`（config 见 §6，C# 生产代码不写回）、P/Invoke 声明 JIT 执行无 `EntryPointNotFound`、遮罩 `Show` 被调用（`OVERLAY_SHOW_(OK|FAIL)`）、`GraphClientId` 为空时条件注入走降级（`CALENDAR_DEGRADED`）。
- **不能证（归用户 Windows 真机验收）**：托盘图标可见（CI 无 explorer shell）、WASAPI 出声（无设备）、媒体键触发 QQ 音乐（无 QQ 音乐）、遮罩真实覆盖与键盘拦截、Esc 双语义。QQ 音乐候选进程名（`QQMusic` / `QQMusicTray`）需真机校准。
- **认证红线**：Graph 设备码授权 100% 由用户本人完成——client id 来自用户配置，授权在用户浏览器内进行，凭证与授权码不进入任何 Agent 会话或 chat。CI 无法验证真实 Graph（无账户），仅证解析层 + 编排 + 条件降级；token 内存缓存（重启需重新设备码授权）。

## References

<a id="ref1"></a>[1] Swift.org, "Swift on Windows — Official Toolchain," *Swift.org*, 2026. [Online]. Available: https://www.swift.org/install/windows

<a id="ref2"></a>[2] Apple Inc., "AppKit — Framework Reference," *Apple Developer Documentation*, 2024. [Online]. Available: https://developer.apple.com/documentation/appkit

<a id="ref3"></a>[3] Apple Inc., "CGShieldingWindowLevel() / CGEvent — Core Graphics Reference," *Apple Developer Documentation*, 2026. [Online]. Available: https://developer.apple.com/documentation/coregraphics/cgshieldingwindowlevel()

<a id="ref4"></a>[4] Apple Inc., "EventKit Framework — EKEventStore," *Apple Developer Documentation*, 2024. [Online]. Available: https://developer.apple.com/documentation/eventkit

<a id="ref5"></a>[5] Microsoft, "SendInput function and virtual-key codes (VK_MEDIA_PLAY_PAUSE)," *Microsoft Learn*, 2024. [Online]. Available: https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-sendinput

<a id="ref6"></a>[6] Microsoft, "GetLastInputInfo and GetTickCount64," *Microsoft Learn*, 2024. [Online]. Available: https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-getlastinputinfo

<a id="ref7"></a>[7] Microsoft, "LowLevelKeyboardProc callback function (WH_KEYBOARD_LL)," *Microsoft Learn*, 2024. [Online]. Available: https://learn.microsoft.com/windows/win32/winmsg/lowlevelkeyboardproc

<a id="ref8"></a>[8] Microsoft, "Microsoft Graph API — Calendar resources," *Microsoft Learn*, 2024. [Online]. Available: https://learn.microsoft.com/graph/api/resources/calendar

<a id="ref9"></a>[9] Apple Inc., "Resolving Common Notarization Issues," *Apple Developer Documentation*, 2024. [Online]. Available: https://developer.apple.com/documentation/security/resolving-common-notarization-issues

<a id="ref10"></a>[10] M. Tsai, "Sequoia Removes Gatekeeper Contextual Menu Override," *mjtsai.com*, 2024. [Online]. Available: https://mjtsai.com/blog/2024/07/05/sequoia-removes-gatekeeper-contextual-menu-override/

<a id="ref11"></a>[11] Stack Overflow, "Win32 full screen and hiding the taskbar," *stackoverflow.com*, 2024. [Online]. Available: https://stackoverflow.com/questions/2382464/win32-full-screen-and-hiding-the-taskbar

<a id="ref12"></a>[12] Microsoft, "SmartScreen reputation for Windows app developers," *Microsoft Learn*, 2025. [Online]. Available: https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation

# Knowledge Map（知识索引）

> 项目内文档与关键能力索引；按主题正交分组，链接为相对路径以便跨上下文跳转。
> 新增/变更文档时应即时同步本表。

## 应用入口与规约

| 文档 | 说明 |
|---|---|
| [README.md](../README.md) | Give me a break 应用主文档：构建/运行/权限/配置/架构 |
| [docs/give-me-a-break-design.md](../docs/give-me-a-break-design.md) | 设计文档：调度引擎 + 集成契约 + 数据模型 + 测试矩阵 + IEEE 引用 |
| [docs/windows-port-design.md](../docs/windows-port-design.md) | Windows 移植技术方案：跨平台不可行性循证 + C#/.NET WPF 架构 + 全屏遮罩妥协设计 |

## 协作支撑

| 文档 | 说明 |
|---|---|
| [.agents/issue.md](./issue.md) | 跨上下文问题经验沉淀 |

## 关键代码位置

| 能力 | 文件 |
|---|---|
| 进程入口（@main，纯 AppKit + accessory 策略钉死，避免 SwiftUI App 强制 Scene） | `Sources/GiveMeABreak/GiveMeABreakApp.swift` |
| 应用装配根（引擎 + 心跳 + 系统采样 + 三大 controller 装配；睡眠/唤醒观察；状态节流持久化与退出落盘编排） | `Sources/GiveMeABreakIntegrations/AppRoot.swift` |
| 引擎集成契约（Clock / Heartbeat / SystemStateProvider 等协议，签名无 AppKit、可纯 Foundation 测试） | `Sources/GiveMeABreakEngine/Protocols.swift` |
| 调度核心（FSM + evaluate 纯函数） | `Sources/GiveMeABreakEngine/Engine.swift` |
| 引擎接线 + sleep/wake + fast-forward | `Sources/GiveMeABreakEngine/LiveGiveMeABreakEngine.swift` |
| 心跳定时器（DispatchSourceTimer wall-clock 1Hz；suspend/resume 顺序敏感） | `Sources/GiveMeABreakIntegrations/Heartbeat.swift` |
| 系统状态采样（AFK 空闲 via CGEventSource HID 层，沙盒可用 + 睡眠标志） | `Sources/GiveMeABreakIntegrations/SystemSensors.swift` |
| 菜单栏状态项（叶子图标颜色承载状态语义 + 实时状态行；下拉菜单分组：即时动作 / 查看 / 补录 / 偏好 / 退出） | `Sources/GiveMeABreakIntegrations/StatusItemController.swift` |
| 多屏遮罩 + 软强制 Esc | `Sources/GiveMeABreakIntegrations/Overlay/LiveOverlayController.swift` |
| 主动屏幕遮罩（手动，遮罩期间心跳冻结计时）+ 系统锁屏快捷键接管 | `Sources/GiveMeABreakIntegrations/Overlay/ScreenMaskController.swift` + `Sources/GiveMeABreakIntegrations/LockShortcutMonitor.swift` |
| 系统壁纸解析（Index.plist / 航拍视频定位 / 防路径穿越 / 回退链，纯函数） | `Sources/GiveMeABreakEngine/SystemWallpaper.swift` |
| 遮罩共享航拍播放器（单 AVPlayer 多屏一路解码 + 熄屏暂停 + 失败回退静帧） | `Sources/GiveMeABreakIntegrations/Overlay/MaskBackground/MaskBackdropPlayer.swift` |
| 遮罩期间键盘白名单拦截（HID tap + 30min 看门狗验尸 + 应急短路） | `Sources/GiveMeABreakIntegrations/Overlay/MaskInputGuard.swift` |
| 遮罩背景合成（手动/休息遮罩共用单一事实源：渐变兜底 + 视频/静帧 + 暗纱 + 文案） | `Sources/GiveMeABreakIntegrations/Overlay/MaskBackground/MaskBackground.swift` |
| 全局快捷键（⌃⌥⌘K/R，RegisterEventHotKey，零权限） | `Sources/GiveMeABreakIntegrations/GlobalHotkeyCenter.swift` |
| 防止空闲睡眠/熄屏（IOKit 电源断言，等同 caffeinate -d/-i） | `Sources/GiveMeABreakIntegrations/IdleSleepGuard.swift` |
| 开机自启（SMAppService.mainApp，macOS 13+；状态实时读取勿缓存） | `Sources/GiveMeABreakIntegrations/LoginService.swift` |
| 辅助功能权限预检与授权引导（CGEvent 媒体键合成必需；授权仅由用户完成） | `Sources/GiveMeABreakIntegrations/AccessibilityChecker.swift` |
| Coding Proxy 子进程托管（Foundation.Process + 双管道日志流 + 控制台窗口；命令解析/校验/apply 决策纯逻辑在 Engine 层） | `Sources/GiveMeABreakIntegrations/CodingProxy/CodingProxyProcessController.swift` + `CodingProxyConsoleView.swift` + `CodingProxyConsoleWindowController.swift` + `Sources/GiveMeABreakEngine/CodingProxySupport.swift` |
| 休息音效（三轨：自定义休息音频 restMusicPath → 内置粉噪音 → QQ 音乐媒体键叠加） | `Sources/GiveMeABreakIntegrations/LiveMusicController.swift` + `AmbientSoundPlayer.swift`（AVAudioEngine 合成粉噪音，Paul Kellet 算法） |
| 设置界面（7 页签：通用/电源/作息/音效/日志/运动/Agentic AI；页签与宽度 SSOT = `SettingsTabMetrics`，draft-apply 模式） | `Sources/GiveMeABreakIntegrations/Settings/SettingsView.swift` |
| 设置窗承载（NSHostingView + .resizable，尺寸归用户；contentMinSize 锁页签条自然宽度下限；autosave 持久化位置尺寸） | `Sources/GiveMeABreakIntegrations/Settings/SettingsWindowController.swift` |
| Claude 设置编辑器探测与打开（Agentic AI 页 groundwork） | `Sources/GiveMeABreakIntegrations/Settings/ClaudeSettingsLauncher.swift` |
| 配置 schema 迁移（容错解码） | `Sources/GiveMeABreakEngine/Models.swift` + `ConfigStore.swift` |
| 工作日志（休息前记录 + 周期报告 + 补录；报告窗支持逐条编辑/删除/清空） | `Sources/GiveMeABreakEngine/WorkLogStore.swift` + `WorkLogReport.swift` + `Sources/GiveMeABreakIntegrations/WorkLog/`（提示/补录/报告窗与表单） |
| 运动记录（休息自然结束录入 + 补录 + 综合 周/月/季/年 报告，明细行可编辑/删除） | `Sources/GiveMeABreakEngine/ExerciseModels.swift` + `ExerciseStore.swift` + `CombinedReport.swift` + `Sources/GiveMeABreakIntegrations/Exercise/`（提示/补录/综合报告窗与表单） |
| 报告日期键（day/week/month/quarter/year，SSOT） | `Sources/GiveMeABreakEngine/ReportDateKeys.swift` |
| pre-break 拦截 + completeDeferredRest 不变量 | `Sources/GiveMeABreakEngine/LiveGiveMeABreakEngine.swift`（见 issue #6） |
| post-break 回调（仅休息自然结束触发运动录入） | `Sources/GiveMeABreakEngine/LiveGiveMeABreakEngine.swift`（onPostBreak） |
| Google 日历 EventKit 门控 | `Sources/GiveMeABreakIntegrations/LiveCalendarProvider.swift` |
| 跨端契约与共享数据（config.schema.json + work-log.schema.json；test-fixtures/ 黄金 fixture 仅 C# 测试消费；Swift 端为原始用例，C# 时序测试逐条镜像之） | `shared/` |
| C# Windows 移植（7 个 csproj：Engine / Win32 / Graph / Shell + 3 个测试工程；2 个 sln） | `windows/`（架构详见 [windows-port-design.md](../docs/windows-port-design.md)） |
| macOS 单元测试（自建极简运行器：expect/expectEqual 断言 + 退出码，`make test` → `swift run` 驱动） | `tests/` |
| 应用图标生成脚本（leaf.fill + squircle） | `scripts/generate_icon.swift` |
| 稳定自签名证书创建（一次性；TCC 授权跨版本持久） | `scripts/create-signing-cert.sh` |
| 知识索引链接同步校验（CI 文档门禁调用） | `scripts/check_knowledge_map.sh` |
| 一键安装/升级（下载 + 去隔离 + 装配 + 启动） | `install.sh` |
| .app 装配 + 图标生成 + 签名（身份可插拔，`Makefile.local` 本机覆写） | `Makefile` |
| CI 复合 action（setup-macos-swift：Swift 工具链探测 + SwiftPM 分层缓存；verify-version：tag ↔ Info.plist 版本强校验 SSOT） | `.github/actions/` |
| 文档与依赖门禁配置（lychee 链接校验 / markdownlint / dependabot） | `.github/{lychee.toml,markdownlint.json,dependabot.yml}` |
| CI/CD 工作流（测试 / 文档门禁 / 发布） | `.github/workflows/` |
| Archify 架构图库（每图目录 = candidate JSON 图源 SSOT + 交互版 HTML + 双主题嵌入 SVG） | [docs/diagrams/](../docs/diagrams/) |

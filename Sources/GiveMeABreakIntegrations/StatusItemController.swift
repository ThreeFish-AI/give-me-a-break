import AppKit
import GiveMeABreakEngine

/// 菜单栏状态项控制器（AppKit：NSStatusItem 无 SwiftUI 对等物）。
/// 叶子品牌图标（颜色承载状态语义）+ 悬停 Tooltip + 下拉菜单（立即休息 / 屏幕遮罩 / 防止睡眠 / 开机自启 / 退出）。
/// 继承 NSObject 以承载 NSMenuDelegate（menuWillOpen 自愈刷新勾选态）。
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let onForceRest: () -> Void
    private let onEnterScreenMask: () -> Void
    private let onSetLaunchAtLogin: (Bool) -> Void
    private let preventIdleSleepEnabled: () -> Bool
    private let onSetPreventIdleSleep: (Bool) -> Void
    private let onOpenSettings: () -> Void
    private let onOpenWorkLog: () -> Void
    private let onOpenBackfillWorkLog: () -> Void
    private let onOpenCombinedReport: () -> Void
    private let onOpenBackfillExercise: () -> Void
    /// 「防止睡眠」勾选项（menuWillOpen 时刷新勾选态，须持有引用）。
    private var preventSleepItem: NSMenuItem?
    /// 菜单状态行（只读；title 由心跳按秒刷新）。
    private var statusLineItem: NSMenuItem?
    /// 当前已渲染的 phase / 状态文案（缓存去重，心跳每秒调用仅变化时写 UI）。
    private var currentPhase: EnginePhase?
    private var currentStatusText: String?

    init(onForceRest: @escaping () -> Void,
         onEnterScreenMask: @escaping () -> Void,
         loginEnabled: Bool,
         onSetLaunchAtLogin: @escaping (Bool) -> Void,
         preventIdleSleepEnabled: @escaping () -> Bool,
         onSetPreventIdleSleep: @escaping (Bool) -> Void,
         onOpenSettings: @escaping () -> Void,
         onOpenWorkLog: @escaping () -> Void,
         onOpenBackfillWorkLog: @escaping () -> Void,
         onOpenCombinedReport: @escaping () -> Void,
         onOpenBackfillExercise: @escaping () -> Void) {
        self.onForceRest = onForceRest
        self.onEnterScreenMask = onEnterScreenMask
        self.onSetLaunchAtLogin = onSetLaunchAtLogin
        self.preventIdleSleepEnabled = preventIdleSleepEnabled
        self.onSetPreventIdleSleep = onSetPreventIdleSleep
        self.onOpenSettings = onOpenSettings
        self.onOpenWorkLog = onOpenWorkLog
        self.onOpenBackfillWorkLog = onOpenBackfillWorkLog
        self.onOpenCombinedReport = onOpenCombinedReport
        self.onOpenBackfillExercise = onOpenBackfillExercise
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.image = Self.statusBarLeafImage(for: nil)  // 初始灰叶，心跳首秒覆盖
        configureMenu(loginEnabled: loginEnabled)
    }

    private func configureMenu(loginEnabled: Bool) {
        let menu = NSMenu()

        // 标题行：叶子品牌图标（teal、非 template 免疫禁用态灰化）+ 「Give me a break」；禁用态呈标题观感。
        let header = NSMenuItem(title: "Give me a break", action: nil, keyEquivalent: "")
        header.image = Self.leafHeaderImage()
        header.isEnabled = false
        menu.addItem(header)

        // 状态行：当前状态与倒计时（只读、禁用态呈标题观感；title 由心跳按秒刷新）。
        let statusLine = NSMenuItem(title: "启动中…", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        statusLineItem = statusLine

        // 分组（文案统一 2~4 字；「…」尾缀遵循 macOS「打开窗口」约定，不计入字数）：
        //  即时动作 ┃ 查看（报告）┃ 录入（补录）┃ 偏好 ┃ 退出
        menu.addItem(.separator())

        // 即时动作
        let rest = NSMenuItem(title: "立即休息", action: #selector(forceRest), keyEquivalent: "r")
        rest.target = self
        // 全局快捷键（GlobalHotkeyCenter 经 RegisterEventHotKey 注册）真实生效于任意应用前台，
        // 菜单如实展示 ⌃⌥⌘R；裸字母 keyEquivalent 仅在菜单展开时生效，易被误读为全局。
        rest.keyEquivalentModifierMask = [.control, .option, .command]
        rest.image = Self.menuSymbol("moon.zzz", description: "立即休息")
        menu.addItem(rest)

        let screenMask = NSMenuItem(title: "屏幕遮罩", action: #selector(enterScreenMask), keyEquivalent: "k")
        screenMask.target = self
        screenMask.keyEquivalentModifierMask = [.control, .option, .command]
        screenMask.image = Self.menuSymbol("lock.fill", description: "屏幕遮罩")
        menu.addItem(screenMask)

        menu.addItem(.separator())

        // 查看
        let workLog = NSMenuItem(title: "工作日志…", action: #selector(openWorkLog), keyEquivalent: "l")
        workLog.target = self
        workLog.image = Self.menuSymbol("list.bullet.rectangle", description: "工作日志")
        menu.addItem(workLog)

        let combined = NSMenuItem(title: "综合报告…", action: #selector(openCombinedReport), keyEquivalent: "")
        combined.target = self
        combined.image = Self.menuSymbol("chart.bar.doc.horizontal", description: "综合报告")
        menu.addItem(combined)

        menu.addItem(.separator())

        // 录入（补录）
        let backfill = NSMenuItem(title: "补录工作…", action: #selector(openBackfillWorkLog), keyEquivalent: "")
        backfill.target = self
        backfill.image = Self.menuSymbol("square.and.pencil", description: "补录工作")
        menu.addItem(backfill)

        let backfillExercise = NSMenuItem(title: "补录运动…", action: #selector(openBackfillExercise), keyEquivalent: "")
        backfillExercise.target = self
        backfillExercise.image = Self.menuSymbol("figure.run", description: "补录运动")
        menu.addItem(backfillExercise)

        menu.addItem(.separator())

        // 偏好
        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        settings.image = Self.menuSymbol("gearshape", description: "设置")
        menu.addItem(settings)

        // 防止空闲睡眠（IOKit 电源断言，等同 caffeinate -d/-i）：勾选型快捷开关，
        // 防护模式在设置「电源」页配置。cup.and.saucer：caffeinate 的咖啡隐喻，
        // macOS 生态对该功能的惯用符号（且与 App「关于」页品牌角标同源）。
        let preventSleep = NSMenuItem(title: "防止睡眠", action: #selector(togglePreventIdleSleep(_:)), keyEquivalent: "")
        preventSleep.target = self
        preventSleep.image = Self.menuSymbol("cup.and.saucer", description: "防止睡眠")
        preventSleep.state = preventIdleSleepEnabled() ? .on : .off
        preventSleepItem = preventSleep
        menu.addItem(preventSleep)

        let login = NSMenuItem(title: "开机自启", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.image = Self.menuSymbol("power", description: "开机自启")
        login.state = loginEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        // 退出
        let quit = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        quit.image = Self.menuSymbol("xmark.circle", description: "退出")
        menu.addItem(quit)

        menu.delegate = self   // menuWillOpen 自愈刷新「防止睡眠」勾选态
        statusItem.menu = menu
    }

    /// 行首菜单图标（与菜单字体等高，由 NSMenu 自动垂直居中对齐文字）。
    private static func menuSymbol(_ name: String, description: String) -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            .applying(.init(scale: .medium))
        return NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(cfg)
    }

    /// 标题叶子（teal 品牌、非 template，免疫禁用态灰化）。
    private static func leafHeaderImage() -> NSImage? {
        // hierarchical 单色配色 → teal 渲染 SF Symbol；isTemplate=false 使菜单按原色绘制而非模板化灰化。
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            .applying(.init(scale: .medium))
            .applying(.init(hierarchicalColor: .systemTeal))
        let img = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "Give me a break")?
            .withSymbolConfiguration(cfg)
        img?.isTemplate = false
        return img
    }

    /// 更新菜单栏叶子图标（颜色=状态语义）+ 悬停 Tooltip + 菜单状态行文案。
    /// 心跳每秒调用；缓存 phase/文案，仅变化时写 UI，避免无谓刷新。
    func setPhase(_ phase: EnginePhase?, statusText: String) {
        guard let button = statusItem.button else { return }
        if currentPhase != phase {
            currentPhase = phase
            button.image = Self.statusBarLeafImage(for: phase)
        }
        if currentStatusText != statusText {
            currentStatusText = statusText
            button.toolTip = statusText
            statusLineItem?.title = statusText
        }
    }

    /// 状态栏叶子配色：形状统一承载品牌，颜色承载状态语义（深浅菜单栏均可辨）。
    private static func leafColor(for phase: EnginePhase?) -> NSColor {
        switch phase {
        case .working: return .systemTeal                                  // 专注工作（品牌色）
        case .resting: return .systemGreen                                 // 休息恢复
        case .inMeeting: return .systemOrange                              // 会议中（暂停计时）
        case .idle: return .systemGray                                     // 暂停
        case .offDuty: return .systemGray.withAlphaComponent(0.45)         // 非工作时段：淡灰
        case nil: return .systemGray                                       // 引擎未就绪兜底
        }
    }

    /// 状态栏叶子（按 phase 染色、非 template 保留品牌色；14pt 适配菜单栏约 18pt 可用高度）。
    private static func statusBarLeafImage(for phase: EnginePhase?) -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(.init(scale: .medium))
            .applying(.init(hierarchicalColor: leafColor(for: phase)))
        let img = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "Give me a break")?
            .withSymbolConfiguration(cfg)
        img?.isTemplate = false
        return img
    }

    @objc private func forceRest() { onForceRest() }

    @objc private func enterScreenMask() { onEnterScreenMask() }

    @objc private func openSettings() { onOpenSettings() }

    @objc private func openWorkLog() { onOpenWorkLog() }

    @objc private func openBackfillWorkLog() { onOpenBackfillWorkLog() }

    @objc private func openCombinedReport() { onOpenCombinedReport() }

    @objc private func openBackfillExercise() { onOpenBackfillExercise() }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        let newState = sender.state != .on
        onSetLaunchAtLogin(newState)
        sender.state = newState ? .on : .off
    }

    @objc private func togglePreventIdleSleep(_ sender: NSMenuItem) {
        let newState = sender.state != .on
        onSetPreventIdleSleep(newState)
        sender.state = newState ? .on : .off
    }
}

// MARK: - NSMenuDelegate（勾选态自愈）

extension StatusItemController: NSMenuDelegate {
    /// 每次菜单展开前按 provider 闭包刷新勾选态——自愈式：菜单自身 toggle / 设置窗「应用」/
    /// 未来任意 config 变更路径均自动一致，无需逐一通知。
    /// （「开机自启」未纳入同款刷新：SMAppService.status 是系统调用，留作后续独立优化。）
    func menuWillOpen(_ menu: NSMenu) {
        preventSleepItem?.state = preventIdleSleepEnabled() ? .on : .off
    }
}

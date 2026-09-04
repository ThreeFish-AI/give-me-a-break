import AppKit

/// 菜单栏状态项控制器（AppKit：NSStatusItem 无 SwiftUI 对等物）。
/// 状态文案 + 倒计时 + 下拉菜单（立即休息 / 开机自启 / 退出）。
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let onForceRest: () -> Void
    private let onEnterScreenMask: () -> Void
    private let onSetLaunchAtLogin: (Bool) -> Void
    private let onOpenSettings: () -> Void
    private let onOpenWorkLog: () -> Void
    private let onOpenBackfillWorkLog: () -> Void
    private let onOpenCombinedReport: () -> Void
    private let onOpenBackfillExercise: () -> Void

    init(onForceRest: @escaping () -> Void,
         onEnterScreenMask: @escaping () -> Void,
         loginEnabled: Bool,
         onSetLaunchAtLogin: @escaping (Bool) -> Void,
         onOpenSettings: @escaping () -> Void,
         onOpenWorkLog: @escaping () -> Void,
         onOpenBackfillWorkLog: @escaping () -> Void,
         onOpenCombinedReport: @escaping () -> Void,
         onOpenBackfillExercise: @escaping () -> Void) {
        self.onForceRest = onForceRest
        self.onEnterScreenMask = onEnterScreenMask
        self.onSetLaunchAtLogin = onSetLaunchAtLogin
        self.onOpenSettings = onOpenSettings
        self.onOpenWorkLog = onOpenWorkLog
        self.onOpenBackfillWorkLog = onOpenBackfillWorkLog
        self.onOpenCombinedReport = onOpenCombinedReport
        self.onOpenBackfillExercise = onOpenBackfillExercise
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureMenu(loginEnabled: loginEnabled)
    }

    private func configureMenu(loginEnabled: Bool) {
        let menu = NSMenu()

        // 标题行：叶子品牌图标（teal、非 template 免疫禁用态灰化）+ 「Give me a break」；禁用态呈标题观感。
        let header = NSMenuItem(title: "Give me a break", action: nil, keyEquivalent: "")
        header.image = Self.leafHeaderImage()
        header.isEnabled = false
        menu.addItem(header)

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

    /// 更新菜单栏倒计时标题（等宽数字防抖动）。
    func setStatus(text: String) {
        guard let button = statusItem.button else { return }
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
        button.attributedTitle = NSAttributedString(string: text, attributes: [.font: font])
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
}

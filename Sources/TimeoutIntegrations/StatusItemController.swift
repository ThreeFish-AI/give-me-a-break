import AppKit

/// 菜单栏状态项控制器（AppKit：NSStatusItem 无 SwiftUI 对等物）。
/// 状态文案 + 倒计时 + 下拉菜单（立即休息 / 开机自启 / 退出）。
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let onForceRest: () -> Void
    private let onSetLaunchAtLogin: (Bool) -> Void
    private let onOpenSettings: () -> Void

    init(onForceRest: @escaping () -> Void,
         loginEnabled: Bool,
         onSetLaunchAtLogin: @escaping (Bool) -> Void,
         onOpenSettings: @escaping () -> Void) {
        self.onForceRest = onForceRest
        self.onSetLaunchAtLogin = onSetLaunchAtLogin
        self.onOpenSettings = onOpenSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureMenu(loginEnabled: loginEnabled)
    }

    private func configureMenu(loginEnabled: Bool) {
        let menu = NSMenu()

        // 标题行：叶子品牌图标（teal、非 template 免疫禁用态灰化）+ 「Timeout」；禁用态呈标题观感。
        let header = NSMenuItem(title: "Timeout", action: nil, keyEquivalent: "")
        header.image = Self.leafHeaderImage()
        header.isEnabled = false
        menu.addItem(header)

        let rest = NSMenuItem(title: "立即休息", action: #selector(forceRest), keyEquivalent: "r")
        rest.target = self
        rest.image = Self.menuSymbol("moon.zzz", description: "立即休息")
        menu.addItem(rest)

        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        settings.image = Self.menuSymbol("gearshape", description: "设置")
        menu.addItem(settings)

        menu.addItem(.separator())

        let login = NSMenuItem(title: "开机自启", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.image = Self.menuSymbol("power", description: "开机自启")
        login.state = loginEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 Timeout", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        let img = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "Timeout")?
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

    @objc private func openSettings() { onOpenSettings() }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        let newState = sender.state != .on
        onSetLaunchAtLogin(newState)
        sender.state = newState ? .on : .off
    }
}

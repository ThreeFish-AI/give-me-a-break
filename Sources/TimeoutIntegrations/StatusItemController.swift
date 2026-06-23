import AppKit

/// 菜单栏状态项控制器（AppKit：NSStatusItem 无 SwiftUI 对等物）。
/// 图标 + 倒计时标题 + 下拉菜单（立即休息 / 开机自启 / 退出）。
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
        configureButton()
        configureMenu(loginEnabled: loginEnabled)
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let symbol = NSImage(systemSymbolName: "hourglass", accessibilityDescription: "Timeout")?
            .withSymbolConfiguration(config)
        button.image = symbol
        button.image?.isTemplate = true
    }

    private func configureMenu(loginEnabled: Bool) {
        let menu = NSMenu()
        menu.addItem(.sectionHeader(title: "Timeout"))

        let rest = NSMenuItem(title: "立即休息", action: #selector(forceRest), keyEquivalent: "r")
        rest.target = self
        menu.addItem(rest)

        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let login = NSMenuItem(title: "开机自启", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = loginEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 Timeout", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        statusItem.menu = menu
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

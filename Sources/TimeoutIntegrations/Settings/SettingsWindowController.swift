import AppKit
import SwiftUI
import TimeoutEngine

/// 设置窗口控制器：NSWindow + NSHostingController 承载 SwiftUI SettingsView。
/// 每次 show 以当前引擎配置作为初始草稿；应用 → 持久化 + 热更新引擎。
final class SettingsWindowController {
    private var window: NSWindow?
    private let onApply: (DayPlanConfig) -> Void

    init(onApply: @escaping (DayPlanConfig) -> Void) {
        self.onApply = onApply
    }

    func show(currentConfig: DayPlanConfig) {
        let view = SettingsView(
            initial: currentConfig,
            onApply: { [weak self] newConfig in
                self?.onApply(newConfig)
                self?.window?.close()
            },
            onCancel: { [weak self] in self?.window?.close() }
        )

        if window == nil {
            let hosting = NSHostingController(rootView: view)
            let w = NSWindow(contentViewController: hosting)
            w.title = "Timeout 设置"
            w.titlebarAppearsTransparent = false
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            window = w
        } else {
            (window?.contentViewController as? NSHostingController<SettingsView>)?.rootView = view
        }
        window?.center()
        // accessory app 需主动激活 + 强制前置（用户从菜单点击时 app 已激活，此处兜底）
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

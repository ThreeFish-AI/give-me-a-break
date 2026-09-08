import AppKit
import SwiftUI

/// Coding Proxy 控制台窗口控制器（同 WorkLogReportWindowController 范式）：
/// 单例复用 NSWindow + 每次 show 重建 NSHostingController（`@State` 干净初始化）；
/// 尺寸位置经 `setFrameAutosaveName` 跨启动记忆（同 SettingsWindowController），无记录时显式居中。
final class CodingProxyConsoleWindowController {
    private static let frameAutosaveName = "CodingProxyConsoleWindow"

    private var window: NSWindow?
    private let controller: CodingProxyProcessController

    init(controller: CodingProxyProcessController) {
        self.controller = controller
    }

    func show() {
        let view = CodingProxyConsoleView(controller: controller)

        if window == nil {
            let w = NSWindow()
            w.title = "Coding Proxy 控制台"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.contentMinSize = NSSize(width: 680, height: 420)
            w.setContentSize(NSSize(width: 840, height: 540))
            w.isReleasedWhenClosed = false
            // 原生 frame 持久化：有记录 → 恢复用户摆放；无记录 → 显式居中（同 SettingsWindowController）。
            // 注意二者不可叠加——setFrameUsingName 已恢复的 frame 会被无条件居中覆盖。
            _ = w.setFrameAutosaveName(Self.frameAutosaveName)
            if !w.setFrameUsingName(Self.frameAutosaveName) {
                centerOnMainScreenVisibleArea(w)
            }
            window = w
        }
        window?.contentViewController = NSHostingController(rootView: view)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    /// 显式居中到主屏可见区（弃 center()，issue #7：accessory + 多屏下会落到负坐标）。
    private func centerOnMainScreenVisibleArea(_ w: NSWindow) {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        let f = w.frame
        w.setFrameOrigin(NSPoint(x: visible.midX - f.width / 2, y: visible.midY - f.height / 2))
    }
}

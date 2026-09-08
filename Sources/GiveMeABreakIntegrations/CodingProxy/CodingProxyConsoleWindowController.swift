import AppKit
import SwiftUI

/// Coding Proxy 控制台窗口控制器（同 WorkLogReportWindowController 范式）：
/// 单例复用 NSWindow + 每次 show 重建 NSHostingController（`@State` 干净初始化）；
/// 尺寸位置经 `setFrameAutosaveName` 跨启动记忆（同 SettingsWindowController），首开显式居中。
final class CodingProxyConsoleWindowController {
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
            w.setFrameAutosaveName("CodingProxyConsoleWindow")   // 尺寸/位置跨启动记忆
            window = w

            // 首次打开显式居中主屏可见区（issue #7 协议）；其后由 autosave 恢复用户摆放。
            if let screen = NSScreen.main {
                let visible = screen.visibleFrame
                let frame = w.frame
                w.setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2,
                                         y: visible.midY - frame.height / 2))
            }
        }
        window?.contentViewController = NSHostingController(rootView: view)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

import AppKit
import SwiftUI
import GiveMeABreakEngine

/// 工作日志报告窗口控制器：NSWindow + NSHostingController（同 SettingsWindowController 范式）。
/// 单例复用；每次 show 重新读取 store 并按当前 scope 渲染。
final class WorkLogReportWindowController {
    private var window: NSWindow?
    private let store: WorkLogStore

    init(store: WorkLogStore) {
        self.store = store
    }

    func show() {
        // 调试：GIVEMEABREAK_WORKLOG_SCOPE=today|week|month|all 指定初始周期（截图验证用；默认今日）
        let initialScope = ProcessInfo.processInfo.environment["GIVEMEABREAK_WORKLOG_SCOPE"]
            .flatMap { WorkLogReportScope(rawValue: $0) } ?? .today
        let view = WorkLogReportView(store: store, initialScope: initialScope) { [weak self] in
            self?.window?.close()
        }

        // 每次重建 NSHostingController：强制 SwiftUI 新视图树，`@State`（scope/sheet/pendingDelete）干净初始化，
        // 规避 root 身份不变导致的状态残留（同其它控制器）。
        if window == nil {
            let w = NSWindow()
            w.title = "工作日志"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.contentMinSize = NSSize(width: 600, height: 460)
            w.setContentSize(NSSize(width: 720, height: 560))
            w.isReleasedWhenClosed = false
            window = w
        }
        window?.contentViewController = NSHostingController(rootView: view)

        // 显式居中到主屏可见区（弃 center()，issue #7）
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let frame = window?.frame ?? NSRect(x: 0, y: 0, width: 720, height: 560)
            window?.setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2,
                                           y: visible.midY - frame.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

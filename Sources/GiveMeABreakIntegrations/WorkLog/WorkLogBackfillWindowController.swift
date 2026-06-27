import AppKit
import SwiftUI
import GiveMeABreakEngine

/// 补录工作日志窗口控制器：NSWindow + NSHostingController（同 WorkLogPromptWindowController 范式）。
///
/// 用户主动补录漏掉的时段：**无超时**（非紧迫、用户主导）、不触发休息、不冻结心跳。
/// 保存 → `onSave(entry)`（由 AppRoot 落库 `work-log.json`），取消 → 关窗。
final class WorkLogBackfillWindowController {
    private var window: NSWindow?
    private let onSave: (WorkLogEntry) -> Void

    init(onSave: @escaping (WorkLogEntry) -> Void) {
        self.onSave = onSave
    }

    /// 弹出补录窗。`defaultStart`：建议起始（通常为上一条日志的 `endedAt`，或默认 50 分钟前）。
    func show(defaultStart: Date) {
        let view = WorkLogBackfillView(
            defaultStart: defaultStart,
            defaultEnd: Date(),
            onSubmit: { [weak self] entry in
                self?.onSave(entry)
                self?.window?.close()
            },
            onCancel: { [weak self] in self?.window?.close() }
        )

        if window == nil {
            let hosting = NSHostingController(rootView: view)
            let w = NSWindow(contentViewController: hosting)
            w.title = "补录工作日志"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.level = .floating
            w.setContentSize(NSSize(width: 440, height: 420))
            window = w
        } else {
            (window?.contentViewController as? NSHostingController<WorkLogBackfillView>)?.rootView = view
        }

        centerOnMainScreen()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    // MARK: - 显式居中（弃 center()，issue #7：accessory app 多屏下 center() 落离屏负坐标）

    private func centerOnMainScreen() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let frame = window?.frame ?? NSRect(x: 0, y: 0, width: 440, height: 420)
        window?.setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2,
                                       y: visible.midY - frame.height / 2))
    }
}

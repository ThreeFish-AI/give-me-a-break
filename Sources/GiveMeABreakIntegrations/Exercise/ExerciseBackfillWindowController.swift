import AppKit
import SwiftUI
import GiveMeABreakEngine

/// 补录运动记录窗口控制器（镜像 `WorkLogBackfillWindowController` 范式）。
///
/// 用户主动补录漏掉的运动：**无超时**（非紧迫、用户主导）、不触发休息、不冻结心跳。
/// 保存 → `onSave(entry)`（由 AppRoot 落库 `exercise-log.json`），取消 → 关窗。
final class ExerciseBackfillWindowController {
    private var window: NSWindow?
    private let onSave: (ExerciseEntry) -> Void

    init(onSave: @escaping (ExerciseEntry) -> Void) {
        self.onSave = onSave
    }

    /// 弹出补录窗。`defaultStart/defaultEnd`：建议时段（由 AppRoot 按 `[now − restDuration, now]` 计算）。
    /// `exerciseTypes`：Picker 数据源（配置注册表）。
    func show(defaultStart: Date, defaultEnd: Date, exerciseTypes: [String]) {
        let view = ExerciseEntryFormView(
            mode: .create(defaultStart: defaultStart, defaultEnd: defaultEnd),
            types: exerciseTypes,
            onSubmit: { [weak self] entry in
                self?.onSave(entry)
                self?.window?.close()
            },
            onCancel: { [weak self] in self?.window?.close() }
        )

        // 每次重建 NSHostingController：强制 SwiftUI 新视图树，@State（时段/drafts/note）干净初始化，
        // 规避「上次补录内容残留」（root 身份不变导致 @State 不重置）。
        if window == nil {
            let w = NSWindow()
            w.title = "补录运动记录"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.level = .floating
            w.setContentSize(NSSize(width: 460, height: 460))
            window = w
        }
        window?.contentViewController = NSHostingController(rootView: view)

        centerOnMainScreen()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    // MARK: - 显式居中（弃 center()，issue #7）

    private func centerOnMainScreen() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let frame = window?.frame ?? NSRect(x: 0, y: 0, width: 460, height: 460)
        window?.setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2,
                                       y: visible.midY - frame.height / 2))
    }
}

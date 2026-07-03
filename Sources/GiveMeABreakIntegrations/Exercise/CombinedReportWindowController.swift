import AppKit
import SwiftUI
import GiveMeABreakEngine

/// 综合报告窗口控制器：NSWindow + NSHostingController（同 WorkLogReportWindowController 范式）。
/// 单例复用；每次 show 重新读取两个 store 并按当前 scope 渲染。
final class CombinedReportWindowController {
    private var window: NSWindow?
    private let workStore: WorkLogStore
    private let exerciseStore: ExerciseStore
    /// 弹窗时读取最新运动类型注册表（配置可在运行期变，故用 provider 闭包而非快照）。
    private let exerciseTypesProvider: () -> [String]
    private let onSaveExercise: (ExerciseEntry) -> Void
    private let onUpdateExercise: (ExerciseEntry) -> Void

    init(workStore: WorkLogStore,
         exerciseStore: ExerciseStore,
         exerciseTypesProvider: @escaping () -> [String],
         onSaveExercise: @escaping (ExerciseEntry) -> Void,
         onUpdateExercise: @escaping (ExerciseEntry) -> Void) {
        self.workStore = workStore
        self.exerciseStore = exerciseStore
        self.exerciseTypesProvider = exerciseTypesProvider
        self.onSaveExercise = onSaveExercise
        self.onUpdateExercise = onUpdateExercise
    }

    func show() {
        // 调试：GIVEMEABREAK_COMBINED_SCOPE=week|month|quarter|year 指定初始周期（默认本周）
        let initialScope = ProcessInfo.processInfo.environment["GIVEMEABREAK_COMBINED_SCOPE"]
            .flatMap { CombinedReportScope(rawValue: $0) } ?? .week
        let view = CombinedReportView(
            workStore: workStore,
            exerciseStore: exerciseStore,
            exerciseTypes: exerciseTypesProvider(),
            initialScope: initialScope,
            onSaveExercise: onSaveExercise,
            onUpdateExercise: onUpdateExercise,
            onClose: { [weak self] in self?.window?.close() }
        )

        // 每次重建 NSHostingController（非复用 rootView）：强制 SwiftUI 视为新视图树，
        // @State（scope/sheet/pendingDelete）干净初始化，规避 root 身份不变导致的状态残留。
        if window == nil {
            let w = NSWindow()
            w.title = "综合报告"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.contentMinSize = NSSize(width: 620, height: 480)
            w.setContentSize(NSSize(width: 740, height: 580))
            w.isReleasedWhenClosed = false
            window = w
        }
        window?.contentViewController = NSHostingController(rootView: view)

        // 显式居中到主屏可见区（弃 center()，issue #7）
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let frame = window?.frame ?? NSRect(x: 0, y: 0, width: 740, height: 580)
            window?.setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2,
                                           y: visible.midY - frame.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

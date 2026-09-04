import AppKit
import SwiftUI

/// 休息前工作日志提示窗口控制器：NSWindow + NSHostingController（同 SettingsWindowController 范式）。
///
/// 关键：窗口在遮罩**之前**渲染（普通层级 `.floating`），规避 issue #6「对话框被 CGShieldingWindowLevel
/// 遮罩遮挡」陷阱。超时可配置（`config.workLogPromptTimeoutSeconds`）：>0 则到点自动跳过（绝不卡住休息），
/// `0` 则永久等待——不调度定时器，须用户手动操作（提交/跳过/关窗）。计时器为 DispatchSource，独立于被冻结的引擎心跳。
/// 作为 `NSWindowDelegate`：红色关闭按钮（`windowWillClose`）等同「跳过」，保证永久等待下也有安全出口。
final class WorkLogPromptWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    /// 超时计时器（到点自动放行）。永久等待（timeout≤0）时不调度。独立于引擎心跳——心跳此时已 suspend。
    private var timeoutTimer: DispatchSourceTimer?
    /// 占位示例轮换索引（跨会话递增，对抗提示疲劳）。
    private var seedIndex: Int = 0
    /// 防重入：提示进行中不再 present。
    private var presenting = false
    /// 提示窗是否正在展示（AppRoot 据此在系统唤醒时避免抢恢复心跳，防延迟休息被静默判定结束）。
    var isPresenting: Bool { presenting }
    /// 当前轮次回调（present 注入；submit/skip/超时/关窗多路统一经由 finish 触发，回调只跑一次）。
    private var onSubmit: ((String, String?) -> Void)?
    private var onSkip: (() -> Void)?

    override init() { super.init() }

    /// 弹出提示。`onSubmit`/`onSkip` 由 AppRoot 提供：前者落库 + completeDeferredRest，后者直接放行。
    /// 两条路径都必最终进入休息（绝不卡住）。`timeoutSeconds`：>0 自动放行等待秒数，`0` 永久等待。
    func present(workDurationSeconds: TimeInterval,
                 timeoutSeconds: TimeInterval,
                 onSubmit: @escaping (String, String?) -> Void,
                 onSkip: @escaping () -> Void) {
        guard !presenting else { return }
        presenting = true
        self.onSubmit = onSubmit
        self.onSkip = onSkip
        seedIndex = (seedIndex + 1) % 1_000_000  // 单调递增取模，驱动占位轮换

        let view = WorkLogPromptView(
            workDurationSeconds: workDurationSeconds,
            seedIndex: seedIndex,
            onSubmit: { [weak self] summary, nextAction in self?.submit(summary: summary, nextAction: nextAction) },
            onSkip: { [weak self] in self?.skip() }
        )

        // 每次重建 NSHostingController：强制 SwiftUI 视为新视图树，`@State`（summary/nextAction/nextExpanded）
        // 干净初始化。此前在稳定 hosting 上反复赋 `rootView`，SwiftUI 因 root 身份不变而**保留 @State**，
        // 导致「输入文字 → 跳过」后下次弹窗文字仍在（视觉=复用上次记录，用户报告的 bug 根因）。
        if window == nil {
            let w = NSWindow()
            w.title = "记录这段工作"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.level = .floating
            w.delegate = self  // 红色关闭按钮经 windowWillClose 等同「跳过」
            w.setContentSize(NSSize(width: 440, height: 300))
            window = w
        }
        window?.contentViewController = NSHostingController(rootView: view)

        centerOnMainScreen()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        startTimeout(after: timeoutSeconds)
    }

    // MARK: - 提交 / 跳过 / 超时 / 关窗（多路合一，guard presenting 幂等防二次回调）

    private func submit(summary: String, nextAction: String?) {
        guard presenting else { return }
        finish { self.onSubmit?(summary, nextAction) }
    }

    private func skip() {
        guard presenting else { return }
        finish { self.onSkip?() }
    }

    /// 红色关闭按钮 = 跳过（保证永久等待下也有安全出口）。
    /// `finish` 用 `orderOut` 而非 `close`，故提交/跳过/超时三路不会回调本方法，无递归。
    func windowWillClose(_ notification: Notification) {
        skip()
    }

    /// `seconds > 0`：到点自动跳过；`seconds <= 0`：永久等待，不调度定时器。
    private func startTimeout(after seconds: TimeInterval) {
        cancelTimeout()
        guard seconds > 0 else { return }  // 永久等待：无超时
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + seconds)
        timer.setEventHandler { [weak self] in
            // 到点自动跳过：等同用户点「跳过」，确保「绝不卡住休息」。
            self?.skip()
        }
        timer.resume()
        timeoutTimer = timer
    }

    private func cancelTimeout() {
        if let timeoutTimer {
            timeoutTimer.cancel()
            self.timeoutTimer = nil
        }
    }

    /// 统一收尾：取消超时、隐藏窗口、清重入标志，再触发回调（确保回调只跑一次）。
    private func finish(_ action: () -> Void) {
        cancelTimeout()
        window?.orderOut(nil)
        presenting = false
        action()        // 先触发回调（闭包内读 self.onSubmit/onSkip）
        onSubmit = nil  // 再清空，防超时与提交竞争导致二次回调
        onSkip = nil
    }

    // MARK: - 显式居中（弃 center()，issue #7：accessory app 多屏下 center() 落离屏负坐标）

    private func centerOnMainScreen() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let frame = window?.frame ?? NSRect(x: 0, y: 0, width: 440, height: 300)
        window?.setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2,
                                       y: visible.midY - frame.height / 2))
    }
}

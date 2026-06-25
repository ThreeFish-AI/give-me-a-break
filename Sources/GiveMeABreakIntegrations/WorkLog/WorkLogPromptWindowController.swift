import AppKit
import SwiftUI

/// 休息前工作日志提示窗口控制器：NSWindow + NSHostingController（同 SettingsWindowController 范式）。
///
/// 关键：窗口在遮罩**之前**渲染（普通层级 `.floating`），规避 issue #6「对话框被 CGShieldingWindowLevel
/// 遮罩遮挡」陷阱。永不阻塞休息：60s 硬超时自动跳过（DispatchSource 计时器，独立于被冻结的引擎心跳）。
final class WorkLogPromptWindowController {
    private var window: NSWindow?
    /// 超时计时器（60s 自动放行）。独立于引擎心跳——心跳此时已 suspend。
    private var timeoutTimer: DispatchSourceTimer?
    /// 占位示例轮换索引（跨会话递增，对抗提示疲劳）。
    private var seedIndex: Int = 0
    /// 防重入：提示进行中不再 present。
    private var presenting = false
    /// 当前轮次回调（present 注入；submit/skip/超时三路统一经由 finish 触发，回调只跑一次）。
    private var onSubmit: ((String, String?) -> Void)?
    private var onSkip: (() -> Void)?

    /// 弹出提示。`onSubmit`/`onSkip` 由 AppRoot 提供：前者落库 + completeDeferredRest，后者直接放行。
    /// 两条路径都必最终进入休息（绝不卡住）。
    func present(workDurationSeconds: TimeInterval,
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

        if window == nil {
            let hosting = NSHostingController(rootView: view)
            let w = NSWindow(contentViewController: hosting)
            w.title = "记录这段工作"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.level = .floating
            w.setContentSize(NSSize(width: 440, height: 300))
            window = w
        } else {
            (window?.contentViewController as? NSHostingController<WorkLogPromptView>)?.rootView = view
        }

        centerOnMainScreen()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        startTimeout()
    }

    // MARK: - 提交 / 跳过 / 超时（三路合一）

    private func submit(summary: String, nextAction: String?) {
        finish { self.onSubmit?(summary, nextAction) }
    }

    private func skip() {
        finish { self.onSkip?() }
    }

    private func startTimeout() {
        cancelTimeout()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 60)
        timer.setEventHandler { [weak self] in
            // 60s 自动跳过：等同用户点「跳过」，确保「绝不卡住休息」。
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

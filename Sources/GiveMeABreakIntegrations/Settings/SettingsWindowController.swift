import AppKit
import SwiftUI
import GiveMeABreakEngine

/// 设置窗口控制器：NSWindow + NSHostingController 承载 SwiftUI SettingsView。
/// 每次 show 以当前引擎配置作为初始草稿；应用 → 持久化 + 热更新引擎。
///
/// 尺寸策略：窗口尺寸完全由当前页签内容驱动（`sizingOptions = .preferredContentSize`），
/// 切换页签 / 增删工作时段 / 展开工作日志项时自适应高度——既无垂直滚动条，也无多余留白。
/// 首次显示完整居中到主屏可见区；其后伸缩时顶边锚定（向下生长）+ 保持水平中心，并限制在屏内。
final class SettingsWindowController {
    private var window: NSWindow?
    private var sizeObservation: NSKeyValueObservation?
    private var moveObserver: NSObjectProtocol?
    /// 锚点：上次定位后的顶边 Y 与水平中心 X，供内容伸缩时参照（保持顶边/中心稳定）。
    private var anchorTopY: CGFloat?
    private var anchorCenterX: CGFloat?
    /// 自调整窗口期间置位，避免我方 setFrame 触发的 didMove 把锚点覆写成中间态。
    private var isAdjustingFrame = false
    private let onApply: (DayPlanConfig) -> Void
    private let onToggleLogin: (Bool) -> Void

    init(onApply: @escaping (DayPlanConfig) -> Void,
         onToggleLogin: @escaping (Bool) -> Void) {
        self.onApply = onApply
        self.onToggleLogin = onToggleLogin
    }

    func show(currentConfig: DayPlanConfig, loginEnabled: Bool) {
        let view = SettingsView(
            initial: currentConfig,
            loginEnabled: loginEnabled,
            onApply: { [weak self] newConfig in
                self?.onApply(newConfig)
                self?.window?.close()
            },
            onCancel: { [weak self] in self?.window?.close() },
            onToggleLogin: { [weak self] v in self?.onToggleLogin(v) }
        )

        if window == nil {
            let hosting = NSHostingController(rootView: view)
            // 让控制器按 SwiftUI 内容理想尺寸更新 preferredContentSize；窗口据此自适应。
            hosting.sizingOptions = [.preferredContentSize]
            let w = NSWindow(contentViewController: hosting)
            w.title = "Give me a break 设置"
            w.titlebarAppearsTransparent = false
            // 固定窗口（无 .resizable）：尺寸由内容裁决，无需用户手动调节，避免人为留白/滚动。
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            window = w

            // 内容理想尺寸变化 → 异步重排，确保我方为最终裁决者（覆盖系统隐式跟随）。
            sizeObservation = hosting.observe(\.preferredContentSize, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.layoutWindowToContent(initialCenter: false) }
            }
            // 用户手动移动窗口后更新锚点，使后续伸缩沿用新位置。
            moveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: w, queue: .main
            ) { [weak self] _ in
                guard let self, !self.isAdjustingFrame, let f = self.window?.frame else { return }
                self.anchorTopY = f.maxY
                self.anchorCenterX = f.midX
            }
        } else {
            // 窗口复用：刷新 view（同步最新登录态）；重开视为重新居中。
            (window?.contentViewController as? NSHostingController<SettingsView>)?.rootView = view
        }

        // accessory app 需主动激活 + 强制前置（用户从菜单点击时 app 已激活，此处兜底）。
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        layoutWindowToContent(initialCenter: true)
        window?.orderFrontRegardless()
    }

    /// 依内容理想尺寸调整窗口尺寸与位置。
    /// - initialCenter: true 时完整居中到主屏可见区（含垂直）；false 时顶边锚定 + 保持水平中心。
    private func layoutWindowToContent(initialCenter: Bool) {
        guard let window, let hosting = window.contentViewController else { return }

        // preferredContentSize 尚未就绪（布局前为 0）时回退 fittingSize，避免零尺寸。
        var content = hosting.preferredContentSize
        if content.width < 1 || content.height < 1 { content = hosting.view.fittingSize }
        guard content.width >= 1, content.height >= 1 else { return }

        let visible = (window.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // 由内容尺寸推算外框；超出可见区时收口（仅极端情况下 Form 内部才滚动）。
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content))
        frame.size.width = min(frame.size.width, visible.width)
        frame.size.height = min(frame.size.height, visible.height)

        if initialCenter || anchorTopY == nil || anchorCenterX == nil {
            frame.origin.x = visible.midX - frame.width / 2
            frame.origin.y = visible.midY - frame.height / 2   // 首次完整居中
        } else {
            frame.origin.x = anchorCenterX! - frame.width / 2   // 保持水平中心
            frame.origin.y = anchorTopY! - frame.height         // 顶边锚定：向下生长
        }
        // 限制在可见区内，避免越界离屏（issue #7：accessory + 多屏下 center() 会落到负坐标）。
        frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)

        isAdjustingFrame = true
        window.setFrame(frame, display: true, animate: false)
        isAdjustingFrame = false

        anchorTopY = frame.maxY
        anchorCenterX = frame.midX
    }

    deinit {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
    }
}

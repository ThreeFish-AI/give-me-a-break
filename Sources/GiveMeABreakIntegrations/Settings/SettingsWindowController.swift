import AppKit
import SwiftUI
import GiveMeABreakEngine

/// 设置窗口控制器：NSWindow + NSHostingController 承载 SwiftUI SettingsView。
/// 每次 show 以当前引擎配置作为初始草稿；应用 → 持久化 + 热更新引擎。
final class SettingsWindowController {
    private var window: NSWindow?
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
            let w = NSWindow(contentViewController: hosting)
            w.title = "Give me a break 设置"
            w.titlebarAppearsTransparent = false
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]  // 允许用户调整窗口大小
            w.contentMinSize = NSSize(width: 500, height: 420)                // 约束最小尺寸，避免拉得太小
            // 初始尺寸：页签化后每页内容更短；尽量一次显示当前页签的全部 Section，免首次需滚动。
            // NSHostingController 默认用 fittingSize（≈min），idealHeight 不生效，故显式设定。
            w.setContentSize(NSSize(width: 560, height: 600))
            w.isReleasedWhenClosed = false
            window = w
        } else {
            // 窗口复用：每次刷新 view，同步最新登录态（用户可能在系统设置改过登录项）
            (window?.contentViewController as? NSHostingController<SettingsView>)?.rootView = view
        }
        // accessory app 需主动激活 + 强制前置（用户从菜单点击时 app 已激活，此处兜底）
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        // 显式居中到主屏可见区：center() 在 accessory（无 key window）+ 多屏配置下
        // 会把窗口落到离屏负坐标（实测 X/Y 为大负数），导致窗口不可见。先 order front 确定 frame 再定位。
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let frame = window?.frame ?? NSRect(x: 0, y: 0, width: 480, height: 460)
            window?.setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2,
                                           y: visible.midY - frame.height / 2))
        }
        window?.orderFrontRegardless()
    }
}

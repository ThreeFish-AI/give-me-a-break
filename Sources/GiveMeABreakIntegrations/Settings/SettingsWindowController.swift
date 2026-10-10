import AppKit
import SwiftUI
import GiveMeABreakEngine

/// 设置窗口控制器：NSWindow + NSHostingView 承载 SwiftUI SettingsView。
/// 每次 show 以当前引擎配置作为初始草稿；应用 → 持久化 + 热更新引擎。
///
/// 尺寸策略：窗口尺寸归用户所有（.resizable + contentMinSize 锁「页签条自然宽度 ∨ 表单可读性」
/// 下限，该下限运行期按页签文案测算，见 SettingsView 的 SettingsTabMetrics）；位置/尺寸经 setFrameAutosaveName
/// 原生持久化，首次显示走默认尺寸 + 显式居中主屏可见区（issue #7：弃 center()）。内容不再反向
/// 驱动窗口——页签内容高于窗口时由 Form（grouped 即 ScrollView）内部滚动，与系统设置窗行为一致。
/// 故用 NSHostingView（contentView，视图适配窗口）而非 NSHostingController（contentViewController，
/// 窗口会跟随内容 resize，与「用户拥有尺寸」冲突）；每次 show 新建 hosting 视图保证 @State
/// 干净初始化（issue #9）。
final class SettingsWindowController {
    private var window: NSWindow?
    private let onApply: (DayPlanConfig) -> Void
    private let onToggleLogin: (Bool) -> Void
    private let onTogglePreventIdleSleep: (Bool) -> Void
    /// 尺寸/位置持久化键（AppKit 落 "NSWindow Frame <name>"，随移动/缩放自动保存）。
    private static let frameAutosaveName = "GiveMeABreakSettingsWindow"

    init(onApply: @escaping (DayPlanConfig) -> Void,
         onToggleLogin: @escaping (Bool) -> Void,
         onTogglePreventIdleSleep: @escaping (Bool) -> Void) {
        self.onApply = onApply
        self.onToggleLogin = onToggleLogin
        self.onTogglePreventIdleSleep = onTogglePreventIdleSleep
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
            onToggleLogin: { [weak self] v in self?.onToggleLogin(v) },
            onTogglePreventIdleSleep: { [weak self] v in self?.onTogglePreventIdleSleep(v) }
        )
        // 每次新建 NSHostingView（非复用 rootView）：强制 SwiftUI 视为新视图树，@State（draft）
        // 干净初始化为当前 config（issue #9）。sizingOptions 置空：视图不向窗口施加任何尺寸约束。
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []

        if window == nil {
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: SettingsView.defaultContentSize),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "Give me a break 设置"
            w.titlebarAppearsTransparent = false
            // contentRect 含标题栏，此行校准为纯内容尺寸；下限锁住「页签平铺」最小宽度
            // （须先于 autosave 恢复就位：恢复帧受 min/max 收口）。
            w.setContentSize(SettingsView.defaultContentSize)
            w.contentMinSize = NSSize(width: SettingsView.minimumContentWidth,
                                      height: SettingsView.minimumContentHeight)
            w.isReleasedWhenClosed = false
            w.contentView = hosting
            // 原生 frame 持久化：有记录 → 恢复（min 已收口尺寸）+ 离屏兜底；无记录 → 显式居中。
            _ = w.setFrameAutosaveName(Self.frameAutosaveName)   // 返回 Bool 仅表示名字可用/未占用
            if w.setFrameUsingName(Self.frameAutosaveName) {     // 返回 true = 读到持久化 frame
                clampToVisibleScreen(w)
            } else {
                centerOnMainScreenVisibleArea(w)
            }
            window = w
        } else {
            window?.contentView = hosting                        // 只换内容视图，不动 frame
        }

        // accessory app 需主动激活 + 强制前置（用户从菜单点击时 app 已激活，此处兜底）。
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    /// 屏内收口：旧持久化尺寸可能小于新 contentMinSize（版本升级抬高下限时），先补足再压回可见区。
    /// constrainFrameRect 仅约束顶边/高度、不修水平位置，故水平离屏须我方处理（issue #7）。
    private func clampToVisibleScreen(_ w: NSWindow) {
        let cw = w.contentView?.bounds.width ?? 0, ch = w.contentView?.bounds.height ?? 0
        if cw < w.contentMinSize.width || ch < w.contentMinSize.height {
            w.setContentSize(NSSize(width: max(w.contentMinSize.width, cw),
                                    height: max(w.contentMinSize.height, ch)))
        }
        guard let visible = (w.screen ?? NSScreen.main)?.visibleFrame else { return }
        let f = w.frame
        w.setFrameOrigin(NSPoint(
            x: min(max(f.minX, visible.minX), visible.maxX - f.width),
            y: min(max(f.minY, visible.minY), visible.maxY - f.height)))
    }

    /// 显式居中到主屏可见区（弃 center()，issue #7：accessory + 多屏下会落到负坐标）。
    private func centerOnMainScreenVisibleArea(_ w: NSWindow) {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        let f = w.frame
        w.setFrameOrigin(NSPoint(x: visible.midX - f.width / 2, y: visible.midY - f.height / 2))
    }
}

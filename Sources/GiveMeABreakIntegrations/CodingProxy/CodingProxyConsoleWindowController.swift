import AppKit
import SwiftUI

/// Coding Proxy 控制台窗口控制器（同 SettingsWindowController 范式）：
/// 单例复用 NSWindow + 每次 show 新建 NSHostingView（`@State` 干净初始化，issue #9）；
/// `sizingOptions = []` 切断 SwiftUI 内容对窗口的尺寸反压——NSHostingController 赋
/// contentViewController 会使窗口收缩到内容 fitting size，用户尺寸每次被吞且 autosave
/// 反持久化缩水帧（issue #14）；尺寸位置经 `setFrameAutosaveName` 跨启动记忆，
/// 无记录时显式居中，有记录时恢复 + 屏内收口（多屏/拔屏兜底，issue #7）。
final class CodingProxyConsoleWindowController {
    /// v0.1.10 的 contentViewController 缺陷已把缩水 frame 写满旧键 "CodingProxyConsoleWindow"
    /// （每次 show 必写坏值，存量记录无幸存好值），一次性弃用换键（issue #14）。
    private static let frameAutosaveName = "CodingProxyConsoleWindow-v2"

    private var window: NSWindow?
    private let controller: CodingProxyProcessController

    init(controller: CodingProxyProcessController) {
        self.controller = controller
    }

    func show() {
        let view = CodingProxyConsoleView(controller: controller)
        // 每次新建 NSHostingView（非复用 rootView）：强制 SwiftUI 视为新视图树，@State（lines/autoScroll）
        // 干净初始化（issue #9）；onAppear 重拉快照重订阅、旧树拆除退订，日志订阅语义不变。
        // sizingOptions 置空：视图不向窗口施加任何尺寸约束，窗口尺寸归用户所有（issue #14）。
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []

        if window == nil {
            let w = NSWindow()
            w.title = "Coding Proxy 控制台"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.contentMinSize = NSSize(width: 680, height: 420)
            w.setContentSize(NSSize(width: 840, height: 540))
            w.isReleasedWhenClosed = false
            w.contentView = hosting
            // 原生 frame 持久化：有记录 → 恢复用户摆放 + 屏内收口；无记录 → 显式居中（同 SettingsWindowController）。
            // 注意二者不可叠加——setFrameUsingName 已恢复的 frame 会被无条件居中覆盖（issue #12(a)）。
            _ = w.setFrameAutosaveName(Self.frameAutosaveName)
            if w.setFrameUsingName(Self.frameAutosaveName) {
                clampToVisibleScreen(w)
            } else {
                centerOnMainScreenVisibleArea(w)
            }
            window = w
        } else {
            window?.contentView = hosting   // 复用窗口只换内容视图，不动 frame（用户尺寸幸存）
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    /// 屏内收口：旧持久化尺寸可能小于 contentMinSize 或落在已拔掉的屏幕上，先补足再压回可见区
    /// （constrainFrameRect 仅约束顶边/高度、不修水平位置，故水平离屏须我方处理，issue #7）。
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

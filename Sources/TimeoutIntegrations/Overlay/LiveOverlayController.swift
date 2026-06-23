import AppKit
import SwiftUI
import TimeoutEngine

/// 全屏遮罩控制器：为每个 NSScreen 创建一个 borderless NSPanel，置于 CGShieldingWindowLevel
/// （压过菜单栏/Dock/全屏/系统屏保），collectionBehavior 覆盖全 Space。软强制：Esc → NSAlert 二次确认。
final class LiveOverlayController: OverlayController {
    var onRequestEarlyExit: (() -> Void)?

    private var panels: [OverlayPanel] = []
    private var escMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var currentDeadline: Date?
    private var alertShowing = false

    var isShown: Bool { !panels.isEmpty }

    func show(restDeadline: Date) {
        guard panels.isEmpty else { return }  // 幂等
        currentDeadline = restDeadline
        for screen in NSScreen.screens {
            panels.append(makePanel(screen: screen, deadline: restDeadline))
        }
        installEscMonitor()
        observeScreens(deadline: restDeadline)
        NSApp.activate(ignoringOtherApps: true)
        NSLog("[Timeout][overlay] show：\(panels.count) 屏，deadline=\(restDeadline)")
    }

    func dismiss() {
        guard !panels.isEmpty else { return }  // 幂等
        removeEscMonitor()
        removeScreenObserver()
        for panel in panels {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                panel.animator().alphaValue = 0
            } completionHandler: { [weak panel] in
                panel?.orderOut(nil)
            }
        }
        panels.removeAll()
        currentDeadline = nil
        NSLog("[Timeout][overlay] dismiss")
    }

    // MARK: - Panel 构造

    private func makePanel(screen: NSScreen, deadline: Date) -> OverlayPanel {
        let panel = OverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications]

        let hosting = NSHostingView(rootView: OverlayContentView(deadline: deadline))
        panel.contentView = hosting
        panel.setFrame(screen.frame, display: true)  // 显式 setFrame（macOS 15 已知零 frame 回退）
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            panel.animator().alphaValue = 1
        }
        return panel
    }

    // MARK: - Esc 软强制（本地事件监听 → NSAlert 二次确认）

    private func installEscMonitor() {
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else { return event }  // 53 = Esc
            self.promptEarlyExit()
            return nil  // 消费该事件
        }
    }

    private func removeEscMonitor() {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        escMonitor = nil
    }

    private func promptEarlyExit() {
        guard !alertShowing else { return }
        alertShowing = true
        let alert = NSAlert()
        alert.messageText = "提前结束休息？"
        alert.informativeText = "休息尚未到时。提前结束将重置计时器，从零开始累计工作。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "继续休息")
        alert.addButton(withTitle: "提前结束")
        let response = alert.runModal()
        alertShowing = false
        if response == .alertSecondButtonReturn {
            onRequestEarlyExit?()
        }
    }

    // MARK: - 屏幕热插拔

    private func observeScreens(deadline: Date) {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.isShown else { return }
            self.rebuildPanels(deadline: deadline)
        }
    }

    private func rebuildPanels(deadline: Date) {
        for p in panels { p.orderOut(nil) }
        panels.removeAll()
        for screen in NSScreen.screens {
            panels.append(makePanel(screen: screen, deadline: deadline))
        }
        NSLog("[Timeout][overlay] 屏幕变化，重建 \(panels.count) 屏")
    }

    private func removeScreenObserver() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }
}

/// borderless 面板子类：可成为 key 以接收键盘（Esc 经本地监听捕获，双保险）。
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

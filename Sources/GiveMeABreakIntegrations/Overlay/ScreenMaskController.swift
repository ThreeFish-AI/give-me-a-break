import AppKit
import SwiftUI

/// 手动屏幕遮罩控制器：与 LiveOverlayController 结构对称（多屏 CGShieldingWindowLevel 面板 +
/// 双击 Esc），但与调度引擎（FSM）零耦合——不读写 EngineState、不触发任何休息相关副作用。
/// 故退出逻辑无需像 LiveOverlayController 那样经回调桥接到引擎，dismiss() 由本类直接调用。
/// 复用 LiveOverlayController.swift 内定义的 OverlayPanel（NSPanel 子类，internal 可跨文件访问）。
final class ScreenMaskController {
    private var panels: [OverlayPanel] = []
    private var escMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var lastEscAt: Date?  // 双击 Esc 检测：上次 Esc 时刻（0.4s 窗口，同休息遮罩）

    var isShown: Bool { !panels.isEmpty }

    func show() {
        guard panels.isEmpty else { return }  // 幂等
        for screen in NSScreen.screens {
            panels.append(makePanel(screen: screen))
        }
        installEscMonitor()
        observeScreens()
        NSApp.activate(ignoringOtherApps: true)
        NSLog("[GiveMeABreak][screenMask] show：\(panels.count) 屏")
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
        lastEscAt = nil  // 干净初始态，防下次 show 残留双击计时
        NSLog("[GiveMeABreak][screenMask] dismiss")
    }

    // MARK: - Panel 构造

    private func makePanel(screen: NSScreen) -> OverlayPanel {
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

        let hosting = NSHostingView(rootView: ScreenMaskContentView())
        panel.contentView = hosting
        panel.setFrame(screen.frame, display: true)  // 显式 setFrame（macOS 15 已知零 frame 回退）
        panel.alphaValue = 0
        if panels.isEmpty {
            panel.makeKeyAndOrderFront(nil)  // 主屏：成为 key，使本地 Esc 监听可靠接收
        } else {
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            panel.animator().alphaValue = 1
        }
        return panel
    }

    // MARK: - 双击 Esc 退出（无单击确认态：手动遮罩无「提前退出有代价」语义，双击只为防误触）

    private func installEscMonitor() {
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else { return event }  // 53 = Esc
            let now = Date()
            if let last = self.lastEscAt, now.timeIntervalSince(last) < 0.4 {
                self.lastEscAt = nil  // 消费，防三连击的第三次被当作新一轮首击
                self.dismiss()
            } else {
                self.lastEscAt = now
            }
            return nil  // 消费该事件
        }
    }

    private func removeEscMonitor() {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        escMonitor = nil
    }

    // MARK: - 屏幕热插拔

    private func observeScreens() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.isShown else { return }
            self.rebuildPanels()
        }
    }

    private func rebuildPanels() {
        for p in panels { p.orderOut(nil) }
        panels.removeAll()
        for screen in NSScreen.screens {
            panels.append(makePanel(screen: screen))
        }
        NSLog("[GiveMeABreak][screenMask] 屏幕变化，重建 \(panels.count) 屏")
    }

    private func removeScreenObserver() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }
}

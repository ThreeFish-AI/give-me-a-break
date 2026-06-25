import AppKit
import SwiftUI
import GiveMeABreakEngine

/// 全屏遮罩控制器：为每个 NSScreen 创建一个 borderless NSPanel，置于 CGShieldingWindowLevel
/// （压过菜单栏/Dock/全屏/系统屏保），collectionBehavior 覆盖全 Space。软强制：Esc → 遮罩内嵌确认视图。
///
/// 关键设计：确认 UI（继续休息 / 直接退出）直接渲染在遮罩面板内部（与遮罩同层级），
/// 而非 NSAlert 模态窗——后者默认 level=NSModalPanelWindowLevel 远低于遮罩，
/// 对话框会渲染在遮罩之下不可见，导致 Esc 退出永远失效。
final class LiveOverlayController: OverlayController {
    var onRequestEarlyExit: (() -> Void)?

    private var panels: [OverlayPanel] = []
    private var escMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var currentDeadline: Date?
    private var lastEscAt: Date?  // 双击 Esc 直退检测：上次 Esc 时刻
    private var viewModel: OverlayViewModel?  // 确认态共享源（取代原 alertShowing）

    var isShown: Bool { !panels.isEmpty }

    func show(restDeadline: Date) {
        guard panels.isEmpty else { return }  // 幂等
        currentDeadline = restDeadline
        // 入口创建新 vm（dismiss 时置 nil，故此处恒为干净实例，无需判空复用）
        viewModel = OverlayViewModel(deadline: restDeadline) { [weak self] in
            self?.confirmEarlyExit()
        }
        for screen in NSScreen.screens {
            panels.append(makePanel(screen: screen))
        }
        installEscMonitor()
        observeScreens()
        NSApp.activate(ignoringOtherApps: true)
        NSLog("[GiveMeABreak][overlay] show：\(panels.count) 屏，deadline=\(restDeadline)")
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
        lastEscAt = nil  // 干净初始态，防下次 show 残留双击计时
        viewModel?.isConfirming = false
        viewModel = nil  // 干净初始态，防下次 show 残留确认态
        NSLog("[GiveMeABreak][overlay] dismiss")
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

        // resting 期间 viewModel 必非 nil（show 创建、dismiss 才置 nil）；多屏共享同一实例
        let hosting = NSHostingView(rootView: OverlayContentView(viewModel: viewModel!))
        panel.contentView = hosting
        panel.setFrame(screen.frame, display: true)  // 显式 setFrame（macOS 15 已知零 frame 回退）
        panel.alphaValue = 0
        if panels.isEmpty {
            panel.makeKeyAndOrderFront(nil)  // 主屏：成为 key，使 SwiftUI Button 可接收点击 / 回车
        } else {
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            panel.animator().alphaValue = 1
        }
        return panel
    }

    // MARK: - Esc 软强制（本地事件监听 → 遮罩内嵌确认双语义）

    private func installEscMonitor() {
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else { return event }  // 53 = Esc
            let now = Date()
            if let last = self.lastEscAt, now.timeIntervalSince(last) < 0.4 {
                // 双击 Esc → 直接退出休息（复用「直接退出」按钮同款安全退出路径）
                self.lastEscAt = nil  // 消费，防三连击的第三次被当作新一轮首击
                self.confirmEarlyExit()
            } else {
                // 单击 Esc = 进入/取消确认（保留既有语义）
                self.lastEscAt = now
                self.viewModel?.isConfirming.toggle()
            }
            return nil  // 消费该事件
        }
    }

    private func removeEscMonitor() {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        escMonitor = nil
    }

    /// 用户在确认视图中点击「直接退出」。
    private func confirmEarlyExit() {
        viewModel?.isConfirming = false
        onRequestEarlyExit?()
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
        NSLog("[GiveMeABreak][overlay] 屏幕变化，重建 \(panels.count) 屏")
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

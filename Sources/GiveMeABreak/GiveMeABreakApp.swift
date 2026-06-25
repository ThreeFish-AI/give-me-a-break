import AppKit
import GiveMeABreakIntegrations

/// 应用生命周期委托（薄层：仅装配 + accessory 策略钉死）。
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppRoot.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppRoot.shared.shutdown()
        NSLog("[GiveMeABreak] 即将退出")
    }
}

/// 进程入口（@main）。纯 AppKit 启动，避免 SwiftUI App 强制 Scene 的尴尬；
/// SwiftUI 仅用于后续遮罩内容与设置窗（NSHostingView 注入）。
@main
enum GiveMeABreakApp {
    /// 强引用持有 delegate（NSApplication.delegate 为 weak）。
    private static let appDelegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = appDelegate
        // 运行时二次钉死 accessory 策略，防交互时 Dock 图标复现。
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

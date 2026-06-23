import ApplicationServices

/// Accessibility（辅助功能）权限：CGEvent 媒体键合成所必需。
/// 首次 bootstrap 时若未授权，弹出系统授权引导窗（仅一次）。
/// Agent 不得绕过——授权由用户在系统设置中手动完成。
enum AccessibilityChecker {
    static func bootstrap() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        NSLog("[Timeout] Accessibility 受信状态：\(trusted)（媒体键控制 QQ 音乐需此项）")
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }
}

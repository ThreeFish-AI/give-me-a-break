import AppKit
import CoreGraphics
import TimeoutEngine

/// QQ 音乐控制器：经系统 Now Playing 路由，用 CGEvent 合成媒体键控制播放/暂停。
/// 关键事实（二进制验证）：QQ 音乐不可 AppleScript 脚本化，但注册为 Now Playing 应用，
/// 故 NX_KEYTYPE_PLAY 媒体键会被 OS 路由到它。
final class LiveMusicController: MusicController {
    private let qqMusicBundleId = "com.tencent.QQMusicMac"
    private let qqMusicAppURL = URL(fileURLWithPath: "/Applications/QQMusic.app")

    func startPlayback() {
        guard AccessibilityChecker.isTrusted else {
            NSLog("[Timeout][music] Accessibility 未授权，媒体键将无效；请在系统设置授权后重试")
            launchQQMusicIfNeeded()
            return
        }
        launchQQMusicIfNeeded()
        // 启动后稍候再发媒体键，确保 QQ 音乐已注册为 Now Playing。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.postMediaKey(16)  // NX_KEYTYPE_PLAY toggle → 播放
            NSLog("[Timeout][music] 发送 play 媒体键")
        }
    }

    func pausePlayback() {
        postMediaKey(16)  // NX_KEYTYPE_PLAY toggle → 暂停（保留队列/进度）
        NSLog("[Timeout][music] 发送 pause 媒体键（toggle，保留队列）")
    }

    // MARK: - 启动 QQ 音乐

    private func launchQQMusicIfNeeded() {
        let running = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == qqMusicBundleId }
        guard !running else { return }
        guard FileManager.default.fileExists(atPath: qqMusicAppURL.path) else {
            NSLog("[Timeout][music] 未找到 /Applications/QQMusic.app，跳过启动")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: qqMusicAppURL, configuration: config) { _, error in
            if let error { NSLog("[Timeout][music] 启动 QQ 音乐失败：\(error.localizedDescription)") }
            else { NSLog("[Timeout][music] 已拉起 QQ 音乐") }
        }
    }

    // MARK: - CGEvent 媒体键合成

    /// 构造 systemDefined 媒体键事件（subtype=8 NX_SUBTYPE_AUX_CONTROL_BUTTONS，data1 编码 keyType + down/up）。
    private func postMediaKey(_ keyCode: Int32) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        for down in [true, false] {
            let mouseType: CGEventType = down ? .otherMouseDown : .otherMouseUp
            guard let event = CGEvent(mouseEventSource: source, mouseType: mouseType,
                                      mouseCursorPosition: .zero, mouseButton: .center) else { continue }
            event.setIntegerValueField(.mouseEventSubtype, value: 8)  // NX_SUBTYPE_AUX_CONTROL_BUTTONS
            let flags: Int64 = down ? (0x0A << 8) : (0x0B << 8)
            let data1 = (Int64(keyCode) << 16) | flags
            event.setIntegerValueField(.eventSourceUserData, value: data1)
            event.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }
}

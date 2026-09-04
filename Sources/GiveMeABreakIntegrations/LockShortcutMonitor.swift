import AppKit
import CoreGraphics

/// 占用系统锁屏快捷键（默认 Control+Command+Q）：`CGEventTap` 在 HID 层拦截，命中即消费（系统不再
/// 真正锁屏），转投 `onTriggered`（由 AppRoot 接线至手动屏幕遮罩）。与 AccessibilityChecker 的权限
/// 模型正交——那里管的是*发送*合成事件（媒体键），这里需要的是*监听*系统级按键的「输入监控」权限。
///
/// 已知边界（macOS 系统行为，非本实现缺陷，详见 docs/give-me-a-break-design.md §8）：
/// Secure Input 生效时全机 CGEventTap 静默失效；输入监控权限变更需重启 App 才生效。
final class LockShortcutMonitor {
    var onTriggered: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // MARK: - 目标组合键判定（纯函数，零副作用）
    //
    // 全案唯一「判错即灾难」的代码：误判为 true 会让下方回调吞掉不该吞的按键，
    // 导致全系统键盘输入瞬间失灵（键盘已死时唯一恢复手段是强制重启进程）。
    // 保持极简、与下方 @convention(c) 胶水代码物理隔离，便于 review。
    //
    // CGEventFlags 无 NSEvent.ModifierFlags 那样现成的 deviceIndependentFlagsMask，
    // 故显式声明关心的修饰键位掩码：要求恰好 Control+Command（Shift/Option/CapsLock/Fn 均不可按下），
    // 忽略 .maskNonCoalesced/.maskNumericPad 等与修饰键无关的硬件杂位。
    private static let relevantModifierMask: CGEventFlags = [
        .maskShift, .maskControl, .maskAlternate, .maskCommand, .maskAlphaShift, .maskSecondaryFn,
    ]

    static func isLockScreenChord(keyCode: Int64, flags: CGEventFlags) -> Bool {
        keyCode == 12 && flags.intersection(relevantModifierMask) == [.maskControl, .maskCommand]  // 12 = Q
    }

    func start() {
        if ProcessInfo.processInfo.environment["GIVEMEABREAK_DISABLE_LOCK_HIJACK"] != nil {
            NSLog("[GiveMeABreak][lockShortcut] 已由环境变量禁用（开发期/应急短路）")
            return
        }
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()  // 触发系统一次性「输入监控」授权弹窗
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)  // 严格只订阅 keyDown
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,  // ⚠️ 必须 defaultTap；.listenOnly 只能观察无法拦截，会让功能静默失效
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let refcon {
                        let monitor = Unmanaged<LockShortcutMonitor>.fromOpaque(refcon).takeUnretainedValue()
                        if let tap = monitor.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    }
                    return Unmanaged.passUnretained(event)
                }
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                if LockShortcutMonitor.isLockScreenChord(keyCode: keyCode, flags: event.flags) {
                    let monitor = Unmanaged<LockShortcutMonitor>.fromOpaque(refcon).takeUnretainedValue()
                    DispatchQueue.main.async { monitor.onTriggered?() }  // 回调保持轻量，防 tapDisabledByTimeout
                    return nil  // 消费：系统不再处理，不会真正锁屏
                }
                return Unmanaged.passUnretained(event)  // 未命中：原样放行，绝不吞掉其他按键
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("[GiveMeABreak][lockShortcut] CGEventTap 创建失败（输入监控未授权？），回退：仅菜单「屏幕遮罩」可用")
            return
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)  // commonModes：菜单 tracking/模态循环期间也生效
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[GiveMeABreak][lockShortcut] 已接管系统锁屏快捷键 Control+Command+Q")
    }

    /// 唤醒/健康检查钩子：tap 若因罕见原因被系统静默禁用，尝试重新启用。
    func recheckHealth() {
        guard let tap = eventTap, !CGEvent.tapIsEnabled(tap: tap) else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[GiveMeABreak][lockShortcut] 健康检查：已重新启用被禁用的 tap")
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }
}

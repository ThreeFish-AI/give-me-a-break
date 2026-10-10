import AppKit
import CoreGraphics

/// 遮罩期间的全键白名单拦截器（HID 层 `CGEventTap`）。
///
/// 遮罩面板靠「成为 key 窗口」阻断普通按键，但系统级组合键（⌘Tab / ⌘` / ⌃←→ / F3 /
/// ⌘空格 / ⌘⇧345 / ⌘H / ⌘⌥Esc）由 WindowServer 在应用分发前处理，本地事件监听永远
/// 看不到——本类是唯一能拦住它们的层。与 `LockShortcutMonitor`（常驻、只认 ⌃⌘Q）不同：
/// 本 tap **仅在遮罩升起期间存在**（begin/end 与两处 show/dismiss 对称成对），白名单外
/// 一律吞掉。与锁屏劫持共用同一「输入监控」授权；未授权时降级为面板级阻断（普通按键
/// 仍被 key 面板挡住，仅系统组合键放行），fail-open。
///
/// 逃生通道盘点（白名单下的诚实声明）：双击 Esc；裸 Return（休息遮罩确认框「继续休息」）；
/// 看门狗 30min 验尸（见下）；ssh / 他机 kill 本进程；电源键硬关机（丢未保存工作，最后手段）。
/// 环境变量 `GIVEMEABREAK_DISABLE_INPUT_GUARD`（存在即禁用）为应急短路。
final class MaskInputGuard {
    /// 看门狗周期：到点验尸（遮罩仍在 → 续期；不在 → 强制停 tap）。手动遮罩为无上限模式，
    /// 故看门狗不是「30 分钟后自动解除」，而是「30 分钟核实一次 tap 是否已沦为僵尸」。
    private static let watchdogInterval: TimeInterval = 30 * 60

    // MARK: - 放行判定（纯函数，零副作用）
    //
    // 「判错即灾难」代码（同 isLockScreenChord 教义）：误放行 = 系统组合键穿透遮罩（功能缺陷），
    // 误吞 = 用户失去唯一键盘出口（灾难——此时连 ⌘⌥Esc 强退、⌃⌘Q、Apple 菜单键盘路径均不可用，
    // 只剩电源键硬关机）。保持单表达式、与 @convention(c) 胶水物理隔离，便于 review；
    // 若需增长即触发「抽出可测试缝」。
    //
    // 放行集 = 裸 Esc（53：双击退出 / 确认态切换）+ 裸 Return（36：确认框默认按钮）。
    // ⌘/⌃/⌥ 任一按下的 Esc/Return 一律吞——⌘⌥Esc 强退面板正是 keyCode 53 带修饰键，
    // 若只看 keyCode 会放行，且其默认按钮恰好吃裸 Return（双重穿透）。
    // Shift / CapsLock(.alphaShift) / Fn 刻意**不**计入屏蔽集：Caps Lock 常亮的用户每次按键
    // 都携带该位，若计入将永久失去 Esc 出口——这是比功能穿透更严重的灾难。
    private static let blockedModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]

    static func shouldPassThrough(keyCode: Int64, flags: CGEventFlags) -> Bool {
        (keyCode == 53 || keyCode == 36) && flags.intersection(blockedModifiers).isEmpty
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var watchdog: DispatchSourceTimer?
    private var active = false
    /// 降级提示只发一次（每次运行）；权限非热更新，反复刷屏无意义。
    private var loggedDegradeOnce = false

    var isActive: Bool { active }

    // MARK: - 生命周期（与两处 show/dismiss 对称成对；幂等）

    func begin() {
        guard !active else { return }
        if ProcessInfo.processInfo.environment["GIVEMEABREAK_DISABLE_INPUT_GUARD"] != nil {
            NSLog("[GiveMeABreak][maskInputGuard] 已由环境变量禁用（应急短路，遮罩期间系统组合键将放行）")
            return
        }

        // 严格只订阅 keyDown：媒体键/亮度走 NX_SYSDEFINED（休息听歌需要），修饰键状态
        // 变化走 flagsChanged（⌘Tab 切换器由 Tab 的 keyDown 触发，吞掉它即拦住）。
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,  // ⚠️ 必须 defaultTap；.listenOnly 只能观察无法拦截
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let refcon {
                        let guard_ = Unmanaged<MaskInputGuard>.fromOpaque(refcon).takeUnretainedValue()
                        if let tap = guard_.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    }
                    return Unmanaged.passUnretained(event)
                }
                // 白名单外一律吞（返回 nil）；谓词为纯静态函数——此处不需要实例，
                // 回调保持零副作用、零派发（防 tapDisabledByTimeout）。
                if MaskInputGuard.shouldPassThrough(keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                                                    flags: event.flags) {
                    return Unmanaged.passUnretained(event)
                }
                return nil
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            if !loggedDegradeOnce {
                loggedDegradeOnce = true
                // .defaultTap 实际同时受辅助功能信任门控（非仅输入监控），两项都打以便定位。
                NSLog("[GiveMeABreak][maskInputGuard] CGEventTap 创建失败，降级为面板级阻断（输入监控="
                     + "\(CGPreflightListenEventAccess()) 辅助功能=\(AXIsProcessTrusted())）——系统组合键（⌘Tab 等）将放行；授权后需重启 App")
            }
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)  // commonModes：菜单 tracking/模态循环期间也生效
        CGEvent.tapEnable(tap: tap, enable: true)
        active = true
        startWatchdog()
        NSLog("[GiveMeABreak][maskInputGuard] 键盘白名单拦截已启用（放行：裸 Esc / 裸 Return）")
    }

    func end() {
        guard active else { return }
        cancelWatchdog()
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        active = false
        NSLog("[GiveMeABreak][maskInputGuard] 键盘白名单拦截已停用")
    }

    /// 唤醒/健康检查钩子：tap 若因罕见原因被系统静默禁用，尝试重新启用（未激活时 no-op）。
    func recheckHealth() {
        guard active, let tap = eventTap, !CGEvent.tapIsEnabled(tap: tap) else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[GiveMeABreak][maskInputGuard] 健康检查：已重新启用被禁用的 tap")
    }

    // MARK: - 看门狗（独立于遮罩代码的兵底守卫）
    //
    // 针对的僵尸态：进程活着、tap 活着、遮罩却没了（show/dismiss 之外的 unforeseen 路径）。
    // 此态下用户键盘被吞却看不见任何提示，唯一自救是硬关机——故必须有与被守护代码
    // 无关的独立断路器。心跳在手动遮罩期间被挂起，不能承载；采用独立 DispatchSourceTimer
    // （同 WorkLogPromptWindowController.startTimeout 先例），.main 保证与 tap 同 runloop。
    //
    // 验尸只读 WindowServer 真相（CGWindowListCopyWindowInfo），不读任何控制器状态：
    // 本进程存在 ≥ 屏蔽层级的屏上窗口 = 遮罩仍在（合法长遮罩/跨睡眠）→ 续期；
    // 不存在 = 僵尸态 → 强制停 tap。正常路径崩溃/SIGKILL 由内核回收 tap，非本守卫职责。
    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.watchdogInterval)
        timer.setEventHandler { [weak self] in
            guard let self, self.active else { return }
            if Self.maskVisiblePerWindowServer() {
                self.startWatchdog()  // 遮罩仍在：续期下一轮
                NSLog("[GiveMeABreak][maskInputGuard] 看门狗：遮罩仍在屏（长时遮罩/跨睡眠），续期监控")
            } else {
                NSLog("[GiveMeABreak][maskInputGuard] 看门狗：未发现屏上遮罩窗口，强制停用拦截（防僵尸 tap 吞键）")
                self.end()
            }
        }
        timer.resume()
        watchdog = timer
    }

    private func cancelWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }

    /// WindowServer 视角的遮罩存在性（独立于任何控制器状态）。
    private static func maskVisiblePerWindowServer() -> Bool {
        let shielding = Int(CGShieldingWindowLevel())
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        return list.contains { w in
            (w[kCGWindowOwnerName as String] as? String) == "GiveMeABreak"
                && (w[kCGWindowLayer as String] as? Int ?? 0) >= shielding
        }
    }

    deinit {
        // 正常路径 end()/shutdown() 已停；泄漏时进程退出内核亦回收 tap。双保险，无副作用。
        if active { end() }
    }
}

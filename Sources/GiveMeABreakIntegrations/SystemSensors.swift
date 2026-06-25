import Foundation
import CoreGraphics
import GiveMeABreakEngine

/// 系统状态采样：AFK 空闲（CGEventSource HID 层，沙盒下可用、无需 entitlement）+ 睡眠标志。
/// isAsleep 由 AppRoot 的 NSWorkspace 观察者置位。
final class SystemSensors: SystemStateProvider {
    /// 任意 HID 输入事件类型（kCGAnyInputEventType = ~0）。
    private static let anyInputType = CGEventType(rawValue: 0xFFFFFFFF) ?? .null

    var isAsleep: Bool = false

    func idleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: Self.anyInputType)
    }
}

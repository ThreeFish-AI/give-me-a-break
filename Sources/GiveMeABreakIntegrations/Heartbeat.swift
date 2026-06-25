import Foundation
import GiveMeABreakEngine

/// 基于 DispatchSourceTimer 的心跳实现（wall-clock，1Hz）。
/// suspend/resume/cancel 顺序敏感（cancel 前必须 resume，双 suspend 崩溃）→ 状态守卫协调。
final class HeartbeatTimer: Heartbeat {
    private let timer: DispatchSourceTimer
    private var suspended = true

    init(queue: DispatchQueue = .main) {
        timer = DispatchSource.makeTimerSource(queue: queue)
    }

    func start(interval: TimeInterval, handler: @escaping () -> Void) {
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(100))
        timer.setEventHandler(handler: handler)
        resume()
    }

    func suspend() {
        guard !suspended else { return }
        suspended = true
        timer.suspend()
    }

    func resume() {
        guard suspended else { return }
        suspended = false
        timer.resume()
    }

    func stop() {
        resume()  // cancel 前必须处于非挂起态
        timer.cancel()
    }
}

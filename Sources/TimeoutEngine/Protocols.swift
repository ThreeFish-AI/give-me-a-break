import Foundation

// MARK: - 时钟抽象（注入虚拟时钟即可单元测试，零真实时间依赖）

public protocol Clock {
    func now() -> Date
}

public struct SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
}

// MARK: - 三大集成契约（签名无 AppKit，可放纯 Foundation 模块测试）

/// 全屏遮罩控制器：多屏覆盖 + 软强制 Esc 二次确认。
public protocol OverlayController: AnyObject {
    /// 进入休息：显示遮罩，倒计时至 restDeadline。
    func show(restDeadline: Date)
    /// 离开休息：退出遮罩（幂等）。
    func dismiss()
    var isShown: Bool { get }
}

/// 音乐控制器：CGEvent 媒体键控制 QQ 音乐。
public protocol MusicController: AnyObject {
    /// 进入休息：启动/恢复 QQ 音乐播放。
    func startPlayback()
    /// 离开休息：发送暂停媒体键（toggle），保留队列/进度。
    func pausePlayback()
}

/// 日历提供者：返回合并后的忙碌时间线（Google CalDAV 过滤后）。
public protocol CalendarProvider: AnyObject {
    func currentTimeline() -> MeetingTimeline
}

/// 系统状态提供者：AFK 空闲秒数 + 睡眠标志（实现用 CGEventSource + NSWorkspace 观察者）。
public protocol SystemStateProvider: AnyObject {
    var isAsleep: Bool { get }
    func idleSeconds() -> TimeInterval
}

// MARK: - 心跳抽象（实现见 LiveTimeoutEngine / Heartbeat）

public protocol Heartbeat: AnyObject {
    func start(interval: TimeInterval, handler: @escaping () -> Void)
    func suspend()
    func resume()
    func stop()
}

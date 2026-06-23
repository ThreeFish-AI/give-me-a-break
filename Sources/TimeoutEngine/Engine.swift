import Foundation

// MARK: - evaluate（纯函数：谓词优先级 FSM 决策）

/// 按固定顺序短路求值，首个匹配决定目标态：
/// (1) 不在工作窗口 → offDuty（最高，压过会议）
/// (2) AFK/asleep → idle
/// (3) 活跃会议 → inMeeting（会议压过休息）
/// (4) workAccum ≥ 阈值 → resting
/// (5) 否则 → working
///
/// 触发休息的不变量：workAccum ≥ workInterval AND activeMeeting == nil
/// （谓词 3 已保证到达谓词 4 时无活跃会议）。
public func evaluate(_ s: EngineSnapshot) -> EnginePhase {
    if !s.inWorkWindow { return .offDuty }
    if s.isAFK || s.isAsleep { return .idle }
    if s.activeMeeting != nil { return .inMeeting }
    if s.workAccumulatedSeconds >= s.workIntervalSeconds { return .resting }
    return .working
}

// MARK: - advance（纯函数：基于「转换前 phase」推进累加器）

/// 用 (now - lastTickAt) 时间戳差值对账，限幅防异常 tick（如长睡眠漏 tick）。
/// 仅当 `active`（非 AFK/非睡眠）且 phase ∈ {working, inMeeting} 时推进累加器。
public func advance(_ state: EngineState, to now: Date, maxDelta: TimeInterval = 60, active: Bool = true) -> EngineState {
    var s = state
    let delta = now.timeIntervalSince(s.lastTickAt)
    s.lastTickAt = now
    let clamped = min(max(0, delta), maxDelta)
    if active && (s.phase == .working || s.phase == .inMeeting) {
        s.workAccumulatedSeconds += clamped
    }
    return s
}

// MARK: - SideEffects（纯函数：from→to 的幂等副作用清单）

public struct SideEffects: Equatable {
    public var showOverlay: Bool = false
    public var dismissOverlay: Bool = false
    public var startMusic: Bool = false
    public var pauseMusic: Bool = false

    public init() {}
}

/// 进入 resting（from != resting）→ 显示遮罩 + 播放音乐；
/// 离开 resting（自然结束 / 被打断）→ 退出遮罩 + 暂停音乐。
public func sideEffects(from: EnginePhase, to: EnginePhase) -> SideEffects {
    var e = SideEffects()
    if from != .resting && to == .resting {
        e.showOverlay = true
        e.startMusic = true
    }
    if from == .resting && to != .resting {
        e.dismissOverlay = true
        e.pauseMusic = true
    }
    return e
}

// MARK: - transition（纯函数：phase 跃迁 + 休息生命周期）

/// 处理当前 phase → 目标 phase 的跃迁，并维护 restStartedAt / 累加器重置。
/// 休息态特判：被会议打断或离开窗口 → abort-and-reset（v1 默认，U7）；
/// 到时 → 重置累加器并重新评估（通常 → working）；AFK 不中断休息。
/// `forcedRest`：用户「立即休息」——无视工作窗口与会议，直接进入/保持休息直到自然结束。
public func transition(_ state: EngineState, snapshot: EngineSnapshot, config: DayPlanConfig, forcedRest: Bool = false) -> EngineState {
    var s = state

    if s.phase == .resting {
        let restStart = s.restStartedAt ?? snapshot.now
        let restDeadline = restStart.addingTimeInterval(config.restDurationSeconds)

        if snapshot.now >= restDeadline {
            // 休息自然结束 → 重置累加器并以 0 重新评估（强制休息结束后回到正常 FSM）
            s.workAccumulatedSeconds = 0
            s.restStartedAt = nil
            s.phase = evaluate(snapshot.zeroingAccumulator())
        } else if !forcedRest && !snapshot.inWorkWindow {
            // 离开工作窗口 → 中止休息，下班（强制休息不触发）
            s.workAccumulatedSeconds = 0
            s.restStartedAt = nil
            s.phase = .offDuty
        } else if !forcedRest && snapshot.activeMeeting != nil {
            // 会议打断休息 → abort-and-reset（强制休息不触发）
            s.workAccumulatedSeconds = 0
            s.restStartedAt = nil
            s.phase = .inMeeting
        } else {
            // 继续休息（AFK 不中断休息）
            s.phase = .resting
        }
        return s
    }

    // 非休息态：强制休息直接进入（无视窗口/会议）
    if forcedRest {
        s.phase = .resting
        s.restStartedAt = snapshot.now
        return s
    }

    // 非休息态：正常评估目标态
    let target = evaluate(snapshot)
    if target == .resting {
        s.restStartedAt = snapshot.now
    }
    s.phase = target
    return s
}

extension EngineSnapshot {
    /// 以 workAccum = 0 重新评估时构造的快照。
    func zeroingAccumulator() -> EngineSnapshot {
        EngineSnapshot(
            now: now,
            inWorkWindow: inWorkWindow,
            isAFK: isAFK,
            isAsleep: isAsleep,
            activeMeeting: activeMeeting,
            workAccumulatedSeconds: 0,
            workIntervalSeconds: workIntervalSeconds
        )
    }
}

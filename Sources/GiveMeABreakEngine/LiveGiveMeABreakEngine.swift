import Foundation

/// 引擎接线层：汇聚心跳 / 日历 / idle / sleep 输入 → 调用纯函数（advance/transition/sideEffects）
/// → 幂等分发副作用到三大 controller → 持久化状态。
///
/// 仅依赖协议（Clock/CalendarProvider/OverlayController/MusicController/SystemStateProvider），
/// 无 AppKit，可用 mock + 虚拟时钟单元测试。
public final class LiveGiveMeABreakEngine {
    private let clock: Clock
    private let calendar: Calendar
    private let calendarProvider: CalendarProvider
    private let overlay: OverlayController
    private let music: MusicController
    private let systemState: SystemStateProvider
    public private(set) var config: DayPlanConfig
    public private(set) var state: EngineState
    private var persistHandler: ((EngineState) -> Void)?
    /// 用户「立即休息」标志：下个 tick 无视工作窗口/会议进入休息，休息自然结束即清除。
    private var forcedRest = false

    public init(clock: Clock,
                calendar: Calendar = .current,
                calendarProvider: CalendarProvider,
                overlay: OverlayController,
                music: MusicController,
                systemState: SystemStateProvider,
                config: DayPlanConfig,
                initialState: EngineState? = nil) {
        self.clock = clock
        self.calendar = calendar
        self.calendarProvider = calendarProvider
        self.overlay = overlay
        self.music = music
        self.systemState = systemState
        self.config = config
        self.state = initialState ?? EngineState(phase: .offDuty, lastTickAt: clock.now())
        music.updateConfig(config)   // 同步音乐相关配置（粉噪音 / QQ 音乐开关）给播放器
    }

    public func setPersistHandler(_ handler: @escaping (EngineState) -> Void) {
        self.persistHandler = handler
    }

    /// 心跳 tick（Heartbeat 每秒调用）。
    public func tick() {
        let now = clock.now()
        let oldPhase = state.phase

        // ② 先取系统活动状态（AFK/睡眠），决定本 tick 是否计工作
        let isAFK = systemState.idleSeconds() > config.afkThresholdSeconds
        let isAsleep = systemState.isAsleep
        let active = !isAFK && !isAsleep

        // ① 对账 + 推进累加器（仅 active 且工作态时累计）
        var s = advance(state, to: now, active: active)

        // ② 聚合快照
        let timeline = calendarProvider.currentTimeline()
        let inWindow = config.workWindows.contains { $0.contains(date: now, calendar: calendar) }

        let snap = EngineSnapshot(
            now: now,
            inWorkWindow: inWindow,
            isAFK: isAFK,
            isAsleep: systemState.isAsleep,
            activeMeeting: timeline.activeMeeting(at: now),
            workAccumulatedSeconds: s.workAccumulatedSeconds,
            workIntervalSeconds: config.workIntervalSeconds
        )

        // ③ 纯函数决策 + 幂等副作用
        s = transition(s, snapshot: snap, config: config, forcedRest: forcedRest)
        if oldPhase == .resting && s.phase != .resting {
            forcedRest = false  // 休息结束（含强制休息），清除标志
        }
        let eff = sideEffects(from: oldPhase, to: s.phase)
        state = s

        if eff.showOverlay, let restStart = s.restStartedAt {
            overlay.show(restDeadline: restStart.addingTimeInterval(config.restDurationSeconds))
        }
        if eff.dismissOverlay { overlay.dismiss() }
        if eff.startMusic { music.startPlayback() }
        if eff.pauseMusic { music.pausePlayback() }

        persistHandler?(state)
    }

    // MARK: - 睡眠 / 唤醒 / 崩溃恢复

    /// 系统睡眠（willSleep）：收尾——把睡眠 onset 之前的工作时间计入累加器，然后冻结。
    /// 心跳在调用方挂起，睡眠期间无 tick。
    public func handleSleep() {
        state = advance(state, to: clock.now())
    }

    /// 系统唤醒（didWake）：重置对账基点为 now，使首个唤醒 tick 的 delta≈0，不回灌睡眠时长。
    public func handleWake() {
        state.lastTickAt = clock.now()
    }

    /// 启动崩溃恢复：依据持久化的 lastTickAt 与当前 now 的间隔决策。
    /// 短中断（≤ sanity）→ 按工作态推进（计入累加）；长中断 → 仅对账基点，不回灌。
    public func fastForward(sanityLimit: TimeInterval = 300) {
        let now = clock.now()
        let elapsed = now.timeIntervalSince(state.lastTickAt)
        if elapsed <= sanityLimit, elapsed > 0 {
            state = advance(state, to: now, maxDelta: max(sanityLimit, elapsed))
        } else {
            state.lastTickAt = now
        }
    }

    /// 用户在遮罩内 Esc 二次确认提前结束休息。
    /// 与 tick（:72-73）共享同一不变量：离开 .resting 即清除 forcedRest。
    /// 否则「立即休息」入口进入休息后 Esc，下个 tick 见 forcedRest 残留仍 true，
    /// transition 会无视一切重进 .resting 并重置倒计时 → 死循环无法退出。
    public func requestEarlyRestExit() {
        guard state.phase == .resting else { return }
        let oldPhase = state.phase
        state.workAccumulatedSeconds = 0
        state.restStartedAt = nil
        state.phase = .working
        forcedRest = false  // 离开 .resting 必清强制标志（与 tick 对齐），杜绝下个 tick 重拉回休息
        let eff = sideEffects(from: oldPhase, to: state.phase)
        if eff.dismissOverlay { overlay.dismiss() }
        if eff.pauseMusic { music.pausePlayback() }
    }

    /// 菜单「立即休息」：设置强制标志，下一 tick（或 AppRoot 立即 tick）无视工作窗口/会议进入休息。
    public func forceRestNow() {
        forcedRest = true
        NSLog("[GiveMeABreak] 用户触发立即休息（无视工作窗口）")
    }

    /// 设置 UI 应用新配置（工作窗口/间隔/音乐开关）。
    public func updateConfig(_ newConfig: DayPlanConfig) {
        config = newConfig
        music.updateConfig(newConfig)   // 热更新音乐播放器配置
    }
}

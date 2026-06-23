import Foundation
import TimeoutEngine

// MARK: - Mocks

final class MockClock: Clock {
    var value: Date
    init(_ d: Date) { value = d }
    func now() -> Date { value }
    @discardableResult func advance(by s: TimeInterval) -> MockClock { value = value.addingTimeInterval(s); return self }
}

final class MockOverlay: OverlayController {
    var showCount = 0
    var dismissCount = 0
    var lastDeadline: Date?
    func show(restDeadline: Date) { showCount += 1; lastDeadline = restDeadline }
    func dismiss() { dismissCount += 1 }
    var isShown: Bool { showCount > dismissCount }
}

final class MockMusic: MusicController {
    var startCount = 0
    var pauseCount = 0
    func startPlayback() { startCount += 1 }
    func pausePlayback() { pauseCount += 1 }
}

final class StubCalendar: CalendarProvider {
    var timeline = MeetingTimeline.empty
    func currentTimeline() -> MeetingTimeline { timeline }
}

final class MockSystemState: SystemStateProvider {
    var asleep = false
    var idleValue: TimeInterval = 0
    var isAsleep: Bool { asleep }
    func idleSeconds() -> TimeInterval { idleValue }
}

// MARK: - Helpers

private func utcCalendar() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private func fullDayConfig(interval: TimeInterval, rest: TimeInterval) -> DayPlanConfig {
    DayPlanConfig(
        workWindows: [WorkWindow(start: TimeOfDay(hours: 0), end: TimeOfDay(hours: 23, minutes: 59))],
        workIntervalSeconds: interval,
        restDurationSeconds: rest
    )
}

/// 以 step（默认 60s）粒度驱动引擎 tick。step ≤ maxDelta(60) 保证不触发限幅损失。
func runTicks(_ engine: LiveTimeoutEngine, clock: MockClock, seconds: TimeInterval, step: TimeInterval = 60) {
    var elapsed: TimeInterval = 0
    while elapsed < seconds {
        let s = min(step, seconds - elapsed)
        clock.advance(by: s)
        engine.tick()
        elapsed += s
    }
}

func runEngineWiringCases() {
    let m = minutes__ // 局部别名，避免与文件内 minutes 冲突

    // U1：真实引擎——工作→会议→休息→工作，断言控制器调用序列
    test("U1 引擎接线：控制器调用序列") {
        let t0 = Date(timeIntervalSince1970: 0)
        let clock = MockClock(t0)
        let overlay = MockOverlay(), music = MockMusic(), calProv = StubCalendar(), sys = MockSystemState()
        calProv.timeline = MeetingTimeline(busyIntervals: [
            DateRange(start: t0.addingTimeInterval(m(30)), end: t0.addingTimeInterval(m(60))),
        ])
        let engine = LiveTimeoutEngine(
            clock: clock, calendar: utcCalendar(), calendarProvider: calProv,
            overlay: overlay, music: music, systemState: sys,
            config: fullDayConfig(interval: m(50), rest: m(10)),
            initialState: EngineState(phase: .working, lastTickAt: t0)
        )

        runTicks(engine, clock: clock, seconds: m(29))
        expectEqual(engine.state.phase, .working)

        runTicks(engine, clock: clock, seconds: m(21))  // → 50min（会议 [30,60) 进行中）
        expectEqual(engine.state.phase, .inMeeting, "t=50 在会议中")
        expectEqual(overlay.showCount, 0)

        runTicks(engine, clock: clock, seconds: m(10))  // → 60min（会议结束）
        expectEqual(engine.state.phase, .resting, "t=60 触发休息")
        expectEqual(overlay.showCount, 1)
        expectEqual(music.startCount, 1)

        runTicks(engine, clock: clock, seconds: m(10))  // → 70min（休息结束）
        expectEqual(engine.state.phase, .working)
        expectEqual(overlay.dismissCount, 1)
        expectEqual(music.pauseCount, 1)
    }

    // U5：AFK → IDLE 冻结累加器；输入恢复后续增
    test("U5 AFK 冻结累加器，恢复后续增") {
        let t0 = Date(timeIntervalSince1970: 0)
        let clock = MockClock(t0)
        let overlay = MockOverlay(), music = MockMusic(), calProv = StubCalendar(), sys = MockSystemState()
        let engine = LiveTimeoutEngine(
            clock: clock, calendar: utcCalendar(), calendarProvider: calProv,
            overlay: overlay, music: music, systemState: sys,
            config: fullDayConfig(interval: m(10), rest: m(2)),
            initialState: EngineState(phase: .working, lastTickAt: t0)
        )
        runTicks(engine, clock: clock, seconds: m(2))
        let accumBefore = engine.state.workAccumulatedSeconds

        sys.idleValue = 999  // > afkThreshold(180) → AFK
        runTicks(engine, clock: clock, seconds: m(2))
        expectEqual(engine.state.phase, .idle)
        expect(approx(engine.state.workAccumulatedSeconds, accumBefore, 0.001), "AFK 期间累加器冻结")

        sys.idleValue = 0  // 输入恢复
        runTicks(engine, clock: clock, seconds: 120)  // 首 tick idle→working 不累加，次 tick 起续增
        expectEqual(engine.state.phase, .working)
        expect(engine.state.workAccumulatedSeconds > accumBefore, "恢复后累加器续增")
    }

    // U6：睡眠/唤醒——sleep 期间不累计，唤醒不回灌 8 小时
    test("U6 睡眠/唤醒不回灌") {
        let t0 = Date(timeIntervalSince1970: 0)
        let clock = MockClock(t0)
        let overlay = MockOverlay(), music = MockMusic(), calProv = StubCalendar(), sys = MockSystemState()
        let engine = LiveTimeoutEngine(
            clock: clock, calendar: utcCalendar(), calendarProvider: calProv,
            overlay: overlay, music: music, systemState: sys,
            config: fullDayConfig(interval: m(50), rest: m(10)),
            initialState: EngineState(phase: .working, lastTickAt: t0)
        )
        runTicks(engine, clock: clock, seconds: m(3))
        let accumBefore = engine.state.workAccumulatedSeconds

        sys.asleep = true
        engine.handleSleep()
        clock.advance(by: 8 * 3600)  // 睡眠 8 小时（心跳已挂起，无 tick）
        sys.asleep = false
        engine.handleWake()
        engine.tick()  // 首个唤醒 tick：delta≈0，不回灌

        expect(approx(engine.state.workAccumulatedSeconds, accumBefore, 0.001), "唤醒后不回灌 8h")
        expectEqual(engine.state.phase, .working)
    }

    // U11：fast-forward 短中断推进、长中断冻结
    test("U11 fast-forward 短中断推进") {
        let t0 = Date(timeIntervalSince1970: 0)
        let clock = MockClock(t0)
        let overlay = MockOverlay(), music = MockMusic(), calProv = StubCalendar(), sys = MockSystemState()
        // 模拟崩溃：持久化状态为 working/累加 1500s/lastTickAt=t0
        let engine = LiveTimeoutEngine(
            clock: clock, calendar: utcCalendar(), calendarProvider: calProv,
            overlay: overlay, music: music, systemState: sys,
            config: fullDayConfig(interval: m(50), rest: m(10)),
            initialState: EngineState(phase: .working, workAccumulatedSeconds: 1500, lastTickAt: t0)
        )
        clock.advance(by: 120)  // 重启于 t0+120s（短中断）
        engine.fastForward(sanityLimit: 300)
        expect(approx(engine.state.workAccumulatedSeconds, 1620, 1), "短中断 120s 应计入累加")
    }

    test("U11 fast-forward 长中断冻结") {
        let t0 = Date(timeIntervalSince1970: 0)
        let clock = MockClock(t0)
        let overlay = MockOverlay(), music = MockMusic(), calProv = StubCalendar(), sys = MockSystemState()
        let engine = LiveTimeoutEngine(
            clock: clock, calendar: utcCalendar(), calendarProvider: calProv,
            overlay: overlay, music: music, systemState: sys,
            config: fullDayConfig(interval: m(50), rest: m(10)),
            initialState: EngineState(phase: .working, workAccumulatedSeconds: 1500, lastTickAt: t0)
        )
        clock.advance(by: 1800)  // 30min 中断 > sanity(300)
        engine.fastForward(sanityLimit: 300)
        expect(approx(engine.state.workAccumulatedSeconds, 1500, 0.001), "长中断不回灌")
        expectEqual(engine.state.lastTickAt, t0.addingTimeInterval(1800))
    }

    // requestEarlyRestExit：Esc 二次确认提前结束休息
    test("Esc 提前结束休息：暂停音乐 + 退出遮罩 + 累加器归零") {
        let t0 = Date(timeIntervalSince1970: 0)
        let clock = MockClock(t0)
        let overlay = MockOverlay(), music = MockMusic(), calProv = StubCalendar(), sys = MockSystemState()
        let engine = LiveTimeoutEngine(
            clock: clock, calendar: utcCalendar(), calendarProvider: calProv,
            overlay: overlay, music: music, systemState: sys,
            config: fullDayConfig(interval: m(2), rest: m(10)),
            initialState: EngineState(phase: .working, lastTickAt: t0)
        )
        runTicks(engine, clock: clock, seconds: m(2))  // → 触发休息
        expectEqual(engine.state.phase, .resting)
        expectEqual(overlay.showCount, 1)

        engine.requestEarlyRestExit()
        expectEqual(engine.state.phase, .working)
        expectEqual(overlay.dismissCount, 1)
        expectEqual(music.pauseCount, 1)
        expect(approx(engine.state.workAccumulatedSeconds, 0, 0.001))
    }

    // 立即休息：无视工作窗口（offDuty 下强制进入休息，且休息期间不被 offDuty 中断）
    test("立即休息无视工作窗口") {
        let t0 = Date(timeIntervalSince1970: 0)
        let clock = MockClock(t0)
        let overlay = MockOverlay(), music = MockMusic(), calProv = StubCalendar(), sys = MockSystemState()
        let config = DayPlanConfig(workWindows: [], workIntervalSeconds: m(50), restDurationSeconds: m(2))
        let engine = LiveTimeoutEngine(
            clock: clock, calendar: utcCalendar(), calendarProvider: calProv,
            overlay: overlay, music: music, systemState: sys,
            config: config, initialState: EngineState(phase: .offDuty, lastTickAt: t0)
        )
        runTicks(engine, clock: clock, seconds: 10)
        expectEqual(engine.state.phase, .offDuty, "空窗口应恒 offDuty")

        engine.forceRestNow()
        runTicks(engine, clock: clock, seconds: 2)
        expectEqual(engine.state.phase, .resting, "强制休息应无视空工作窗口生效")
        expectEqual(overlay.showCount, 1)

        runTicks(engine, clock: clock, seconds: 60)
        expectEqual(engine.state.phase, .resting, "强制休息期间不被 offDuty 中断")
        expectEqual(overlay.showCount, 1, "不应重复显示遮罩")

        // 休息自然结束（2min）→ 回到正常 FSM（空窗口→offDuty），标志清除
        runTicks(engine, clock: clock, seconds: 90)
        expectEqual(engine.state.phase, .offDuty, "强制休息结束后回到正常评估")
        expectEqual(overlay.dismissCount, 1)
    }

    // 设置 UI 应用新配置：updateConfig 后引擎按新间隔触发休息
    test("updateConfig 热更新引擎配置") {
        let t0 = Date(timeIntervalSince1970: 0)
        let clock = MockClock(t0)
        let overlay = MockOverlay(), music = MockMusic(), calProv = StubCalendar(), sys = MockSystemState()
        let engine = LiveTimeoutEngine(
            clock: clock, calendar: utcCalendar(), calendarProvider: calProv,
            overlay: overlay, music: music, systemState: sys,
            config: fullDayConfig(interval: m(50), rest: m(10)),
            initialState: EngineState(phase: .working, lastTickAt: t0)
        )
        runTicks(engine, clock: clock, seconds: m(10))
        expectEqual(engine.state.phase, .working)  // 10min < 50min 阈值

        // 用户在设置里把工作时长改为 8min
        var newConfig = engine.config
        newConfig.workIntervalSeconds = m(8)
        engine.updateConfig(newConfig)

        runTicks(engine, clock: clock, seconds: m(5))  // 累计到 15min > 8min
        expectEqual(engine.state.phase, .resting, "新间隔 8min 应已触发休息")
        expectEqual(overlay.showCount, 1)
    }
}

private func minutes__(_ m: TimeInterval) -> TimeInterval { m * 60 }

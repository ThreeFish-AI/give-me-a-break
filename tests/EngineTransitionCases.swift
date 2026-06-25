import Foundation
import GiveMeABreakEngine

// MARK: - 忠实模拟 1Hz 心跳：advance → transition → sideEffects，记录非空副作用跃迁

final class Simulator {
    struct Record {
        let at: Date
        let from: EnginePhase
        let to: EnginePhase
        let effects: SideEffects
        let accumAfter: TimeInterval
        let restStartedAt: Date?
    }

    let config: DayPlanConfig
    let t0: Date
    private let meetings: [DateRange]
    private let inWindow: (Date) -> Bool
    private(set) var state: EngineState
    private(set) var records: [Record] = []

    init(t0: Date,
         config: DayPlanConfig,
         meetings: [DateRange] = [],
         inWindow: @escaping (Date) -> Bool = { _ in true }) {
        self.t0 = t0
        self.config = config
        self.meetings = meetings
        self.inWindow = inWindow
        // 初始即处于稳态（若在窗口内则 working），避免冷启动首 tick 的 1s 累计损失影响短间隔测试精度。
        self.state = EngineState(phase: inWindow(t0) ? .working : .offDuty, lastTickAt: t0)
    }

    private func snapshot(at now: Date) -> EngineSnapshot {
        let timeline = MeetingTimeline(busyIntervals: mergeBusyIntervals(meetings))
        return EngineSnapshot(
            now: now,
            inWorkWindow: inWindow(now),
            isAFK: false,
            isAsleep: false,
            activeMeeting: timeline.activeMeeting(at: now),
            workAccumulatedSeconds: state.workAccumulatedSeconds,
            workIntervalSeconds: config.workIntervalSeconds
        )
    }

    /// 以 1s 粒度 tick 到 target（避免粗粒度触发 advance 限幅）。
    @discardableResult
    func tick(to target: Date) -> Simulator {
        while state.lastTickAt < target {
            let step = min(1.0, target.timeIntervalSince(state.lastTickAt))
            let next = state.lastTickAt.addingTimeInterval(step)
            let oldPhase = state.phase
            state = advance(state, to: next)
            let snap = snapshot(at: next)
            state = transition(state, snapshot: snap, config: config)
            let eff = sideEffects(from: oldPhase, to: state.phase)
            if eff != SideEffects() {
                records.append(Record(at: next, from: oldPhase, to: state.phase,
                                      effects: eff, accumAfter: state.workAccumulatedSeconds,
                                      restStartedAt: state.restStartedAt))
            }
        }
        return self
    }

    var phase: EnginePhase { state.phase }
    var accum: TimeInterval { state.workAccumulatedSeconds }
}

private func minutes(_ m: TimeInterval) -> TimeInterval { m * 60 }

func runEngineTransitionCases() {
    test("U1 工作示例：会议推迟休息 30+30→60→10") {
        let t0 = Date(timeIntervalSince1970: 0)
        let config = DayPlanConfig(workIntervalSeconds: minutes(50), restDurationSeconds: minutes(10))
        let meetings = [DateRange(start: t0.addingTimeInterval(minutes(30)),
                                  end: t0.addingTimeInterval(minutes(60)))]
        let sim = Simulator(t0: t0, config: config, meetings: meetings)

        sim.tick(to: t0.addingTimeInterval(minutes(29)))
        expectEqual(sim.phase, .working)
        expect(approx(sim.accum, minutes(29)))

        sim.tick(to: t0.addingTimeInterval(minutes(50)))
        expectEqual(sim.phase, .inMeeting, "t=50 应在会议中，休息被推迟")
        expect(sim.accum >= minutes(50))

        sim.tick(to: t0.addingTimeInterval(minutes(60)))
        expectEqual(sim.phase, .resting, "t=60 会议结束应触发休息")
        let enter = sim.records.last { $0.to == .resting }!
        expect(enter.effects.showOverlay)
        expect(enter.effects.startMusic)
        expect(approx(enter.restStartedAt!.timeIntervalSince1970,
                      t0.addingTimeInterval(minutes(60)).timeIntervalSince1970))

        sim.tick(to: t0.addingTimeInterval(minutes(70)))
        expectEqual(sim.phase, .working)
        let exit = sim.records.last { $0.from == .resting }!
        expect(exit.effects.dismissOverlay)
        expect(exit.effects.pauseMusic)
        expect(approx(sim.accum, 0, 0.001), "休息后累加器应归零")
    }

    test("U2 会议恰在阈值点开始 → 不触发瞬间休息") {
        let t0 = Date(timeIntervalSince1970: 0)
        let config = DayPlanConfig(workIntervalSeconds: minutes(50), restDurationSeconds: minutes(10))
        let meetings = [DateRange(start: t0.addingTimeInterval(minutes(50)),
                                  end: t0.addingTimeInterval(minutes(70)))]
        let sim = Simulator(t0: t0, config: config, meetings: meetings)
        sim.tick(to: t0.addingTimeInterval(minutes(50)))
        expectEqual(sim.phase, .inMeeting, "t=50 会议开始应进 inMeeting")
        expect(!sim.records.contains { $0.to == .resting }, "不应触发休息")
    }

    test("U3 背靠背会议跨接缝持续 inMeeting") {
        let t0 = Date(timeIntervalSince1970: 0)
        let config = DayPlanConfig(workIntervalSeconds: minutes(50), restDurationSeconds: minutes(10))
        let meetings = [
            DateRange(start: t0.addingTimeInterval(minutes(50)), end: t0.addingTimeInterval(minutes(70))),
            DateRange(start: t0.addingTimeInterval(minutes(70)), end: t0.addingTimeInterval(minutes(90))),
        ]
        let sim = Simulator(t0: t0, config: config, meetings: meetings)
        sim.tick(to: t0.addingTimeInterval(minutes(70)))
        expectEqual(sim.phase, .inMeeting, "t=70 第二个会议开始仍 inMeeting")
        expect(!sim.records.contains { $0.to == .resting }, "[50,70) 不应触发休息")
    }

    test("U4 会议跨工作窗口边界 → offDuty 优先") {
        let t0 = Date(timeIntervalSince1970: 0)
        let config = DayPlanConfig(workIntervalSeconds: minutes(50), restDurationSeconds: minutes(10))
        let meetings = [DateRange(start: t0.addingTimeInterval(minutes(50)),
                                  end: t0.addingTimeInterval(minutes(70)))]
        let sim = Simulator(t0: t0, config: config, meetings: meetings) { d in
            d < t0.addingTimeInterval(minutes(60))
        }
        sim.tick(to: t0.addingTimeInterval(minutes(65)))
        expectEqual(sim.phase, .offDuty, "t=65 已离开工作窗口 → offDuty 压过会议")
    }

    test("U7 休息被会议打断 → abort-and-reset") {
        let t0 = Date(timeIntervalSince1970: 0)
        let config = DayPlanConfig(workIntervalSeconds: minutes(2), restDurationSeconds: minutes(5))
        let meetings = [DateRange(start: t0.addingTimeInterval(minutes(3)),
                                  end: t0.addingTimeInterval(minutes(5)))]
        let sim = Simulator(t0: t0, config: config, meetings: meetings)

        sim.tick(to: t0.addingTimeInterval(minutes(2)))
        expectEqual(sim.phase, .resting, "t=120 触发休息")

        sim.tick(to: t0.addingTimeInterval(minutes(3)))
        expectEqual(sim.phase, .inMeeting, "t=180 会议打断休息")
        let abort = sim.records.last { $0.from == .resting }!
        expect(abort.effects.dismissOverlay)
        expect(abort.effects.pauseMusic)
        expect(approx(sim.accum, 0, 0.001), "打断休息后累加器应归零")
    }

    test("U9 同态幂等：休息中 showOverlay/startMusic 仅一次") {
        let t0 = Date(timeIntervalSince1970: 0)
        let config = DayPlanConfig(workIntervalSeconds: minutes(2), restDurationSeconds: minutes(10))
        let sim = Simulator(t0: t0, config: config, meetings: [])
        sim.tick(to: t0.addingTimeInterval(minutes(2)))
        sim.tick(to: t0.addingTimeInterval(minutes(5)))
        sim.tick(to: t0.addingTimeInterval(minutes(8)))

        expectEqual(sim.records.filter { $0.effects.showOverlay }.count, 1)
        expectEqual(sim.records.filter { $0.effects.startMusic }.count, 1)
        expectEqual(sim.phase, .resting)
    }
}

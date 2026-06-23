import Foundation
import TimeoutEngine

// MARK: - evaluate 谓词优先级（P1-P5）+ advance 限幅（U10）+ mergeBusyIntervals（U13）

private let interval: TimeInterval = 50 * 60
private let sampleMeeting = DateRange(start: Date(timeIntervalSince1970: 1000),
                                      end: Date(timeIntervalSince1970: 2000))

private func snap(
    now: Date = Date(timeIntervalSince1970: 0),
    inWorkWindow: Bool = true,
    isAFK: Bool = false,
    isAsleep: Bool = false,
    activeMeeting: DateRange? = nil,
    workAccum: TimeInterval = 0,
    workInterval: TimeInterval = 50 * 60
) -> EngineSnapshot {
    EngineSnapshot(now: now, inWorkWindow: inWorkWindow, isAFK: isAFK, isAsleep: isAsleep,
                   activeMeeting: activeMeeting, workAccumulatedSeconds: workAccum,
                   workIntervalSeconds: workInterval)
}

func runEvaluateCases() {
    // P1: 不在工作窗口 → offDuty，即便同时 AFK + 会议 + 达阈值
    test("P1 offDuty 压过一切") {
        let s = snap(inWorkWindow: false, isAFK: true, activeMeeting: sampleMeeting, workAccum: interval * 10)
        expectEqual(evaluate(s), .offDuty)
    }

    test("P2 idle 压过会议与达阈值") {
        let s = snap(isAFK: true, activeMeeting: sampleMeeting, workAccum: interval * 10)
        expectEqual(evaluate(s), .idle)
    }

    test("P3 会议压过达阈值（推迟休息）") {
        let s = snap(activeMeeting: sampleMeeting, workAccum: interval * 2)
        expectEqual(evaluate(s), .inMeeting)
    }

    test("P4 达阈值触发休息") {
        let s = snap(workAccum: interval)
        expectEqual(evaluate(s), .resting)
    }

    test("P5 默认 working") {
        let s = snap(workAccum: interval - 1)
        expectEqual(evaluate(s), .working)
    }

    test("休息不变量：达阈值但有会议 → 不 resting") {
        let s = snap(activeMeeting: sampleMeeting, workAccum: interval * 5)
        expect(evaluate(s) != .resting)
    }

    // U10: 单次异常 tick（delta=3600s）被限幅为 maxDelta
    test("U10 advance 限幅异常 tick") {
        let t0 = Date(timeIntervalSince1970: 0)
        let state = EngineState(phase: .working, lastTickAt: t0)
        let advanced = advance(state, to: t0.addingTimeInterval(3600), maxDelta: 60)
        expect(approx(advanced.workAccumulatedSeconds, 60, 0.001))
        expectEqual(advanced.lastTickAt, t0.addingTimeInterval(3600))
    }

    test("advance resting 冻结累加器") {
        let t0 = Date(timeIntervalSince1970: 0)
        let state = EngineState(phase: .resting, workAccumulatedSeconds: 100, lastTickAt: t0)
        let advanced = advance(state, to: t0.addingTimeInterval(30), maxDelta: 60)
        expect(approx(advanced.workAccumulatedSeconds, 100, 0.001))
    }

    test("advance 负 delta 夹紧为 0") {
        let t0 = Date(timeIntervalSince1970: 100)
        let state = EngineState(phase: .working, lastTickAt: t0)
        let advanced = advance(state, to: t0.addingTimeInterval(-50), maxDelta: 60)
        expect(approx(advanced.workAccumulatedSeconds, 0, 0.001))
    }

    // U13: 重叠/相邻区间合并
    test("U13 merge 重叠与间隙") {
        let b = Date(timeIntervalSince1970: 0)
        let ranges = [
            DateRange(start: b.addingTimeInterval(10), end: b.addingTimeInterval(30)),
            DateRange(start: b.addingTimeInterval(20), end: b.addingTimeInterval(40)),
            DateRange(start: b.addingTimeInterval(45), end: b.addingTimeInterval(50)),
        ]
        let merged = mergeBusyIntervals(ranges)
        expectEqual(merged.count, 2)
        expectEqual(merged[0].start.timeIntervalSince1970, 10)
        expectEqual(merged[0].end.timeIntervalSince1970, 40)
        expectEqual(merged[1].start.timeIntervalSince1970, 45)
        expectEqual(merged[1].end.timeIntervalSince1970, 50)
    }

    test("merge 背靠背端点相接合并") {
        let b = Date(timeIntervalSince1970: 0)
        let ranges = [
            DateRange(start: b.addingTimeInterval(0), end: b.addingTimeInterval(30)),
            DateRange(start: b.addingTimeInterval(30), end: b.addingTimeInterval(60)),
        ]
        let merged = mergeBusyIntervals(ranges, mergeGap: 0)
        expectEqual(merged.count, 1, "半开区间端点相接应合并")
        expectEqual(merged[0].end.timeIntervalSince1970, 60)
    }

    test("merge 空列表") {
        expect(mergeBusyIntervals([]).isEmpty)
    }

    test("MeetingTimeline activeMeeting 半开语义") {
        let b = Date(timeIntervalSince1970: 0)
        let timeline = MeetingTimeline(busyIntervals: [
            DateRange(start: b.addingTimeInterval(30), end: b.addingTimeInterval(60)),
        ])
        expect(timeline.activeMeeting(at: b.addingTimeInterval(45)) != nil)
        expect(timeline.activeMeeting(at: b.addingTimeInterval(60)) == nil, "end 时刻会议已结束")
        expect(timeline.activeMeeting(at: b.addingTimeInterval(10)) == nil)
    }
}

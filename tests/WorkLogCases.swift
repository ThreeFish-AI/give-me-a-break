import Foundation
import GiveMeABreakEngine

// MARK: - Helpers

private var dirCounter = 0
private func makeTempDir() -> URL {
    dirCounter += 1
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("givemeabreak-worklog-test-\(dirCounter)-\(ProcessInfo.processInfo.processIdentifier)")
    try? FileManager.default.removeItem(at: dir)
    return dir
}

private func utcCalendar() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private func utcTZ() -> TimeZone { TimeZone(identifier: "UTC")! }

// MARK: - WorkLogStore

func runWorkLogCases() {
    let s = minutes__

    test("WorkLogStore round-trip + 顺序保持") {
        let store = try! WorkLogStore(directory: makeTempDir())
        let t0 = Date(timeIntervalSince1970: 0)
        store.append(WorkLogEntry(startedAt: t0, endedAt: t0.addingTimeInterval(s(50)),
                                  summary: "调试登录 bug", nextAction: "补单测",
                                  durationSeconds: s(50)))
        store.append(WorkLogEntry(startedAt: t0.addingTimeInterval(s(60)), endedAt: t0.addingTimeInterval(s(110)),
                                  summary: "写周报", durationSeconds: s(50)))

        let loaded = store.loadEntries()
        expectEqual(loaded.count, 2)
        expectEqual(loaded[0].summary, "调试登录 bug")
        expectEqual(loaded[1].summary, "写周报")
        expectEqual(loaded[0].nextAction, "补单测")
        expectEqual(loaded[1].nextAction, nil, "空 nextAction 应规约为 nil")
    }

    test("WorkLogStore 缺失/损坏文件 → 空列表") {
        let dir = makeTempDir()
        let store = try! WorkLogStore(directory: dir)
        expectEqual(store.loadEntries().count, 0, "无文件应返回空")

        let url = dir.appendingPathComponent("work-log.json")
        try! "{not json".data(using: .utf8)!.write(to: url, options: .atomic)
        expectEqual(store.loadEntries().count, 0, "损坏 JSON 应回退空")
    }

    test("WorkLogStore replaceAll 清空 + 排序") {
        let store = try! WorkLogStore(directory: makeTempDir())
        let t0 = Date(timeIntervalSince1970: 0)
        store.append(WorkLogEntry(startedAt: t0.addingTimeInterval(s(3)), endedAt: t0.addingTimeInterval(s(4)),
                                  summary: "b", durationSeconds: s(10)))
        store.append(WorkLogEntry(startedAt: t0, endedAt: t0.addingTimeInterval(s(1)),
                                  summary: "a", durationSeconds: s(10)))
        expectEqual(store.loadEntries().count, 2)

        store.replaceAll([])
        expectEqual(store.loadEntries().count, 0, "replaceAll([]) 应清空")

        // replaceAll 应按 startedAt 升序规整
        store.replaceAll([
            WorkLogEntry(startedAt: t0.addingTimeInterval(s(3)), endedAt: t0.addingTimeInterval(s(4)), summary: "late", durationSeconds: s(10)),
            WorkLogEntry(startedAt: t0, endedAt: t0.addingTimeInterval(s(1)), summary: "early", durationSeconds: s(10)),
        ])
        let loaded = store.loadEntries()
        expectEqual(loaded.first?.summary, "early", "应按 startedAt 升序")
    }

    test("WorkLogEntry 容错解码（缺字段补默认）") {
        // 手写缺字段的 JSON（无 nextAction/modelVersion）
        let json = """
        [{"id":"x","startedAt":0,"endedAt":0,"summary":"ok","durationSeconds":600}]
        """.data(using: .utf8)!
        let decoded = try! JSONDecoder().decode([WorkLogEntry].self, from: json)
        expectEqual(decoded.count, 1)
        expectEqual(decoded[0].nextAction, nil, "缺 nextAction → nil")
        expectEqual(decoded[0].modelVersion, WorkLogEntry.currentModelVersion, "缺 modelVersion → 补当前版本")
    }

    // MARK: - humanizedDuration

    test("humanizedDuration 格式") {
        expectEqual(humanizedDuration(0), "0m")
        expectEqual(humanizedDuration(45 * 60), "45m")
        expectEqual(humanizedDuration(60 * 60), "1h")
        expectEqual(humanizedDuration(90 * 60), "1h 30m")
        expectEqual(humanizedDuration(50 * 60), "50m")
        expectEqual(humanizedDuration(125 * 60), "2h 5m")
    }

    // MARK: - filterWorkLogEntries（分桶边界）

    test("filterWorkLogEntries today/week/month/all 分桶") {
        // 固定 now = 2026-06-25 12:00 UTC（周四）；构造跨日/跨周/跨月条目
        let cal = utcCalendar()
        let tz = utcTZ()
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 12))!
        let d = { (year: Int, month: Int, day: Int, hour: Int) in
            cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
        }
        let entries = [
            WorkLogEntry(startedAt: d(2026, 6, 25, 9), endedAt: d(2026, 6, 25, 9), summary: "今日上午", durationSeconds: s(50)),   // 今日
            WorkLogEntry(startedAt: d(2026, 6, 24, 9), endedAt: d(2026, 6, 24, 9), summary: "昨日", durationSeconds: s(50)),       // 本周非今日
            WorkLogEntry(startedAt: d(2026, 6, 1, 9), endedAt: d(2026, 6, 1, 9), summary: "本月早", durationSeconds: s(50)),       // 本月非本周
            WorkLogEntry(startedAt: d(2026, 5, 20, 9), endedAt: d(2026, 5, 20, 9), summary: "上月", durationSeconds: s(50)),       // 上月
        ]
        expectEqual(filterWorkLogEntries(entries, scope: .today, now: now, calendar: cal, timeZone: tz).count, 1)
        expectEqual(filterWorkLogEntries(entries, scope: .month, now: now, calendar: cal, timeZone: tz).count, 3, "本月 = 今日+昨日+本月早")
        expectEqual(filterWorkLogEntries(entries, scope: .all, now: now, calendar: cal, timeZone: tz).count, 4)
        // 周：2026-06-25 为周四，ISO 周（周一起）覆盖 06-22~06-28 → 含今日+昨日，不含 06-01
        expectEqual(filterWorkLogEntries(entries, scope: .week, now: now, calendar: cal, timeZone: tz).count, 2, "本周含今日+昨日")
    }

    // MARK: - renderWorkLogReport（结构 + 幂等）

    test("renderWorkLogReport 日报结构与幂等") {
        let cal = utcCalendar()
        let tz = utcTZ()
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 18))!
        let t0 = cal.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 9))!
        let entries = [
            WorkLogEntry(startedAt: t0, endedAt: t0.addingTimeInterval(s(50)), summary: "调试登录 bug", nextAction: "补单测", durationSeconds: s(50)),
            WorkLogEntry(startedAt: t0.addingTimeInterval(s(60)), endedAt: t0.addingTimeInterval(s(110)), summary: "写周报第一稿", durationSeconds: s(50)),
        ]
        let md1 = renderWorkLogReport(entries: entries, scope: .today, now: now, calendar: cal, timeZone: tz)
        let md2 = renderWorkLogReport(entries: entries, scope: .today, now: now, calendar: cal, timeZone: tz)

        expect(md1 == md2, "同输入两次渲染必须字节幂等")
        expect(md1.contains("# 今日工作回顾 · 2026-06-25"), "应有 H1 标题与日期")
        expect(md1.contains("2 条记录"), "blockquote 应含条数")
        expect(md1.contains("今日 Top 3"), "应有 Top 3 节")
        expect(md1.contains("完成清单"), "应有完成清单节")
        expect(md1.contains("调试登录 bug"), "应含摘要正文")
        expect(md1.contains("下一步：补单测"), "应含 nextAction 引用块")
        expect(md1.contains("待续 · 下一步"), "应有待续·下一步节")
    }

    test("renderWorkLogReport 空条目不崩且含占位") {
        let cal = utcCalendar()
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 18))!
        let md = renderWorkLogReport(entries: [], scope: .week, now: now, calendar: cal, timeZone: utcTZ())
        expect(md.contains("暂无记录"), "空应含占位文案")
        expect(md.contains("# 本周工作回顾"), "空也应渲染 H1")
    }

    test("renderWorkLogReport 月报含按周拆解；全部含按月汇总表") {
        let cal = utcCalendar()
        let tz = utcTZ()
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 18))!
        let t0 = cal.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))!
        let entries = [
            WorkLogEntry(startedAt: t0, endedAt: t0.addingTimeInterval(s(50)), summary: "月初", durationSeconds: s(50)),
            WorkLogEntry(startedAt: cal.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 9))!,
                         endedAt: cal.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 9))!,
                         summary: "今日", durationSeconds: s(50)),
            WorkLogEntry(startedAt: cal.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 9))!,
                         endedAt: cal.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 9))!,
                         summary: "上月", durationSeconds: s(50)),
        ]
        let monthly = renderWorkLogReport(entries: entries, scope: .month, now: now, calendar: cal, timeZone: tz)
        expect(monthly.contains("按周拆解"), "月报应有按周拆解")
        expect(monthly.contains("W"), "按周拆解应含 ISO 周键（YYYY-Www）")

        let all = renderWorkLogReport(entries: entries, scope: .all, now: now, calendar: cal, timeZone: tz)
        expect(all.contains("按月汇总"), "全部应有按月汇总表")
        expect(all.contains("|---|---:|---:|"), "按月汇总应为时长右对齐 Markdown 表")
        expect(all.contains("2026-05") && all.contains("2026-06"), "按月汇总应跨月分行")
    }
}

private func minutes__(_ m: TimeInterval) -> TimeInterval { m * 60 }

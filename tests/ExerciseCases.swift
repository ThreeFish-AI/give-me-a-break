import Foundation
import GiveMeABreakEngine

// MARK: - Helpers

private var exDirCounter = 0
private func makeTempDir() -> URL {
    exDirCounter += 1
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("givemeabreak-exercise-test-\(exDirCounter)-\(ProcessInfo.processInfo.processIdentifier)")
    try? FileManager.default.removeItem(at: dir)
    return dir
}

private func utcCalendar() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private func utcTZ() -> TimeZone { TimeZone(identifier: "UTC")! }

private func exMinutes(_ m: TimeInterval) -> TimeInterval { m * 60 }

// MARK: - 入口

func runExerciseCases() {
    let s = exMinutes

    // MARK: ExerciseStore（镜像 WorkLogStore 范式）

    test("ExerciseStore round-trip + 顺序保持") {
        let store = try! ExerciseStore(directory: makeTempDir())
        let t0 = Date(timeIntervalSince1970: 0)
        store.append(ExerciseEntry(startedAt: t0, endedAt: t0.addingTimeInterval(s(10)),
                                   sets: [ExerciseSet(type: "深蹲", reps: 20)], note: "午后"))
        store.append(ExerciseEntry(startedAt: t0.addingTimeInterval(s(60)), endedAt: t0.addingTimeInterval(s(70)),
                                   sets: [ExerciseSet(type: "俯卧撑", reps: 15)]))
        let loaded = store.loadEntries()
        expectEqual(loaded.count, 2)
        expectEqual(loaded[0].sets.first?.type, "深蹲")
        expectEqual(loaded[1].sets.first?.type, "俯卧撑")
        expectEqual(loaded[0].note, "午后")
        expectEqual(loaded[1].note, nil, "空 note 应规约为 nil")
        expectEqual(loaded[0].totalReps, 20)
    }

    test("ExerciseStore 补录过去时段：按 startedAt 升序落库") {
        let store = try! ExerciseStore(directory: makeTempDir())
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        store.append(ExerciseEntry(startedAt: t0.addingTimeInterval(3600), endedAt: t0.addingTimeInterval(4200),
                                   sets: [ExerciseSet(type: "深蹲", reps: 20)]))
        store.append(ExerciseEntry(startedAt: t0, endedAt: t0.addingTimeInterval(600),
                                   sets: [ExerciseSet(type: "提膝击掌", reps: 40)]))
        let loaded = store.loadEntries()
        expectEqual(loaded.count, 2)
        expectEqual(loaded[0].sets.first?.type, "提膝击掌", "补录的更早条目应排到最前")
        expectEqual(loaded[0].startedAt, t0)
    }

    test("ExerciseStore 缺失/损坏文件 → 空列表") {
        let dir = makeTempDir()
        let store = try! ExerciseStore(directory: dir)
        expectEqual(store.loadEntries().count, 0, "无文件应返回空")
        let url = dir.appendingPathComponent("exercise-log.json")
        try! "{not json".data(using: .utf8)!.write(to: url, options: .atomic)
        expectEqual(store.loadEntries().count, 0, "损坏 JSON 应回退空")
    }

    test("ExerciseStore replaceAll 清空 + 排序") {
        let store = try! ExerciseStore(directory: makeTempDir())
        let t0 = Date(timeIntervalSince1970: 0)
        store.append(ExerciseEntry(startedAt: t0.addingTimeInterval(s(3)), endedAt: t0.addingTimeInterval(s(4)),
                                   sets: [ExerciseSet(type: "深蹲", reps: 1)]))
        store.replaceAll([])
        expectEqual(store.loadEntries().count, 0, "replaceAll([]) 应清空")
        store.replaceAll([
            ExerciseEntry(startedAt: t0.addingTimeInterval(s(3)), endedAt: t0.addingTimeInterval(s(4)), sets: [ExerciseSet(type: "晚", reps: 1)]),
            ExerciseEntry(startedAt: t0, endedAt: t0.addingTimeInterval(s(1)), sets: [ExerciseSet(type: "早", reps: 1)]),
        ])
        expectEqual(store.loadEntries().first?.sets.first?.type, "早", "应按 startedAt 升序")
    }

    test("ExerciseStore update 按 id 改写并重排；未命中 no-op") {
        let store = try! ExerciseStore(directory: makeTempDir())
        let t0 = Date(timeIntervalSince1970: 0)
        store.append(ExerciseEntry(id: "a", startedAt: t0, endedAt: t0.addingTimeInterval(s(10)),
                                   sets: [ExerciseSet(type: "深蹲", reps: 20)]))
        store.append(ExerciseEntry(id: "b", startedAt: t0.addingTimeInterval(s(60)), endedAt: t0.addingTimeInterval(s(70)),
                                   sets: [ExerciseSet(type: "俯卧撑", reps: 15)]))
        store.update(ExerciseEntry(id: "a", startedAt: t0.addingTimeInterval(s(120)), endedAt: t0.addingTimeInterval(s(130)),
                                   sets: [ExerciseSet(type: "深蹲", reps: 30)]))
        let loaded = store.loadEntries()
        expectEqual(loaded.count, 2, "update 不应改变条数")
        expectEqual(loaded[0].id, "b", "a 起始推后应重排到 b 之后")
        expectEqual(loaded[1].id, "a")
        expectEqual(loaded[1].totalReps, 30)
        store.update(ExerciseEntry(id: "zzz", startedAt: t0, endedAt: t0, sets: []))
        expectEqual(store.loadEntries().count, 2, "未命中 id 不应新增")
    }

    test("ExerciseStore delete 按 id 删除；删不存在不变") {
        let store = try! ExerciseStore(directory: makeTempDir())
        let t0 = Date(timeIntervalSince1970: 0)
        store.append(ExerciseEntry(id: "a", startedAt: t0, endedAt: t0.addingTimeInterval(s(1)), sets: [ExerciseSet(type: "深蹲", reps: 1)]))
        store.append(ExerciseEntry(id: "b", startedAt: t0.addingTimeInterval(s(60)), endedAt: t0.addingTimeInterval(s(61)), sets: [ExerciseSet(type: "俯卧撑", reps: 1)]))
        store.delete(id: "a")
        let loaded = store.loadEntries()
        expectEqual(loaded.count, 1)
        expectEqual(loaded[0].id, "b")
        store.delete(id: "nope")
        expectEqual(store.loadEntries().count, 1, "删不存在 id 列表不变")
    }

    test("ExerciseEntry/ExerciseSet 容错解码（缺字段补默认）") {
        // 缺 note/modelVersion；set 缺 reps
        let json = """
        [{"id":"x","startedAt":0,"endedAt":600,"sets":[{"type":"深蹲","reps":20},{"type":"俯卧撑"}]}]
        """.data(using: .utf8)!
        let decoded = try! JSONDecoder().decode([ExerciseEntry].self, from: json)
        expectEqual(decoded.count, 1)
        expectEqual(decoded[0].note, nil, "缺 note → nil")
        expectEqual(decoded[0].modelVersion, ExerciseEntry.currentModelVersion, "缺 modelVersion → 补当前版本")
        expectEqual(decoded[0].sets.count, 2)
        expectEqual(decoded[0].sets[1].reps, 0, "缺 reps → 0")
        expectEqual(decoded[0].totalReps, 20)
        // 缺 sets → 空数组
        let json2 = """
        [{"id":"y","startedAt":0,"endedAt":0}]
        """.data(using: .utf8)!
        let decoded2 = try! JSONDecoder().decode([ExerciseEntry].self, from: json2)
        expectEqual(decoded2[0].sets.count, 0, "缺 sets → 空数组")
    }

    // MARK: filterExerciseEntries（周/月/季/年分桶边界）

    test("filterExerciseEntries 周/月/季/年分桶（含跨季/跨年边界）") {
        let cal = utcCalendar(); let tz = utcTZ()
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 12))!
        func e(_ y: Int, _ mo: Int, _ da: Int) -> ExerciseEntry {
            let d = cal.date(from: DateComponents(year: y, month: mo, day: da, hour: 9))!
            return ExerciseEntry(startedAt: d, endedAt: d, sets: [ExerciseSet(type: "深蹲", reps: 10)])
        }
        let entries = [
            e(2026, 6, 25),  // 本周
            e(2026, 6, 22),  // 本周（周一）
            e(2026, 6, 10),  // 本月非本周
            e(2026, 4, 15),  // 本季（Q2）非本月
            e(2026, 1, 20),  // 本年非本季（Q1）
            e(2025, 12, 31), // 去年
        ]
        expectEqual(filterExerciseEntries(entries, scope: .week, now: now, calendar: cal, timeZone: tz).count, 2, "本周含 06-25 + 06-22")
        expectEqual(filterExerciseEntries(entries, scope: .month, now: now, calendar: cal, timeZone: tz).count, 3, "本月含 25/22/10")
        expectEqual(filterExerciseEntries(entries, scope: .quarter, now: now, calendar: cal, timeZone: tz).count, 4, "Q2 含 6 月 3 条 + 4 月 1 条")
        expectEqual(filterExerciseEntries(entries, scope: .year, now: now, calendar: cal, timeZone: tz).count, 5, "2026 全年 5 条（不含 2025-12-31）")
    }

    // MARK: exerciseTypeSummary（按类型聚合）

    test("exerciseTypeSummary 聚合（Σreps、记录条数、按数量降序）") {
        let t0 = Date(timeIntervalSince1970: 0)
        let entries = [
            ExerciseEntry(startedAt: t0, endedAt: t0, sets: [ExerciseSet(type: "深蹲", reps: 20), ExerciseSet(type: "俯卧撑", reps: 15)]),
            ExerciseEntry(startedAt: t0.addingTimeInterval(60), endedAt: t0.addingTimeInterval(60), sets: [ExerciseSet(type: "深蹲", reps: 30)]),
            ExerciseEntry(startedAt: t0.addingTimeInterval(120), endedAt: t0.addingTimeInterval(120), sets: [ExerciseSet(type: "提膝击掌", reps: 40)]),
        ]
        let rows = exerciseTypeSummary(entries)
        expectEqual(rows.count, 3)
        expectEqual(rows[0].key, "深蹲", "数量最多在前")
        expectEqual(rows[0].reps, 50)
        expectEqual(rows[0].sessions, 2, "深蹲出现在 2 条记录")
        expectEqual(rows[1].key, "提膝击掌"); expectEqual(rows[1].reps, 40)
        expectEqual(rows[2].key, "俯卧撑"); expectEqual(rows[2].reps, 15)
    }

    // MARK: buildCombinedReportModel（结构化模型）

    test("buildCombinedReportModel 结构（周：工作 Top/分布 + 运动按类型/明细；季：运动按月）") {
        let cal = utcCalendar(); let tz = utcTZ()
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 18))!
        let (work, exercise) = combinedFixture(cal: cal)

        let week = buildCombinedReportModel(workEntries: work, exerciseEntries: exercise, scope: .week, now: now, calendar: cal, timeZone: tz)
        expect(!week.isEmpty)
        expectEqual(week.work.sessionCount, 3, "本周工作 3 条")
        expectEqual(week.work.top.count, 3)
        expectEqual(week.work.top[0].durationSeconds, s(50), "最长工作在前（50m）")
        expectEqual(week.work.byPeriod.count, 2, "本周按日：06-22 与 06-25")
        expectEqual(week.exercise.sessionCount, 3, "本周运动 3 条")
        expectEqual(week.exercise.byType.first?.key, "深蹲")
        expectEqual(week.exercise.byType.first?.reps, 50, "深蹲 20+30")
        expectEqual(week.exercise.sessions.count, 3, "周报含逐条明细")
        expectEqual(week.exercise.byMonth.count, 0, "周报不含按月汇总")

        let quarter = buildCombinedReportModel(workEntries: work, exerciseEntries: exercise, scope: .quarter, now: now, calendar: cal, timeZone: tz)
        expectEqual(quarter.work.sessionCount, 5, "Q2 工作 5 条")
        expectEqual(quarter.exercise.sessionCount, 5, "Q2 运动 5 条")
        expectEqual(quarter.exercise.sessions.count, 0, "季报不含逐条明细")
        expectEqual(quarter.exercise.byMonth.count, 2, "季报按月：2026-04 与 2026-06")
        expectEqual(quarter.exercise.byMonth[0].key, "2026-04")
        expectEqual(quarter.exercise.byMonth[1].key, "2026-06")

        let empty = buildCombinedReportModel(workEntries: [], exerciseEntries: [], scope: .week, now: now, calendar: cal, timeZone: tz)
        expect(empty.isEmpty, "工作与运动均空 → isEmpty")
    }

    // MARK: renderCombinedReport（结构 + 幂等 + 空态）

    test("renderCombinedReport 结构与字节幂等") {
        let cal = utcCalendar(); let tz = utcTZ()
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 18))!
        let (work, exercise) = combinedFixture(cal: cal)
        let md1 = renderCombinedReport(workEntries: work, exerciseEntries: exercise, scope: .week, now: now, calendar: cal, timeZone: tz)
        let md2 = renderCombinedReport(workEntries: work, exerciseEntries: exercise, scope: .week, now: now, calendar: cal, timeZone: tz)
        expect(md1 == md2, "同输入两次渲染必须字节幂等")
        expect(md1.contains("# 综合报告 · 本周 · 2026-W26"), "应有 H1 标题与周期")
        expect(md1.contains("## 工作回顾"), "应有工作回顾段")
        expect(md1.contains("## 运动概览"), "应有运动概览段")
        expect(md1.contains("### 按类型"), "应有按类型表")
        expect(md1.contains("深蹲×20 + 俯卧撑×15"), "明细应展开多组动作")

        let quarter = renderCombinedReport(workEntries: work, exerciseEntries: exercise, scope: .quarter, now: now, calendar: cal, timeZone: tz)
        expect(quarter.contains("# 综合报告 · 本季 · 2026-Q2"), "季报标题")
        expect(quarter.contains("### 按月"), "季报运动应按月汇总而非逐条")
    }

    test("renderCombinedReport 全空占位") {
        let cal = utcCalendar()
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 18))!
        let md = renderCombinedReport(workEntries: [], exerciseEntries: [], scope: .year, now: now, calendar: cal, timeZone: utcTZ())
        expect(md.contains("# 综合报告 · 本年 · 2026"), "空也应渲染 H1")
        expect(md.contains("暂无记录"), "全空应含占位")
    }

    // MARK: golden 快照（重构安全网：锁定导出 Markdown 逐字节不变）

    test("renderCombinedReport golden 快照（周/月/季/年，字节一致）") {
        let cal = utcCalendar(); let tz = utcTZ()
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 18))!
        let (work, exercise) = combinedFixture(cal: cal)
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixtures")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for scope in CombinedReportScope.allCases {
            let md = renderCombinedReport(workEntries: work, exerciseEntries: exercise, scope: scope, now: now, calendar: cal, timeZone: tz)
            let file = dir.appendingPathComponent("combined_\(scope.rawValue).md")
            if let golden = try? String(contentsOf: file, encoding: .utf8) {
                expectEqual(md, golden, "renderCombinedReport(\(scope.rawValue)) 偏离 golden 快照——重构破坏了导出 Markdown")
            } else {
                try? md.data(using: .utf8)?.write(to: file, options: .atomic)
                print("  · golden bootstrap 写入 fixtures/\(file.lastPathComponent)")
            }
        }
    }

    // MARK: 纯函数（exerciseBackfillDefaultRange / appendedExerciseTypes）

    test("exerciseBackfillDefaultRange：以 now 为终点、restDuration 为跨度回溯") {
        let now = Date(timeIntervalSince1970: 1_000_000)
        // 10 分钟休息
        let r10 = exerciseBackfillDefaultRange(now: now, restDurationSeconds: 600)
        expect(approx(r10.end.timeIntervalSince1970, 1_000_000, 0.001), "end 应为 now")
        expect(approx(r10.start.timeIntervalSince1970, 1_000_000 - 600, 0.001), "start 应为 now − 600s")
        expect(r10.start < r10.end, "start 必须早于 end")

        // 0 / 负休息时长裁剪为 0（start == end，不产生负跨度）
        let r0 = exerciseBackfillDefaultRange(now: now, restDurationSeconds: 0)
        expectEqual(r0.start, r0.end, "0 时长 → start == end")
        let rNeg = exerciseBackfillDefaultRange(now: now, restDurationSeconds: -300)
        expectEqual(rNeg.start, rNeg.end, "负时长裁剪为 0 → start == end")
    }

    test("appendedExerciseTypes：仅追加新类型，去重、保序、去空白") {
        let current = ["深蹲", "俯卧撑"]
        let sets = [
            ExerciseSet(type: "深蹲", reps: 20),       // 已存在 → 跳过
            ExerciseSet(type: "平板支撑", reps: 30),    // 新 → 追加
            ExerciseSet(type: "  开合跳  ", reps: 15),  // 新 + 需去空白 → 追加「开合跳」
            ExerciseSet(type: "平板支撑", reps: 12),    // 重复新 → 去重
            ExerciseSet(type: "", reps: 5),            // 空白 → 跳过
            ExerciseSet(type: "   ", reps: 5)          // 纯空白 → 跳过
        ]
        let updated = appendedExerciseTypes(current: current, sets: sets)
        expectEqual(updated, ["深蹲", "俯卧撑", "平板支撑", "开合跳"], "应按出现顺序追加去空白后的新类型，去重")
    }

    test("appendedExerciseTypes：无新类型返回 nil（调用方据此跳过写盘）") {
        let current = ["深蹲", "俯卧撑"]
        let sets = [ExerciseSet(type: "深蹲", reps: 20), ExerciseSet(type: "俯卧撑", reps: 10)]
        expect(appendedExerciseTypes(current: current, sets: sets) == nil, "全为已存在类型 → nil")
        expect(appendedExerciseTypes(current: current, sets: []) == nil, "空 sets → nil")
    }
}

/// golden / 模型测试共用 fixture：工作 + 运动跨周/月/季/年，覆盖各序列化分支。
/// now = 2026-06-25（周四，2026-W26，Q2）。
private func combinedFixture(cal: Calendar) -> (work: [WorkLogEntry], exercise: [ExerciseEntry]) {
    func d(_ y: Int, _ mo: Int, _ da: Int, _ h: Int, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: da, hour: h, minute: mi))!
    }
    let work = [
        WorkLogEntry(id: "w1", startedAt: d(2026, 6, 25, 9), endedAt: d(2026, 6, 25, 9, 50), summary: "调试登录 bug", nextAction: "补单测", durationSeconds: 50 * 60),
        WorkLogEntry(id: "w2", startedAt: d(2026, 6, 25, 10), endedAt: d(2026, 6, 25, 10, 50), summary: "写周报第一稿", durationSeconds: 50 * 60),
        WorkLogEntry(id: "w3", startedAt: d(2026, 6, 22, 9), endedAt: d(2026, 6, 22, 9, 30), summary: "周一立项", durationSeconds: 30 * 60),
        WorkLogEntry(id: "w4", startedAt: d(2026, 6, 10, 9), endedAt: d(2026, 6, 10, 9, 40), summary: "需求评审", durationSeconds: 40 * 60),
        WorkLogEntry(id: "w5", startedAt: d(2026, 4, 15, 9), endedAt: d(2026, 4, 15, 9, 20), summary: "季度规划", durationSeconds: 20 * 60),
        WorkLogEntry(id: "w6", startedAt: d(2026, 1, 20, 9), endedAt: d(2026, 1, 20, 10), summary: "年初目标", durationSeconds: 60 * 60),
    ]
    let exercise = [
        ExerciseEntry(id: "e1", startedAt: d(2026, 6, 25, 10, 50), endedAt: d(2026, 6, 25, 11), sets: [ExerciseSet(type: "深蹲", reps: 20), ExerciseSet(type: "俯卧撑", reps: 15)], note: "午后"),
        ExerciseEntry(id: "e2", startedAt: d(2026, 6, 25, 15), endedAt: d(2026, 6, 25, 15, 10), sets: [ExerciseSet(type: "深蹲", reps: 30)]),
        ExerciseEntry(id: "e3", startedAt: d(2026, 6, 22, 9, 30), endedAt: d(2026, 6, 22, 9, 40), sets: [ExerciseSet(type: "提膝击掌", reps: 40)]),
        ExerciseEntry(id: "e4", startedAt: d(2026, 6, 10, 9, 40), endedAt: d(2026, 6, 10, 9, 50), sets: [ExerciseSet(type: "胯下击掌", reps: 50)]),
        ExerciseEntry(id: "e5", startedAt: d(2026, 4, 15, 9, 20), endedAt: d(2026, 4, 15, 9, 30), sets: [ExerciseSet(type: "深蹲", reps: 25), ExerciseSet(type: "俯卧撑", reps: 10)]),
        ExerciseEntry(id: "e6", startedAt: d(2026, 1, 20, 10), endedAt: d(2026, 1, 20, 10, 10), sets: [ExerciseSet(type: "俯卧撑", reps: 20)]),
    ]
    return (work, exercise)
}

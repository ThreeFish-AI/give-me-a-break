import Foundation

// MARK: - 工作日志报告（纯函数：零副作用、确定性、可单测）

/// 报告周期粒度。`now` + `timeZone` 决定「今日/本周/本月」的边界。
public enum WorkLogReportScope: String, Equatable, Sendable {
    case today
    case week
    case month
    case all
}

/// 将秒数格式化为人类可读时长：「1h 30m」/「45m」/「2h」/「0m」。用于报告与提示上下文。
public func humanizedDuration(_ seconds: TimeInterval) -> String {
    let totalMin = max(0, Int((seconds / 60).rounded()))
    let h = totalMin / 60
    let m = totalMin % 60
    if h > 0 && m > 0 { return "\(h)h \(m)m" }
    if h > 0 { return "\(h)h" }
    return "\(m)m"
}

/// 按 `scope` 过滤条目（以 `startedAt` 在指定时区分桶）。返回保持时间升序。
public func filterWorkLogEntries(
    _ entries: [WorkLogEntry],
    scope: WorkLogReportScope,
    now: Date,
    calendar: Calendar,
    timeZone: TimeZone
) -> [WorkLogEntry] {
    let cal = isoCalendar(base: calendar, timeZone: timeZone)
    let nowDay = dayKey(now, calendar: cal)
    let nowMonth = monthKey(now, calendar: cal)
    let nowWeek = weekKey(now, calendar: cal)
    return entries.filter { e in
        switch scope {
        case .today:  return dayKey(e.startedAt, calendar: cal) == nowDay
        case .week:   return weekKey(e.startedAt, calendar: cal) == nowWeek
        case .month:  return monthKey(e.startedAt, calendar: cal) == nowMonth
        case .all:    return true
        }
    }.sorted { $0.startedAt < $1.startedAt }
}

/// 渲染 Markdown 报告（确定性幂等：同 entries + 同 now/cal/tz → 字节一致）。
/// 结构：恰好一个 H1（标题+周期）+ blockquote 元数据 + 周期专属章节（Top 3 / 按日或按周拆解 / 待续·下一步）。
public func renderWorkLogReport(
    entries: [WorkLogEntry],
    scope: WorkLogReportScope,
    now: Date,
    calendar: Calendar,
    timeZone: TimeZone
) -> String {
    let cal = isoCalendar(base: calendar, timeZone: timeZone)
    let scoped = filterWorkLogEntries(entries, scope: scope, now: now, calendar: calendar, timeZone: timeZone)
    let tz = timeZoneIdentifier(timeZone)

    var out = ""
    out += reportTitle(scope: scope, now: now, calendar: cal) + "\n\n"
    out += metaBlock(scope: scope, entries: scoped, now: now, calendar: cal, timeZone: tz) + "\n"

    if scoped.isEmpty {
        out += "\n_（暂无记录）_\n"
        return out
    }

    // Top 3（按时长降序，并列按时间升序）
    out += topThreeSection(title: topThreeTitle(scope: scope), entries: scoped)

    // 按日/按周拆解
    switch scope {
    case .today, .all:
        break  // today 的明细见「完成清单」；all 见「按月汇总」
    case .week:
        out += byDaySection(entries: scoped, calendar: cal)
    case .month:
        out += byWeekSection(entries: scoped, calendar: cal)
    }

    // 明细 / 汇总表
    switch scope {
    case .today:
        out += todayDetailSection(entries: scoped, calendar: cal)
    case .all:
        out += byMonthSummaryTable(entries: scoped, calendar: cal)
    default:
        break
    }

    // 待续 · 下一步
    out += nextActionsSection(entries: scoped)
    return out
}

// MARK: - 章节渲染

private func topThreeSection(title: String, entries: [WorkLogEntry]) -> String {
    let top = entries
        .sorted { lhs, rhs in
            lhs.durationSeconds != rhs.durationSeconds
                ? lhs.durationSeconds > rhs.durationSeconds
                : lhs.startedAt < rhs.startedAt
        }
        .prefix(3)
    var s = "## \(title)\n\n"
    if top.isEmpty {
        s += "_（暂无）_\n\n"
        return s
    }
    for e in top {
        s += "- \(e.summary)（\(humanizedDuration(e.durationSeconds))）\n"
    }
    s += "\n"
    return s
}

private func byDaySection(entries: [WorkLogEntry], calendar: Calendar) -> String {
    let groups = groupByDay(entries, calendar: calendar)  // [(dayKey, [entries])] 升序
    var s = "## 按日拆解\n\n"
    for (key, list) in groups {
        let total = list.reduce(0) { $0 + $1.durationSeconds }
        let wd = list.first!.startedAt
        s += "### \(key) \(weekdayCN(wd, calendar: calendar)) · \(humanizedDuration(total))\n\n"
        s += entryBullets(list, calendar: calendar)
        s += "\n"
    }
    return s
}

private func byWeekSection(entries: [WorkLogEntry], calendar: Calendar) -> String {
    let groups = groupByWeek(entries, calendar: calendar)  // [(weekKey, [entries])] 升序
    var s = "## 按周拆解\n\n"
    for (key, list) in groups {
        let total = list.reduce(0) { $0 + $1.durationSeconds }
        s += "### \(key) · \(list.count) 条 · \(humanizedDuration(total))\n\n"
        s += entryBullets(list, calendar: calendar)
        s += "\n"
    }
    return s
}

private func todayDetailSection(entries: [WorkLogEntry], calendar: Calendar) -> String {
    var s = "## 完成清单\n\n"
    s += entryBullets(entries, calendar: calendar)
    s += "\n"
    return s
}

private func byMonthSummaryTable(entries: [WorkLogEntry], calendar: Calendar) -> String {
    let groups = groupByMonth(entries, calendar: calendar)  // 升序
    var s = "## 按月汇总\n\n"
    s += "| 月份 | 条数 | 专注 |\n"
    s += "|---|---:|---:|\n"
    for (key, list) in groups {
        let total = list.reduce(0) { $0 + $1.durationSeconds }
        s += "| \(key) | \(list.count) | \(humanizedDuration(total)) |\n"
    }
    s += "\n"
    return s
}

private func nextActionsSection(entries: [WorkLogEntry]) -> String {
    let actions = entries.compactMap { $0.nextAction }
    guard !actions.isEmpty else { return "" }
    var s = "## 待续 · 下一步\n\n"
    for a in actions { s += "- \(a)\n" }
    s += "\n"
    return s
}

/// 单条记录的 Markdown 项目符号（时间序）：`- **HH:mm** · {时长} — {summary}`，nextAction 以引用块附。
private func entryBullets(_ entries: [WorkLogEntry], calendar: Calendar) -> String {
    var s = ""
    for e in entries {
        s += "- **\(hhmm(e.startedAt, calendar: calendar))** · \(humanizedDuration(e.durationSeconds)) — \(e.summary)\n"
        if let na = e.nextAction {
            s += "  > 下一步：\(na)\n"
        }
    }
    return s
}

// MARK: - 标题 / 元数据块

private func reportTitle(scope: WorkLogReportScope, now: Date, calendar: Calendar) -> String {
    switch scope {
    case .today:
        return "# 今日工作回顾 · \(dayKey(now, calendar: calendar)) \(weekdayCN(now, calendar: calendar))"
    case .week:
        return "# 本周工作回顾 · \(weekKey(now, calendar: calendar))"
    case .month:
        return "# 本月工作回顾 · \(monthKey(now, calendar: calendar))"
    case .all:
        return "# 工作日志 · 全部记录"
    }
}

private func metaBlock(scope: WorkLogReportScope, entries: [WorkLogEntry], now: Date, calendar: Calendar, timeZone: String) -> String {
    let count = entries.count
    let total = entries.reduce(0) { $0 + $1.durationSeconds }
    let days = Set(entries.map { dayKey($0.startedAt, calendar: calendar) }).count
    switch scope {
    case .today:
        return "> 周期 \(dayKey(now, calendar: calendar))（\(timeZone)） · \(count) 条记录 · 专注 \(humanizedDuration(total))\n"
    case .week:
        return "> 周期 \(weekKey(now, calendar: calendar))（\(timeZone)） · \(count) 条 · 专注 \(humanizedDuration(total)) · \(days) 天\n"
    case .month:
        return "> 周期 \(monthKey(now, calendar: calendar))（\(timeZone)） · \(count) 条 · 专注 \(humanizedDuration(total)) · \(days) 天\n"
    case .all:
        if let earliest = entries.map(\.startedAt).min(), let latest = entries.map(\.startedAt).max() {
            return "> \(timeZone) · \(count) 条 · 专注 \(humanizedDuration(total)) · \(days) 天 · 自 \(dayKey(earliest, calendar: calendar)) 至 \(dayKey(latest, calendar: calendar))\n"
        }
        return "> \(timeZone) · 0 条 · 专注 0m\n"
    }
}

private func topThreeTitle(scope: WorkLogReportScope) -> String {
    switch scope {
    case .today: return "今日 Top 3"
    case .week:  return "本周三件事"
    case .month: return "本月 Top 3"
    case .all:   return "全部 Top 3"
    }
}

// MARK: - 分组（保持键升序）

private func groupByDay(_ entries: [WorkLogEntry], calendar: Calendar) -> [(String, [WorkLogEntry])] {
    var dict: [String: [WorkLogEntry]] = [:]
    for e in entries {
        let key = dayKey(e.startedAt, calendar: calendar)
        dict[key, default: []].append(e)
    }
    return dict.sorted { $0.key < $1.key }
}

private func groupByWeek(_ entries: [WorkLogEntry], calendar: Calendar) -> [(String, [WorkLogEntry])] {
    var dict: [String: [WorkLogEntry]] = [:]
    for e in entries {
        let key = weekKey(e.startedAt, calendar: calendar)
        dict[key, default: []].append(e)
    }
    return dict.sorted { $0.key < $1.key }
}

private func groupByMonth(_ entries: [WorkLogEntry], calendar: Calendar) -> [(String, [WorkLogEntry])] {
    var dict: [String: [WorkLogEntry]] = [:]
    for e in entries {
        let key = monthKey(e.startedAt, calendar: calendar)
        dict[key, default: []].append(e)
    }
    return dict.sorted { $0.key < $1.key }
}

// MARK: - 日期格式化（手动拼接，零 locale 依赖，确定性）

/// ISO 周历（周一为首日、首周含首个周四）。复用传入 calendar 的 timeZone。
private func isoCalendar(base: Calendar, timeZone: TimeZone) -> Calendar {
    var c = base
    c.timeZone = timeZone
    c.firstWeekday = 2                  // 周一
    c.minimumDaysInFirstWeek = 4        // ISO 8601
    return c
}

private func dayKey(_ date: Date, calendar: Calendar) -> String {
    let p = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0)
}

private func monthKey(_ date: Date, calendar: Calendar) -> String {
    let p = calendar.dateComponents([.year, .month], from: date)
    return String(format: "%04d-%02d", p.year ?? 0, p.month ?? 0)
}

private func weekKey(_ date: Date, calendar: Calendar) -> String {
    // calendar 已配置为 ISO 8601（周一首日、首周含首个周四）：
    // yearForWeekOfYear + weekOfYear 即 ISO 周日期（YYYY-Www）。
    let yearForWeek = calendar.component(.yearForWeekOfYear, from: date)
    let week = calendar.component(.weekOfYear, from: date)
    return String(format: "%04d-W%02d", yearForWeek, week)
}

private func hhmm(_ date: Date, calendar: Calendar) -> String {
    let p = calendar.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", p.hour ?? 0, p.minute ?? 0)
}

private func weekdayCN(_ date: Date, calendar: Calendar) -> String {
    // Calendar.weekday：1=周日 … 7=周六
    switch calendar.component(.weekday, from: date) {
    case 1: return "周日"
    case 2: return "周一"
    case 3: return "周二"
    case 4: return "周三"
    case 5: return "周四"
    case 6: return "周五"
    case 7: return "周六"
    default: return ""
    }
}

private func timeZoneIdentifier(_ tz: TimeZone) -> String {
    tz.identifier
}

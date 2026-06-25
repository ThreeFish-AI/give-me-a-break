using System.Globalization;
using TimeoutEngine;

namespace TimeoutEngine.Graph;

// MARK: - 纯函数：Graph 事件 → 合并后的 MeetingTimeline
// 对齐 macOS LiveCalendarProvider.refresh 的 filter（busy/tentative）/map（DateRange）/merge（mergeBusyIntervals）。

public static class GraphTimelineMapper
{
    /// <summary>门控保留的 showAs 值（对齐 macOS availability == .busy || .tentative）。</summary>
    private static readonly HashSet<string> BusyShowAs =
        new(StringComparer.OrdinalIgnoreCase) { "busy", "tentative" };

    /// <summary>Graph 事件 → MeetingTimeline（filter busy/tentative，排除 isAllDay，复用 Engine.MergeBusyIntervals）。</summary>
    public static MeetingTimeline ToTimeline(IEnumerable<GraphEvent?> events, DateTimeOffset generatedAt)
    {
        var ranges = new List<DateRange>();
        foreach (var e in events)
        {
            if (e is null) continue;
            if (e.IsAllDay is true) continue;                              // 排除全天（非"会议"）
            if (e.ShowAs is null || !BusyShowAs.Contains(e.ShowAs)) continue;  // 仅 busy/tentative
            if (!TryParse(e.Start, out var start)) continue;
            if (!TryParse(e.End, out var end)) continue;
            if (end <= start) continue;                                    // 丢弃非法区间（瞬时/颠倒）
            ranges.Add(new DateRange(start, end));
        }
        var merged = Engine.MergeBusyIntervals(ranges);
        return new MeetingTimeline(merged, generatedAt);
    }

    /// <summary>Graph dateTime（Prefer UTC 下无偏移）→ DateTimeOffset。
    /// AssumeUniversal：无偏移字符串当 UTC（对齐请求头 Prefer: outlook.timezone="UTC"）。</summary>
    private static bool TryParse(GraphDateTimeTimeZone? dtz, out DateTimeOffset value)
    {
        value = default;
        if (dtz?.DateTime is null) return false;
        return DateTimeOffset.TryParse(dtz.DateTime, CultureInfo.InvariantCulture,
            DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out value);
    }
}

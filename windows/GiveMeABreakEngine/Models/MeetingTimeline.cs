namespace TimeoutEngine;

// 镜像 Sources/TimeoutEngine/Models.swift · MeetingTimeline。
// 合并后的忙碌时间线（会议展平为不相交区间）。

/// <summary>合并后的忙碌时间线（会议展平为不相交区间）。</summary>
public sealed class MeetingTimeline
{
    public List<DateRange> BusyIntervals { get; set; } = new();
    public DateTimeOffset GeneratedAt { get; set; } = DateTimeOffset.FromUnixTimeSeconds(0);

    public MeetingTimeline() { }

    public MeetingTimeline(List<DateRange>? busyIntervals = null, DateTimeOffset? generatedAt = null)
    {
        BusyIntervals = busyIntervals ?? new List<DateRange>();
        GeneratedAt = generatedAt ?? DateTimeOffset.FromUnixTimeSeconds(0);
    }

    public static MeetingTimeline Empty { get; } = new MeetingTimeline();

    public DateRange? ActiveMeeting(DateTimeOffset now)
    {
        foreach (var iv in BusyIntervals)
            if (iv.Contains(now)) return iv;
        return null;
    }
}

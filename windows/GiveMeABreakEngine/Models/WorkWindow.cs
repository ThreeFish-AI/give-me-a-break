namespace TimeoutEngine;

// MARK: - 工作窗口
// 镜像 Sources/TimeoutEngine/Models.swift · WorkWindow。一天内的「工作时段」，支持跨午夜。

/// <summary>一天内的「工作时段」（如 09:00–12:00），每日重复。支持跨午夜。</summary>
public sealed class WorkWindow : IEquatable<WorkWindow>
{
    public TimeOfDay Start { get; set; }
    public TimeOfDay End { get; set; }

    public WorkWindow() { }

    public WorkWindow(TimeOfDay start, TimeOfDay end)
    {
        Start = start;
        End = end;
    }

    /// <summary>是否跨越午夜（start > end，如 22:00–02:00）。</summary>
    public bool CrossesMidnight => Start.RawValue > End.RawValue;

    public bool Contains(int secondsSinceMidnight)
    {
        if (CrossesMidnight)
            return secondsSinceMidnight >= Start.RawValue || secondsSinceMidnight < End.RawValue;
        return secondsSinceMidnight >= Start.RawValue && secondsSinceMidnight < End.RawValue;
    }

    /// <summary>按 date 在其偏移量下的「时分秒」判定（对齐 Swift 在指定 calendar/timeZone 下的取值）。
    /// 运行与测试须使用一致的时区（测试用 UTC）。</summary>
    public bool Contains(DateTimeOffset date)
    {
        var t = date.TimeOfDay;
        int s = (int)Math.Floor(t.TotalSeconds);
        return Contains(s);
    }

    public bool Equals(WorkWindow? other)
        => other is not null && Start == other.Start && End == other.End;
    public override bool Equals(object? obj) => obj is WorkWindow w && Equals(w);
    public override int GetHashCode() => HashCode.Combine(Start, End);
}

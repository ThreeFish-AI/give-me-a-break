namespace TimeoutEngine;

// MARK: - 会议时间线
// 镜像 Sources/TimeoutEngine/Models.swift · DateRange。半开区间 [start, end)。

/// <summary>半开区间 [start, end)：end 时刻视为已结束。</summary>
public sealed class DateRange : IEquatable<DateRange>
{
    public DateTimeOffset Start { get; set; }
    public DateTimeOffset End { get; set; }

    public DateRange() { }

    public DateRange(DateTimeOffset start, DateTimeOffset end)
    {
        if (end < start)
            throw new ArgumentOutOfRangeException(nameof(end), "DateRange end 必须 >= start");
        Start = start;
        End = end;
    }

    public bool Contains(DateTimeOffset date) => date >= Start && date < End;

    public bool Equals(DateRange? other)
        => other is not null && Start == other.Start && End == other.End;
    public override bool Equals(object? obj) => obj is DateRange d && Equals(d);
    public override int GetHashCode() => HashCode.Combine(Start, End);
}

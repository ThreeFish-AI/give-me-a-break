using System.Text.Json.Serialization;

namespace TimeoutEngine;

// MARK: - 当日时刻
// 镜像 Sources/TimeoutEngine/Models.swift · TimeOfDay（RawRepresentable<Int>）。
// JSON 序列化为裸整数 rawValue，对齐 Swift Codable（见 _JsonConverters.cs）。

/// <summary>自午夜起的秒数 [0, 86400)，可持久化。</summary>
[JsonConverter(typeof(TimeOfDayJsonConverter))]
public readonly struct TimeOfDay : IEquatable<TimeOfDay>
{
    /// <summary>自午夜起的秒数。</summary>
    public int RawValue { get; }

    public TimeOfDay(int rawValue)
    {
        if (rawValue < 0 || rawValue >= 86_400)
            throw new ArgumentOutOfRangeException(nameof(rawValue), "TimeOfDay 必须落在 [0, 86400) 区间");
        RawValue = rawValue;
    }

    public TimeOfDay(int hours = 0, int minutes = 0, int seconds = 0)
        : this(hours * 3600 + minutes * 60 + seconds) { }

    public int HourComponent => RawValue / 3600;
    public int MinuteComponent => (RawValue % 3600) / 60;
    public int SecondComponent => RawValue % 60;

    public bool Equals(TimeOfDay other) => RawValue == other.RawValue;
    public override bool Equals(object? obj) => obj is TimeOfDay t && Equals(t);
    public override int GetHashCode() => RawValue;
    public static bool operator ==(TimeOfDay a, TimeOfDay b) => a.Equals(b);
    public static bool operator !=(TimeOfDay a, TimeOfDay b) => !a.Equals(b);

    public override string ToString()
        => $"TimeOfDay({HourComponent}:{MinuteComponent:D2}:{SecondComponent:D2})";
}

namespace TimeoutEngine;

// MARK: - 快照（evaluate 纯函数的输入，零时间依赖）
// 镜像 Sources/TimeoutEngine/Models.swift · EngineSnapshot。

/// <summary>evaluate 纯函数的输入快照。</summary>
public readonly struct EngineSnapshot
{
    public DateTimeOffset Now { get; }
    public bool InWorkWindow { get; }
    public bool IsAFK { get; }
    public bool IsAsleep { get; }
    public DateRange? ActiveMeeting { get; }
    public double WorkAccumulatedSeconds { get; }
    public double WorkIntervalSeconds { get; }

    public EngineSnapshot(DateTimeOffset now, bool inWorkWindow, bool isAFK, bool isAsleep,
        DateRange? activeMeeting, double workAccumulatedSeconds, double workIntervalSeconds)
    {
        Now = now;
        InWorkWindow = inWorkWindow;
        IsAFK = isAFK;
        IsAsleep = isAsleep;
        ActiveMeeting = activeMeeting;
        WorkAccumulatedSeconds = workAccumulatedSeconds;
        WorkIntervalSeconds = workIntervalSeconds;
    }

    /// <summary>以 workAccum = 0 重新评估时构造的快照（镜像 Engine.swift zeroingAccumulator）。</summary>
    internal EngineSnapshot ZeroingAccumulator()
        => new EngineSnapshot(Now, InWorkWindow, IsAFK, IsAsleep, ActiveMeeting, 0, WorkIntervalSeconds);
}

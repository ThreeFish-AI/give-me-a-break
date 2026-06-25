using TimeoutEngine;

namespace TimeoutEngine.Tests;

// MARK: - Mocks（镜像 tests/EngineWiringCases.swift · Mocks）
// 仅用于注入 LiveTimeoutEngine，记录控制器调用序列，断言副作用分发。

internal sealed class MockClock : IClock
{
    public DateTimeOffset Value { get; private set; }
    public MockClock(DateTimeOffset initial) { Value = initial; }
    public DateTimeOffset Now() => Value;
    public MockClock AdvanceBy(double seconds) { Value = Value.AddSeconds(seconds); return this; }
}

internal sealed class MockOverlay : IOverlayController
{
    public int ShowCount { get; private set; }
    public int DismissCount { get; private set; }
    public DateTimeOffset? LastDeadline { get; private set; }
    public void Show(DateTimeOffset restDeadline) { ShowCount++; LastDeadline = restDeadline; }
    public void Dismiss() { DismissCount++; }
    public bool IsShown => ShowCount > DismissCount;
}

internal sealed class MockMusic : IMusicController
{
    public int StartCount { get; private set; }
    public int PauseCount { get; private set; }
    public DayPlanConfig? LastConfig { get; private set; }
    public void UpdateConfig(DayPlanConfig config) { LastConfig = config; }
    public void StartPlayback() { StartCount++; }
    public void PausePlayback() { PauseCount++; }
}

internal sealed class StubCalendar : ICalendarProvider
{
    public MeetingTimeline Timeline { get; set; } = MeetingTimeline.Empty;
    public MeetingTimeline CurrentTimeline() => Timeline;
}

internal sealed class MockSystemState : ISystemStateProvider
{
    public bool Asleep { get; set; }
    public double IdleValue { get; set; }
    public bool IsAsleep => Asleep;
    public double IdleSeconds() => IdleValue;
}

// MARK: - Helpers

internal static class TestHelpers
{
    public static DateTimeOffset Epoch(long seconds) => DateTimeOffset.FromUnixTimeSeconds(seconds);
    public static DateTimeOffset Epoch0 => DateTimeOffset.FromUnixTimeSeconds(0);
    public static double Minutes(double m) => m * 60;

    /// <summary>全天工作窗口（0:00–23:59），镜像 Swift fullDayConfig。</summary>
    public static DayPlanConfig FullDayConfig(double intervalSec, double restSec) => new()
    {
        WorkWindows = new() { new WorkWindow(new TimeOfDay(0, 0), new TimeOfDay(23, 59)) },
        WorkIntervalSeconds = intervalSec,
        RestDurationSeconds = restSec,
    };

    /// <summary>以 step（默认 60s）粒度驱动引擎 tick。step ≤ maxDelta(60) 保证不触发限幅损失。
    /// 镜像 tests/EngineWiringCases.swift · runTicks。</summary>
    public static void RunTicks(LiveTimeoutEngine engine, MockClock clock, double seconds, double step = 60)
    {
        double elapsed = 0;
        while (elapsed < seconds)
        {
            double s = Math.Min(step, seconds - elapsed);
            clock.AdvanceBy(s);
            engine.Tick();
            elapsed += s;
        }
    }

    /// <summary>浮点近似比对（镜像 Swift approx，默认 eps=2）。</summary>
    public static bool Approx(double a, double b, double eps = 2) => Math.Abs(a - b) < eps;
}

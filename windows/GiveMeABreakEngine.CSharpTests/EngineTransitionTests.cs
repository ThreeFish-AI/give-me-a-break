using Xunit;
using TimeoutEngine;

namespace TimeoutEngine.Tests;

// MARK: - B 层 · 时序场景镜像测试（镜像 tests/EngineTransitionCases.swift）
// 忠实重写 Swift Simulator（1Hz tick），每个测试注释标注对应 Swift 用例名，便于交叉 code review。

/// <summary>忠实模拟 1Hz 心跳：advance → transition → sideEffects，记录非空副作用跃迁。
/// 镜像 tests/EngineTransitionCases.swift · Simulator。</summary>
internal sealed class Simulator
{
    internal sealed record TransitionRecord(
        DateTimeOffset At, EnginePhase From, EnginePhase To,
        SideEffects Effects, double AccumAfter, DateTimeOffset? RestStartedAt);

    public DayPlanConfig Config { get; }
    private readonly List<DateRange> _meetings;
    private readonly Func<DateTimeOffset, bool> _inWindow;
    public EngineState State { get; private set; }
    public List<TransitionRecord> Records { get; } = new();

    public Simulator(DateTimeOffset t0, DayPlanConfig config, List<DateRange>? meetings = null, Func<DateTimeOffset, bool>? inWindow = null)
    {
        Config = config;
        _meetings = meetings ?? new();
        _inWindow = inWindow ?? (_ => true);
        // 初始即处于稳态（若在窗口内则 working），避免冷启动首 tick 的累计损失影响短间隔精度。
        State = new() { Phase = _inWindow(t0) ? EnginePhase.Working : EnginePhase.OffDuty, LastTickAt = t0 };
    }

    private EngineSnapshot Snapshot(DateTimeOffset now)
    {
        var timeline = new MeetingTimeline(Engine.MergeBusyIntervals(_meetings));
        return new(now, _inWindow(now), false, false, timeline.ActiveMeeting(now),
            State.WorkAccumulatedSeconds, Config.WorkIntervalSeconds);
    }

    /// <summary>以 1s 粒度 tick 到 target（避免粗粒度触发 advance 限幅）。</summary>
    public Simulator TickTo(DateTimeOffset target)
    {
        while (State.LastTickAt < target)
        {
            double step = Math.Min(1.0, (target - State.LastTickAt).TotalSeconds);
            var next = State.LastTickAt.AddSeconds(step);
            var oldPhase = State.Phase;
            State = Engine.Advance(State, next);
            var snap = Snapshot(next);
            State = Engine.Transition(State, snap, Config);
            var eff = Engine.SideEffectsOf(oldPhase, State.Phase);
            if (!eff.Equals(SideEffects.Empty))
                Records.Add(new(next, oldPhase, State.Phase, eff, State.WorkAccumulatedSeconds, State.RestStartedAt));
        }
        return this;
    }

    public EnginePhase Phase => State.Phase;
    public double Accum => State.WorkAccumulatedSeconds;
}

public class EngineTransitionTests
{
    private static DateTimeOffset T0 => TestHelpers.Epoch0;

    // 镜像 EngineTransitionCases "U1 工作示例：会议推迟休息 30+30→60→10"
    [Fact]
    public void U1_WorkExample_MeetingDefersRest()
    {
        var config = new DayPlanConfig { WorkIntervalSeconds = TestHelpers.Minutes(50), RestDurationSeconds = TestHelpers.Minutes(10) };
        var meetings = new List<DateRange> { new(T0.AddSeconds(TestHelpers.Minutes(30)), T0.AddSeconds(TestHelpers.Minutes(60))) };
        var sim = new Simulator(T0, config, meetings);

        sim.TickTo(T0.AddSeconds(TestHelpers.Minutes(29)));
        Assert.Equal(EnginePhase.Working, sim.Phase);
        Assert.True(TestHelpers.Approx(sim.Accum, TestHelpers.Minutes(29)));

        sim.TickTo(T0.AddSeconds(TestHelpers.Minutes(50)));
        Assert.Equal(EnginePhase.InMeeting, sim.Phase);   // t=50 在会议中，休息被推迟
        Assert.True(sim.Accum >= TestHelpers.Minutes(50));

        sim.TickTo(T0.AddSeconds(TestHelpers.Minutes(60)));
        Assert.Equal(EnginePhase.Resting, sim.Phase);     // t=60 会议结束触发休息
        var enter = sim.Records.Last(r => r.To == EnginePhase.Resting);
        Assert.True(enter.Effects.ShowOverlay);
        Assert.True(enter.Effects.StartMusic);
        Assert.Equal(T0.AddSeconds(TestHelpers.Minutes(60)).ToUnixTimeSeconds(),
                     enter.RestStartedAt!.Value.ToUnixTimeSeconds());

        sim.TickTo(T0.AddSeconds(TestHelpers.Minutes(70)));
        Assert.Equal(EnginePhase.Working, sim.Phase);
        var exit = sim.Records.Last(r => r.From == EnginePhase.Resting);
        Assert.True(exit.Effects.DismissOverlay);
        Assert.True(exit.Effects.PauseMusic);
        Assert.True(TestHelpers.Approx(sim.Accum, 0, 0.001));
    }

    // 镜像 EngineTransitionCases "U2 会议恰在阈值点开始 → 不触发瞬间休息"
    [Fact]
    public void U2_MeetingStartsAtThreshold_NoInstantRest()
    {
        var config = new DayPlanConfig { WorkIntervalSeconds = TestHelpers.Minutes(50), RestDurationSeconds = TestHelpers.Minutes(10) };
        var meetings = new List<DateRange> { new(T0.AddSeconds(TestHelpers.Minutes(50)), T0.AddSeconds(TestHelpers.Minutes(70))) };
        var sim = new Simulator(T0, config, meetings);
        sim.TickTo(T0.AddSeconds(TestHelpers.Minutes(50)));
        Assert.Equal(EnginePhase.InMeeting, sim.Phase);   // t=50 会议开始进 inMeeting
        Assert.DoesNotContain(sim.Records, r => r.To == EnginePhase.Resting);
    }

    // 镜像 EngineTransitionCases "U3 背靠背会议跨接缝持续 inMeeting"
    [Fact]
    public void U3_BackToBackMeetings_StayInMeeting()
    {
        var config = new DayPlanConfig { WorkIntervalSeconds = TestHelpers.Minutes(50), RestDurationSeconds = TestHelpers.Minutes(10) };
        var meetings = new List<DateRange>
        {
            new(T0.AddSeconds(TestHelpers.Minutes(50)), T0.AddSeconds(TestHelpers.Minutes(70))),
            new(T0.AddSeconds(TestHelpers.Minutes(70)), T0.AddSeconds(TestHelpers.Minutes(90))),
        };
        var sim = new Simulator(T0, config, meetings);
        sim.TickTo(T0.AddSeconds(TestHelpers.Minutes(70)));
        Assert.Equal(EnginePhase.InMeeting, sim.Phase);   // t=70 第二个会议开始仍 inMeeting
        Assert.DoesNotContain(sim.Records, r => r.To == EnginePhase.Resting);
    }

    // 镜像 EngineTransitionCases "U4 会议跨工作窗口边界 → offDuty 优先"
    [Fact]
    public void U4_MeetingAcrossWindow_OffDutyWins()
    {
        var config = new DayPlanConfig { WorkIntervalSeconds = TestHelpers.Minutes(50), RestDurationSeconds = TestHelpers.Minutes(10) };
        var meetings = new List<DateRange> { new(T0.AddSeconds(TestHelpers.Minutes(50)), T0.AddSeconds(TestHelpers.Minutes(70))) };
        var sim = new Simulator(T0, config, meetings, d => d < T0.AddSeconds(TestHelpers.Minutes(60)));
        sim.TickTo(T0.AddSeconds(TestHelpers.Minutes(65)));
        Assert.Equal(EnginePhase.OffDuty, sim.Phase);     // t=65 已离开工作窗口 → offDuty 压过会议
    }

    // 镜像 EngineTransitionCases "U7 休息被会议打断 → abort-and-reset"
    [Fact]
    public void U7_RestInterruptedByMeeting_AbortAndReset()
    {
        var config = new DayPlanConfig { WorkIntervalSeconds = TestHelpers.Minutes(2), RestDurationSeconds = TestHelpers.Minutes(5) };
        var meetings = new List<DateRange> { new(T0.AddSeconds(TestHelpers.Minutes(3)), T0.AddSeconds(TestHelpers.Minutes(5))) };
        var sim = new Simulator(T0, config, meetings);

        sim.TickTo(T0.AddSeconds(TestHelpers.Minutes(2)));
        Assert.Equal(EnginePhase.Resting, sim.Phase);     // t=120 触发休息

        sim.TickTo(T0.AddSeconds(TestHelpers.Minutes(3)));
        Assert.Equal(EnginePhase.InMeeting, sim.Phase);   // t=180 会议打断休息
        var abort = sim.Records.Last(r => r.From == EnginePhase.Resting);
        Assert.True(abort.Effects.DismissOverlay);
        Assert.True(abort.Effects.PauseMusic);
        Assert.True(TestHelpers.Approx(sim.Accum, 0, 0.001));
    }

    // 镜像 EngineTransitionCases "U9 同态幂等：休息中 showOverlay/startMusic 仅一次"
    [Fact]
    public void U9_Idempotent_OverlayAndMusicOnce()
    {
        var config = new DayPlanConfig { WorkIntervalSeconds = TestHelpers.Minutes(2), RestDurationSeconds = TestHelpers.Minutes(10) };
        var sim = new Simulator(T0, config, meetings: new());
        sim.TickTo(T0.AddSeconds(TestHelpers.Minutes(2)));
        sim.TickTo(T0.AddSeconds(TestHelpers.Minutes(5)));
        sim.TickTo(T0.AddSeconds(TestHelpers.Minutes(8)));

        Assert.Equal(1, sim.Records.Count(r => r.Effects.ShowOverlay));
        Assert.Equal(1, sim.Records.Count(r => r.Effects.StartMusic));
        Assert.Equal(EnginePhase.Resting, sim.Phase);
    }
}

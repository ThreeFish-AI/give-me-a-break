using Xunit;
using TimeoutEngine;

namespace TimeoutEngine.Tests;

// MARK: - B 层 · LiveTimeoutEngine 接线镜像测试（镜像 tests/EngineWiringCases.swift）
// 用 Mock 注入，断言控制器调用序列与状态机接线。每个测试注释标注对应 Swift 用例名。

public class EngineWiringTests
{
    private static DateTimeOffset T0 => TestHelpers.Epoch0;

    // 镜像 EngineWiringCases "U1 引擎接线：控制器调用序列"
    [Fact]
    public void U1_Wiring_ControllerCallSequence()
    {
        var clock = new MockClock(T0);
        var overlay = new MockOverlay();
        var music = new MockMusic();
        var calProv = new StubCalendar { Timeline = new(new() { new(T0.AddSeconds(TestHelpers.Minutes(30)), T0.AddSeconds(TestHelpers.Minutes(60))) }) };
        var sys = new MockSystemState();
        var engine = new LiveTimeoutEngine(clock, calProv, overlay, music, sys,
            TestHelpers.FullDayConfig(TestHelpers.Minutes(50), TestHelpers.Minutes(10)),
            new EngineState { Phase = EnginePhase.Working, LastTickAt = T0 });

        TestHelpers.RunTicks(engine, clock, TestHelpers.Minutes(29));
        Assert.Equal(EnginePhase.Working, engine.State.Phase);

        TestHelpers.RunTicks(engine, clock, TestHelpers.Minutes(21));   // → 50min（会议进行中）
        Assert.Equal(EnginePhase.InMeeting, engine.State.Phase);
        Assert.Equal(0, overlay.ShowCount);

        TestHelpers.RunTicks(engine, clock, TestHelpers.Minutes(10));   // → 60min（会议结束）
        Assert.Equal(EnginePhase.Resting, engine.State.Phase);
        Assert.Equal(1, overlay.ShowCount);
        Assert.Equal(1, music.StartCount);

        TestHelpers.RunTicks(engine, clock, TestHelpers.Minutes(10));   // → 70min（休息结束）
        Assert.Equal(EnginePhase.Working, engine.State.Phase);
        Assert.Equal(1, overlay.DismissCount);
        Assert.Equal(1, music.PauseCount);
    }

    // 镜像 EngineWiringCases "U5 AFK 冻结累加器，恢复后续增"
    [Fact]
    public void U5_AFK_FreezesAccumulator_ThenResumes()
    {
        var clock = new MockClock(T0);
        var overlay = new MockOverlay();
        var music = new MockMusic();
        var calProv = new StubCalendar();
        var sys = new MockSystemState();
        var engine = new LiveTimeoutEngine(clock, calProv, overlay, music, sys,
            TestHelpers.FullDayConfig(TestHelpers.Minutes(10), TestHelpers.Minutes(2)),
            new EngineState { Phase = EnginePhase.Working, LastTickAt = T0 });

        TestHelpers.RunTicks(engine, clock, TestHelpers.Minutes(2));
        double accumBefore = engine.State.WorkAccumulatedSeconds;

        sys.IdleValue = 999;   // > afkThreshold(180) → AFK
        TestHelpers.RunTicks(engine, clock, TestHelpers.Minutes(2));
        Assert.Equal(EnginePhase.Idle, engine.State.Phase);
        Assert.True(TestHelpers.Approx(engine.State.WorkAccumulatedSeconds, accumBefore, 0.001));

        sys.IdleValue = 0;    // 输入恢复
        TestHelpers.RunTicks(engine, clock, 120);   // 首 tick idle→working 不累加，次 tick 起续增
        Assert.Equal(EnginePhase.Working, engine.State.Phase);
        Assert.True(engine.State.WorkAccumulatedSeconds > accumBefore);
    }

    // 镜像 EngineWiringCases "U6 睡眠/唤醒不回灌"
    [Fact]
    public void U6_SleepWake_NoBackfill()
    {
        var clock = new MockClock(T0);
        var overlay = new MockOverlay();
        var music = new MockMusic();
        var calProv = new StubCalendar();
        var sys = new MockSystemState();
        var engine = new LiveTimeoutEngine(clock, calProv, overlay, music, sys,
            TestHelpers.FullDayConfig(TestHelpers.Minutes(50), TestHelpers.Minutes(10)),
            new EngineState { Phase = EnginePhase.Working, LastTickAt = T0 });

        TestHelpers.RunTicks(engine, clock, TestHelpers.Minutes(3));
        double accumBefore = engine.State.WorkAccumulatedSeconds;

        sys.Asleep = true;
        engine.HandleSleep();
        clock.AdvanceBy(8 * 3600);    // 睡眠 8 小时（心跳已挂起，无 tick）
        sys.Asleep = false;
        engine.HandleWake();
        engine.Tick();                 // 首个唤醒 tick：delta≈0，不回灌

        Assert.True(TestHelpers.Approx(engine.State.WorkAccumulatedSeconds, accumBefore, 0.001));
        Assert.Equal(EnginePhase.Working, engine.State.Phase);
    }

    // 镜像 EngineWiringCases "U11 fast-forward 短中断推进"
    [Fact]
    public void U11_FastForward_ShortOutage_Advances()
    {
        var clock = new MockClock(T0);
        var engine = new LiveTimeoutEngine(clock, new StubCalendar(), new MockOverlay(), new MockMusic(), new MockSystemState(),
            TestHelpers.FullDayConfig(TestHelpers.Minutes(50), TestHelpers.Minutes(10)),
            new EngineState { Phase = EnginePhase.Working, WorkAccumulatedSeconds = 1500, LastTickAt = T0 });

        clock.AdvanceBy(120);   // 重启于 t0+120s（短中断）
        engine.FastForward(sanityLimit: 300);
        Assert.True(TestHelpers.Approx(engine.State.WorkAccumulatedSeconds, 1620, 1));
    }

    // 镜像 EngineWiringCases "U11 fast-forward 长中断冻结"
    [Fact]
    public void U11_FastForward_LongOutage_Frozen()
    {
        var clock = new MockClock(T0);
        var engine = new LiveTimeoutEngine(clock, new StubCalendar(), new MockOverlay(), new MockMusic(), new MockSystemState(),
            TestHelpers.FullDayConfig(TestHelpers.Minutes(50), TestHelpers.Minutes(10)),
            new EngineState { Phase = EnginePhase.Working, WorkAccumulatedSeconds = 1500, LastTickAt = T0 });

        clock.AdvanceBy(1800);  // 30min 中断 > sanity(300)
        engine.FastForward(sanityLimit: 300);
        Assert.True(TestHelpers.Approx(engine.State.WorkAccumulatedSeconds, 1500, 0.001));
        Assert.Equal(T0.AddSeconds(1800), engine.State.LastTickAt);
    }

    // 镜像 EngineWiringCases "Esc 提前结束休息：暂停音乐 + 退出遮罩 + 累加器归零 + 退出后不重进"
    [Fact]
    public void Esc_EarlyRestExit_NoReentry()
    {
        var clock = new MockClock(T0);
        var overlay = new MockOverlay();
        var music = new MockMusic();
        var engine = new LiveTimeoutEngine(clock, new StubCalendar(), overlay, music, new MockSystemState(),
            TestHelpers.FullDayConfig(TestHelpers.Minutes(50), TestHelpers.Minutes(10)),
            new EngineState { Phase = EnginePhase.Working, LastTickAt = T0 });

        TestHelpers.RunTicks(engine, clock, TestHelpers.Minutes(50));   // → 自然触发休息
        Assert.Equal(EnginePhase.Resting, engine.State.Phase);
        Assert.Equal(1, overlay.ShowCount);

        engine.RequestEarlyRestExit();
        Assert.Equal(EnginePhase.Working, engine.State.Phase);
        Assert.Equal(1, overlay.DismissCount);
        Assert.Equal(1, music.PauseCount);
        Assert.True(TestHelpers.Approx(engine.State.WorkAccumulatedSeconds, 0, 0.001));

        int showBefore = overlay.ShowCount;
        TestHelpers.RunTicks(engine, clock, TestHelpers.Minutes(5));    // 累加器从 0 续增，5min < 50min
        Assert.Equal(EnginePhase.Working, engine.State.Phase);
        Assert.Equal(showBefore, overlay.ShowCount);
    }

    // 镜像 EngineWiringCases "立即休息下 Esc 提前结束：清除 forcedRest，下个 tick 不重进休息"（Bug2 回归）
    [Fact]
    public void ForcedRest_EscClearsFlag_NoRestLoop()
    {
        var clock = new MockClock(T0);
        var overlay = new MockOverlay();
        var engine = new LiveTimeoutEngine(clock, new StubCalendar(), overlay, new MockMusic(), new MockSystemState(),
            TestHelpers.FullDayConfig(TestHelpers.Minutes(50), TestHelpers.Minutes(10)),
            new EngineState { Phase = EnginePhase.Working, LastTickAt = T0 });

        engine.ForceRestNow();                          // 经「立即休息」入口（forcedRest=true）
        TestHelpers.RunTicks(engine, clock, 2);          // 下个 tick 即进休息
        Assert.Equal(EnginePhase.Resting, engine.State.Phase);
        Assert.Equal(1, overlay.ShowCount);

        engine.RequestEarlyRestExit();
        Assert.Equal(EnginePhase.Working, engine.State.Phase);
        Assert.Equal(1, overlay.DismissCount);

        TestHelpers.RunTicks(engine, clock, 2);          // 修复前 forcedRest 残留 → 重进 resting → overlay 再弹
        Assert.Equal(EnginePhase.Working, engine.State.Phase);
        Assert.Equal(1, overlay.ShowCount);              // 修复前=2（死循环重弹），修复后=1

        TestHelpers.RunTicks(engine, clock, TestHelpers.Minutes(5));   // 继续多 tick 确认稳定
        Assert.Equal(EnginePhase.Working, engine.State.Phase);
        Assert.Equal(1, overlay.ShowCount);
    }

    // 镜像 EngineWiringCases "立即休息无视工作窗口"
    [Fact]
    public void ForcedRest_IgnoresWorkWindow()
    {
        var clock = new MockClock(T0);
        var overlay = new MockOverlay();
        var config = new DayPlanConfig { WorkWindows = new(), WorkIntervalSeconds = TestHelpers.Minutes(50), RestDurationSeconds = TestHelpers.Minutes(2) };
        var engine = new LiveTimeoutEngine(clock, new StubCalendar(), overlay, new MockMusic(), new MockSystemState(),
            config, new EngineState { Phase = EnginePhase.OffDuty, LastTickAt = T0 });

        TestHelpers.RunTicks(engine, clock, 10);
        Assert.Equal(EnginePhase.OffDuty, engine.State.Phase);    // 空窗口应恒 offDuty

        engine.ForceRestNow();
        TestHelpers.RunTicks(engine, clock, 2);
        Assert.Equal(EnginePhase.Resting, engine.State.Phase);    // 强制休息无视空工作窗口生效
        Assert.Equal(1, overlay.ShowCount);

        TestHelpers.RunTicks(engine, clock, 60);
        Assert.Equal(EnginePhase.Resting, engine.State.Phase);    // 强制休息期间不被 offDuty 中断
        Assert.Equal(1, overlay.ShowCount);

        TestHelpers.RunTicks(engine, clock, 90);                   // 休息自然结束（2min）→ 回正常 FSM
        Assert.Equal(EnginePhase.OffDuty, engine.State.Phase);
        Assert.Equal(1, overlay.DismissCount);
    }

    // 镜像 EngineWiringCases "updateConfig 热更新引擎配置"
    [Fact]
    public void UpdateConfig_HotReloads()
    {
        var clock = new MockClock(T0);
        var overlay = new MockOverlay();
        var music = new MockMusic();
        var engine = new LiveTimeoutEngine(clock, new StubCalendar(), overlay, music, new MockSystemState(),
            TestHelpers.FullDayConfig(TestHelpers.Minutes(50), TestHelpers.Minutes(10)),
            new EngineState { Phase = EnginePhase.Working, LastTickAt = T0 });

        TestHelpers.RunTicks(engine, clock, TestHelpers.Minutes(10));
        Assert.Equal(EnginePhase.Working, engine.State.Phase);    // 10min < 50min

        var newConfig = engine.Config;
        newConfig.WorkIntervalSeconds = TestHelpers.Minutes(8);
        engine.UpdateConfig(newConfig);

        TestHelpers.RunTicks(engine, clock, TestHelpers.Minutes(5));   // 累计 15min > 8min
        Assert.Equal(EnginePhase.Resting, engine.State.Phase);
        Assert.Equal(1, overlay.ShowCount);

        Assert.NotNull(music.LastConfig);                                       // init 后已同步配置到播放器
        Assert.Equal(TestHelpers.Minutes(8), music.LastConfig!.WorkIntervalSeconds);
    }
}

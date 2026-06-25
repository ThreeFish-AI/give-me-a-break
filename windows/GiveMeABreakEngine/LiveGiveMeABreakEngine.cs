namespace TimeoutEngine;

// MARK: - 引擎接线层
// 镜像 Sources/TimeoutEngine/LiveTimeoutEngine.swift。
// 汇聚心跳 / 日历 / idle / sleep 输入 → 调用纯函数（Advance/Transition/SideEffectsOf）
// → 幂等分发副作用到三大 controller → 持久化状态。
// 仅依赖协议（interface），可用 mock + 虚拟时钟单元测试。

public sealed class LiveTimeoutEngine
{
    private readonly IClock _clock;
    private readonly ICalendarProvider _calendarProvider;
    private readonly IOverlayController _overlay;
    private readonly IMusicController _music;
    private readonly ISystemStateProvider _systemState;

    public DayPlanConfig Config { get; private set; }
    public EngineState State { get; private set; }

    private Action<EngineState>? _persistHandler;

    /// <summary>用户「立即休息」标志：下个 tick 无视工作窗口/会议进入休息，休息自然结束即清除。</summary>
    private bool _forcedRest;

    public LiveTimeoutEngine(IClock clock,
        ICalendarProvider calendarProvider,
        IOverlayController overlay,
        IMusicController music,
        ISystemStateProvider systemState,
        DayPlanConfig config,
        EngineState? initialState = null)
    {
        _clock = clock;
        _calendarProvider = calendarProvider;
        _overlay = overlay;
        _music = music;
        _systemState = systemState;
        Config = config;
        State = initialState ?? new EngineState { Phase = EnginePhase.OffDuty, LastTickAt = clock.Now() };
        _music.UpdateConfig(config);   // 同步音乐相关配置给播放器
    }

    public void SetPersistHandler(Action<EngineState> handler) => _persistHandler = handler;

    /// <summary>心跳 tick（Heartbeat 每秒调用）。镜像 LiveTimeoutEngine.swift tick() 时序。</summary>
    public void Tick()
    {
        var now = _clock.Now();
        var oldPhase = State.Phase;

        // ② 先取系统活动状态（AFK/睡眠），决定本 tick 是否计工作
        bool isAFK = _systemState.IdleSeconds() > Config.AfkThresholdSeconds;
        bool isAsleep = _systemState.IsAsleep;
        bool active = !isAFK && !isAsleep;

        // ① 对账 + 推进累加器（仅 active 且工作态时累计）
        var s = Engine.Advance(State, now, active: active);

        // ② 聚合快照
        var timeline = _calendarProvider.CurrentTimeline();
        bool inWindow = false;
        foreach (var w in Config.WorkWindows)
        {
            if (w.Contains(now)) { inWindow = true; break; }
        }

        var snap = new EngineSnapshot(
            now: now,
            inWorkWindow: inWindow,
            isAFK: isAFK,
            isAsleep: _systemState.IsAsleep,
            activeMeeting: timeline.ActiveMeeting(now),
            workAccumulatedSeconds: s.WorkAccumulatedSeconds,
            workIntervalSeconds: Config.WorkIntervalSeconds);

        // ③ 纯函数决策 + 幂等副作用
        s = Engine.Transition(s, snap, Config, _forcedRest);
        if (oldPhase == EnginePhase.Resting && s.Phase != EnginePhase.Resting)
        {
            _forcedRest = false;  // 休息结束（含强制休息），清除标志（Bug2 回归点）
        }
        var eff = Engine.SideEffectsOf(oldPhase, s.Phase);
        State = s;

        if (eff.ShowOverlay && s.RestStartedAt is DateTimeOffset restStart)
            _overlay.Show(restStart.AddSeconds(Config.RestDurationSeconds));
        if (eff.DismissOverlay) _overlay.Dismiss();
        if (eff.StartMusic) _music.StartPlayback();
        if (eff.PauseMusic) _music.PausePlayback();

        _persistHandler?.Invoke(State);
    }

    // MARK: - 睡眠 / 唤醒 / 崩溃恢复

    /// <summary>系统睡眠：收尾——把睡眠 onset 之前的工作时间计入累加器，然后冻结。</summary>
    public void HandleSleep() => State = Engine.Advance(State, _clock.Now());

    /// <summary>系统唤醒：重置对账基点为 now，使首个唤醒 tick 的 delta≈0，不回灌睡眠时长。</summary>
    public void HandleWake() => State = State with { LastTickAt = _clock.Now() };

    /// <summary>启动崩溃恢复：短中断（≤ sanity）→ 按工作态推进；长中断 → 仅对账基点，不回灌。</summary>
    public void FastForward(double sanityLimit = 300)
    {
        var now = _clock.Now();
        double elapsed = (now - State.LastTickAt).TotalSeconds;
        if (elapsed <= sanityLimit && elapsed > 0)
            State = Engine.Advance(State, now, maxDelta: Math.Max(sanityLimit, elapsed));
        else
            State = State with { LastTickAt = now };
    }

    /// <summary>遮罩内 Esc 二次确认提前结束休息。离开 .resting 必清 forcedRest（与 Tick 对齐，杜绝下个 tick 重拉回休息）。</summary>
    public void RequestEarlyRestExit()
    {
        if (State.Phase != EnginePhase.Resting) return;
        var oldPhase = State.Phase;
        State = State with
        {
            WorkAccumulatedSeconds = 0,
            RestStartedAt = null,
            Phase = EnginePhase.Working
        };
        _forcedRest = false;
        var eff = Engine.SideEffectsOf(oldPhase, State.Phase);
        if (eff.DismissOverlay) _overlay.Dismiss();
        if (eff.PauseMusic) _music.PausePlayback();
    }

    /// <summary>菜单「立即休息」：设置强制标志，下一 tick 无视工作窗口/会议进入休息。</summary>
    public void ForceRestNow() => _forcedRest = true;

    /// <summary>设置 UI 应用新配置（工作窗口/间隔/音乐开关）。</summary>
    public void UpdateConfig(DayPlanConfig newConfig)
    {
        Config = newConfig;
        _music.UpdateConfig(newConfig);   // 热更新音乐播放器配置
    }
}

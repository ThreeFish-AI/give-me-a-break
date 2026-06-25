namespace TimeoutEngine;

// MARK: - 纯函数引擎（FSM 决策核心）
// 镜像 Sources/TimeoutEngine/Engine.swift（evaluate / advance / transition / sideEffects / mergeBusyIntervals）。
// 分支顺序与谓词优先级与 Swift 实现逐字对齐——这是 Bug2 类回归高发区，严禁擅自调整。

/// <summary>FSM 纯函数集合。无时间依赖、无副作用，便于单测与跨端黄金验证。</summary>
public static class Engine
{
    /// <summary>谓词优先级短路求值，首个匹配决定目标态（镜像 Engine.swift evaluate）：
    /// (1) 不在工作窗口 → offDuty（最高，压过会议）
    /// (2) AFK/asleep → idle
    /// (3) 活跃会议 → inMeeting（会议压过休息）
    /// (4) workAccum ≥ 阈值 → resting
    /// (5) 否则 → working</summary>
    public static EnginePhase Evaluate(EngineSnapshot s)
    {
        if (!s.InWorkWindow) return EnginePhase.OffDuty;
        if (s.IsAFK || s.IsAsleep) return EnginePhase.Idle;
        if (s.ActiveMeeting is not null) return EnginePhase.InMeeting;
        if (s.WorkAccumulatedSeconds >= s.WorkIntervalSeconds) return EnginePhase.Resting;
        return EnginePhase.Working;
    }

    /// <summary>基于「转换前 phase」推进累加器（镜像 Engine.swift advance）。
    /// 用 (now - lastTickAt) 时间戳差值对账，限幅防异常 tick。仅当 active 且 phase ∈ {working, inMeeting} 时推进。</summary>
    public static EngineState Advance(EngineState state, DateTimeOffset now, double maxDelta = 60, bool active = true)
    {
        double delta = (now - state.LastTickAt).TotalSeconds;
        double clamped = Math.Min(Math.Max(0, delta), maxDelta);
        double accum = state.WorkAccumulatedSeconds;
        if (active && (state.Phase == EnginePhase.Working || state.Phase == EnginePhase.InMeeting))
            accum += clamped;
        return state with { LastTickAt = now, WorkAccumulatedSeconds = accum };
    }

    /// <summary>from→to 的幂等副作用清单（镜像 Engine.swift sideEffects）。
    /// 进入 resting → 显示遮罩 + 播放音乐；离开 resting → 退出遮罩 + 暂停音乐。</summary>
    public static SideEffects SideEffectsOf(EnginePhase from, EnginePhase to)
    {
        var e = new SideEffects();
        if (from != EnginePhase.Resting && to == EnginePhase.Resting)
        {
            e.ShowOverlay = true;
            e.StartMusic = true;
        }
        if (from == EnginePhase.Resting && to != EnginePhase.Resting)
        {
            e.DismissOverlay = true;
            e.PauseMusic = true;
        }
        return e;
    }

    /// <summary>phase 跃迁 + 休息生命周期（镜像 Engine.swift transition）。
    /// 休息态特判：被会议打断或离开窗口 → abort-and-reset；到时 → 重置重评估；AFK 不中断休息。
    /// forcedRest：用户「立即休息」——无视工作窗口与会议，直接进入/保持休息直到自然结束。</summary>
    public static EngineState Transition(EngineState state, EngineSnapshot snapshot, DayPlanConfig config, bool forcedRest = false)
    {
        var s = state;

        if (s.Phase == EnginePhase.Resting)
        {
            var restStart = s.RestStartedAt ?? snapshot.Now;
            var restDeadline = restStart.AddSeconds(config.RestDurationSeconds);

            if (snapshot.Now >= restDeadline)
            {
                // 休息自然结束 → 重置累加器并以 0 重新评估（强制休息结束后回到正常 FSM）
                return s with
                {
                    WorkAccumulatedSeconds = 0,
                    RestStartedAt = null,
                    Phase = Evaluate(snapshot.ZeroingAccumulator())
                };
            }
            if (!forcedRest && !snapshot.InWorkWindow)
            {
                // 离开工作窗口 → 中止休息，下班（强制休息不触发）
                return s with { WorkAccumulatedSeconds = 0, RestStartedAt = null, Phase = EnginePhase.OffDuty };
            }
            if (!forcedRest && snapshot.ActiveMeeting is not null)
            {
                // 会议打断休息 → abort-and-reset（强制休息不触发）
                return s with { WorkAccumulatedSeconds = 0, RestStartedAt = null, Phase = EnginePhase.InMeeting };
            }
            // 继续休息（AFK 不中断休息）
            return s with { Phase = EnginePhase.Resting };
        }

        // 非休息态：强制休息直接进入（无视窗口/会议）
        if (forcedRest)
        {
            return s with { Phase = EnginePhase.Resting, RestStartedAt = snapshot.Now };
        }

        // 非休息态：正常评估目标态
        var target = Evaluate(snapshot);
        var restStartedAt = s.RestStartedAt;
        if (target == EnginePhase.Resting) restStartedAt = snapshot.Now;
        return s with { Phase = target, RestStartedAt = restStartedAt };
    }

    /// <summary>纯函数：将重叠/相邻的 busy 区间合并为不相交、按 start 排序的列表（镜像 mergeBusyIntervals）。
    /// mergeGap 允许相邻区间（间隙 ≤ gap）被合并。</summary>
    public static List<DateRange> MergeBusyIntervals(List<DateRange> ranges, double mergeGap = 0)
    {
        if (ranges.Count == 0) return new List<DateRange>();
        var sorted = ranges.OrderBy(r => r.Start).ToList();
        var merged = new List<DateRange>();
        var current = sorted[0];
        for (int i = 1; i < sorted.Count; i++)
        {
            var next = sorted[i];
            if (next.Start <= current.End.AddSeconds(mergeGap))
            {
                var end = current.End > next.End ? current.End : next.End;
                current = new DateRange(current.Start, end);
            }
            else
            {
                merged.Add(current);
                current = next;
            }
        }
        merged.Add(current);
        return merged;
    }
}

/// <summary>from→to 的幂等副作用清单（镜像 Engine.swift SideEffects）。默认全 false。</summary>
public sealed class SideEffects : IEquatable<SideEffects>
{
    public bool ShowOverlay { get; set; }
    public bool DismissOverlay { get; set; }
    public bool StartMusic { get; set; }
    public bool PauseMusic { get; set; }

    public static SideEffects Empty { get; } = new SideEffects();

    public bool Equals(SideEffects? other)
        => other is not null
           && ShowOverlay == other.ShowOverlay
           && DismissOverlay == other.DismissOverlay
           && StartMusic == other.StartMusic
           && PauseMusic == other.PauseMusic;
    public override bool Equals(object? obj) => obj is SideEffects s && Equals(s);
    public override int GetHashCode()
        => HashCode.Combine(ShowOverlay, DismissOverlay, StartMusic, PauseMusic);
}

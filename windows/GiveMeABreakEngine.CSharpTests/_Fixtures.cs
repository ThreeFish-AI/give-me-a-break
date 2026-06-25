using System.Text.Json;
using TimeoutEngine;

namespace TimeoutEngine.Tests;

// MARK: - 黄金 fixture 加载（A 层）
// 读 shared/test-fixtures/*.json，解析为输入。时间统一用 Unix epoch 秒整数（两端一致），
// 规避 ISO 8601 解析差异。容错：DTO 字段可空，缺字段取默认。

internal static class FixtureLoader
{
    public static string Load(string name)
    {
        string path = Path.Combine(AppContext.BaseDirectory, "shared", name);
        return File.ReadAllText(path);
    }

    public static DateTimeOffset Epoch(long s) => DateTimeOffset.FromUnixTimeSeconds(s);

    public static EnginePhase ParsePhase(string s) => s switch
    {
        "offDuty" => EnginePhase.OffDuty,
        "idle" => EnginePhase.Idle,
        "inMeeting" => EnginePhase.InMeeting,
        "working" => EnginePhase.Working,
        "resting" => EnginePhase.Resting,
        _ => throw new ArgumentException($"未知 phase: {s}", nameof(s)),
    };
}

internal sealed class RangeDto
{
    public long Start { get; set; }
    public long End { get; set; }
    public DateRange ToRange() => new(FixtureLoader.Epoch(Start), FixtureLoader.Epoch(End));
}

// MARK: evaluate

internal sealed class EvaluateFixtureDoc { public List<EvaluateCaseDoc> Cases { get; set; } = new(); }

internal sealed class EvaluateCaseDoc
{
    public string Name { get; set; } = "";
    public EvaluateSnapDoc Snapshot { get; set; } = new();
    public string? Expected { get; set; }
    public string? ExpectedNot { get; set; }
}

internal sealed class EvaluateSnapDoc
{
    public bool InWorkWindow { get; set; } = true;
    public bool IsAFK { get; set; }
    public bool IsAsleep { get; set; }
    public RangeDto? ActiveMeeting { get; set; }
    public double WorkAccumulatedSeconds { get; set; }
    public double WorkIntervalSeconds { get; set; }

    public EngineSnapshot ToSnapshot() => new(
        now: FixtureLoader.Epoch(0),
        inWorkWindow: InWorkWindow,
        isAFK: IsAFK,
        isAsleep: IsAsleep,
        activeMeeting: ActiveMeeting?.ToRange(),
        workAccumulatedSeconds: WorkAccumulatedSeconds,
        workIntervalSeconds: WorkIntervalSeconds);
}

// MARK: advance

internal sealed class AdvanceFixtureDoc { public List<AdvanceCaseDoc> Cases { get; set; } = new(); }

internal sealed class AdvanceCaseDoc
{
    public string Name { get; set; } = "";
    public AdvanceStateDoc Initial { get; set; } = new();
    public long To { get; set; }
    public double MaxDelta { get; set; } = 60;
    public bool Active { get; set; } = true;
    public double? ExpectWorkAccum { get; set; }
    public long? ExpectLastTickAt { get; set; }
}

internal sealed class AdvanceStateDoc
{
    public string? Phase { get; set; }
    public double WorkAccumulatedSeconds { get; set; }
    public long LastTickAt { get; set; }

    public EngineState ToState() => new()
    {
        Phase = Phase is null ? EnginePhase.OffDuty : FixtureLoader.ParsePhase(Phase),
        WorkAccumulatedSeconds = WorkAccumulatedSeconds,
        LastTickAt = FixtureLoader.Epoch(LastTickAt),
    };
}

// MARK: side-effects

internal sealed class SideEffectsFixtureDoc { public List<SideEffectsCaseDoc> Cases { get; set; } = new(); }

internal sealed class SideEffectsCaseDoc
{
    public string Name { get; set; } = "";
    public string From { get; set; } = "";
    public string To { get; set; } = "";
    public SideEffectsDoc Expected { get; set; } = new();
}

internal sealed class SideEffectsDoc
{
    public bool ShowOverlay { get; set; }
    public bool DismissOverlay { get; set; }
    public bool StartMusic { get; set; }
    public bool PauseMusic { get; set; }

    public SideEffects ToSideEffects() => new()
    {
        ShowOverlay = ShowOverlay,
        DismissOverlay = DismissOverlay,
        StartMusic = StartMusic,
        PauseMusic = PauseMusic,
    };
}

// MARK: merge-busy

internal sealed class MergeFixtureDoc { public List<MergeCaseDoc> Cases { get; set; } = new(); }

internal sealed class MergeCaseDoc
{
    public string Name { get; set; } = "";
    public List<RangeDto> Input { get; set; } = new();
    public double MergeGap { get; set; }
    public List<RangeDto> Expected { get; set; } = new();
}

namespace TimeoutEngine;

// MARK: - 引擎状态（单一事实源，可持久化以支持崩溃/重启恢复）
// 镜像 Sources/TimeoutEngine/Models.swift · EngineState。
// 采用 record + init：支持 with 表达式做非破坏性更新，对齐 Swift struct 值语义。
// 各端本地持久化，不跨平台互换（见 docs/windows-port-design.md §5）。

/// <summary>引擎状态：相位 + 工作累加器 + 对账基点 + 休息起始。</summary>
public sealed record EngineState
{
    public EnginePhase Phase { get; init; } = EnginePhase.OffDuty;

    /// <summary>单调 wall-clock 工作累加器，仅 working/inMeeting 推进。</summary>
    public double WorkAccumulatedSeconds { get; init; }

    /// <summary>对账基点（wall-clock）。</summary>
    public DateTimeOffset LastTickAt { get; init; } = DateTimeOffset.FromUnixTimeSeconds(0);

    /// <summary>RESTING 起始时刻（算 restDeadline）。</summary>
    public DateTimeOffset? RestStartedAt { get; init; }

    public int ModelVersion { get; init; } = 1;
}

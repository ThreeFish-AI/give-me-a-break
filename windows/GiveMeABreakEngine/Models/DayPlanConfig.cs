using System.Text.Json;

namespace TimeoutEngine;

// MARK: - 一日计划配置
// 镜像 Sources/TimeoutEngine/Models.swift · DayPlanConfig。含容错解码（缺字段补默认）。

/// <summary>一日计划配置：工作窗口 + 间隔/休息/AFK 阈值 + 音频/QQ 音乐开关。</summary>
public sealed class DayPlanConfig : IEquatable<DayPlanConfig>
{
    public const int CurrentSchemaVersion = 2;

    public int SchemaVersion { get; set; }
    public List<WorkWindow> WorkWindows { get; set; } = new();
    /// <summary>触发休息的工作累计阈值（秒），默认 50 分钟。</summary>
    public double WorkIntervalSeconds { get; set; }
    /// <summary>单次休息时长（秒），默认 10 分钟。</summary>
    public double RestDurationSeconds { get; set; }
    /// <summary>系统空闲超过此值视为 AFK，暂停累加（秒），默认 180。</summary>
    public double AfkThresholdSeconds { get; set; }
    /// <summary>休息时播放内置粉噪音，默认开。</summary>
    public bool AmbientSoundEnabled { get; set; }
    /// <summary>休息时联动 QQ 音乐媒体键，默认开。</summary>
    public bool ControlQQMusic { get; set; }

    /// <summary>Microsoft Graph 日历门控 client id（Phase 3）。空=禁用日历门控，降级为无会议。</summary>
    public string? GraphClientId { get; set; }

    public DayPlanConfig() { }

    /// <summary>默认配置（单一事实源：默认值取自此处，容错解码时缺字段回退到此）。</summary>
    public static DayPlanConfig Default { get; } = new DayPlanConfig
    {
        SchemaVersion = CurrentSchemaVersion,
        WorkWindows = new()
        {
            new WorkWindow(new TimeOfDay(9, 0), new TimeOfDay(12, 0)),
            new WorkWindow(new TimeOfDay(13, 40), new TimeOfDay(18, 0)),
        },
        WorkIntervalSeconds = 50 * 60,
        RestDurationSeconds = 10 * 60,
        AfkThresholdSeconds = 180,
        AmbientSoundEnabled = true,
        ControlQQMusic = true,
    };

    /// <summary>容错解码：缺字段补默认（对齐 Swift init(from:) 的 decodeIfPresent ?? default）。
    /// schema 版本规范化 / 超前回退由 ConfigStore.Migrate 负责。</summary>
    public static DayPlanConfig FromJson(string json, JsonSerializerOptions options)
    {
        var dto = JsonSerializer.Deserialize<Dto>(json, options) ?? new Dto();
        var d = Default;
        return new DayPlanConfig
        {
            SchemaVersion = dto.SchemaVersion ?? d.SchemaVersion,
            WorkWindows = dto.WorkWindows ?? CloneWindows(d.WorkWindows),
            WorkIntervalSeconds = dto.WorkIntervalSeconds ?? d.WorkIntervalSeconds,
            RestDurationSeconds = dto.RestDurationSeconds ?? d.RestDurationSeconds,
            AfkThresholdSeconds = dto.AfkThresholdSeconds ?? d.AfkThresholdSeconds,
            AmbientSoundEnabled = dto.AmbientSoundEnabled ?? true,
            ControlQQMusic = dto.ControlQQMusic ?? true,
            GraphClientId = dto.GraphClientId,
        };
    }

    private static List<WorkWindow> CloneWindows(List<WorkWindow> src)
    {
        var list = new List<WorkWindow>(src.Count);
        foreach (var w in src) list.Add(new WorkWindow(w.Start, w.End));
        return list;
    }

    public bool Equals(DayPlanConfig? other)
    {
        if (other is null) return false;
        if (ReferenceEquals(this, other)) return true;
        if (SchemaVersion != other.SchemaVersion
            || WorkIntervalSeconds != other.WorkIntervalSeconds
            || RestDurationSeconds != other.RestDurationSeconds
            || AfkThresholdSeconds != other.AfkThresholdSeconds
            || AmbientSoundEnabled != other.AmbientSoundEnabled
            || ControlQQMusic != other.ControlQQMusic
            || GraphClientId != other.GraphClientId
            || WorkWindows.Count != other.WorkWindows.Count) return false;
        for (int i = 0; i < WorkWindows.Count; i++)
            if (!WorkWindows[i].Equals(other.WorkWindows[i])) return false;
        return true;
    }

    public override bool Equals(object? obj) => obj is DayPlanConfig c && Equals(c);

    public override int GetHashCode()
    {
        var h = new HashCode();
        h.Add(SchemaVersion);
        h.Add(WorkIntervalSeconds);
        h.Add(RestDurationSeconds);
        h.Add(AfkThresholdSeconds);
        h.Add(AmbientSoundEnabled);
        h.Add(ControlQQMusic);
        h.Add(GraphClientId);
        foreach (var w in WorkWindows) h.Add(w);
        return h.ToHashCode();
    }

    // 可空内部 DTO：容忍缺字段（反序列化缺失 → null → 补默认）。
    private sealed class Dto
    {
        public int? SchemaVersion { get; set; }
        public List<WorkWindow>? WorkWindows { get; set; }
        public double? WorkIntervalSeconds { get; set; }
        public double? RestDurationSeconds { get; set; }
        public double? AfkThresholdSeconds { get; set; }
        public bool? AmbientSoundEnabled { get; set; }
        public bool? ControlQQMusic { get; set; }
        public string? GraphClientId { get; set; }
    }
}

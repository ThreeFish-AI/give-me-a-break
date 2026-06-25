using System.Text.Json.Serialization;

namespace TimeoutEngine;

// 镜像 Sources/TimeoutEngine/Models.swift · EnginePhase（String enum）。
// JSON 序列化为 camelCase 字符串（"offDuty" 等），对齐 Swift Codable 默认形态。

/// <summary>引擎状态机相位。</summary>
[JsonConverter(typeof(CamelCaseStringEnumConverter))]
public enum EnginePhase
{
    OffDuty,
    Idle,
    InMeeting,
    Working,
    Resting
}

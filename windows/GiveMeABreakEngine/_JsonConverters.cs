using System.Text.Json;
using System.Text.Json.Serialization;

namespace TimeoutEngine;

// MARK: - JSON 转换器（对齐 Swift Codable 形态）
// 跨端序列化兼容的集中维护点。EnginePhase 的 camelCase 由其自身 attribute 处理。

/// <summary>TimeOfDay ↔ JSON 裸整数 rawValue（对齐 Swift RawRepresentable&lt;Int&gt; Codable）。</summary>
public sealed class TimeOfDayJsonConverter : JsonConverter<TimeOfDay>
{
    public override TimeOfDay Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        => new TimeOfDay(reader.GetInt32());

    public override void Write(Utf8JsonWriter writer, TimeOfDay value, JsonSerializerOptions options)
        => writer.WriteNumberValue(value.RawValue);
}

/// <summary>Enum ↔ JSON camelCase 字符串（对齐 Swift String enum Codable 形态）。
/// 以无参构造子类呈现，便于在 [JsonConverter(typeof(...))] attribute 中用 typeof 引用。</summary>
public sealed class CamelCaseStringEnumConverter : JsonStringEnumConverter
{
    public CamelCaseStringEnumConverter() : base(JsonNamingPolicy.CamelCase) { }
}

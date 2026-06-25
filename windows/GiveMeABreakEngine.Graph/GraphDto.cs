namespace TimeoutEngine.Graph;

// MARK: - Graph /me/calendarView 响应 DTO（仅取门控所需字段）
// 反序列化时用 PropertyNameCaseInsensitive=true（camelCase）。

/// <summary>Graph 事件的日期时间 + 时区。</summary>
public sealed class GraphDateTimeTimeZone
{
    /// <summary>"2026-06-24T14:00:00.0000000"（Prefer: outlook.timezone="UTC" 下为 UTC）。</summary>
    public string? DateTime { get; set; }
    /// <summary>"UTC"（请求头强制）或 Windows 时区名。</summary>
    public string? TimeZone { get; set; }
}

/// <summary>Graph 单个事件（仅门控所需字段）。</summary>
public sealed class GraphEvent
{
    public string? Subject { get; set; }
    public GraphDateTimeTimeZone? Start { get; set; }
    public GraphDateTimeTimeZone? End { get; set; }
    /// <summary>free | tentative | busy | oof | workingElsewhere | unknown。</summary>
    public string? ShowAs { get; set; }
    public bool? IsAllDay { get; set; }
}

/// <summary>Graph /me/calendarView 响应根。</summary>
public sealed class GraphCalendarViewResponse
{
    public List<GraphEvent>? Value { get; set; }
}

namespace TimeoutEngine.Graph;

// MARK: - Graph 客户端抽象（mockable，隔离 MSAL/HttpClient 不可测部分）
// 同 Phase 1 ISendInputPort 隔离 SendInput 范式：壳 MsalGraphClient 实现真实调用，测试用 mock。

public interface IGraphClient
{
    /// <summary>查询指定起始日 [start, start+1day) 的日历事件（calendarView 已展开重复事件）。</summary>
    Task<IReadOnlyList<GraphEvent>> FetchTodayEventsAsync(DateTimeOffset start, CancellationToken ct);
}

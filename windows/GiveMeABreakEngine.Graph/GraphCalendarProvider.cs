using TimeoutEngine;

namespace TimeoutEngine.Graph;

// MARK: - ICalendarProvider 实现：Graph 日历门控
// 镜像 macOS LiveCalendarProvider：CurrentTimeline 同步返回缓存 + 惰性刷新到期 fire-and-forget 后台刷新 + 失败降级。
// 注入 IClock 驱动限流判定（虚拟时钟可测，Phase 0 范式）。未授权/失败降级返回缓存或 Empty（不阻断引擎）。

public sealed class GraphCalendarProvider : ICalendarProvider
{
    private readonly IGraphClient _client;
    private readonly TimelineCache _cache;
    private readonly IClock _clock;

    public GraphCalendarProvider(IGraphClient client, IClock clock, TimelineCache? cache = null)
    {
        _client = client;
        _clock = clock;
        _cache = cache ?? new TimelineCache();
    }

    /// <summary>ICalendarProvider 契约（同步）。引擎 1Hz tick 调用。
    /// 返回缓存；惰性刷新到期则后台 fire-and-forget 触发，本调用立即返回缓存（对齐 macOS）。</summary>
    public MeetingTimeline CurrentTimeline()
    {
        var now = _clock.Now();
        if (_cache.LazyRefreshDue(now)) TriggerRefresh(now);
        return _cache.Snapshot();
    }

    private void TriggerRefresh(DateTimeOffset now)
    {
        if (!_cache.TryBeginRefresh(now)) return;   // 限流/in-flight 抑制
        // fire-and-forget（对齐 macOS DispatchQueue.global(qos:.utility).async）。
        // 不 await：CurrentTimeline() 同步语义；刷新结果在下一 tick 生效。
        _ = Task.Run(async () =>
        {
            try
            {
                var start = now.Date;   // 今天 startOfDay
                var events = await _client.FetchTodayEventsAsync(start, CancellationToken.None);
                var timeline = GraphTimelineMapper.ToTimeline(events, now);
                _cache.CommitRefresh(timeline, now);
            }
            catch
            {
                _cache.AbortRefresh();   // 降级：保留旧缓存，下次 tick 重试（限流推迟到 minInterval 后）
            }
        });
    }
}

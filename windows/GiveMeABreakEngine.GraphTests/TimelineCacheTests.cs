using Xunit;
using TimeoutEngine;
using TimeoutEngine.Graph;

namespace TimeoutEngine.GraphTests;

// MARK: - TimelineCache 限流 + 线程安全（对齐 macOS minRefreshInterval/lazyRefreshInterval）

public class TimelineCacheTests
{
    private static readonly DateTimeOffset T0 = DateTimeOffset.Parse("2026-06-24T08:00:00Z");

    [Fact]
    public void LazyRefreshDue_InitiallyTrue()
    {
        var cache = new TimelineCache();
        Assert.True(cache.LazyRefreshDue(T0));   // _lastRefresh=epoch，远早于 T0
    }

    [Fact]
    public void LazyRefreshDue_AfterCommit_FalseWithinInterval()
    {
        var cache = new TimelineCache();
        cache.CommitRefresh(MeetingTimeline.Empty, T0);
        Assert.False(cache.LazyRefreshDue(T0.AddSeconds(179)));   // < 180s
        Assert.True(cache.LazyRefreshDue(T0.AddSeconds(180)));    // = 180s 到期
    }

    [Fact]
    public void TryBeginRefresh_FirstTrue_SecondFalse_InFlight()
    {
        var cache = new TimelineCache();
        Assert.True(cache.TryBeginRefresh(T0));    // 置 in-flight
        Assert.False(cache.TryBeginRefresh(T0));   // in-flight 抑制
    }

    [Fact]
    public void TryBeginRefresh_MinInterval_Gates()
    {
        var cache = new TimelineCache();
        Assert.True(cache.TryBeginRefresh(T0));
        cache.CommitRefresh(MeetingTimeline.Empty, T0);
        Assert.False(cache.TryBeginRefresh(T0.AddSeconds(59)));   // < minInterval(60)
        Assert.True(cache.TryBeginRefresh(T0.AddSeconds(60)));    // = 60 允许
    }

    [Fact]
    public void AbortRefresh_ClearsInFlight_KeepsCache()
    {
        var cache = new TimelineCache();
        var timeline = new MeetingTimeline(new() { new(DateTimeOffset.Parse("2026-06-24T09:00:00Z"), DateTimeOffset.Parse("2026-06-24T10:00:00Z")) });
        cache.CommitRefresh(timeline, T0);
        Assert.True(cache.TryBeginRefresh(T0.AddSeconds(60)));
        cache.AbortRefresh();   // 失败：清 in-flight，保留缓存
        Assert.Single(cache.Snapshot().BusyIntervals);   // 旧缓存保留
    }

    [Fact]
    public void Snapshot_ReturnsCommitted()
    {
        var cache = new TimelineCache();
        var timeline = new MeetingTimeline(new() { new(DateTimeOffset.Parse("2026-06-24T09:00:00Z"), DateTimeOffset.Parse("2026-06-24T10:00:00Z")) });
        cache.CommitRefresh(timeline, T0);
        Assert.Same(timeline.BusyIntervals, cache.Snapshot().BusyIntervals);
    }
}

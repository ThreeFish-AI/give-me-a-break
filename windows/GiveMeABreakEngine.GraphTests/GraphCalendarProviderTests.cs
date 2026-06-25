using Xunit;
using TimeoutEngine;
using TimeoutEngine.Graph;

namespace TimeoutEngine.GraphTests;

// MARK: - GraphCalendarProvider 编排（mock IGraphClient + 虚拟 IClock）
// 对齐 macOS LiveCalendarProvider：CurrentTimeline 同步返回缓存 + 惰性刷新 fire-and-forget + 限流 + 失败降级。

public class GraphCalendarProviderTests
{
    private static GraphEvent Busy(string start, string end) => new()
    {
        Start = new GraphDateTimeTimeZone { DateTime = start, TimeZone = "UTC" },
        End = new GraphDateTimeTimeZone { DateTime = end, TimeZone = "UTC" },
        ShowAs = "busy",
    };

    private sealed class CapturingClient : IGraphClient
    {
        public int CallCount;
        public IReadOnlyList<GraphEvent> Events = Array.Empty<GraphEvent>();
        public Exception? Throw;
        public async Task<IReadOnlyList<GraphEvent>> FetchTodayEventsAsync(DateTimeOffset start, CancellationToken ct)
        {
            CallCount++;
            await Task.Yield();
            if (Throw is not null) throw Throw;
            return Events;
        }
    }

    private sealed class FakeClock : IClock
    {
        public DateTimeOffset Value;
        public DateTimeOffset Now() => Value;
    }

    private static async Task WaitForAsync(Func<bool> cond, int timeoutMs)
    {
        var deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
        while (DateTime.UtcNow < deadline)
        {
            if (cond()) return;
            await Task.Delay(10);
        }
    }

    [Fact]
    public async Task FirstCall_TriggersRefresh_PopulatesCache()
    {
        var client = new CapturingClient { Events = new[] { Busy("2026-06-24T09:00:00", "2026-06-24T10:00:00") } };
        var clock = new FakeClock { Value = DateTimeOffset.Parse("2026-06-24T08:00:00Z") };
        var cache = new TimelineCache(lazyIntervalSec: 1, minIntervalSec: 1);
        var provider = new GraphCalendarProvider(client, clock, cache);

        var first = provider.CurrentTimeline();   // 触发 fire-and-forget 刷新，立即返回空缓存
        Assert.Empty(first.BusyIntervals);

        await WaitForAsync(() => client.CallCount >= 1, 1000);
        Assert.Equal(1, client.CallCount);
        await WaitForAsync(() => cache.Snapshot().BusyIntervals.Count > 0, 1000);

        var updated = provider.CurrentTimeline();   // 返回已更新缓存
        Assert.NotEmpty(updated.BusyIntervals);
    }

    [Fact]
    public async Task Throttle_PreventsRepeatedCalls_WithinMinInterval()
    {
        var client = new CapturingClient { Events = new[] { Busy("2026-06-24T09:00:00", "2026-06-24T10:00:00") } };
        var clock = new FakeClock { Value = DateTimeOffset.Parse("2026-06-24T08:00:00Z") };
        var provider = new GraphCalendarProvider(client, clock, new TimelineCache(lazyIntervalSec: 1, minIntervalSec: 1000));

        provider.CurrentTimeline();   // 触发首次刷新
        await WaitForAsync(() => client.CallCount >= 1, 1000);
        // 时钟前进但 < minInterval(1000s) → 不重复触发
        clock.Value = clock.Value.AddSeconds(60);
        provider.CurrentTimeline();
        Assert.Equal(1, client.CallCount);
    }

    [Fact]
    public async Task Failure_DoesNotThrow_ReturnsCache()
    {
        var client = new CapturingClient { Throw = new InvalidOperationException("graph down") };
        var clock = new FakeClock { Value = DateTimeOffset.Parse("2026-06-24T08:00:00Z") };
        var provider = new GraphCalendarProvider(client, clock, new TimelineCache(lazyIntervalSec: 1, minIntervalSec: 1));

        var first = provider.CurrentTimeline();   // 触发刷新（将抛），但不阻塞、不抛
        Assert.Empty(first.BusyIntervals);        // 降级返回空缓存
        await WaitForAsync(() => client.CallCount >= 1, 1000);

        // 第二次调用：刷新失败后 in-flight 已清，但限流内不重试；仍返回空（不抛）
        var second = provider.CurrentTimeline();
        Assert.Empty(second.BusyIntervals);
    }
}

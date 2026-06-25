using TimeoutEngine;

namespace TimeoutEngine.Graph;

// MARK: - 限流 + 线程安全缓存（对齐 macOS cached/lastRefresh/refreshInFlight/minRefreshInterval）
// lazyInterval=180s（引擎 1Hz tick 惰性刷新）；minInterval=60s（显式刷新最低间隔）。

public sealed class TimelineCache
{
    public const double DefaultLazyIntervalSec = 180;   // 引擎 tick 触发的惰性刷新间隔
    public const double DefaultMinIntervalSec = 60;     // 显式刷新最低间隔

    private readonly object _lock = new();
    private MeetingTimeline _cached = MeetingTimeline.Empty;
    private DateTimeOffset _lastRefresh = DateTimeOffset.FromUnixTimeSeconds(0);
    private bool _refreshInFlight;
    private readonly double _lazyIntervalSec;
    private readonly double _minIntervalSec;

    public TimelineCache(double lazyIntervalSec = DefaultLazyIntervalSec, double minIntervalSec = DefaultMinIntervalSec)
    {
        _lazyIntervalSec = lazyIntervalSec;
        _minIntervalSec = minIntervalSec;
    }

    /// <summary>惰性刷新是否到期（引擎 1Hz tick 入口判定）。</summary>
    public bool LazyRefreshDue(DateTimeOffset now)
    {
        lock (_lock) return (now - _lastRefresh).TotalSeconds >= _lazyIntervalSec;
    }

    /// <summary>是否允许发起刷新（限流 ≥ minInterval 且无 in-flight）。
    /// 返回 true 时原子置位 _refreshInFlight，防并发重复刷新。</summary>
    public bool TryBeginRefresh(DateTimeOffset now)
    {
        lock (_lock)
        {
            if (_refreshInFlight) return false;
            if ((now - _lastRefresh).TotalSeconds < _minIntervalSec) return false;
            _refreshInFlight = true;
            return true;
        }
    }

    /// <summary>刷新完成：写入新时间线 + 更新时间戳 + 清 in-flight。</summary>
    public void CommitRefresh(MeetingTimeline timeline, DateTimeOffset now)
    {
        lock (_lock)
        {
            _cached = timeline;
            _lastRefresh = now;
            _refreshInFlight = false;
        }
    }

    /// <summary>刷新失败：清 in-flight（缓存保留旧值，降级返回过期但仍可用的缓存）。</summary>
    public void AbortRefresh()
    {
        lock (_lock) _refreshInFlight = false;
    }

    /// <summary>返回当前缓存（线程安全快照）。</summary>
    public MeetingTimeline Snapshot()
    {
        lock (_lock) return _cached;
    }
}

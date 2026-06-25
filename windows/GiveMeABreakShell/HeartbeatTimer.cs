using System.Windows.Threading;
using TimeoutEngine;

namespace TimeoutShell;

// IHeartbeat · System.Threading.Timer 1Hz。回调 marshal 到 UI Dispatcher
// （对齐 macOS Heartbeat 主队列，保证 overlay/music 操作 UI 线程）。
public sealed class HeartbeatTimer : IHeartbeat
{
    private Timer? _timer;
    private TimeSpan _period;
    private Action? _handler;
    private readonly Dispatcher _dispatcher;

    public HeartbeatTimer(Dispatcher dispatcher) => _dispatcher = dispatcher;

    public void Start(double intervalSeconds, Action handler)
    {
        _period = TimeSpan.FromSeconds(intervalSeconds);
        _handler = handler;
        if (_timer is null)
            _timer = new Timer(Callback, null, _period, _period);
        else
            _timer.Change(_period, _period);
    }

    private void Callback(object? state)
    {
        if (_handler is not null) _dispatcher.BeginInvoke(_handler);
    }

    public void Suspend() => _timer?.Change(Timeout.InfiniteTimeSpan, Timeout.InfiniteTimeSpan);

    public void Resume() => _timer?.Change(_period, _period);

    public void Stop()
    {
        _timer?.Dispose();
        _timer = null;
    }
}

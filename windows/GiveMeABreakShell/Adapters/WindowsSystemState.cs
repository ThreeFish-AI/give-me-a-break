using TimeoutEngine;
using TimeoutEngine.Win32;

namespace TimeoutShell.Adapters;

// ISystemStateProvider · 空闲检测（Win32IdleProbe.GetCurrentIdleSeconds 封装 native）
// + 睡眠标志（PowerEventBridge 置位）。对齐 macOS SystemSensors + NSWorkspace 睡眠观察者。
public sealed class WindowsSystemState : ISystemStateProvider
{
    private volatile bool _isAsleep;
    public bool IsAsleep => _isAsleep;

    /// <summary>由 PowerEventBridge 在 Suspend/Resume 时置位。</summary>
    internal void SetAsleep(bool asleep) => _isAsleep = asleep;

    public double IdleSeconds() => Win32IdleProbe.GetCurrentIdleSeconds();
}

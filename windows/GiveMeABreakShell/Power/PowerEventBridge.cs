using Microsoft.Win32;
using TimeoutEngine;

namespace TimeoutShell.Power;

// 订阅 SystemEvents.PowerModeChanged → engine.HandleSleep/Wake（对齐 macOS NSWorkspace willSleep/didWake）。
// SystemEvents 需 Windows 消息泵（WPF Application 提供）。
public sealed class PowerEventBridge : IDisposable
{
    private readonly LiveTimeoutEngine _engine;
    private readonly IHeartbeat _heartbeat;
    private readonly Adapters.WindowsSystemState _systemState;

    public PowerEventBridge(LiveTimeoutEngine engine, IHeartbeat heartbeat, Adapters.WindowsSystemState systemState)
    {
        _engine = engine;
        _heartbeat = heartbeat;
        _systemState = systemState;
    }

    public void Start() => SystemEvents.PowerModeChanged += OnPowerModeChanged;

    private void OnPowerModeChanged(object? sender, PowerModeChangedEventArgs e)
    {
        switch (e.Mode)
        {
            case PowerModes.Suspend:
                _heartbeat.Suspend();
                _systemState.SetAsleep(true);
                _engine.HandleSleep();
                Console.WriteLine("[Timeout][power] 系统睡眠");
                break;
            case PowerModes.Resume:
                _engine.HandleWake();
                _systemState.SetAsleep(false);
                _heartbeat.Resume();
                Console.WriteLine("[Timeout][power] 系统唤醒");
                break;
        }
    }

    public void Dispose() => SystemEvents.PowerModeChanged -= OnPowerModeChanged;
}

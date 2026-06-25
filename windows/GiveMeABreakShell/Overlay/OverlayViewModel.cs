using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace TimeoutShell.Overlay;

// 遮罩共享状态（镜像 Swift OverlayViewModel）。INPC 驱动 WPF 倒计时/确认双态切换。
public sealed class OverlayViewModel : INotifyPropertyChanged
{
    private bool _isConfirming;

    /// <summary>是否处于「提前结束确认」态（false=倒计时态）。</summary>
    public bool IsConfirming
    {
        get => _isConfirming;
        set
        {
            if (_isConfirming != value)
            {
                _isConfirming = value;
                OnPropertyChanged();
            }
        }
    }

    /// <summary>休息截止时刻（倒计时由 OverlayWindow DispatcherTimer 每秒更新）。</summary>
    public DateTimeOffset Deadline { get; }

    /// <summary>用户「直接退出」回调（AppRoot 桥接 engine.RequestEarlyRestExit）。</summary>
    public Action OnConfirmExit { get; }

    public OverlayViewModel(DateTimeOffset deadline, Action onConfirmExit)
    {
        Deadline = deadline;
        OnConfirmExit = onConfirmExit;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

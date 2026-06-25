using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;
using TimeoutEngine.Win32;

namespace TimeoutShell.Overlay;

/// <summary>全屏遮罩窗口（WPF）。镜像 macOS LiveOverlayController + docs/windows-port-design.md §5。</summary>
public partial class OverlayWindow : Window
{
    private readonly OverlayViewModel _vm;
    private readonly DispatcherTimer _timer;
    private DateTimeOffset _lastEscAt = DateTimeOffset.MinValue;

    public OverlayWindow(OverlayViewModel vm)
    {
        _vm = vm;
        InitializeComponent();
        _vm.PropertyChanged += (_, _) => UpdateConfirmVisibility();
        UpdateConfirmVisibility();
        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _timer.Tick += (_, _) => UpdateCountdown();
        UpdateCountdown();
        _timer.Start();
    }

    private void UpdateCountdown()
    {
        var remain = _vm.Deadline - DateTimeOffset.Now;
        int total = (int)Math.Ceiling(Math.Max(0, remain.TotalSeconds));
        CountdownText.Text = $"{total / 60:D2}:{total % 60:D2}";
    }

    private void UpdateConfirmVisibility()
    {
        CountdownPanel.Visibility = _vm.IsConfirming ? Visibility.Collapsed : Visibility.Visible;
        ConfirmPanel.Visibility = _vm.IsConfirming ? Visibility.Visible : Visibility.Collapsed;
    }

    /// <summary>Esc 双语义（镜像 macOS LiveOverlayController.swift:95-110）：
    /// 单击 toggle IsConfirming；双击（&lt;0.4s）→ OnConfirmExit → 引擎 RequestEarlyRestExit（不自 Dismiss）。</summary>
    private void OnKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Escape) return;
        e.Handled = true;
        var now = DateTimeOffset.Now;
        if ((now - _lastEscAt).TotalSeconds < 0.4)
        {
            _lastEscAt = DateTimeOffset.MinValue;
            _vm.OnConfirmExit();
        }
        else
        {
            _lastEscAt = now;
            _vm.IsConfirming = !_vm.IsConfirming;
        }
    }

    private void OnContinueClick(object sender, RoutedEventArgs e) => _vm.IsConfirming = false;

    private void OnExitClick(object sender, RoutedEventArgs e) => _vm.OnConfirmExit();

    /// <summary>规避 ShowInTaskbar=False 致 WS_EX_TOPMOST 失效坑（WebSearch 确认）：
    /// OnSourceInitialized 强制加 WS_EX_TOPMOST|TOOLWINDOW|NOACTIVATE + SetWindowPos(HWND_TOPMOST)。</summary>
    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        try
        {
            IntPtr hwnd = new WindowInteropHelper(this).Handle;
            int style = NativeOverlayMethods.GetWindowLong(hwnd, WindowEx.GwlExstyle);
            NativeOverlayMethods.SetWindowLong(hwnd, WindowEx.GwlExstyle,
                style | WindowEx.WsExTopmost | WindowEx.WsExToolwindow | WindowEx.WsExNoactivate);
            NativeOverlayMethods.SetWindowPos(hwnd, WindowEx.HwndTopmost, 0, 0, 0, 0,
                WindowEx.SwpNomove | WindowEx.SwpNosize | WindowEx.SwpNoactivate);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Timeout][overlay] SetWindowPos 强制置顶失败（降级）：{ex.Message}");
        }
    }
}

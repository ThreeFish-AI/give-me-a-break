using System.Runtime.InteropServices;
using Microsoft.Win32;
using TimeoutEngine;
using TimeoutEngine.Win32;
using TimeoutShell.Overlay;

namespace TimeoutShell.Adapters;

/// <summary>IOverlayController 实现：多屏全屏遮罩 + WH_KEYBOARD_LL soft-force + Esc 双语义。
/// 镜像 macOS LiveOverlayController + docs/windows-port-design.md §5 妥协分层。
/// headless（无桌面会话）全程 try/catch 降级，记 OVERLAY_* 标记供 CI 烟测断言。</summary>
public sealed class FullscreenOverlayController : IOverlayController, IDisposable
{
    private readonly System.Windows.Threading.Dispatcher _dispatcher;
    private readonly List<OverlayWindow> _windows = new();
    private KeyboardLowLevelHook? _hook;
    private OverlayViewModel? _vm;
    private bool _displayChangedSubscribed;

    /// <summary>用户「直接退出」回调（AppRoot 桥接 engine.RequestEarlyRestExit）。</summary>
    public Action? OnRequestEarlyExit;

    public bool IsShown => _windows.Count > 0;

    public FullscreenOverlayController(System.Windows.Threading.Dispatcher dispatcher) => _dispatcher = dispatcher;

    public void Show(DateTimeOffset restDeadline)
    {
        if (IsShown) return;   // 幂等
        try
        {
            _vm = new OverlayViewModel(restDeadline, () => OnRequestEarlyExit?.Invoke());
            foreach (var rect in EnumAllMonitors())
                CreateWindowForScreen(rect);
            _hook = new KeyboardLowLevelHook();
            _hook.Install();
            if (!_displayChangedSubscribed)
            {
                SystemEvents.DisplaySettingsChanged += OnDisplayChanged;
                _displayChangedSubscribed = true;
            }
            Console.WriteLine($"OVERLAY_SHOW_OK {_windows.Count} 屏 deadline={restDeadline:O}");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"OVERLAY_SHOW_FAIL {ex.Message}");
        }
    }

    public void Dismiss()
    {
        if (!IsShown) return;   // 幂等
        try
        {
            _hook?.Uninstall();
            _hook = null;
            foreach (var w in _windows) { try { w.Close(); } catch { } }
            _windows.Clear();
            _vm = null;
            Console.WriteLine("OVERLAY_DISMISS_OK");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"OVERLAY_DISMISS_FAIL {ex.Message}");
        }
    }

    private void CreateWindowForScreen(RECT rect)
    {
        var win = new OverlayWindow(_vm!)
        {
            Left = rect.Left,
            Top = rect.Top,
            Width = rect.Right - rect.Left,
            Height = rect.Bottom - rect.Top,
        };
        try { win.Show(); } catch (Exception ex) { Console.WriteLine($"OVERLAY_WINDOW_FAIL {ex.Message}"); }
        _windows.Add(win);
    }

    /// <summary>屏幕热插拔 → 重建窗口（对齐 macOS rebuildPanels）。</summary>
    private void OnDisplayChanged(object? sender, EventArgs e)
    {
        if (!IsShown) return;
        _dispatcher.BeginInvoke(new Action(() =>
        {
            foreach (var w in _windows) { try { w.Close(); } catch { } }
            _windows.Clear();
            foreach (var rect in EnumAllMonitors())
                CreateWindowForScreen(rect);
            Console.WriteLine($"OVERLAY_REBUILD {_windows.Count} 屏");
        }));
    }

    private static List<RECT> EnumAllMonitors()
    {
        var list = new List<RECT>();
        try
        {
            NativeOverlayMethods.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero,
                (_, _, lprc, _) => { list.Add(Marshal.PtrToStructure<RECT>(lprc)); return true; },
                IntPtr.Zero);
        }
        catch (Exception ex) { Console.WriteLine($"[Timeout][overlay] EnumDisplayMonitors 失败：{ex.Message}"); }
        if (list.Count == 0)
        {
            // 兜底：EnumDisplayMonitors 失败（headless 无桌面会话）时用虚拟主屏，保 Show 不崩。
            list.Add(new RECT { Left = 0, Top = 0, Right = 1920, Bottom = 1080 });
        }
        return list;
    }

    public void Dispose()
    {
        if (_displayChangedSubscribed) SystemEvents.DisplaySettingsChanged -= OnDisplayChanged;
        _hook?.Dispose();
        foreach (var w in _windows) { try { w.Close(); } catch { } }
        _windows.Clear();
    }
}

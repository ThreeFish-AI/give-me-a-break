using System.Runtime.InteropServices;

namespace TimeoutEngine.Win32;

// MARK: - 全屏遮罩 + 低级键盘钩子 P/Invoke（net8.0 可编译，运行时需 Windows）
// 镜像 docs/windows-port-design.md §5：WS_EX_TOPMOST + WH_KEYBOARD_LL 妥协分层。
// P/Invoke 声明是元数据，macOS 可编译；执行在 Windows 壳内。
// public：壳（TimeoutShell）多处调用（KeyboardHook/OverlayWindow/Controller），互操作库本职。

/// <summary>全屏遮罩 + 键盘钩子相关 Win32 P/Invoke。</summary>
public static class NativeOverlayMethods
{
    // ── 低级键盘钩子（拦截 Alt+Tab/Win/Ctrl+Esc，soft-force）──
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    public static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    // ── 窗口置顶（规避 ShowInTaskbar=false 致 WS_EX_TOPMOST 失效坑，WebSearch 确认）──
    [DllImport("user32.dll")]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    // ── 多屏枚举 ──
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumProc lpfnEnum, IntPtr dwData);
}

// MARK: - delegate 签名（壳实例化 + 防引用回收）

/// <summary>低级键盘钩子回调（WH_KEYBOARD_LL）。返回 IntPtr（LRESULT）。</summary>
public delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

/// <summary>显示器枚举回调（EnumDisplayMonitors）。lprcMonitor 为 RECT 指针。</summary>
public delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdcMonitor, IntPtr lprcMonitor, IntPtr dwData);

// MARK: - 结构

/// <summary>低级键盘钩子参数（WH_KEYBOARD_LL 的 lParam 指向此结构）。</summary>
[StructLayout(LayoutKind.Sequential)]
public struct KBDLLHOOKSTRUCT
{
    public uint vkCode;
    public uint scanCode;
    public uint flags;
    public uint time;
    public IntPtr dwExtraInfo;
}

[StructLayout(LayoutKind.Sequential)]
public struct POINT { public int X; public int Y; }

[StructLayout(LayoutKind.Sequential)]
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

// MARK: - 常量（值锁 NativeOverlayConstantsTests，防漂移）

/// <summary>钩子相关 Win32 常量。</summary>
public static class WinHook
{
    public const int WhKeyboardLl = 13;        // WH_KEYBOARD_LL
    public const int HcAction = 0;             // HC_ACTION（nCode：处理消息）
    public const int WmKeydown = 0x0100;       // WM_KEYDOWN
    public const int WmKeyup = 0x0101;         // WM_KEYUP
    public const int WmSyskeydown = 0x0104;    // WM_SYSKEYDOWN（Alt 组合键）
    public const int WmSyskeyup = 0x0105;      // WM_SYSKEYUP
    public const uint LlkhfAltdown = 0x0020;   // LLKHF_ALTDOWN（flags 位：Alt 按下）
}

/// <summary>窗口扩展样式 + SetWindowPos 常量。</summary>
public static class WindowEx
{
    public const int WsExTopmost = 0x00000008;      // WS_EX_TOPMOST
    public const int WsExToolwindow = 0x00000080;   // WS_EX_TOOLWINDOW
    public const int WsExNoactivate = 0x08000000;   // WS_EX_NOACTIVATE
    public const int GwlExstyle = -20;              // GWL_EXSTYLE

    public static readonly IntPtr HwndTopmost = new(-1);      // HWND_TOPMOST
    public static readonly IntPtr HwndNotopmost = new(-2);    // HWND_NOTOPMOST

    public const uint SwpNosize = 0x0001;       // SWP_NOSIZE
    public const uint SwpNomove = 0x0002;       // SWP_NOMOVE
    public const uint SwpNoactivate = 0x0010;   // SWP_NOACTIVATE
    public const uint SwpShowwindow = 0x0040;   // SWP_SHOWWINDOW
}

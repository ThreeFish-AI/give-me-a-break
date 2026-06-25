using Xunit;
using TimeoutEngine.Win32;

namespace TimeoutEngine.Win32Tests;

// MARK: - Win32 常量值锁（防漂移；net8.0 本地可验证）
// 这些常量是 WH_KEYBOARD_LL 钩子 + WS_EX_TOPMOST 窗口互操作的基础，值错会导致拦截/置顶失效。

public class NativeOverlayConstantsTests
{
    [Fact]
    public void KeyboardHookConstants()
    {
        Assert.Equal(13, WinHook.WhKeyboardLl);
        Assert.Equal(0, WinHook.HcAction);
    }

    [Fact]
    public void WindowMessageConstants()
    {
        Assert.Equal(0x0100, WinHook.WmKeydown);
        Assert.Equal(0x0101, WinHook.WmKeyup);
        Assert.Equal(0x0104, WinHook.WmSyskeydown);
        Assert.Equal(0x0105, WinHook.WmSyskeyup);
        Assert.Equal(0x0020u, WinHook.LlkhfAltdown);
    }

    [Fact]
    public void WindowExtendedStyleConstants()
    {
        Assert.Equal(0x00000008, WindowEx.WsExTopmost);
        Assert.Equal(0x00000080, WindowEx.WsExToolwindow);
        Assert.Equal(0x08000000, WindowEx.WsExNoactivate);
        Assert.Equal(-20, WindowEx.GwlExstyle);
    }

    [Fact]
    public void HwndTopmostHandles()
    {
        Assert.Equal(new IntPtr(-1), WindowEx.HwndTopmost);
        Assert.Equal(new IntPtr(-2), WindowEx.HwndNotopmost);
    }

    [Fact]
    public void SetWindowPosFlags()
    {
        Assert.Equal(0x0001u, WindowEx.SwpNosize);
        Assert.Equal(0x0002u, WindowEx.SwpNomove);
        Assert.Equal(0x0010u, WindowEx.SwpNoactivate);
        Assert.Equal(0x0040u, WindowEx.SwpShowwindow);
    }

    [Fact]
    public void WindowsKeyVirtualCodes()
    {
        Assert.Equal(0x5B, VirtualKeyCodes.LWin);
        Assert.Equal(0x5C, VirtualKeyCodes.RWin);
    }
}

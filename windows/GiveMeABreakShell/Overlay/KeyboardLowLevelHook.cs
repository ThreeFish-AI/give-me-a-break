using System.Runtime.InteropServices;
using TimeoutEngine.Win32;

namespace TimeoutShell.Overlay;

// WH_KEYBOARD_LL 低级键盘钩子（soft-force）。镜像 docs/windows-port-design.md §5。
// 拦截 Alt+Tab / Win(L/R)；放行 Esc（交 WPF 双语义）+ Ctrl+Alt+Del（SAS 不可拦，逃生口）。
//
// 关键妥协：LLKHF 仅有 ALTDOWN 标志、无 Ctrl 标志，无法在钩子内区分纯 Esc vs Ctrl+Esc。
// 故 Esc 全放行（WPF 双语义），不专门拦 Ctrl+Esc（开始菜单可弹，但遮罩 topmost 覆盖；
// 用户可 Ctrl+Alt+Del 逃生）。对齐软强制哲学（留摩擦非硬锁）。
public sealed class KeyboardLowLevelHook : IDisposable
{
    private IntPtr _hookHandle = IntPtr.Zero;
    // 保强引用防 GC 回收（钩子存活期；回调 delegate 被 native 引用，CLR 不知情会被回收）。
    private readonly LowLevelKeyboardProc _proc;

    private const uint VkTab = 0x09;

    public KeyboardLowLevelHook() => _proc = HookCallback;

    public bool IsInstalled => _hookHandle != IntPtr.Zero;

    public void Install()
    {
        if (IsInstalled) return;
        // hMod=nullptr + dwThreadId=0：全局低级钩子（当前进程，需消息泵——WPF Dispatcher 提供）。
        _hookHandle = NativeOverlayMethods.SetWindowsHookEx(WinHook.WhKeyboardLl, _proc, IntPtr.Zero, 0);
        if (!IsInstalled)
            Console.WriteLine("[Timeout][hook] SetWindowsHookEx 失败（headless/无桌面会话？降级不拦）");
    }

    public void Uninstall()
    {
        if (!IsInstalled) return;
        NativeOverlayMethods.UnhookWindowsHookEx(_hookHandle);
        _hookHandle = IntPtr.Zero;
    }

    // 回调极简零阻塞 IO（避 LowLevelHooksTimeout 系统繁忙时钩子被跳过漏拦）。
    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode == WinHook.HcAction)
        {
            int msg = wParam.ToInt32();
            bool keyDown = msg == WinHook.WmKeydown || msg == WinHook.WmSyskeydown;
            if (keyDown)
            {
                var k = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
                if (ShouldBlock(k))
                {
                    return (IntPtr)1;   // 吞掉（soft-force，不传 CallNextHookEx）
                }
            }
        }
        return NativeOverlayMethods.CallNextHookEx(_hookHandle, nCode, wParam, lParam);
    }

    /// <summary>拦截 Alt+Tab / Win(L/R)；放行其余（含 Esc、Ctrl+Alt+Del）。</summary>
    private static bool ShouldBlock(KBDLLHOOKSTRUCT k)
    {
        uint vk = k.vkCode;
        bool altDown = (k.flags & WinHook.LlkhfAltdown) != 0;
        if (altDown && vk == VkTab) return true;                              // Alt+Tab
        if (vk == VirtualKeyCodes.LWin || vk == VirtualKeyCodes.RWin) return true;  // Win 键
        return false;
    }

    public void Dispose() => Uninstall();
}

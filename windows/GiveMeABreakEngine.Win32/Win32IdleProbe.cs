using System.Runtime.InteropServices;

namespace TimeoutEngine.Win32;

// MARK: - 空闲检测（64 位 tick 回绕处理）
// 镜像文档 §4：GetLastInputInfo（32 位 tick）+ GetTickCount64（64 位，避 49.7 天回绕）。
// ComputeIdleSeconds 为纯函数（net8.0 可单测回绕）；GetCurrentIdleSeconds 封装 native 调用供壳工程跨工程使用。

/// <summary>系统空闲时长计算。GetLastInputInfo.dwTime 是 32 位 GetTickCount 值（49.7 天回绕）；
/// 用 GetTickCount64 的低 32 位与之做 uint 减法（自动回绕），只要空闲 &lt; 49.7 天即正确。</summary>
public static class Win32IdleProbe
{
    /// <summary>计算空闲秒数（纯函数，可单测回绕）。</summary>
    public static double ComputeIdleSeconds(uint lastInputTick, ulong nowTick64)
    {
        uint nowLow = (uint)(nowTick64 & 0xFFFFFFFFUL);
        uint idleTicks = nowLow - lastInputTick;   // uint 减法自动处理 32 位回绕
        return idleTicks / 1000.0;
    }

    /// <summary>获取当前空闲秒数（封装 native 调用）。
    /// public 以便壳工程（TimeoutShell）跨工程访问，规避 NativeMethods 的 internal 限制。</summary>
    public static double GetCurrentIdleSeconds()
    {
        var info = new LASTINPUTINFO { cbSize = (uint)Marshal.SizeOf<LASTINPUTINFO>() };
        if (!NativeMethods.GetLastInputInfo(ref info)) return 0;
        return ComputeIdleSeconds(info.dwTime, NativeMethods.GetTickCount64());
    }
}

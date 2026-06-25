using Xunit;
using TimeoutEngine.Win32;

namespace TimeoutEngine.Win32Tests;

// MARK: - 空闲检测 64 位 tick 回绕（文档 §4 强调的坑：须避 49.7 天回绕）

public class Win32IdleProbeTests
{
    [Fact]
    public void NormalCase_1000TicksBack_Is1Second()
    {
        // lastInput 在 1000ms 前，now=2000ms → 空闲 1s
        Assert.Equal(1.0, Win32IdleProbe.ComputeIdleSeconds(lastInputTick: 1000, nowTick64: 2000));
    }

    [Fact]
    public void ZeroIdle()
    {
        Assert.Equal(0.0, Win32IdleProbe.ComputeIdleSeconds(5000, 5000));
    }

    [Fact]
    public void Wraparound_Around32BitBoundary_Correct()
    {
        // 32 位 tick 回绕边界：lastInput = 0xFFFFFF00（回绕前），now 低 32 位 = 1280（回绕后）。
        // uint 减法回绕：1280 - 0xFFFFFF00 = 1280 + 256 = 1536 tick = 1.536s
        uint lastInput = 0xFFFFFF00u;   // 4294967040
        ulong now64 = 1280UL;           // 低 32 位 = 1280
        double idle = Win32IdleProbe.ComputeIdleSeconds(lastInput, now64);
        Assert.Equal(1.536, idle, 0.001);
    }

    [Fact]
    public void High64BitNow_Low32MatchesDwTime()
    {
        // 系统运行 > 49.7 天：now64 高位非 0，但低 32 位仍与 GetLastInputInfo.dwTime 同空间
        ulong now64 = 0x1_0000_0000UL + 5000UL;   // 低 32 位 = 5000
        Assert.Equal(2.0, Win32IdleProbe.ComputeIdleSeconds(3000, now64));   // 5000-3000=2000 tick=2s
    }
}

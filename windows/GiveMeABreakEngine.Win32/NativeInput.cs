using System.Runtime.InteropServices;

namespace TimeoutEngine.Win32;

// MARK: - Win32 P/Invoke 声明（net8.0 可编译，运行时需 Windows）
// [DllImport] 是元数据，macOS 上 dotnet build 不报错（不检查 DLL 存在）；执行时才 P/Invoke。

internal static class NativeMethods
{
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    [DllImport("kernel32.dll")]
    public static extern ulong GetTickCount64();

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
}

// MARK: - 结构体（对齐 Win32 内存布局）

/// <summary>GetLastInputInfo 的输出结构。</summary>
[StructLayout(LayoutKind.Sequential)]
public struct LASTINPUTINFO
{
    public uint cbSize;
    public uint dwTime;   // 32 位 tick（GetTickCount 空间，49.7 天回绕）
}

public static class InputType
{
    public const int Keyboard = 1;
}

public static class KeybdFlags
{
    public const uint KeyUp = 0x0002;
}

[StructLayout(LayoutKind.Sequential)]
public struct KEYBDINPUT
{
    public ushort wVk;
    public ushort wScan;
    public uint dwFlags;
    public uint time;
    public IntPtr dwExtraInfo;
}

/// <summary>SendInput 输入结构。仅键盘分支（mouse/hardware 省略，本项目只用媒体键）。
/// Explicit 布局模拟 C union；x64 下 union 偏移 8（type:4 + 对齐填充:4）。</summary>
[StructLayout(LayoutKind.Explicit)]
public struct INPUT
{
    [FieldOffset(0)] public int type;
    [FieldOffset(8)] public KEYBDINPUT ki;
}

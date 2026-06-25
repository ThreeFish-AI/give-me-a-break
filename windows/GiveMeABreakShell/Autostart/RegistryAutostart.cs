using Microsoft.Win32;

namespace TimeoutShell.Autostart;

// 开机自启 · HKCU\Software\Microsoft\Windows\CurrentVersion\Run（非提权）。
// 对齐 macOS LoginService(SMAppService)。写 HKCU 无需管理员权限。
public static class RegistryAutostart
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "Timeout";

    public static bool IsEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKey);
        return key?.GetValue(ValueName) is string s && s.Length > 0;
    }

    public static void Enable(string exePath)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKey);
        key.SetValue(ValueName, $"\"{exePath}\"");
    }

    public static void Disable()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true);
        key?.DeleteValue(ValueName, throwOnMissingValue: false);
    }
}

using System.Diagnostics;

namespace TimeoutEngine.Win32;

// MARK: - QQ 音乐进程检测（mockable，对齐 macOS NSWorkspace.runningApplications）
// 对齐 Sources/TimeoutIntegrations/LiveMusicController.swift 的 QQ 音乐联动语义。

/// <summary>进程名查询的可注入端口。生产用 ProcessNameProvider（调 Process.GetProcessesByName）；
/// 测试用 mock。</summary>
public interface IProcessNameProvider
{
    /// <summary>返回匹配进程名的进程标识数组（长度>0 表示存在）。</summary>
    string[] GetProcessNames(string processName);
}

/// <summary>Process.GetProcessesByName 实现（运行时跨平台，但语义对齐 Windows QQ 音乐进程名）。</summary>
public sealed class ProcessNameProvider : IProcessNameProvider
{
    public string[] GetProcessNames(string processName)
    {
        var procs = Process.GetProcessesByName(processName);
        var names = new string[procs.Length];
        for (int i = 0; i < procs.Length; i++) names[i] = procs[i].ProcessName;
        return names;
    }
}

/// <summary>QQ 音乐运行检测。
/// 候选进程名需用户在 Windows 真机实测校准（CI 无法验证）；检测不到仅不发媒体键，粉噪音仍响，不阻塞。</summary>
public sealed class QqMusicDetector
{
    private readonly IProcessNameProvider _provider;

    /// <summary>QQ 音乐候选进程名（需用户实测校准：Windows 版进程名可能是 QQMusic / QQMusicTray 等）。</summary>
    public static readonly string[] CandidateProcessNames = { "QQMusic", "QQMusicTray" };

    public QqMusicDetector(IProcessNameProvider provider) => _provider = provider;

    public bool IsRunning()
    {
        foreach (var name in CandidateProcessNames)
        {
            if (_provider.GetProcessNames(name).Length > 0) return true;
        }
        return false;
    }
}

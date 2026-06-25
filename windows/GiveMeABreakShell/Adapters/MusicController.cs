using System.Diagnostics;
using System.IO;
using TimeoutEngine;
using TimeoutEngine.Win32;

namespace TimeoutShell.Adapters;

// IMusicController 实现 · 粉噪音（可靠底噪）+ QQ 音乐媒体键联动（可选增强）。
// 对齐 macOS LiveMusicController：ambientSoundEnabled 控粉噪音，controlQQMusic 控 QQ 音乐媒体键。
// toggle 语义继承（VK_MEDIA_PLAY_PAUSE 与 NX_KEYTYPE_PLAY 同为 toggle，正在播时发键反暂停是已知限制）。
public sealed class MusicController : IMusicController, IDisposable
{
    private readonly WasapiAmbientPlayer _ambient;
    private readonly MediaKeySender _mediaKey;
    private readonly QqMusicDetector _qqDetector;
    private DayPlanConfig _config = DayPlanConfig.Default;

    public MusicController(WasapiAmbientPlayer ambient, MediaKeySender mediaKey, QqMusicDetector qqDetector)
    {
        _ambient = ambient;
        _mediaKey = mediaKey;
        _qqDetector = qqDetector;
    }

    public void UpdateConfig(DayPlanConfig config) => _config = config;

    public void StartPlayback()
    {
        if (_config.AmbientSoundEnabled) _ambient.Start();
        if (_config.ControlQQMusic) StartQQMusic();
    }

    public void PausePlayback()
    {
        _ambient.Stop();   // 幂等：未播放时 no-op
        if (_config.ControlQQMusic)
        {
            _mediaKey.SendPlayPause();   // toggle → 暂停（保留队列/进度）
            Console.WriteLine("[Timeout][music] 发送 pause 媒体键（toggle，保留队列）");
        }
    }

    private void StartQQMusic()
    {
        bool running = _qqDetector.IsRunning();
        Console.WriteLine($"[Timeout][music] QQ 音乐：running={running}");
        if (!running) QqMusicLauncher.TryLaunch();
        // 启动后稍候再发媒体键，确保 QQ 音乐已注册为 Now Playing（对齐 macOS 1.5s 等待）
        _ = Task.Run(async () =>
        {
            await Task.Delay(1500);
            _mediaKey.SendPlayPause();
            Console.WriteLine("[Timeout][music] 发送 play 媒体键");
        });
    }

    public void Dispose() => _ambient.Dispose();
}

/// <summary>QQ 音乐拉起（路径探测兜底；CI 无 QQ 音乐仅记录尝试）。</summary>
internal static class QqMusicLauncher
{
    private static readonly string[] CandidatePaths =
    {
        @"C:\Program Files (x86)\Tencent\QQMusic\QQMusic.exe",
        @"C:\Program Files\Tencent\QQMusic\QQMusic.exe",
    };

    public static void TryLaunch()
    {
        foreach (var path in CandidatePaths)
        {
            if (File.Exists(path))
            {
                try
                {
                    Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
                    Console.WriteLine("[Timeout][music] 已拉起 QQ 音乐");
                    return;
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[Timeout][music] 拉起 QQ 音乐失败：{ex.Message}");
                }
            }
        }
        Console.WriteLine("[Timeout][music] 未找到 QQ 音乐，跳过启动");
    }
}

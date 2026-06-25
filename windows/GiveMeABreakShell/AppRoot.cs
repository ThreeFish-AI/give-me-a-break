using System.Windows.Threading;
using TimeoutEngine;
using TimeoutEngine.Win32;
using TimeoutShell.Adapters;
using TimeoutShell.Power;
using TimeoutShell.Tray;
using TimeoutEngine.Graph;

namespace TimeoutShell;

// 装配点 · 镜像 Swift AppRoot.swift。汇聚 6 个 interface 实现 → 注入 LiveTimeoutEngine →
// 崩溃恢复 → 持久化 handler → 电源事件 → 心跳 1Hz tick → 托盘（非 headless）。
public sealed class AppRoot : IDisposable
{
    private readonly ConfigStore _store;
    private DayPlanConfig _config;
    private readonly WindowsSystemState _systemState = new();
    private readonly ICalendarProvider _calendar;
    private readonly FullscreenOverlayController _overlay;
    private readonly WasapiAmbientPlayer _ambient;
    private readonly MusicController _music;
    private readonly HeartbeatTimer _heartbeat;
    private LiveTimeoutEngine _engine = null!;
    private PowerEventBridge? _power;
    private TrayController? _tray;

    public AppRoot(Dispatcher dispatcher)
    {
        string dir = ConfigStore.DefaultDirectory("com.aurelius.timeout");
        _store = new ConfigStore(dir);
        _config = _store.LoadConfig();
        if (Environment.GetEnvironmentVariable("TIMEOUT_DEBUG") == "1") ApplyDebugConfig();

        _calendar = BuildCalendarProvider(_config);
        _ambient = new WasapiAmbientPlayer(new PinkNoiseGenerator());
        _music = new MusicController(_ambient,
            new MediaKeySender(new PInvokeSendInputPort()),
            new QqMusicDetector(new ProcessNameProvider()));
        _overlay = new FullscreenOverlayController(dispatcher);
        _heartbeat = new HeartbeatTimer(dispatcher);
    }

    public LiveTimeoutEngine Engine => _engine;

    public void Start(bool headless)
    {
        _engine = new LiveTimeoutEngine(
            clock: new SystemClock(),
            calendarProvider: _calendar,
            overlay: _overlay,
            music: _music,
            systemState: _systemState,
            config: _config,
            initialState: _store.LoadState());
        _overlay.OnRequestEarlyExit = () => _engine.RequestEarlyRestExit();  // Esc 双击 → 引擎内部 Dismiss（不自 Dismiss）
        _engine.SetPersistHandler(s => _store.SaveState(s));
        _engine.FastForward();

        _power = new PowerEventBridge(_engine, _heartbeat, _systemState);
        _power.Start();

        if (!headless)
            _tray = new TrayController(_engine, () => Console.WriteLine("[Timeout][settings] (Phase 1 占位)"));

        _heartbeat.Start(1.0, () => _engine.Tick());
        Console.WriteLine($"[Timeout][root] ASSEMBLY_OK 装配完成 headless={headless} interval={_config.WorkIntervalSeconds}s rest={_config.RestDurationSeconds}s");
    }

    /// <summary>TIMEOUT_DEBUG 极速配置：使 CI 烟测在 5s 内见证 working→resting→working 相位转移。</summary>
    private void ApplyDebugConfig()
    {
        _config = new DayPlanConfig
        {
            WorkWindows = new() { new WorkWindow(new TimeOfDay(0, 0), new TimeOfDay(23, 59)) },
            WorkIntervalSeconds = 2,        // 2s 工作
            RestDurationSeconds = 1,        // 1s 休息
            AfkThresholdSeconds = 999_999,  // 抑制 idle 干扰（runner 无人操作），确保触发相位转移
            AmbientSoundEnabled = false,    // headless 无音频设备，避免 WASAPI 异常
            ControlQQMusic = false,
        };
        Console.WriteLine("[Timeout][debug] TIMEOUT_DEBUG 极速配置（2s 工作 / 1s 休息）");
    }

    /// <summary>按 graphClientId 条件注入日历门控；空/失败 → EmptyCalendarProvider 降级（headless 不崩）。</summary>
    private ICalendarProvider BuildCalendarProvider(DayPlanConfig config)
    {
        var clientId = config.GraphClientId;
        if (string.IsNullOrWhiteSpace(clientId))
        {
            Console.WriteLine("CALENDAR_DEGRADED graphClientId 为空，日历门控降级（无会议）");
            return new EmptyCalendarProvider();
        }
        try
        {
            var client = new MsalGraphClient(clientId);
            if (!client.IsConfigured) return new EmptyCalendarProvider();
            Console.WriteLine($"[Timeout][calendar] Graph 日历门控已装配（client id 末 4 位：…{clientId[^4..]}）");
            return new GraphCalendarProvider(client, new SystemClock());
        }
        catch (Exception ex)
        {
            Console.WriteLine($"CALENDAR_DEGRADED Graph 装配失败，降级：{ex.Message}");
            return new EmptyCalendarProvider();
        }
    }

    public void Dispose()
    {
        _heartbeat.Stop();
        _power?.Dispose();
        _tray?.Dispose();
        _overlay.Dispose();   // 卸键盘钩子 + 关遮罩窗
        _music.Dispose();
    }
}

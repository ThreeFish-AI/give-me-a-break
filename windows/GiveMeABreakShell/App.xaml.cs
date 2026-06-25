using System.Windows;
using System.Windows.Threading;

namespace TimeoutShell;

// WPF 入口 · 装配 AppRoot。headless 旁路支持 CI 烟测（TIMEOUT_HEADLESS=1 跳过托盘，5s 后自退）。
public partial class App : Application
{
    private AppRoot? _root;
    private DispatcherTimer? _exitTimer;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        // 尝试 UTF-8 输出（有控制台时中文可读）；stdout 重定向到文件（CI）时 SetConsoleOutputCP
        // 无控制台句柄会抛 IOException——忽略。CI 断言依赖 ASCII 标记（ASSEMBLY_OK/STARTUP_OK），
        // 不依赖中文编码，故 UTF-8 失效不影响断言。
        try { Console.OutputEncoding = System.Text.Encoding.UTF8; } catch (System.IO.IOException) { }
        bool headless = Environment.GetEnvironmentVariable("TIMEOUT_HEADLESS") == "1";
        string debug = Environment.GetEnvironmentVariable("TIMEOUT_DEBUG") ?? "0";

        _root = new AppRoot(Dispatcher);
        _root.Start(headless);
        Console.WriteLine($"[Timeout] STARTUP_OK 启动完成 (headless={headless}, debug={debug})");

        if (headless)
        {
            // CI 烟测：5 秒后自动退出（exit 0）；若此前崩溃，进程异常退出被 CI 捕获。
            _exitTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
            _exitTimer.Tick += (_, _) =>
            {
                Console.WriteLine("[Timeout] headless 5s 到，正常退出 (exit 0)");
                _root.Dispose();
                Shutdown(0);
            };
            _exitTimer.Start();
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _root?.Dispose();
        base.OnExit(e);
    }
}

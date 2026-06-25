namespace TimeoutEngine;

// MARK: - 集成契约（接口）
// 镜像 Sources/TimeoutEngine/Protocols.swift。Phase 0 仅定义接口（签名无平台依赖）；
// Win32 实现（托盘/遮罩/音频/日历/系统状态/心跳）为 Phase 1+ 范围。

// MARK: - 时钟抽象（注入虚拟时钟即可单元测试，零真实时间依赖）

public interface IClock
{
    DateTimeOffset Now();
}

public sealed class SystemClock : IClock
{
    public DateTimeOffset Now() => DateTimeOffset.Now;
}

// MARK: - 三大集成契约

/// <summary>全屏遮罩控制器：多屏覆盖 + 软强制 Esc 二次确认。</summary>
public interface IOverlayController
{
    /// <summary>进入休息：显示遮罩，倒计时至 restDeadline。</summary>
    void Show(DateTimeOffset restDeadline);

    /// <summary>离开休息：退出遮罩（幂等）。</summary>
    void Dismiss();

    bool IsShown { get; }
}

/// <summary>音乐控制器：休息音效（内置粉噪音 + 可选 QQ 音乐媒体键联动）。</summary>
public interface IMusicController
{
    /// <summary>同步音乐相关配置（由引擎在初始化与 UpdateConfig 时调用）。</summary>
    void UpdateConfig(DayPlanConfig config);

    /// <summary>进入休息：按配置播放内置粉噪音 / 联动 QQ 音乐。</summary>
    void StartPlayback();

    /// <summary>离开休息：停止粉噪音 + 发送暂停媒体键（幂等）。</summary>
    void PausePlayback();
}

/// <summary>日历提供者：返回合并后的忙碌时间线。</summary>
public interface ICalendarProvider
{
    MeetingTimeline CurrentTimeline();
}

/// <summary>系统状态提供者：AFK 空闲秒数 + 睡眠标志。</summary>
public interface ISystemStateProvider
{
    bool IsAsleep { get; }
    double IdleSeconds();
}

// MARK: - 心跳抽象

public interface IHeartbeat
{
    void Start(double intervalSeconds, Action handler);
    void Suspend();
    void Resume();
    void Stop();
}

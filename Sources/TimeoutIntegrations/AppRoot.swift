import AppKit
import TimeoutEngine

private let bundleId = "com.aurelius.timeout"

/// 应用根装配点：装配引擎 + 心跳 + 系统采样 + 三大 controller，并注册睡眠/唤醒观察者。
/// 启动加载持久化 config/state；运行期节流持久化状态；退出时落盘。
final public class AppRoot {
    public static let shared = AppRoot()

    private var statusItem: StatusItemController?
    private var engine: LiveTimeoutEngine?
    private var overlayController: LiveOverlayController?
    private var calendarProvider: LiveCalendarProvider?
    private var heartbeat: HeartbeatTimer?
    private var sensors: SystemSensors?
    private var configStore: ConfigStore?
    private var settingsController: SettingsWindowController?
    private var sleepObservers: [NSObjectProtocol] = []

    private var lastSavedPhase: EnginePhase?
    private var lastSaveAt: Date = .distantPast

    private init() {}

    public func start() {
        AccessibilityChecker.bootstrap()  // 引导 Accessibility 授权（媒体键控制必需）

        let dir = ConfigStore.defaultDirectory(bundleId: bundleId)
        let store: ConfigStore?
        do {
            store = try ConfigStore(directory: dir)
        } catch {
            NSLog("[Timeout] 持久化目录初始化失败，本次运行不落盘：\(error)")
            store = nil
        }
        configStore = store

        let config = debugConfigOrLoaded(store: store)
        let sensors = SystemSensors()
        self.sensors = sensors

        let overlay = LiveOverlayController()
        overlay.onRequestEarlyExit = { [weak self] in self?.engine?.requestEarlyRestExit() }
        self.overlayController = overlay

        let calendar = LiveCalendarProvider()
        calendar.bootstrap()  // 触发日历权限请求（用户手动授予）
        self.calendarProvider = calendar

        let engine = LiveTimeoutEngine(
            clock: SystemClock(),
            calendarProvider: calendar,
            overlay: overlay,
            music: LiveMusicController(),
            systemState: sensors,
            config: config,
            initialState: store?.loadState()
        )
        engine.fastForward()  // 启动崩溃恢复
        engine.setPersistHandler { [weak self] state in self?.handlePersist(state) }
        self.engine = engine
        lastSavedPhase = engine.state.phase

        statusItem = StatusItemController(
            onForceRest: { [weak self] in
                self?.engine?.forceRestNow()
                self?.engine?.tick()  // 立即生效，不等下一秒心跳
            },
            loginEnabled: LoginService.isEnabled,
            onSetLaunchAtLogin: { LoginService.setEnabled($0) },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )

        let heartbeat = HeartbeatTimer(queue: .main)  // 主队列：副作用（overlay/music）均 UI 安全
        heartbeat.start(interval: 1.0) { [weak self] in
            guard let self else { return }
            self.engine?.tick()
            if let phase = self.engine?.state.phase {
                self.statusItem?.setStatus(text: self.statusText(for: phase, engine: self.engine))
            }
        }
        self.heartbeat = heartbeat

        settingsController = SettingsWindowController { [weak self] newConfig in
            guard let self else { return }
            if let store = self.configStore {
                do { try store.saveConfig(newConfig) }
                catch { NSLog("[Timeout] 配置保存失败：\(error.localizedDescription)") }
            }
            self.engine?.updateConfig(newConfig)
            NSLog("[Timeout] 配置已应用：\(newConfig.workWindows.count) 个工作窗口 / 工作 \(Int(newConfig.workIntervalSeconds/60))min / 休息 \(Int(newConfig.restDurationSeconds/60))min")
        }

        registerSleepObservers()
        NSLog("[Timeout] 引擎启动 phase=\(engine.state.phase.rawValue) accum=\(Int(engine.state.workAccumulatedSeconds))s")

        // 调试：启动即打开设置窗（便于截图验证 UI）
        if ProcessInfo.processInfo.environment["TIMEOUT_SHOW_SETTINGS"] != nil {
            openSettings()
        }
    }

    /// 应用退出前落盘最终状态。
    public func shutdown() {
        if let state = engine?.state { configStore?.saveState(state) }
        heartbeat?.stop()
        for observer in sleepObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        sleepObservers.removeAll()
    }

    // MARK: - 设置窗口

    func openSettings() {
        guard let config = engine?.config else { return }
        settingsController?.show(currentConfig: config)
    }

    // MARK: - 调试配置

    /// TIMEOUT_DEBUG=1 时使用极速配置（8s 工作 / 15s 休息 / 全天窗口 / 禁用 AFK）便于手动验证遮罩与音乐。
    private func debugConfigOrLoaded(store: ConfigStore?) -> DayPlanConfig {
        if ProcessInfo.processInfo.environment["TIMEOUT_DEBUG"] != nil {
            var c = DayPlanConfig.defaultConfig
            c.workIntervalSeconds = 8
            c.restDurationSeconds = 15
            c.afkThresholdSeconds = 999_999
            c.workWindows = [WorkWindow(start: TimeOfDay(hours: 0), end: TimeOfDay(hours: 23, minutes: 59))]
            NSLog("[Timeout] DEBUG 模式：8s 工作 / 15s 休息 / 全天窗口")
            return c
        }
        return store?.loadConfig() ?? .defaultConfig
    }

    // MARK: - 节流持久化（phase 变化或每 5s 落盘一次）

    private func handlePersist(_ state: EngineState) {
        let now = Date()
        let phaseChanged = state.phase != lastSavedPhase
        guard phaseChanged || now.timeIntervalSince(lastSaveAt) > 5 else { return }
        configStore?.saveState(state)
        lastSavedPhase = state.phase
        lastSaveAt = now
    }

    // MARK: - 菜单栏倒计时文案

    private func statusText(for phase: EnginePhase, engine: LiveTimeoutEngine?) -> String {
        guard let engine else { return "🍅" }
        switch phase {
        case .working:
            let remain = max(0, engine.config.workIntervalSeconds - engine.state.workAccumulatedSeconds)
            return "工作 \(Int(ceil(remain / 60)))′"
        case .resting:
            guard let start = engine.state.restStartedAt else { return "休息中" }
            let deadline = start.addingTimeInterval(engine.config.restDurationSeconds)
            let remain = max(0, deadline.timeIntervalSince(Date()))
            return "休息 \(Int(ceil(remain / 60)))′"
        case .inMeeting: return "会议中"
        case .idle: return "暂停"
        case .offDuty: return "下班"
        }
    }

    // MARK: - 睡眠 / 唤醒

    private func registerSleepObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        let will = nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sensors?.isAsleep = true
            self?.engine?.handleSleep()
            self?.heartbeat?.suspend()
            NSLog("[Timeout] 系统睡眠：挂起心跳")
        }
        let did = nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sensors?.isAsleep = false
            self?.heartbeat?.resume()
            self?.engine?.handleWake()
            NSLog("[Timeout] 系统唤醒：恢复心跳 + 重置对账基点")
        }
        sleepObservers = [will, did]
    }
}

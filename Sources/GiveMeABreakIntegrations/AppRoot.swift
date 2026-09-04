import AppKit
import Carbon.HIToolbox
import GiveMeABreakEngine

private let bundleId = "com.aurelius.givemeabreak"

/// 应用根装配点：装配引擎 + 心跳 + 系统采样 + 三大 controller，并注册睡眠/唤醒观察者。
/// 启动加载持久化 config/state；运行期节流持久化状态；退出时落盘。
final public class AppRoot {
    public static let shared = AppRoot()

    private var statusItem: StatusItemController?
    private var engine: LiveGiveMeABreakEngine?
    private var overlayController: LiveOverlayController?
    private var calendarProvider: LiveCalendarProvider?
    private var heartbeat: HeartbeatTimer?
    private var sensors: SystemSensors?
    private var configStore: ConfigStore?
    private var settingsController: SettingsWindowController?
    private var sleepObservers: [NSObjectProtocol] = []

    // 主动屏幕遮罩（遮罩期间挂起心跳冻结引擎，不触碰调度决策状态）+ 系统锁屏快捷键接管 + 全局快捷键
    private var screenMaskController: ScreenMaskController?
    private var lockShortcutMonitor: LockShortcutMonitor?
    private var globalHotkeyCenter: GlobalHotkeyCenter?

    // 工作日志（休息前记录 + 周期报告 + 补录漏掉的时段）
    private var workLogStore: WorkLogStore?
    private var workLogPromptController: WorkLogPromptWindowController?
    private var workLogReportController: WorkLogReportWindowController?
    private var workLogBackfillController: WorkLogBackfillWindowController?
    /// 连续跳过计数（会话内；≥3 则下次静默并自愈，对抗提示疲劳）。
    private var consecutiveSkips: Int = 0

    // 运动记录（休息自然结束后记录 + 综合报告 + 补录漏掉的时段）
    private var exerciseStore: ExerciseStore?
    private var exercisePromptController: ExercisePromptWindowController?
    private var exerciseBackfillController: ExerciseBackfillWindowController?
    private var combinedReportController: CombinedReportWindowController?
    /// 运动记录连续跳过计数（会话内；≥3 则下次静默并自愈，对抗提示疲劳）。
    private var consecutiveExerciseSkips: Int = 0

    private var lastSavedPhase: EnginePhase?
    private var lastSaveAt: Date = .distantPast

    private init() {}

    public func start() {
        AccessibilityChecker.bootstrap()  // 引导 Accessibility 授权（媒体键控制必需）

        screenMaskController = ScreenMaskController()
        screenMaskController?.onDismiss = { [weak self] in self?.handleScreenMaskDismissed() }
        let lockShortcut = LockShortcutMonitor()
        lockShortcut.onTriggered = { [weak self] in self?.enterScreenMask() }
        lockShortcut.start()  // 引导「输入监控」授权；未授权时自动降级，仅菜单「屏幕遮罩」可用
        lockShortcutMonitor = lockShortcut

        // 全局快捷键（零权限，任意应用前台生效）：⌃⌥⌘R 立即休息 / ⌃⌥⌘K 屏幕遮罩。
        // 菜单项裸字母快捷键仅在菜单展开时生效（AppKit 原生行为），全局诉求由本层承载。
        let hotkeys = GlobalHotkeyCenter()
        let hyperModifiers = UInt32(controlKey | optionKey | cmdKey)
        hotkeys.register(keyCode: UInt32(kVK_ANSI_R), modifiers: hyperModifiers) { [weak self] in
            self?.forceRestNow()
        }
        hotkeys.register(keyCode: UInt32(kVK_ANSI_K), modifiers: hyperModifiers) { [weak self] in
            self?.enterScreenMask()
        }
        globalHotkeyCenter = hotkeys

        let dir = ConfigStore.defaultDirectory(bundleId: bundleId)
        let store: ConfigStore?
        do {
            store = try ConfigStore(directory: dir)
        } catch {
            NSLog("[GiveMeABreak] 持久化目录初始化失败，本次运行不落盘：\(error)")
            store = nil
        }
        configStore = store

        // 工作日志存储（复用同一 Application Support 目录；独立 work-log.json）
        let workLog: WorkLogStore?
        do {
            workLog = try WorkLogStore(directory: dir)
        } catch {
            NSLog("[GiveMeABreak] 工作日志目录初始化失败，本次运行不记录：\(error)")
            workLog = nil
        }
        workLogStore = workLog
        workLogPromptController = WorkLogPromptWindowController()
        if let workLog { workLogReportController = WorkLogReportWindowController(store: workLog) }
        workLogBackfillController = WorkLogBackfillWindowController(onSave: { [weak self] entry in
            self?.workLogStore?.append(entry)   // 补录条目按 startedAt 排序并入 work-log.json
        })

        // 运动记录存储（复用同一 Application Support 目录；独立 exercise-log.json）
        let exercise: ExerciseStore?
        do {
            exercise = try ExerciseStore(directory: dir)
        } catch {
            NSLog("[GiveMeABreak] 运动记录目录初始化失败，本次运行不记录：\(error)")
            exercise = nil
        }
        exerciseStore = exercise
        exercisePromptController = ExercisePromptWindowController()
        exerciseBackfillController = ExerciseBackfillWindowController(onSave: { [weak self] entry in
            guard let self else { return }
            self.exerciseStore?.append(entry)              // 落库 exercise-log.json
            self.learnCustomExerciseTypes(from: entry.sets) // 自定义类型自动记住 → config.exerciseTypes
        })
        if let exercise, let workLog {
            combinedReportController = CombinedReportWindowController(
                workStore: workLog,
                exerciseStore: exercise,
                exerciseTypesProvider: { [weak self] in
                    self?.engine?.config.exerciseTypes ?? defaultExerciseTypes
                },
                onSaveExercise: { [weak self] entry in
                    guard let self else { return }
                    self.exerciseStore?.append(entry)
                    self.learnCustomExerciseTypes(from: entry.sets)
                },
                onUpdateExercise: { [weak self] entry in
                    guard let self else { return }
                    self.exerciseStore?.update(entry)
                    self.learnCustomExerciseTypes(from: entry.sets)
                }
            )
        }

        let config = debugConfigOrLoaded(store: store)
        let sensors = SystemSensors()
        self.sensors = sensors

        let overlay = LiveOverlayController()
        overlay.onRequestEarlyExit = { [weak self] in self?.engine?.requestEarlyRestExit() }
        self.overlayController = overlay

        let calendar = LiveCalendarProvider()
        calendar.bootstrap()  // 触发日历权限请求（用户手动授予）
        self.calendarProvider = calendar

        let engine = LiveGiveMeABreakEngine(
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
        engine.onPreBreak = { [weak self] ctx in self?.handlePreBreak(ctx) }  // 工作日志：休息前拦截
        engine.onPostBreak = { [weak self] ctx in self?.handlePostBreak(ctx) }  // 运动记录：休息自然结束后录入
        self.engine = engine
        lastSavedPhase = engine.state.phase

        statusItem = StatusItemController(
            onForceRest: { [weak self] in self?.forceRestNow() },
            onEnterScreenMask: { [weak self] in self?.enterScreenMask() },
            loginEnabled: LoginService.isEnabled,
            onSetLaunchAtLogin: { LoginService.setEnabled($0) },
            onOpenSettings: { [weak self] in self?.openSettings() },
            onOpenWorkLog: { [weak self] in self?.openWorkLog() },
            onOpenBackfillWorkLog: { [weak self] in self?.openBackfillWorkLog() },
            onOpenCombinedReport: { [weak self] in self?.openCombinedReport() },
            onOpenBackfillExercise: { [weak self] in self?.openBackfillExercise() }
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

        settingsController = SettingsWindowController(
            onApply: { [weak self] newConfig in
                guard let self else { return }
                if let store = self.configStore {
                    do { try store.saveConfig(newConfig) }
                    catch { NSLog("[GiveMeABreak] 配置保存失败：\(error.localizedDescription)") }
                }
                self.engine?.updateConfig(newConfig)
                NSLog("[GiveMeABreak] 配置已应用：\(newConfig.workWindows.count) 个工作窗口 / 工作 \(Int(newConfig.workIntervalSeconds/60))min / 休息 \(Int(newConfig.restDurationSeconds/60))min / 白噪音\(newConfig.ambientSoundEnabled ? "开" : "关") / QQ音乐\(newConfig.controlQQMusic ? "开" : "关")")
            },
            onToggleLogin: { LoginService.setEnabled($0) }
        )

        registerSleepObservers()
        NSLog("[GiveMeABreak] 引擎启动 phase=\(engine.state.phase.rawValue) accum=\(Int(engine.state.workAccumulatedSeconds))s")

        // 调试：启动即打开设置窗（便于截图验证 UI）
        if ProcessInfo.processInfo.environment["GIVEMEABREAK_SHOW_SETTINGS"] != nil {
            openSettings()
        }
        // 调试：启动即打开工作日志窗（便于截图验证阅读器；可配合 GIVEMEABREAK_WORKLOG_SCOPE=today|week|month|all）
        if ProcessInfo.processInfo.environment["GIVEMEABREAK_SHOW_WORKLOG"] != nil {
            openWorkLog()
        }
        // 调试：启动即打开综合报告窗（便于截图验证；可配合 GIVEMEABREAK_COMBINED_SCOPE=week|month|quarter|year）
        if ProcessInfo.processInfo.environment["GIVEMEABREAK_SHOW_COMBINED"] != nil {
            openCombinedReport()
        }
    }

    /// 应用退出前落盘最终状态。
    public func shutdown() {
        if let state = engine?.state { configStore?.saveState(state) }
        heartbeat?.stop()
        lockShortcutMonitor?.stop()
        for observer in sleepObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        sleepObservers.removeAll()
    }

    // MARK: - 设置窗口

    func openSettings() {
        guard let config = engine?.config else { return }
        settingsController?.show(currentConfig: config, loginEnabled: LoginService.isEnabled)
    }

    // MARK: - 主动屏幕遮罩（菜单「屏幕遮罩」+ 系统锁屏快捷键接管的共同入口）

    /// 进入手动屏幕遮罩。遮罩期间**冻结引擎**（挂起心跳）：工作计时暂停、计划性休息及其小结窗
    /// 不会在遮罩中触发。已在强制休息中（.resting，含工作日志小结窗延迟期）时忽略，避免叠加两组遮罩面板。
    func enterScreenMask() {
        guard engine?.state.phase != .resting else {
            NSLog("[GiveMeABreak][screenMask] 强制休息进行中，忽略手动遮罩触发")
            return
        }
        guard let mask = screenMaskController, !mask.isShown else { return }  // 已显示：幂等忽略
        mask.show()
        heartbeat?.suspend()  // 遮罩 ⇒ 引擎冻结（与 handleWake 的 resume 严格配对，见 didWake 守卫）
        NSLog("[GiveMeABreak][screenMask] 遮罩期间工作计时已冻结")
    }

    /// 遮罩结束（双击 Esc / 被「立即休息」让位）：遮罩时长不计入工作累加器（rebase 对账基点，
    /// 语义同 handleWake）+ 恢复心跳。与 enterScreenMask 的 suspend 严格配对。
    private func handleScreenMaskDismissed() {
        engine?.handleScreenMaskEnded()
        heartbeat?.resume()
        NSLog("[GiveMeABreak][screenMask] 遮罩结束：恢复工作计时")
    }

    /// 立即休息（菜单「立即休息」/ 全局快捷键 ⌃⌥⌘R 共用入口）：立即生效，不等下一秒心跳。
    /// 显式用户动作优先于遮罩：先撤遮罩（onDismiss 回调 rebase + 恢复心跳），再进入强制休息。
    func forceRestNow() {
        screenMaskController?.dismiss()
        engine?.forceRestNow()
        engine?.tick()
    }

    // MARK: - 工作日志

    /// 打开「工作日志」报告窗口（菜单入口）。
    func openWorkLog() {
        workLogReportController?.show()
    }

    /// 打开「补录工作日志」窗口（菜单入口）：默认起始取上一条日志的 endedAt（填补最近缺口），无则回退 50 分钟前。
    func openBackfillWorkLog() {
        let lastEnd = workLogStore?.loadEntries().last?.endedAt
        let defaultStart = lastEnd ?? Date().addingTimeInterval(-50 * 60)
        workLogBackfillController?.show(defaultStart: defaultStart)
    }

    // MARK: - 运动记录

    /// 打开「综合报告」窗口（菜单入口）：工作日志 + 运动记录按 周/月/季/年 合成。
    func openCombinedReport() {
        combinedReportController?.show()
    }

    /// 打开「补录运动记录」窗口（菜单入口）：默认时段为 `[now − restDuration, now]`（「补刚才那段休息做的运动」），
    /// 而非沿用上一条记录的 endedAt（那是「紧接续写」语义，属报告内「加一条」按钮）。
    func openBackfillExercise() {
        let rest = engine?.config.restDurationSeconds ?? 600
        let range = exerciseBackfillDefaultRange(now: Date(), restDurationSeconds: rest)
        exerciseBackfillController?.show(defaultStart: range.start,
                                         defaultEnd: range.end,
                                         exerciseTypes: exerciseTypes)
    }

    /// 引擎在休息自然结束、回到工作时回调。决定弹运动录入窗还是静默放行——不阻塞、不冻结心跳。
    private func handlePostBreak(_ ctx: PostBreakContext) {
        let debug = ProcessInfo.processInfo.environment["GIVEMEABREAK_DEBUG"] != nil

        // 关闭开关 → 不弹
        guard (engine?.config.exerciseLogEnabled ?? true) || debug else { return }
        // 连续跳过衰减：≥3 次连续跳过则本次静默并自愈（下次重新提示），对抗提示疲劳
        if consecutiveExerciseSkips >= 3 {
            consecutiveExerciseSkips = 0
            return
        }
        guard let store = exerciseStore, let prompt = exercisePromptController else { return }

        prompt.present(
            restStartedAt: ctx.restStartedAt,
            restEndedAt: ctx.restEndedAt,
            exerciseTypes: exerciseTypes,
            timeoutSeconds: engine?.config.exercisePromptTimeoutSeconds ?? 180,
            onSubmit: { [weak self] sets, note in
                store.append(ExerciseEntry(
                    startedAt: ctx.restStartedAt,
                    endedAt: ctx.restEndedAt,
                    sets: sets,
                    note: note))
                self?.learnCustomExerciseTypes(from: sets)   // 自定义类型自动记住
                self?.consecutiveExerciseSkips = 0
            },
            onSkip: { [weak self] in
                self?.consecutiveExerciseSkips += 1
            }
        )
    }

    /// 引擎在自然休息、遮罩升起前回调。决定弹提示还是直接放行——**任何分支都必最终进入休息**。
    private func handlePreBreak(_ ctx: PreBreakContext) {
        let now = Date()
        let debug = ProcessInfo.processInfo.environment["GIVEMEABREAK_DEBUG"] != nil

        // 周期过短（< 15min 且非 DEBUG，如碎片休息/调试 8s 周期）→ 不值得反思，直接放行
        if ctx.workAccumulatedSeconds < 900 && !debug {
            engine?.completeDeferredRest(now: now)
            return
        }
        // 连续跳过衰减：≥3 次连续跳过则本次静默并自愈（下次重新提示），对抗提示疲劳
        if consecutiveSkips >= 3 {
            consecutiveSkips = 0
            engine?.completeDeferredRest(now: now)
            return
        }
        guard let store = workLogStore, let prompt = workLogPromptController else {
            engine?.completeDeferredRest(now: now)  // 无存储/控制器兜底：绝不卡住
            return
        }

        // 弹提示：冻结心跳，使休息倒计时不被提示耗时侵蚀（提示结束 completeDeferredRest rebase）
        heartbeat?.suspend()
        prompt.present(
            workDurationSeconds: ctx.workAccumulatedSeconds,
            timeoutSeconds: engine?.config.workLogPromptTimeoutSeconds ?? 180,  // 0=永久等待，控制器不调度超时
            onSubmit: { [weak self] summary, nextAction in
                store.append(WorkLogEntry(
                    startedAt: ctx.approxPeriodStartedAt,
                    endedAt: ctx.restStartedAt,
                    summary: summary,
                    nextAction: nextAction,
                    durationSeconds: ctx.workAccumulatedSeconds))
                self?.afterPrompt(submitted: true)
            },
            onSkip: { [weak self] in
                self?.afterPrompt(submitted: false)
            }
        )
    }

    /// 提示结束（提交/跳过/超时/关窗统一）：落 bookkeeping + rebase 进休息 + 恢复心跳。
    private func afterPrompt(submitted: Bool) {
        if submitted { consecutiveSkips = 0 } else { consecutiveSkips += 1 }
        engine?.completeDeferredRest(now: Date())
        heartbeat?.resume()
    }

    // MARK: - 运动类型注册表（config.exerciseTypes 的运行期读取 + 自定义项自动记住）

    /// 当前生效的运动类型注册表（Picker 数据源）；引擎无配置时回退出厂默认。
    private var exerciseTypes: [String] { engine?.config.exerciseTypes ?? defaultExerciseTypes }

    /// 保存一条运动记录后，把其中的自定义类型（不在注册表内的）追加进 `config.exerciseTypes` 并持久化。
    /// 纯计算交由 `appendedExerciseTypes`（可单测）；此处只负责「写 config + 热更新引擎」副作用。
    /// 无新增类型时该纯函数返回 nil，本方法即跳过写盘（避免无谓 I/O）。
    private func learnCustomExerciseTypes(from sets: [ExerciseSet]) {
        guard let engine = engine, let store = configStore else { return }
        var config = engine.config
        guard let updated = appendedExerciseTypes(current: config.exerciseTypes, sets: sets) else { return }
        config.exerciseTypes = updated
        do {
            try store.saveConfig(config)
        } catch {
            NSLog("[GiveMeABreak] 运动类型注册表持久化失败：\(error.localizedDescription)")
        }
        engine.updateConfig(config)
        NSLog("[GiveMeABreak] 运动类型注册表已更新：\(updated.count) 项")
    }

    // MARK: - 调试配置

    /// GIVEMEABREAK_DEBUG=1 时使用极速配置（8s 工作 / 15s 休息 / 全天窗口 / 禁用 AFK）便于手动验证遮罩与音乐。
    private func debugConfigOrLoaded(store: ConfigStore?) -> DayPlanConfig {
        if ProcessInfo.processInfo.environment["GIVEMEABREAK_DEBUG"] != nil {
            var c = DayPlanConfig.defaultConfig
            c.workIntervalSeconds = 8
            c.restDurationSeconds = 15
            c.afkThresholdSeconds = 999_999
            c.workWindows = [WorkWindow(start: TimeOfDay(hours: 0), end: TimeOfDay(hours: 23, minutes: 59))]
            NSLog("[GiveMeABreak] DEBUG 模式：8s 工作 / 15s 休息 / 全天窗口")
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

    private func statusText(for phase: EnginePhase, engine: LiveGiveMeABreakEngine?) -> String {
        guard let engine else { return "🍅" }
        switch phase {
        case .working:
            let remain = max(0, engine.config.workIntervalSeconds - engine.state.workAccumulatedSeconds)
            return "Work \(Int(ceil(remain / 60)))′"
        case .resting:
            guard let start = engine.state.restStartedAt else { return "Break" }
            let deadline = start.addingTimeInterval(engine.config.restDurationSeconds)
            let remain = max(0, deadline.timeIntervalSince(Date()))
            return "Break \(Int(ceil(remain / 60)))′"
        case .inMeeting: return "Meeting"
        case .idle: return "Paused"
        case .offDuty: return "Off"
        }
    }

    // MARK: - 睡眠 / 唤醒

    private func registerSleepObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        let will = nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sensors?.isAsleep = true
            self?.engine?.handleSleep()
            self?.heartbeat?.suspend()
            NSLog("[GiveMeABreak] 系统睡眠：挂起心跳")
        }
        let did = nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.sensors?.isAsleep = false
            // 小结窗仍开启（含永久等待）→ 由提示窗收尾的 afterPrompt 负责恢复；屏幕遮罩仍显示
            // → 由遮罩收尾的 handleScreenMaskDismissed 负责恢复。二者之外才在此恢复心跳，
            // suspend/resume 严格配对，避免唤醒后引擎抢先 tick 把延迟休息/遮罩冻结静默打破。
            let promptPresenting = self.workLogPromptController?.isPresenting == true
            let maskShown = self.screenMaskController?.isShown == true
            if !promptPresenting, !maskShown {
                self.heartbeat?.resume()
            }
            self.engine?.handleWake()
            self.lockShortcutMonitor?.recheckHealth()  // 唤醒时顺带核实锁屏快捷键 tap 是否仍处于启用状态
            NSLog("[GiveMeABreak] 系统唤醒：重置对账基点\(promptPresenting ? "（小结窗开启，心跳保持挂起）" : maskShown ? "（屏幕遮罩中，心跳保持挂起）" : " + 恢复心跳")")
        }
        sleepObservers = [will, did]
    }
}

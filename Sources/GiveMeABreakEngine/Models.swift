import Foundation

// MARK: - 当日时刻

/// 自午夜起的秒数 [0, 86400)，Codable 可持久化。
public struct TimeOfDay: Codable, Equatable, Hashable, Sendable, RawRepresentable {
    public let rawValue: Int

    public init(rawValue: Int) {
        precondition(rawValue >= 0 && rawValue < 86_400, "TimeOfDay 必须落在 [0, 86400) 区间")
        self.rawValue = rawValue
    }

    public init(hours: Int = 0, minutes: Int = 0, seconds: Int = 0) {
        self.init(rawValue: hours * 3600 + minutes * 60 + seconds)
    }

    public var hourComponent: Int { rawValue / 3600 }
    public var minuteComponent: Int { (rawValue % 3600) / 60 }
    public var secondComponent: Int { rawValue % 60 }
}

// MARK: - 工作窗口

/// 一天内的「工作时段」（如 09:00–12:00），每日重复。支持跨午夜。
public struct WorkWindow: Codable, Equatable, Hashable, Sendable {
    public var start: TimeOfDay
    public var end: TimeOfDay

    public init(start: TimeOfDay, end: TimeOfDay) {
        self.start = start
        self.end = end
    }

    /// 是否跨越午夜（start > end，如 22:00–02:00）。
    public var crossesMidnight: Bool { start.rawValue > end.rawValue }

    public func contains(secondsSinceMidnight s: Int) -> Bool {
        if crossesMidnight { return s >= start.rawValue || s < end.rawValue }
        return s >= start.rawValue && s < end.rawValue
    }

    public func contains(date: Date, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        let s = (c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0)
        return contains(secondsSinceMidnight: s)
    }
}

// MARK: - Agentic AI 设置（Claude Code 相关配置)

/// 「Agentic AI」功能域的正交配置子结构（为后续引入 Agentic AI 特性预留的 groundwork）。
/// 仅承载纯 Foundation 的 `String?` 字段，零 AppKit 依赖——编辑器探测/打开等 AppKit 逻辑
/// 位于集成层 `ClaudeSettingsLauncher`。引擎不消费本结构（同 `restMusicPath` 现状，携带即忽略）。
/// 与外围扁平字段正交解耦：Agentic AI 相关配置集中于此，独立生长、互不污染。
public struct AgentSettings: Codable, Equatable, Sendable {
    /// Claude Code 可执行文件的自定义绝对路径覆盖。
    /// `nil`/空 = 不覆盖，运行时自动从系统 `PATH` 探测（推荐）。App 非沙盒，故直接以路径引用。
    /// 当前仅持久化、未接入实际调用（groundwork）。
    public var claudeExecutablePath: String?
    /// 打开 `~/.claude/settings.json` 所用编辑器的 bundle id（如 `com.microsoft.VSCode`）。
    /// `nil` = 使用系统默认关联应用打开；所选编辑器未安装时集成层回退系统默认。
    public var claudeSettingsEditorBundleId: String?

    public init(claudeExecutablePath: String? = nil,
                claudeSettingsEditorBundleId: String? = nil) {
        self.claudeExecutablePath = claudeExecutablePath
        self.claudeSettingsEditorBundleId = claudeSettingsEditorBundleId
    }

    // MARK: - Codable（容错解码：缺字段补 nil，与 DayPlanConfig 范式一致，预留字段生长空间）

    private enum CodingKeys: String, CodingKey {
        case claudeExecutablePath, claudeSettingsEditorBundleId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        claudeExecutablePath = try c.decodeIfPresent(String.self, forKey: .claudeExecutablePath)
        claudeSettingsEditorBundleId = try c.decodeIfPresent(String.self, forKey: .claudeSettingsEditorBundleId)
    }
}

// MARK: - 一日计划配置

public struct DayPlanConfig: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 8

    public var schemaVersion: Int
    public var workWindows: [WorkWindow]
    /// 触发休息的工作累计阈值（秒），默认 50 分钟。
    public var workIntervalSeconds: TimeInterval
    /// 单次休息时长（秒），默认 10 分钟。
    public var restDurationSeconds: TimeInterval
    /// 系统空闲超过此值视为 AFK，暂停累加（秒），默认 180。
    public var afkThresholdSeconds: TimeInterval
    /// 休息时播放内置粉噪音（AVAudioEngine 合成，零音频文件、不依赖外部播放器），默认开。
    public var ambientSoundEnabled: Bool
    /// 休息时经 CGEvent 媒体键联动 QQ 音乐（需安装并授权辅助功能），默认开。
    public var controlQQMusic: Bool
    /// 进入（自然触发）休息前，弹轻量输入框记录这段工作内容与成果（工作日志），默认开。
    /// 仅对累满工作时长的自然休息生效；「立即休息」不弹。详见 WorkLogStore / WorkLogReport。
    public var workLogEnabled: Bool
    /// 工作日志提示窗的自动放行等待时长（秒），默认 180（3 分钟）。
    /// 超过此值未操作即等同「跳过」，自动进入休息（绝不卡住）。
    /// 哨兵值 `0` 表示「永久等待」——不自动跳过、不自动进入休息，须用户手动操作（提交/跳过/关窗）。
    /// 仅作用于 `workLogEnabled` 开启时的自然休息小结窗。
    public var workLogPromptTimeoutSeconds: TimeInterval
    /// 退出休息（自然结束）后，弹轻量输入框记录这段休息里做的微运动（运动记录），默认开。
    /// 仅对休息倒计时自然走完生效；提前结束（Esc）与被会议/下班打断均不弹。详见 ExerciseStore / CombinedReport。
    public var exerciseLogEnabled: Bool
    /// 运动录入提示窗的自动放行等待时长（秒），默认 180（3 分钟）。到点未操作即等同跳过，防窗口悬空。
    /// 哨兵值 `0` 表示「永久等待」——不调度定时器，须用户手动操作。仅作用于 `exerciseLogEnabled` 开启时的运动提示窗。
    /// v7 新增（与 `workLogPromptTimeoutSeconds` 对称，默认值亦一致）。
    public var exercisePromptTimeoutSeconds: TimeInterval
    /// 用户可挑选的运动类型注册表（运动录入 Picker 数据源），默认取 `defaultExerciseTypes`。
    /// 可在设置「运动记录」页增删；录入时输入的自定义类型保存后自动追加（去重、保序）。v7 新增。
    public var exerciseTypes: [String]
    /// 休息模式自定义音频文件的本地绝对路径（AVAudioPlayer 支持格式：mp3/m4a/aac/wav/flac/aiff 等）。
    /// 设置后休息时循环播放该文件，**取代内置粉噪音**；为 nil/空则回退粉噪音（受 `ambientSoundEnabled` 控制）。
    /// 文件由用户本地提供，**不打包、不分发**；App 非沙盒，故直接以路径引用（文件移动/删除会导致回退）。
    public var restMusicPath: String?
    /// Agentic AI 功能域配置（Claude Code 可执行路径覆盖 / `~/.claude/settings.json` 打开编辑器）。
    /// v8 新增；正交子结构，引擎忽略，仅供集成层消费。详见 `AgentSettings`。
    public var agent: AgentSettings

    public init(
        schemaVersion: Int = DayPlanConfig.currentSchemaVersion,
        workWindows: [WorkWindow] = [
            WorkWindow(start: TimeOfDay(hours: 9), end: TimeOfDay(hours: 12)),
            WorkWindow(start: TimeOfDay(hours: 13, minutes: 40), end: TimeOfDay(hours: 18)),
        ],
        workIntervalSeconds: TimeInterval = 50 * 60,
        restDurationSeconds: TimeInterval = 10 * 60,
        afkThresholdSeconds: TimeInterval = 180,
        ambientSoundEnabled: Bool = true,
        controlQQMusic: Bool = true,
        workLogEnabled: Bool = true,
        workLogPromptTimeoutSeconds: TimeInterval = 180,
        exerciseLogEnabled: Bool = true,
        exercisePromptTimeoutSeconds: TimeInterval = 180,
        exerciseTypes: [String] = defaultExerciseTypes,
        restMusicPath: String? = nil,
        agent: AgentSettings = AgentSettings()
    ) {
        self.schemaVersion = schemaVersion
        self.workWindows = workWindows
        self.workIntervalSeconds = workIntervalSeconds
        self.restDurationSeconds = restDurationSeconds
        self.afkThresholdSeconds = afkThresholdSeconds
        self.ambientSoundEnabled = ambientSoundEnabled
        self.controlQQMusic = controlQQMusic
        self.workLogEnabled = workLogEnabled
        self.workLogPromptTimeoutSeconds = workLogPromptTimeoutSeconds
        self.exerciseLogEnabled = exerciseLogEnabled
        self.exercisePromptTimeoutSeconds = exercisePromptTimeoutSeconds
        self.exerciseTypes = exerciseTypes
        self.restMusicPath = restMusicPath
        self.agent = agent
    }

    public static var defaultConfig: DayPlanConfig { DayPlanConfig() }

    // MARK: - Codable（容错解码：旧 schema 配置缺字段时用默认值兜底，保证平滑迁移不丢失）

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, workWindows, workIntervalSeconds, restDurationSeconds
        case afkThresholdSeconds, ambientSoundEnabled, controlQQMusic, workLogEnabled
        case workLogPromptTimeoutSeconds, exerciseLogEnabled, exercisePromptTimeoutSeconds
        case exerciseTypes, restMusicPath, agent
    }

    public init(from decoder: Decoder) throws {
        let d = DayPlanConfig.defaultConfig          // 单一事实源：默认值取自 memberwise init
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? d.schemaVersion
        workWindows = try c.decodeIfPresent([WorkWindow].self, forKey: .workWindows) ?? d.workWindows
        workIntervalSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .workIntervalSeconds) ?? d.workIntervalSeconds
        restDurationSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .restDurationSeconds) ?? d.restDurationSeconds
        afkThresholdSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .afkThresholdSeconds) ?? d.afkThresholdSeconds
        ambientSoundEnabled = try c.decodeIfPresent(Bool.self, forKey: .ambientSoundEnabled) ?? true
        controlQQMusic = try c.decodeIfPresent(Bool.self, forKey: .controlQQMusic) ?? true
        workLogEnabled = try c.decodeIfPresent(Bool.self, forKey: .workLogEnabled) ?? true
        // 显式存在的 0（永久等待）非 nil 故会被保留，不会被误补默认 180（迁移测试钉死此行为）。
        workLogPromptTimeoutSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .workLogPromptTimeoutSeconds) ?? d.workLogPromptTimeoutSeconds
        exerciseLogEnabled = try c.decodeIfPresent(Bool.self, forKey: .exerciseLogEnabled) ?? true
        // 同 workLogPromptTimeoutSeconds：显式 0（永久等待）需保留。
        exercisePromptTimeoutSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .exercisePromptTimeoutSeconds) ?? d.exercisePromptTimeoutSeconds
        // 旧配置（v6 及以前）无此字段 → 回退出厂默认列表；空数组显式保留（用户主动清空也尊重）。
        exerciseTypes = try c.decodeIfPresent([String].self, forKey: .exerciseTypes) ?? d.exerciseTypes
        restMusicPath = try c.decodeIfPresent(String.self, forKey: .restMusicPath)
        // 旧配置（v7 及以前）无此字段 → 补默认（全 nil）；AgentSettings 自身亦容错解码。v8 新增。
        agent = try c.decodeIfPresent(AgentSettings.self, forKey: .agent) ?? d.agent
    }
}

// MARK: - 会议时间线

/// 半开区间 [start, end)：end 时刻会议视为已结束。
public struct DateRange: Codable, Equatable, Hashable, Sendable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        precondition(end >= start, "DateRange end 必须 >= start")
        self.start = start
        self.end = end
    }

    public func contains(_ date: Date) -> Bool { date >= start && date < end }
}

/// 纯函数：将重叠/相邻的 busy 区间合并为不相交、按 start 排序的列表。
/// `mergeGap` 允许相邻区间（间隙 ≤ gap）被合并（背靠背会议视为连续）。
public func mergeBusyIntervals(_ ranges: [DateRange], mergeGap: TimeInterval = 0) -> [DateRange] {
    guard !ranges.isEmpty else { return [] }
    let sorted = ranges.sorted { $0.start < $1.start }
    var merged: [DateRange] = []
    var current = sorted[0]
    for next in sorted.dropFirst() {
        if next.start <= current.end.addingTimeInterval(mergeGap) {
            current = DateRange(start: current.start, end: max(current.end, next.end))
        } else {
            merged.append(current)
            current = next
        }
    }
    merged.append(current)
    return merged
}

/// 合并后的忙碌时间线（会议展平为不相交区间）。
public struct MeetingTimeline: Codable, Equatable, Sendable {
    public var busyIntervals: [DateRange]
    public var generatedAt: Date

    public init(busyIntervals: [DateRange] = [], generatedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.busyIntervals = busyIntervals
        self.generatedAt = generatedAt
    }

    public static let empty = MeetingTimeline()

    public func activeMeeting(at now: Date) -> DateRange? {
        busyIntervals.first { $0.contains(now) }
    }
}

// MARK: - 引擎状态（单一事实源，可持久化以支持崩溃/重启恢复）

public enum EnginePhase: String, Codable, Equatable, Sendable {
    case offDuty
    case idle
    case inMeeting
    case working
    case resting
}

public struct EngineState: Codable, Equatable, Sendable {
    public var phase: EnginePhase
    /// 单调 wall-clock 工作累加器，仅 working/inMeeting 推进。
    public var workAccumulatedSeconds: TimeInterval
    /// 对账基点（wall-clock）。
    public var lastTickAt: Date
    /// RESTING 起始时刻（算 restDeadline）。
    public var restStartedAt: Date?
    public var modelVersion: Int

    public init(
        phase: EnginePhase = .offDuty,
        workAccumulatedSeconds: TimeInterval = 0,
        lastTickAt: Date = Date(timeIntervalSince1970: 0),
        restStartedAt: Date? = nil,
        modelVersion: Int = 1
    ) {
        self.phase = phase
        self.workAccumulatedSeconds = workAccumulatedSeconds
        self.lastTickAt = lastTickAt
        self.restStartedAt = restStartedAt
        self.modelVersion = modelVersion
    }
}

// MARK: - 快照（evaluate 纯函数的输入，零时间依赖）

public struct EngineSnapshot: Equatable, Sendable {
    public let now: Date
    public let inWorkWindow: Bool
    public let isAFK: Bool
    public let isAsleep: Bool
    public let activeMeeting: DateRange?
    public let workAccumulatedSeconds: TimeInterval
    public let workIntervalSeconds: TimeInterval

    public init(
        now: Date,
        inWorkWindow: Bool,
        isAFK: Bool,
        isAsleep: Bool,
        activeMeeting: DateRange?,
        workAccumulatedSeconds: TimeInterval,
        workIntervalSeconds: TimeInterval
    ) {
        self.now = now
        self.inWorkWindow = inWorkWindow
        self.isAFK = isAFK
        self.isAsleep = isAsleep
        self.activeMeeting = activeMeeting
        self.workAccumulatedSeconds = workAccumulatedSeconds
        self.workIntervalSeconds = workIntervalSeconds
    }
}

// MARK: - 工作日志（休息前记录 + 周期报告）

/// 一段工作周期的记录（休息前由用户简述「完成了什么 + 可选下一步」）。
/// `startedAt` ≈ 休息触发时刻向前回溯的周期起点（restStartedAt − workAccumulatedSeconds）；
/// `endedAt` = 进入休息那一刻（即 `restStartedAt`）；`durationSeconds` = 该周期累计专注时长。
/// 由 `WorkLogStore` 持久化、`renderWorkLogReport` 聚合为日报/周报/月报。
public struct WorkLogEntry: Codable, Equatable, Sendable {
    public static let currentModelVersion = 1

    public var id: String
    public var startedAt: Date
    public var endedAt: Date
    /// 用户简述「这段时间完成了什么 / 成果」。空串视为该次未记录（实际不入库）。
    public var summary: String
    /// 可选「下一步第一个动作」（Leroy ready-to-resume plan，认知闭合）。
    public var nextAction: String?
    /// 本周期累计专注时长（秒，来自引擎 workAccumulatedSeconds）。
    public var durationSeconds: TimeInterval
    public var modelVersion: Int

    public init(
        id: String = UUID().uuidString,
        startedAt: Date,
        endedAt: Date,
        summary: String,
        nextAction: String? = nil,
        durationSeconds: TimeInterval,
        modelVersion: Int = WorkLogEntry.currentModelVersion
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.summary = summary
        self.nextAction = nextAction?.isEmpty == false ? nextAction : nil
        self.durationSeconds = durationSeconds
        self.modelVersion = modelVersion
    }

    // MARK: - Codable（容错解码：旧/缺字段补默认，与 DayPlanConfig 范式一致）

    private enum CodingKeys: String, CodingKey {
        case id, startedAt, endedAt, summary, nextAction, durationSeconds, modelVersion
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date(timeIntervalSince1970: 0)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt) ?? startedAt
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        let na = try c.decodeIfPresent(String.self, forKey: .nextAction)
        nextAction = (na?.isEmpty == false) ? na : nil
        durationSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .durationSeconds) ?? 0
        modelVersion = try c.decodeIfPresent(Int.self, forKey: .modelVersion) ?? WorkLogEntry.currentModelVersion
    }
}

/// 「即将进入休息」的转换上下文：由引擎在副作用分发处（遮罩升起前）回调 AppRoot，
/// AppRoot 据此决定是否弹工作日志提示。纯数据，零 UI 依赖。
public struct PreBreakContext: Equatable, Sendable {
    /// 进入休息时刻（即 `EngineState.restStartedAt`）= 本工作周期结束点。
    public let restStartedAt: Date
    /// 本周期累计专注时长（秒）。
    public let workAccumulatedSeconds: TimeInterval

    public init(restStartedAt: Date, workAccumulatedSeconds: TimeInterval) {
        self.restStartedAt = restStartedAt
        self.workAccumulatedSeconds = workAccumulatedSeconds
    }

    /// 近似周期起点（回溯累计专注时长；AFK 冻结期不计入，故为近似值，报告场景足够）。
    public var approxPeriodStartedAt: Date {
        restStartedAt.addingTimeInterval(-workAccumulatedSeconds)
    }
}

/// 「休息刚结束」的转换上下文：由引擎在休息自然结束（.resting → .working）后回调 AppRoot，
/// AppRoot 据此决定是否弹运动记录录入窗。与 `PreBreakContext` 对称，纯数据、零 UI 依赖。
/// 仅自然结束触发——提前结束（Esc 二次确认）与被会议/下班打断均不回调。
public struct PostBreakContext: Equatable, Sendable {
    /// 休息开始时刻（即结束前的 `EngineState.restStartedAt`）。
    public let restStartedAt: Date
    /// 休息结束时刻（= 触发回调时的 now）。运动时段默认取 `[restStartedAt, restEndedAt]`。
    public let restEndedAt: Date

    public init(restStartedAt: Date, restEndedAt: Date) {
        self.restStartedAt = restStartedAt
        self.restEndedAt = restEndedAt
    }
}

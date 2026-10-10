import Foundation

// MARK: - 运动记录（休息后录入 + 周期合成报告）
//
// 与「工作日志」对称：工作日志在进入休息「前」记录刚完成的工作；运动记录在退出休息（自然结束）
// 「后」记录这段休息里做的微运动（如胯下击掌 / 提膝击掌 / 深蹲 / 俯卧撑）。
// 由 `ExerciseStore` 持久化、`CombinedReport` 与工作日志一并聚合为周 / 月 / 季 / 年综合报告。

/// 一组运动：类型 + 数量（如「深蹲」×20）。一次记录可含若干组。
public struct ExerciseSet: Codable, Equatable, Sendable {
    /// 运动类型（如「深蹲」「俯卧撑」；预设见 `defaultExerciseTypes`，亦可自定义）。
    public var type: String
    /// 运动数量（次数）。
    public var reps: Int

    public init(type: String, reps: Int) {
        self.type = type
        self.reps = reps
    }

    // MARK: - Codable（容错解码：缺字段补默认，与 WorkLogEntry 范式一致）

    private enum CodingKeys: String, CodingKey { case type, reps }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        reps = try c.decodeIfPresent(Int.self, forKey: .reps) ?? 0
    }
}

/// 一次运动记录（退出休息后由用户录入「时段 + 若干 (类型, 数量) 组 + 可选备注」）。
/// `startedAt`/`endedAt` 默认取这段休息的起止（运动时段 ≈ 休息时段，可手动微调）；
/// 报告侧以 `startedAt` 在指定时区分桶（周 / 月 / 季 / 年）并按运动类型聚合。
public struct ExerciseEntry: Codable, Equatable, Sendable {
    public static let currentModelVersion = 1

    public var id: String
    public var startedAt: Date
    public var endedAt: Date
    /// 本次记录包含的运动组（至少一组 `type` 非空且 `reps>0` 方有意义；空数组视为未记录，实际不入库）。
    public var sets: [ExerciseSet]
    /// 可选备注（如「热身后做的」）。空串视为 nil。
    public var note: String?
    public var modelVersion: Int

    public init(
        id: String = UUID().uuidString,
        startedAt: Date,
        endedAt: Date,
        sets: [ExerciseSet],
        note: String? = nil,
        modelVersion: Int = ExerciseEntry.currentModelVersion
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sets = sets
        self.note = note?.isEmpty == false ? note : nil
        self.modelVersion = modelVersion
    }

    /// 本次记录的总数量（各组 reps 之和），供报告元数据与按类型聚合校验。
    public var totalReps: Int { sets.reduce(0) { $0 + $1.reps } }

    /// 运动时段跨度（秒，endedAt − startedAt，非负），供上下文展示。
    public var durationSeconds: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }

    // MARK: - Codable（容错解码：旧/缺字段补默认，与 WorkLogEntry 范式一致）

    private enum CodingKeys: String, CodingKey {
        case id, startedAt, endedAt, sets, note, modelVersion
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date(timeIntervalSince1970: 0)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt) ?? startedAt
        sets = try c.decodeIfPresent([ExerciseSet].self, forKey: .sets) ?? []
        let n = try c.decodeIfPresent(String.self, forKey: .note)
        note = (n?.isEmpty == false) ? n : nil
        modelVersion = try c.decodeIfPresent(Int.self, forKey: .modelVersion) ?? ExerciseEntry.currentModelVersion
    }
}

/// 预设运动类型（UI 选择器复用；用户亦可自定义其他类型）。
public let defaultExerciseTypes: [String] = ["胯下击掌", "提膝击掌", "深蹲", "俯卧撑"]

// MARK: - 纯函数（可单测，零时间依赖）

/// 运动补录的默认时段：`[now − restDuration, now]`。
///
/// 语义为「补刚才那段休息里做的运动」，故以**当前时刻**为终点、以单次休息时长为跨度回溯，
/// 而非沿用上一条记录的 `endedAt`（那是「紧接续写」语义，属另一入口）。
/// `now` 由调用方注入（可测）；`restDurationSeconds` 非负裁剪，避免负跨度。
public func exerciseBackfillDefaultRange(now: Date, restDurationSeconds: TimeInterval) -> (start: Date, end: Date) {
    let span = max(0, restDurationSeconds)
    return (start: now.addingTimeInterval(-span), end: now)
}

/// 计算保存一条运动记录后，应追加进配置注册表的新类型列表。
///
/// - 仅追加 `current` 中不存在、且 `sets` 中非空白的新类型；去重、保序（按 `sets` 出现顺序）。
/// - 返回 nil 表示无新增（调用方据此跳过写盘，避免无谓持久化）。
/// - 抽为纯函数便于单测，落库侧（AppRoot）据此 `engine.updateConfig` + `configStore.saveConfig`。
public func appendedExerciseTypes(current: [String], sets: [ExerciseSet]) -> [String]? {
    let existing = Set(current)
    var added: [String] = []
    var seen: Set<String> = []
    for s in sets {
        let t = s.type.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !existing.contains(t), !seen.contains(t) else { continue }
        seen.insert(t)
        added.append(t)
    }
    return added.isEmpty ? nil : current + added
}

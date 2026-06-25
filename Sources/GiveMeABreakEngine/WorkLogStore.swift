import Foundation

/// 工作日志持久化（纯 Foundation，可单测）。镜像 `ConfigStore` 范式：原子写 + 容错读。
/// 路径：~/Library/Application Support/<bundleId>/work-log.json
///
/// 与 `ConfigStore` 职责正交（配置/状态 vs 工作记录），故独立成类、独立文件，
/// 但复用同一 Application Support 目录与同一原子写惯用法（单一事实源：目录解析 + 写盘范式）。
/// 规模量级（数十条/日、数百条/年）下全量读-改-写即可；原子写防半写损坏。
public final class WorkLogStore {
    private let directory: URL
    private let fileManager = FileManager.default

    public init(directory: URL) throws {
        self.directory = directory
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var workLogURL: URL { directory.appendingPathComponent("work-log.json") }

    // MARK: - 读

    /// 读取全部条目（按时间升序）。缺失/损坏 → `[]`，绝不抛出到调用方。
    public func loadEntries() -> [WorkLogEntry] {
        guard let data = try? Data(contentsOf: workLogURL) else { return [] }
        do {
            let decoded = try JSONDecoder().decode([WorkLogEntry].self, from: data)
            return decoded.sorted { $0.startedAt < $1.startedAt }
        } catch {
            NSLog("[GiveMeABreak][worklog] 解码失败，回退空列表：\(error)")
            return []
        }
    }

    // MARK: - 写

    /// 追加一条记录（读-改-写，原子落盘）。
    public func append(_ entry: WorkLogEntry) {
        var entries = loadEntries()
        entries.append(entry)
        saveAll(entries)
    }

    /// 用新列表整体替换（供「清空」等批量操作）。
    public func replaceAll(_ entries: [WorkLogEntry]) {
        saveAll(entries.sorted { $0.startedAt < $1.startedAt })
    }

    // MARK: - Private

    private func saveAll(_ entries: [WorkLogEntry]) {
        do {
            try write(entries, to: workLogURL)
        } catch {
            NSLog("[GiveMeABreak][worklog] 持久化失败：\(error)")
        }
    }

    /// 原子写：pretty-printed + sorted keys（确定性、可读、可 diff），原子落盘防半写损坏。
    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }
}

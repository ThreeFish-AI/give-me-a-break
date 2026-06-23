import Foundation

/// 配置与引擎状态的 JSON 持久化（纯 Foundation，可单测）。
/// 路径：~/Library/Application Support/<bundleId>/{config.json, engine-state.json}
/// 原子写 + schema 版本迁移；读取失败回退默认/nil，绝不抛出到调用方。
public final class ConfigStore {
    private let directory: URL
    private let fileManager = FileManager.default

    public init(directory: URL) throws {
        self.directory = directory
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// 默认目录：~/Library/Application Support/<bundleId>。
    public static func defaultDirectory(bundleId: String) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent(bundleId, isDirectory: true)
    }

    private var configURL: URL { directory.appendingPathComponent("config.json") }
    private var stateURL: URL { directory.appendingPathComponent("engine-state.json") }

    // MARK: - Config

    public func loadConfig() -> DayPlanConfig {
        guard let data = try? Data(contentsOf: configURL) else { return .defaultConfig }
        do {
            let decoded = try JSONDecoder().decode(DayPlanConfig.self, from: data)
            return migrate(decoded)
        } catch {
            NSLog("[Timeout] config 解码失败，回退默认：\(error)")
            return .defaultConfig
        }
    }

    public func saveConfig(_ config: DayPlanConfig) throws {
        try write(config, to: configURL)
    }

    // MARK: - Engine State（崩溃恢复用）

    public func loadState() -> EngineState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(EngineState.self, from: data)
    }

    public func saveState(_ state: EngineState) {
        do {
            try write(state, to: stateURL)
        } catch {
            NSLog("[Timeout] 引擎状态持久化失败：\(error)")
        }
    }

    // MARK: - Private

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)  // 原子写，防半写损坏
    }

    /// schema 迁移：未来版本号升级时在此逐级迁移；高于本版本则回退默认。
    private func migrate(_ config: DayPlanConfig) -> DayPlanConfig {
        guard config.schemaVersion <= DayPlanConfig.currentSchemaVersion else {
            NSLog("[Timeout] config schemaVersion(\(config.schemaVersion)) 高于本版本(\(DayPlanConfig.currentSchemaVersion))，回退默认")
            return .defaultConfig
        }
        return config
    }
}

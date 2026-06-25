import Foundation
import GiveMeABreakEngine

private var dirCounter = 0

private func makeTempDir() -> URL {
    dirCounter += 1
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("givemeabreak-test-\(dirCounter)-\(ProcessInfo.processInfo.processIdentifier)")
    try? FileManager.default.removeItem(at: dir)
    return dir
}

func runConfigStoreCases() {
    test("ConfigStore config round-trip") {
        let store = try! ConfigStore(directory: makeTempDir())
        var config = DayPlanConfig.defaultConfig
        config.workIntervalSeconds = 42 * 60
        config.restDurationSeconds = 7 * 60
        config.workWindows = [WorkWindow(start: TimeOfDay(hours: 10), end: TimeOfDay(hours: 11))]
        try! store.saveConfig(config)

        let loaded = store.loadConfig()
        expectEqual(loaded.workIntervalSeconds, 42 * 60)
        expectEqual(loaded.restDurationSeconds, 7 * 60)
        expectEqual(loaded.workWindows.count, 1)
        expectEqual(loaded.workWindows[0].start, TimeOfDay(hours: 10))
    }

    test("ConfigStore state round-trip") {
        let store = try! ConfigStore(directory: makeTempDir())
        let state = EngineState(phase: .resting, workAccumulatedSeconds: 1234.5,
                                lastTickAt: Date(timeIntervalSince1970: 1000), restStartedAt: Date(timeIntervalSince1970: 1100))
        store.saveState(state)

        let loaded = store.loadState()
        expect(loaded != nil)
        expectEqual(loaded!.phase, .resting)
        expect(approx(loaded!.workAccumulatedSeconds, 1234.5, 0.001))
        expectEqual(loaded!.restStartedAt, Date(timeIntervalSince1970: 1100))
    }

    test("缺失文件 → 默认 config / nil state") {
        let store = try! ConfigStore(directory: makeTempDir())
        expectEqual(store.loadConfig(), DayPlanConfig.defaultConfig)
        expect(store.loadState() == nil)
    }

    test("损坏 JSON → 默认 config / nil state（不崩溃）") {
        let dir = makeTempDir()
        let store = try! ConfigStore(directory: dir)
        let cfgURL = dir.appendingPathComponent("config.json")
        try! "{ this is not valid json".data(using: .utf8)!.write(to: cfgURL)
        expectEqual(store.loadConfig(), DayPlanConfig.defaultConfig, "损坏 config 应回退默认")

        let stateURL = dir.appendingPathComponent("engine-state.json")
        try! "garbage".data(using: .utf8)!.write(to: stateURL)
        expect(store.loadState() == nil, "损坏 state 应返回 nil")
    }

    test("schema 迁移：高于本版本 → 回退默认") {
        let dir = makeTempDir()
        let store = try! ConfigStore(directory: dir)
        // 直接写入一个 schemaVersion=999 的 config（绕过 saveConfig 的当前版本）
        let raw = """
        {"schemaVersion":999,"workWindows":[],"workIntervalSeconds":1,"restDurationSeconds":1,"afkThresholdSeconds":1}
        """.data(using: .utf8)!
        try! raw.write(to: dir.appendingPathComponent("config.json"))
        expectEqual(store.loadConfig(), DayPlanConfig.defaultConfig, "未来版本应回退默认")
    }

    test("schema 迁移：旧 v1 config 缺新字段 → 平滑迁移补默认，原配置保留") {
        let dir = makeTempDir()
        let store = try! ConfigStore(directory: dir)
        // 用当前编码器生成正确的 WorkWindow/TimeOfDay JSON 形态，再删新字段模拟旧版 v1 config
        let seed = DayPlanConfig(
            schemaVersion: 1,
            workWindows: [WorkWindow(start: TimeOfDay(hours: 10), end: TimeOfDay(hours: 11))],
            workIntervalSeconds: 2400,
            restDurationSeconds: 480,
            afkThresholdSeconds: 240
        )
        try! store.saveConfig(seed)
        let cfgURL = dir.appendingPathComponent("config.json")
        var json = try! JSONSerialization.jsonObject(with: Data(contentsOf: cfgURL)) as! [String: Any]
        json.removeValue(forKey: "ambientSoundEnabled")   // 模拟旧版缺失
        json.removeValue(forKey: "controlQQMusic")
        json["schemaVersion"] = 1
        let rewritten = try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try! rewritten.write(to: cfgURL)

        let loaded = store.loadConfig()
        expectEqual(loaded.schemaVersion, DayPlanConfig.currentSchemaVersion, "迁移后版本号应规范化为当前版本")
        expectEqual(loaded.workIntervalSeconds, 2400, "原工作时长应保留")
        expectEqual(loaded.afkThresholdSeconds, 240, "原 AFK 阈值应保留")
        expectEqual(loaded.workWindows.count, 1, "原工作窗口应保留")
        expectEqual(loaded.ambientSoundEnabled, true, "缺失的 ambientSoundEnabled 应补默认 true")
        expectEqual(loaded.controlQQMusic, true, "缺失的 controlQQMusic 应补默认 true")
        expectEqual(loaded.workLogEnabled, true, "缺失的 workLogEnabled（v3 新增）应补默认 true")
    }
}

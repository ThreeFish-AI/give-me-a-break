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
        json.removeValue(forKey: "workLogPromptTimeoutSeconds")  // v4 新增字段，旧版无
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
        expectEqual(loaded.workLogPromptTimeoutSeconds, 180, "缺失的 workLogPromptTimeoutSeconds（v4 新增）应补默认 180")
    }

    test("workLogPromptTimeoutSeconds round-trip：自定义有限时长") {
        let store = try! ConfigStore(directory: makeTempDir())
        var config = DayPlanConfig.defaultConfig
        config.workLogPromptTimeoutSeconds = 300  // 5 分钟
        try! store.saveConfig(config)
        expectEqual(store.loadConfig().workLogPromptTimeoutSeconds, 300, "自定义等待时长应原样读回")
    }

    test("workLogPromptTimeoutSeconds 哨兵 0（永久等待）显式存在时不被误补默认") {
        let store = try! ConfigStore(directory: makeTempDir())
        var config = DayPlanConfig.defaultConfig
        config.workLogPromptTimeoutSeconds = 0  // 永久等待
        try! store.saveConfig(config)
        // 显式 0 非 nil，decodeIfPresent 应保留，不得回退 180（钉死永久等待语义，防回归）
        expectEqual(store.loadConfig().workLogPromptTimeoutSeconds, 0, "显式 0（永久等待）必须严格保留，不被默认 180 覆盖")
    }

    test("schema 迁移：旧 v3 config 缺 workLogPromptTimeoutSeconds → 升 v4 补默认 180，旧字段保留") {
        let dir = makeTempDir()
        let store = try! ConfigStore(directory: dir)
        let seed = DayPlanConfig(
            schemaVersion: 3,
            workWindows: [WorkWindow(start: TimeOfDay(hours: 8), end: TimeOfDay(hours: 12))],
            workIntervalSeconds: 3000,
            restDurationSeconds: 600,
            afkThresholdSeconds: 180,
            ambientSoundEnabled: false,
            controlQQMusic: false,
            workLogEnabled: false,
            workLogPromptTimeoutSeconds: 240
        )
        try! store.saveConfig(seed)
        let cfgURL = dir.appendingPathComponent("config.json")
        var json = try! JSONSerialization.jsonObject(with: Data(contentsOf: cfgURL)) as! [String: Any]
        json.removeValue(forKey: "workLogPromptTimeoutSeconds")  // 模拟 v3 旧配置无此字段
        json["schemaVersion"] = 3
        let rewritten = try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try! rewritten.write(to: cfgURL)

        let loaded = store.loadConfig()
        expectEqual(loaded.schemaVersion, DayPlanConfig.currentSchemaVersion, "v3→v4 版本号应规范化")
        expectEqual(loaded.workLogPromptTimeoutSeconds, 180, "缺失的 workLogPromptTimeoutSeconds 应补默认 180")
        expectEqual(loaded.workLogEnabled, false, "原 workLogEnabled=false 应保留")
        expectEqual(loaded.ambientSoundEnabled, false, "原 ambientSoundEnabled=false 应保留")
        expectEqual(loaded.workWindows.count, 1, "原工作窗口应保留")
    }

    test("restMusicPath 默认 nil：旧配置缺该字段补 nil") {
        let store = try! ConfigStore(directory: makeTempDir())
        let loaded = store.loadConfig()  // 无文件 → 默认
        expect(loaded.restMusicPath == nil, "默认 restMusicPath 应为 nil（无自定义音频，回退粉噪音）")
    }

    test("restMusicPath round-trip：自定义本地音频路径") {
        let store = try! ConfigStore(directory: makeTempDir())
        var config = DayPlanConfig.defaultConfig
        config.restMusicPath = "/Users/demo/Music/windy-hill.mp3"
        try! store.saveConfig(config)
        expectEqual(store.loadConfig().restMusicPath, "/Users/demo/Music/windy-hill.mp3", "自定义音频路径应原样读回")
    }

    test("schema 迁移：旧 v4 config 缺 restMusicPath → 升 v5 补 nil，旧字段保留") {
        let dir = makeTempDir()
        let store = try! ConfigStore(directory: dir)
        let seed = DayPlanConfig(
            schemaVersion: 4,
            workWindows: [WorkWindow(start: TimeOfDay(hours: 9), end: TimeOfDay(hours: 12))],
            workIntervalSeconds: 3000,
            restDurationSeconds: 600,
            afkThresholdSeconds: 180,
            ambientSoundEnabled: true,
            controlQQMusic: true,
            workLogEnabled: true,
            workLogPromptTimeoutSeconds: 240
            // restMusicPath 不传（v5 新增，模拟旧 v4 配置）
        )
        try! store.saveConfig(seed)
        let cfgURL = dir.appendingPathComponent("config.json")
        var json = try! JSONSerialization.jsonObject(with: Data(contentsOf: cfgURL)) as! [String: Any]
        json.removeValue(forKey: "restMusicPath")  // 确保 v4 旧配置无此字段
        json["schemaVersion"] = 4
        let rewritten = try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try! rewritten.write(to: cfgURL)

        let loaded = store.loadConfig()
        expectEqual(loaded.schemaVersion, DayPlanConfig.currentSchemaVersion, "v4→v5 版本号应规范化")
        expect(loaded.restMusicPath == nil, "缺失的 restMusicPath 应补 nil")
        expectEqual(loaded.workLogPromptTimeoutSeconds, 240, "原 workLogPromptTimeoutSeconds 应保留")
        expectEqual(loaded.workWindows.count, 1, "原工作窗口应保留")
    }

    test("exerciseLogEnabled round-trip：自定义关闭值原样读回") {
        let store = try! ConfigStore(directory: makeTempDir())
        var config = DayPlanConfig.defaultConfig
        config.exerciseLogEnabled = false
        try! store.saveConfig(config)
        expectEqual(store.loadConfig().exerciseLogEnabled, false, "原 exerciseLogEnabled=false 应保留")
    }

    test("exerciseTypes round-trip：自定义列表原样读回（保序）") {
        let store = try! ConfigStore(directory: makeTempDir())
        var config = DayPlanConfig.defaultConfig
        config.exerciseTypes = ["深蹲", "俯卧撑", "平板支撑", "开合跳"]
        try! store.saveConfig(config)
        let loaded = store.loadConfig()
        expectEqual(loaded.exerciseTypes, ["深蹲", "俯卧撑", "平板支撑", "开合跳"], "自定义运动类型列表应原样保序读回")
    }

    test("exercisePromptTimeoutSeconds 哨兵 0（永久等待）显式存在时不被误补默认") {
        let store = try! ConfigStore(directory: makeTempDir())
        var config = DayPlanConfig.defaultConfig
        config.exercisePromptTimeoutSeconds = 0  // 永久等待
        try! store.saveConfig(config)
        expectEqual(store.loadConfig().exercisePromptTimeoutSeconds, 0, "显式 0（永久等待）必须严格保留，不被默认 180 覆盖")
    }

    test("schema 迁移：旧 v6 config 缺 exerciseTypes / exercisePromptTimeoutSeconds → 升 v7 补默认，旧字段保留") {
        let dir = makeTempDir()
        let store = try! ConfigStore(directory: dir)
        let seed = DayPlanConfig(
            schemaVersion: 6,
            workWindows: [WorkWindow(start: TimeOfDay(hours: 9), end: TimeOfDay(hours: 12))],
            workIntervalSeconds: 3000,
            restDurationSeconds: 600,
            afkThresholdSeconds: 180,
            ambientSoundEnabled: true,
            controlQQMusic: false,
            workLogEnabled: false,
            workLogPromptTimeoutSeconds: 240,
            restMusicPath: "/tmp/a.mp3"
            // exerciseLogEnabled 用默认；exerciseTypes / exercisePromptTimeoutSeconds 模拟 v6 缺失
        )
        try! store.saveConfig(seed)
        let cfgURL = dir.appendingPathComponent("config.json")
        var json = try! JSONSerialization.jsonObject(with: Data(contentsOf: cfgURL)) as! [String: Any]
        // 模拟真实 v6 配置：移除 v7 新增字段
        json.removeValue(forKey: "exerciseTypes")
        json.removeValue(forKey: "exercisePromptTimeoutSeconds")
        json["schemaVersion"] = 6
        let rewritten = try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try! rewritten.write(to: cfgURL)

        let loaded = store.loadConfig()
        expectEqual(loaded.schemaVersion, DayPlanConfig.currentSchemaVersion, "v6→v7 版本号应规范化")
        expectEqual(loaded.exerciseTypes, defaultExerciseTypes, "缺失的 exerciseTypes 应补出厂默认 4 项")
        expectEqual(loaded.exercisePromptTimeoutSeconds, 180, "缺失的 exercisePromptTimeoutSeconds 应补默认 180")
        expectEqual(loaded.controlQQMusic, false, "原 controlQQMusic=false 应保留")
        expectEqual(loaded.restMusicPath, "/tmp/a.mp3", "原 restMusicPath 应保留")
    }

    test("exerciseTypes 显式空数组被尊重（不回退默认）") {
        let dir = makeTempDir()
        let store = try! ConfigStore(directory: dir)
        let seed = DayPlanConfig.defaultConfig
        try! store.saveConfig(seed)
        let cfgURL = dir.appendingPathComponent("config.json")
        var json = try! JSONSerialization.jsonObject(with: Data(contentsOf: cfgURL)) as! [String: Any]
        json["exerciseTypes"] = []  // 用户主动清空
        let rewritten = try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try! rewritten.write(to: cfgURL)

        let loaded = store.loadConfig()
        expect(loaded.exerciseTypes.isEmpty, "显式空数组应被尊重，不回退默认（用户主动清空也保留）")
    }

    // MARK: - v8：Agentic AI 设置（AgentSettings）

    test("agent 默认：无文件 / 未设时为全 nil AgentSettings") {
        let store = try! ConfigStore(directory: makeTempDir())
        let loaded = store.loadConfig()  // 无文件 → 默认
        expectEqual(loaded.agent, AgentSettings(), "默认 agent 应为全 nil（未覆盖路径、未指定编辑器）")
        expect(loaded.agent.claudeExecutablePath == nil, "默认 claudeExecutablePath 应为 nil（回退系统 PATH 探测）")
        expect(loaded.agent.claudeSettingsEditorBundleId == nil, "默认 claudeSettingsEditorBundleId 应为 nil（系统默认编辑器）")
    }

    test("agent round-trip：自定义可执行路径 + 编辑器 bundle id 原样读回") {
        let store = try! ConfigStore(directory: makeTempDir())
        var config = DayPlanConfig.defaultConfig
        config.agent = AgentSettings(claudeExecutablePath: "/opt/homebrew/bin/claude",
                                     claudeSettingsEditorBundleId: "com.microsoft.VSCode")
        try! store.saveConfig(config)
        let loaded = store.loadConfig()
        expectEqual(loaded.agent.claudeExecutablePath, "/opt/homebrew/bin/claude", "自定义可执行路径应原样读回")
        expectEqual(loaded.agent.claudeSettingsEditorBundleId, "com.microsoft.VSCode", "所选编辑器 bundle id 应原样读回")
    }

    test("AgentSettings 部分字段容错：仅 claudeExecutablePath 存在时另一字段补 nil") {
        let dir = makeTempDir()
        let store = try! ConfigStore(directory: dir)
        let seed = DayPlanConfig.defaultConfig
        try! store.saveConfig(seed)
        let cfgURL = dir.appendingPathComponent("config.json")
        var json = try! JSONSerialization.jsonObject(with: Data(contentsOf: cfgURL)) as! [String: Any]
        // 模拟仅含部分字段的 agent 对象（缺 claudeSettingsEditorBundleId）
        json["agent"] = ["claudeExecutablePath": "/usr/local/bin/claude"]
        let rewritten = try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try! rewritten.write(to: cfgURL)

        let loaded = store.loadConfig()
        expectEqual(loaded.agent.claudeExecutablePath, "/usr/local/bin/claude", "存在的子字段应保留")
        expect(loaded.agent.claudeSettingsEditorBundleId == nil, "缺失的子字段应容错补 nil")
    }

    test("schema 迁移：旧 v7 config 缺 agent → 升 v8 补默认（全 nil），旧字段保留") {
        let dir = makeTempDir()
        let store = try! ConfigStore(directory: dir)
        let seed = DayPlanConfig(
            schemaVersion: 7,
            workWindows: [WorkWindow(start: TimeOfDay(hours: 9), end: TimeOfDay(hours: 12))],
            workIntervalSeconds: 3000,
            restDurationSeconds: 600,
            afkThresholdSeconds: 180,
            ambientSoundEnabled: true,
            controlQQMusic: false,
            workLogEnabled: true,
            workLogPromptTimeoutSeconds: 240,
            exerciseLogEnabled: true,
            exercisePromptTimeoutSeconds: 120,
            exerciseTypes: ["深蹲", "俯卧撑"],
            restMusicPath: "/tmp/a.mp3"
            // agent 不传（v8 新增，模拟旧 v7 配置）
        )
        try! store.saveConfig(seed)
        let cfgURL = dir.appendingPathComponent("config.json")
        var json = try! JSONSerialization.jsonObject(with: Data(contentsOf: cfgURL)) as! [String: Any]
        json.removeValue(forKey: "agent")   // 确保 v7 旧配置无此字段
        json["schemaVersion"] = 7
        let rewritten = try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try! rewritten.write(to: cfgURL)

        let loaded = store.loadConfig()
        expectEqual(loaded.schemaVersion, DayPlanConfig.currentSchemaVersion, "v7→v8 版本号应规范化为当前版本")
        expectEqual(loaded.agent, AgentSettings(), "缺失的 agent 应补默认（全 nil）")
        expectEqual(loaded.controlQQMusic, false, "原 controlQQMusic=false 应保留")
        expectEqual(loaded.restMusicPath, "/tmp/a.mp3", "原 restMusicPath 应保留")
        expectEqual(loaded.exerciseTypes, ["深蹲", "俯卧撑"], "原 exerciseTypes 应保留")
        expectEqual(loaded.exercisePromptTimeoutSeconds, 120, "原 exercisePromptTimeoutSeconds 应保留")
    }
}

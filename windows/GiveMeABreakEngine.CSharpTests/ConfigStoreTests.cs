using Xunit;
using TimeoutEngine;

namespace TimeoutEngine.Tests;

// MARK: - B 层 · ConfigStore 镜像测试（镜像 tests/ConfigStoreCases.swift）

public class ConfigStoreTests
{
    private static string MakeTempDir()
        => Path.Combine(Path.GetTempPath(), "timeout-csharp-test-" + Guid.NewGuid().ToString("N"));

    // 镜像 ConfigStoreCases "ConfigStore config round-trip"
    [Fact]
    public void Config_RoundTrip()
    {
        var store = new ConfigStore(MakeTempDir());
        var config = new DayPlanConfig
        {
            WorkWindows = new() { new(new TimeOfDay(10, 0), new TimeOfDay(11, 0)) },
            WorkIntervalSeconds = 42 * 60,
            RestDurationSeconds = 7 * 60,
        };
        store.SaveConfig(config);

        var loaded = store.LoadConfig();
        Assert.Equal(42 * 60, loaded.WorkIntervalSeconds);
        Assert.Equal(7 * 60, loaded.RestDurationSeconds);
        Assert.Single(loaded.WorkWindows);
        Assert.Equal(new TimeOfDay(10, 0), loaded.WorkWindows[0].Start);
    }

    // 镜像 ConfigStoreCases "ConfigStore state round-trip"
    [Fact]
    public void State_RoundTrip()
    {
        var store = new ConfigStore(MakeTempDir());
        var state = new EngineState
        {
            Phase = EnginePhase.Resting,
            WorkAccumulatedSeconds = 1234.5,
            LastTickAt = TestHelpers.Epoch(1000),
            RestStartedAt = TestHelpers.Epoch(1100),
        };
        store.SaveState(state);

        var loaded = store.LoadState();
        Assert.NotNull(loaded);
        Assert.Equal(EnginePhase.Resting, loaded!.Phase);
        Assert.True(TestHelpers.Approx(loaded.WorkAccumulatedSeconds, 1234.5, 0.001));
        Assert.Equal(TestHelpers.Epoch(1100), loaded.RestStartedAt);
    }

    // 镜像 ConfigStoreCases "缺失文件 → 默认 config / nil state"
    [Fact]
    public void MissingFile_DefaultConfig_NullState()
    {
        var store = new ConfigStore(MakeTempDir());
        Assert.Equal(DayPlanConfig.Default, store.LoadConfig());
        Assert.Null(store.LoadState());
    }

    // 镜像 ConfigStoreCases "损坏 JSON → 默认 config / nil state（不崩溃）"
    [Fact]
    public void CorruptJson_DefaultConfig_NullState()
    {
        var dir = MakeTempDir();
        Directory.CreateDirectory(dir);
        File.WriteAllText(Path.Combine(dir, "config.json"), "{ this is not valid json");
        File.WriteAllText(Path.Combine(dir, "engine-state.json"), "garbage");
        var store = new ConfigStore(dir);

        Assert.Equal(DayPlanConfig.Default, store.LoadConfig());
        Assert.Null(store.LoadState());
    }

    // 镜像 ConfigStoreCases "schema 迁移：高于本版本 → 回退默认"
    [Fact]
    public void SchemaMigration_FutureVersion_FallsBack()
    {
        var dir = MakeTempDir();
        Directory.CreateDirectory(dir);
        File.WriteAllText(Path.Combine(dir, "config.json"),
            """{"schemaVersion":999,"workWindows":[],"workIntervalSeconds":1,"restDurationSeconds":1,"afkThresholdSeconds":1}""");
        var store = new ConfigStore(dir);

        Assert.Equal(DayPlanConfig.Default, store.LoadConfig());
    }

    // 镜像 ConfigStoreCases "schema 迁移：旧 v1 config 缺新字段 → 平滑迁移补默认，原配置保留"
    [Fact]
    public void SchemaMigration_OldV1_MissingFields_FilledWithDefaults()
    {
        var dir = MakeTempDir();
        Directory.CreateDirectory(dir);
        // schemaVersion=1，缺 ambientSoundEnabled / controlQQMusic（模拟旧版）
        File.WriteAllText(Path.Combine(dir, "config.json"),
            """{"schemaVersion":1,"workWindows":[{"start":36000,"end":39600}],"workIntervalSeconds":2400,"restDurationSeconds":480,"afkThresholdSeconds":240}""");
        var store = new ConfigStore(dir);

        var loaded = store.LoadConfig();
        Assert.Equal(2, loaded.SchemaVersion);                  // 迁移后版本号规范化为当前 2
        Assert.Equal(2400, loaded.WorkIntervalSeconds);         // 原工作时长保留
        Assert.Equal(240, loaded.AfkThresholdSeconds);          // 原 AFK 阈值保留
        Assert.Single(loaded.WorkWindows);                      // 原工作窗口保留
        Assert.True(loaded.AmbientSoundEnabled);                // 缺失字段补默认 true
        Assert.True(loaded.ControlQQMusic);                     // 缺失字段补默认 true
    }
}

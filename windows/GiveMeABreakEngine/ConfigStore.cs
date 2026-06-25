using System.Text.Json;

namespace TimeoutEngine;

// MARK: - 配置与引擎状态 JSON 持久化
// 镜像 Sources/TimeoutEngine/ConfigStore.swift。原子写 + schema 迁移；读取失败回退默认/nil，绝不抛出。

public sealed class ConfigStore
{
    private readonly string _directory;

    public ConfigStore(string directory)
    {
        _directory = directory;
        Directory.CreateDirectory(_directory);
    }

    /// <summary>默认目录：%APPDATA%\&lt;bundleId&gt;（Windows）。Phase 1+ 集成层使用。</summary>
    public static string DefaultDirectory(string bundleId)
        => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), bundleId);

    private string ConfigPath => Path.Combine(_directory, "config.json");
    private string StatePath => Path.Combine(_directory, "engine-state.json");

    public DayPlanConfig LoadConfig()
    {
        if (!File.Exists(ConfigPath)) return DayPlanConfig.Default;
        try
        {
            var json = File.ReadAllText(ConfigPath);
            return Migrate(DayPlanConfig.FromJson(json, TimeoutJsonOptions.Default));
        }
        catch
        {
            return DayPlanConfig.Default;
        }
    }

    public void SaveConfig(DayPlanConfig config)
        => WriteAtomic(ConfigPath, JsonSerializer.Serialize(config, TimeoutJsonOptions.Default));

    public EngineState? LoadState()
    {
        if (!File.Exists(StatePath)) return null;
        try
        {
            return JsonSerializer.Deserialize<EngineState>(File.ReadAllText(StatePath), TimeoutJsonOptions.Default);
        }
        catch
        {
            return null;
        }
    }

    public void SaveState(EngineState state)
    {
        try { WriteAtomic(StatePath, JsonSerializer.Serialize(state, TimeoutJsonOptions.Default)); }
        catch { /* 静默：镜像 Swift NSLog 但不抛出到调用方 */ }
    }

    private static void WriteAtomic(string path, string content)
    {
        // 原子写：先写临时文件再覆盖，防半写损坏（对齐 Swift data.write(options: .atomic)）。
        var tmp = path + ".tmp";
        File.WriteAllText(tmp, content);
        File.Move(tmp, path, overwrite: true);
    }

    /// <summary>schema 迁移：高于本版本则回退默认；否则规范化 schemaVersion 为当前版本
    /// （FromJson 已对缺失字段容错补默认，故此处无需逐字段迁移分支）。</summary>
    private static DayPlanConfig Migrate(DayPlanConfig config)
    {
        if (config.SchemaVersion > DayPlanConfig.CurrentSchemaVersion) return DayPlanConfig.Default;
        var c = config;
        c.SchemaVersion = DayPlanConfig.CurrentSchemaVersion;  // 规范化，下次落盘即升级
        return c;
    }
}

/// <summary>共享 JSON 选项：camelCase（对齐 Swift Codable 默认形态）+ 缩进。</summary>
public static class TimeoutJsonOptions
{
    public static readonly JsonSerializerOptions Default = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
    };
}

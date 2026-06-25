namespace TimeoutEngine.Win32;

// MARK: - Paul Kellet 粉噪音合成（逐字移植 Sources/TimeoutIntegrations/AmbientSoundPlayer.swift:55-80）
// 保证 macOS/Windows 两端「同一种雨声」体感一致。纯算法，零依赖，可在 net8.0 单测保真度。

/// <summary>Paul Kellet 粉噪音滤波器，合成指定秒数的单声道 Float32 buffer。
/// 首尾各做 ~50ms 线性淡入淡出，消除循环边界点击声（对齐 Swift 实现）。</summary>
public sealed class PinkNoiseGenerator
{
    public int SampleRate { get; } = 44_100;

    private readonly Random _rng;

    /// <param name="rng">随机源（测试注入固定种子以断言稳定统计量；生产用 Random.Shared）。</param>
    public PinkNoiseGenerator(Random? rng = null) => _rng = rng ?? Random.Shared;

    /// <summary>生成 <paramref name="seconds"/> 秒粉噪音样本（已乘 0.11 增益，与 Swift buffer 内容一致）。
    /// 播放音量由播放器（如 WasapiAmbientPlayer 的 0.4）在播放侧施加。</summary>
    public float[] Generate(double seconds)
    {
        int n = (int)(SampleRate * seconds);
        var data = new float[n];
        // Kellet IIR 滤波器状态（7 级）
        double b0 = 0, b1 = 0, b2 = 0, b3 = 0, b4 = 0, b5 = 0, b6 = 0;
        int fade = (int)(SampleRate * 0.05);   // ~50ms 淡入淡出

        for (int i = 0; i < n; i++)
        {
            double white = _rng.NextDouble() * 2.0 - 1.0;   // [-1, 1)
            b0 = 0.99886 * b0 + white * 0.0555179;
            b1 = 0.99332 * b1 + white * 0.0750759;
            b2 = 0.96900 * b2 + white * 0.1538520;
            b3 = 0.86650 * b3 + white * 0.3104856;
            b4 = 0.55000 * b4 + white * 0.5329522;
            b5 = -0.7616 * b5 - white * 0.0168980;
            double pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362;
            b6 = white * 0.115926;
            double sample = pink * 0.11;

            if (i < fade) sample *= (double)i / fade;            // 首部淡入
            else if (i > n - fade) sample *= (double)(n - i) / fade;  // 尾部淡出

            data[i] = (float)sample;
        }
        return data;
    }
}

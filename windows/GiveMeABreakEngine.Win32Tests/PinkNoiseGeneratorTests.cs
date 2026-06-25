using Xunit;
using TimeoutEngine.Win32;

namespace TimeoutEngine.Win32Tests;

// MARK: - 粉噪音保真度（CI 无音频输出，断言可量化指标；听感靠用户真机验收）
// 镜像 Sources/TimeoutIntegrations/AmbientSoundPlayer.swift 的 Kellet 算法预期。

public class PinkNoiseGeneratorTests
{
    private static float[] Generate8s() => new PinkNoiseGenerator(new Random(42)).Generate(8);

    [Fact]
    public void BufferLength_Is8SecondsAt44100Hz()
    {
        var data = Generate8s();
        Assert.Equal(44_100 * 8, data.Length);   // 352800
    }

    [Fact]
    public void Rms_WithinReasonableBand_NoClipping()
    {
        // Kellet ×0.11 增益：实测 RMS ≈0.2（基于 Random(42)），区间覆盖种子波动；确保不削波（<1）。
        var data = Generate8s();
        double sumSq = 0;
        foreach (var s in data) sumSq += (double)s * s;
        double rms = Math.Sqrt(sumSq / data.Length);
        Assert.InRange(rms, 0.05, 0.4);
    }

    [Fact]
    public void LowFrequencyPower_ExceedsHighFrequency()
    {
        // 粉噪音 -3dB/oct：用 Goertzel 单频功率比较，低频(100Hz)功率应 > 高频(15kHz)。
        var data = Generate8s();
        double lowPower = GoertzelPower(data, 100);
        double highPower = GoertzelPower(data, 15_000);
        Assert.True(lowPower > highPower, $"粉噪音低频功率应 > 高频：low={lowPower:E3} high={highPower:E3}");
    }

    [Fact]
    public void FadeIn_First50Ms_LowerThanMid()
    {
        // 首部 50ms（2205 样本）淡入：幅值包络应整体 < 中段峰值（淡入生效）。
        var data = Generate8s();
        int fade = 44_100 / 20;   // 2205
        double fadePeak = 0;
        for (int i = 0; i < fade; i++) fadePeak = Math.Max(fadePeak, Math.Abs(data[i]));
        double midPeak = 0;
        for (int i = fade; i < fade * 4; i++) midPeak = Math.Max(midPeak, Math.Abs(data[i]));
        Assert.True(fadePeak < midPeak, $"淡入段峰值({fadePeak:E3}) 应 < 中段峰值({midPeak:E3})");
    }

    [Fact]
    public void LoopBoundary_NoClickAtWrap()
    {
        // 循环点 sample[0] 与 sample[N-1] 都应≈0（淡入淡出消除点击声）。
        var data = Generate8s();
        Assert.True(Math.Abs(data[0]) < 0.005, $"循环起点应≈0：{data[0]}");
        Assert.True(Math.Abs(data[^1]) < 0.005, $"循环终点应≈0：{data[^1]}");
    }

    /// <summary>Goertzel 单频功率（O(n)，单测轻量；测 targetHz 频点的功率量级，无需 FFT 库）。</summary>
    private static double GoertzelPower(float[] data, int targetHz)
    {
        const int sampleRate = 44_100;
        int n = data.Length;
        double k = (double)targetHz * n / sampleRate;
        double omega = 2.0 * Math.PI * k / n;
        double coeff = 2.0 * Math.Cos(omega);
        double s1 = 0, s2 = 0;
        for (int i = 0; i < n; i++)
        {
            double s0 = data[i] + coeff * s1 - s2;
            s2 = s1;
            s1 = s0;
        }
        return s1 * s1 + s2 * s2 - coeff * s1 * s2;
    }
}

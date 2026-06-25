using System.Text.Json;
using Xunit;
using TimeoutEngine;

namespace TimeoutEngine.Tests;

// MARK: - A 层 · JSON fixture 驱动黄金测试
// 读 shared/test-fixtures/*.json，调用 Engine 纯函数，比对期望。任一 case 失败汇总报错。
// 这是「FSM 决策边界不漂移」的机器保证核心：两端共用同一份 JSON。

public class EvaluateFixtureTests
{
    [Fact]
    public void Evaluate_GoldenCases()
    {
        var doc = JsonSerializer.Deserialize<EvaluateFixtureDoc>(
            FixtureLoader.Load("evaluate.json"), TimeoutJsonOptions.Default)!;
        var failures = new List<string>();
        foreach (var c in doc.Cases)
        {
            var got = Engine.Evaluate(c.Snapshot.ToSnapshot());
            if (c.Expected is not null && got != FixtureLoader.ParsePhase(c.Expected))
                failures.Add($"[{c.Name}] 期望 {c.Expected}，实际 {got}");
            if (c.ExpectedNot is not null && got == FixtureLoader.ParsePhase(c.ExpectedNot))
                failures.Add($"[{c.Name}] 期望非 {c.ExpectedNot}，但实际匹配");
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }
}

public class AdvanceFixtureTests
{
    [Fact]
    public void Advance_GoldenCases()
    {
        var doc = JsonSerializer.Deserialize<AdvanceFixtureDoc>(
            FixtureLoader.Load("advance.json"), TimeoutJsonOptions.Default)!;
        var failures = new List<string>();
        foreach (var c in doc.Cases)
        {
            var got = Engine.Advance(c.Initial.ToState(), FixtureLoader.Epoch(c.To), c.MaxDelta, c.Active);
            if (c.ExpectWorkAccum is double ewa && !TestHelpers.Approx(got.WorkAccumulatedSeconds, ewa, 0.001))
                failures.Add($"[{c.Name}] workAccum 期望 {ewa}，实际 {got.WorkAccumulatedSeconds}");
            if (c.ExpectLastTickAt is long elt && got.LastTickAt != FixtureLoader.Epoch(elt))
                failures.Add($"[{c.Name}] lastTickAt 期望 {elt}，实际 {got.LastTickAt.ToUnixTimeSeconds()}");
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }
}

public class SideEffectsFixtureTests
{
    [Fact]
    public void SideEffects_GoldenCases()
    {
        var doc = JsonSerializer.Deserialize<SideEffectsFixtureDoc>(
            FixtureLoader.Load("side-effects.json"), TimeoutJsonOptions.Default)!;
        var failures = new List<string>();
        foreach (var c in doc.Cases)
        {
            var got = Engine.SideEffectsOf(FixtureLoader.ParsePhase(c.From), FixtureLoader.ParsePhase(c.To));
            var exp = c.Expected.ToSideEffects();
            if (!got.Equals(exp))
                failures.Add($"[{c.Name}] 期望 {exp.ShowOverlay}/{exp.DismissOverlay}/{exp.StartMusic}/{exp.PauseMusic}" +
                             $"，实际 {got.ShowOverlay}/{got.DismissOverlay}/{got.StartMusic}/{got.PauseMusic}");
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }
}

public class MergeBusyFixtureTests
{
    [Fact]
    public void MergeBusy_GoldenCases()
    {
        var doc = JsonSerializer.Deserialize<MergeFixtureDoc>(
            FixtureLoader.Load("merge-busy.json"), TimeoutJsonOptions.Default)!;
        var failures = new List<string>();
        foreach (var c in doc.Cases)
        {
            var input = c.Input.ConvertAll(r => r.ToRange());
            var got = Engine.MergeBusyIntervals(input, c.MergeGap);
            var exp = c.Expected.ConvertAll(r => r.ToRange());
            if (got.Count != exp.Count)
            {
                failures.Add($"[{c.Name}] 区间数 期望 {exp.Count}，实际 {got.Count}");
                continue;
            }
            for (int i = 0; i < got.Count; i++)
            {
                if (got[i].Start != exp[i].Start || got[i].End != exp[i].End)
                    failures.Add($"[{c.Name}][{i}] 期望 [{exp[i].Start.ToUnixTimeSeconds()},{exp[i].End.ToUnixTimeSeconds()})" +
                                 $"，实际 [{got[i].Start.ToUnixTimeSeconds()},{got[i].End.ToUnixTimeSeconds()})");
            }
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }
}

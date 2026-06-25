using System.Text.Json;
using Xunit;
using TimeoutEngine;
using TimeoutEngine.Graph;

namespace TimeoutEngine.GraphTests;

// MARK: - GraphTimelineMapper 解析（fixture 驱动，对齐 macOS refresh 的 filter/map/merge）

public class GraphTimelineMapperTests
{
    private static readonly JsonSerializerOptions JsonOpts = new() { PropertyNameCaseInsensitive = true };

    private static JsonDocument LoadFixture()
    {
        string path = Path.Combine(AppContext.BaseDirectory, "fixtures", "graph-calendar-view.json");
        return JsonDocument.Parse(File.ReadAllText(path));
    }

    [Fact]
    public void ToTimeline_FiltersFreeOofAllDay_AndMergesOverlap()
    {
        var root = LoadFixture().RootElement;
        var events = root.GetProperty("events").Deserialize<List<GraphEvent>>(JsonOpts)!;
        var expected = root.GetProperty("expectedBusyIntervals").EnumerateArray().ToList();
        var generatedAt = DateTimeOffset.Parse("2026-06-24T08:00:00Z");

        var timeline = GraphTimelineMapper.ToTimeline(events, generatedAt);

        Assert.Equal(generatedAt, timeline.GeneratedAt);
        Assert.Equal(expected.Count, timeline.BusyIntervals.Count);
        for (int i = 0; i < expected.Count; i++)
        {
            Assert.Equal(DateTimeOffset.Parse(expected[i].GetProperty("start").GetString()!), timeline.BusyIntervals[i].Start);
            Assert.Equal(DateTimeOffset.Parse(expected[i].GetProperty("end").GetString()!), timeline.BusyIntervals[i].End);
        }
    }

    [Fact]
    public void ToTimeline_EmptyEvents_ReturnsEmpty()
    {
        var timeline = GraphTimelineMapper.ToTimeline(Array.Empty<GraphEvent>(), DateTimeOffset.UtcNow);
        Assert.Empty(timeline.BusyIntervals);
    }

    [Fact]
    public void ToTimeline_NullAndMissingFields_Skipped()
    {
        var events = new GraphEvent?[]
        {
            null,
            new() { ShowAs = "busy" },                                  // 缺 start/end → 跳过
            new() { Start = new() { DateTime = "2026-06-24T09:00:00" }, ShowAs = "busy" },  // 缺 end → 跳过
            new() { Start = new() { DateTime = "2026-06-24T09:00:00" }, End = new() { DateTime = "2026-06-24T10:00:00" } },  // 缺 showAs → 跳过
        };
        var timeline = GraphTimelineMapper.ToTimeline(events, DateTimeOffset.UtcNow);
        Assert.Empty(timeline.BusyIntervals);
    }
}

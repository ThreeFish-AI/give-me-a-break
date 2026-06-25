using TimeoutEngine;

namespace TimeoutShell.Adapters;

// ICalendarProvider · Phase 1 返回空时间线（无会议门控）。
// Phase 3 替换为 Microsoft Graph API。
public sealed class EmptyCalendarProvider : ICalendarProvider
{
    public MeetingTimeline CurrentTimeline() => MeetingTimeline.Empty;
}

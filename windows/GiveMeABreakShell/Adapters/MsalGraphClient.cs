using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using Microsoft.Identity.Client;
using TimeoutEngine.Graph;

namespace TimeoutShell.Adapters;

// IGraphClient 实现 · MSAL 设备码 flow + HttpClient GET /me/calendarView（壳专属，net8.0-windows）。
// OAuth 红线（CLAUDE.md 浏览器验证协议）：client id 从配置读，设备码 callback 仅打印 URL+code，
// 用户在浏览器授权——Agent 绝不参与认证。首次授权 100% 用户完成；CI 无法验证真实 Graph。
public sealed class MsalGraphClient : IGraphClient, IDisposable
{
    private const string Scopes = "Calendars.Read";
    private const string GraphEndpoint = "https://graph.microsoft.com/v1.0/me/calendarView";

    private readonly string _clientId;
    private readonly IPublicClientApplication? _app;
    private readonly HttpClient _http = new();

    public MsalGraphClient(string clientId)
    {
        _clientId = clientId ?? "";
        if (!string.IsNullOrWhiteSpace(_clientId))
        {
            _app = PublicClientApplicationBuilder.Create(_clientId)
                .WithAuthority(AadAuthorityAudience.AzureAdAndPersonalMicrosoftAccount, true)
                .Build();
        }
    }

    /// <summary>是否已配置 client id（否则降级返回空，不认证）。</summary>
    public bool IsConfigured => _app is not null;

    public async Task<IReadOnlyList<GraphEvent>> FetchTodayEventsAsync(DateTimeOffset start, CancellationToken ct)
    {
        if (_app is null) return Array.Empty<GraphEvent>();   // 未配置 → 降级空（不阻断）

        AuthenticationResult result;
        try
        {
            var accounts = await _app.GetAccountsAsync();
            result = await _app.AcquireTokenSilent(new[] { Scopes }, accounts.FirstOrDefault())
                .ExecuteAsync(ct);
        }
        catch (MsalUiRequiredException)
        {
            // 设备码 flow：首次授权。callback 仅打印 URL+code，用户在浏览器输码（Agent 不自动完成）。
            // 后续进程内：AcquireTokenSilent 命中 MSAL token 缓存（静默）。
            result = await _app.AcquireTokenWithDeviceCode(new[] { Scopes }, dcr =>
            {
                Console.WriteLine($"[Timeout][graph] 设备码授权：访问 {dcr.VerificationUrl} 输入 {dcr.UserCode}");
                return Task.CompletedTask;
            }).ExecuteAsync(ct);
        }
        // 其它异常（取消/网络）→ 抛，上层 GraphCalendarProvider.TriggerRefresh catch 降级。

        var s = start.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss'Z'");
        var e = start.ToUniversalTime().Add(TimeSpan.FromDays(1)).ToString("yyyy-MM-ddTHH:mm:ss'Z'");
        var req = new HttpRequestMessage(HttpMethod.Get,
            $"{GraphEndpoint}?startDateTime={Uri.EscapeDataString(s)}&endDateTime={Uri.EscapeDataString(e)}");
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", result.AccessToken);
        req.Headers.Add("Prefer", "outlook.timezone=\"UTC\"");   // 强制 UTC，规避 tz 转换

        using var resp = await _http.SendAsync(req, ct);
        resp.EnsureSuccessStatusCode();   // 429/5xx → 抛，上层降级
        var json = await resp.Content.ReadAsStringAsync(ct);
        var parsed = JsonSerializer.Deserialize<GraphCalendarViewResponse>(json,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        return parsed?.Value ?? new List<GraphEvent>();
    }

    public void Dispose() => _http.Dispose();
}

using Xunit;
using TimeoutEngine.Win32;

namespace TimeoutEngine.Win32Tests;

// MARK: - 媒体键 down+up 序列（mock ISendInputPort，不实际触发系统媒体键）
// 对齐 macOS LiveMusicController.postMediaKey 的 down/up 循环语义。

public class MediaKeySequenceTests
{
    /// <summary>记录 Send 调用的 mock 端口。</summary>
    private sealed class CapturingPort : ISendInputPort
    {
        public List<INPUT[]> Calls { get; } = new();
        public uint Send(INPUT[] inputs) { Calls.Add(inputs); return (uint)inputs.Length; }
    }

    [Fact]
    public void SendPlayPause_ProducesKeyDownThenKeyUp()
    {
        var port = new CapturingPort();
        var sender = new MediaKeySender(port);

        sender.SendPlayPause();

        Assert.Single(port.Calls);
        var inputs = port.Calls[0];
        Assert.Equal(2, inputs.Length);
        Assert.Equal(InputType.Keyboard, inputs[0].type);
        Assert.Equal(InputType.Keyboard, inputs[1].type);
        Assert.Equal(VirtualKeyCodes.MediaPlayPause, inputs[0].ki.wVk);
        Assert.Equal(VirtualKeyCodes.MediaPlayPause, inputs[1].ki.wVk);
    }

    [Fact]
    public void KeyDownHasNoKeyUpFlag_KeyUpHasKeyUpFlag()
    {
        var port = new CapturingPort();
        new MediaKeySender(port).SendPlayPause();
        var inputs = port.Calls[0];

        Assert.Equal(0u, inputs[0].ki.dwFlags);                 // key down：无 KEYUP
        Assert.Equal(KeybdFlags.KeyUp, inputs[1].ki.dwFlags);   // key up：KEYUP
    }

    [Fact]
    public void ReturnsInjectedCount()
    {
        var port = new CapturingPort();
        uint ret = new MediaKeySender(port).SendPlayPause();
        Assert.Equal(2u, ret);   // 2 events（down + up）
    }
}

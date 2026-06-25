using System.Runtime.InteropServices;

namespace TimeoutEngine.Win32;

// MARK: - 媒体键发送（mockable，down+up 序列可在 net8.0 测试）
// 把「实际 SendInput」收敛到 ISendInputPort，使组装逻辑脱离 Windows 运行时可测。

/// <summary>SendInput 的可注入端口。生产用 PInvokeSendInputPort；测试用 mock。</summary>
public interface ISendInputPort
{
    /// <summary>发送输入事件，返回成功注入的事件数。</summary>
    uint Send(INPUT[] inputs);
}

/// <summary>P/Invoke 实现（运行时需 Windows）。</summary>
public sealed class PInvokeSendInputPort : ISendInputPort
{
    public uint Send(INPUT[] inputs)
        => NativeMethods.SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
}

/// <summary>合成媒体键（对齐 macOS LiveMusicController.postMediaKey）。
/// VK_MEDIA_PLAY_PAUSE 与 NX_KEYTYPE_PLAY 同为 toggle——发送 down+up 一次即触发播放/暂停切换。</summary>
public sealed class MediaKeySender
{
    private readonly ISendInputPort _port;
    public MediaKeySender(ISendInputPort port) => _port = port;

    /// <summary>发送「播放/暂停」toggle 媒体键（key down + key up）。</summary>
    public uint SendPlayPause() => SendKey(VirtualKeyCodes.MediaPlayPause);

    private uint SendKey(ushort vk)
    {
        var inputs = new INPUT[2];
        inputs[0] = KeyboardInput(vk, keyDown: true);
        inputs[1] = KeyboardInput(vk, keyDown: false);
        return _port.Send(inputs);
    }

    private static INPUT KeyboardInput(ushort vk, bool keyDown) => new()
    {
        type = InputType.Keyboard,
        ki = new KEYBDINPUT
        {
            wVk = vk,
            wScan = 0,
            dwFlags = keyDown ? 0u : KeybdFlags.KeyUp,
            time = 0,
            dwExtraInfo = IntPtr.Zero,
        },
    };
}

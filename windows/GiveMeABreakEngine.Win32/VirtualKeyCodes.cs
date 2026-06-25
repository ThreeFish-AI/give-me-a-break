namespace TimeoutEngine.Win32;

// MARK: - 虚拟键码常量（Winuser.h）
// VK_MEDIA_* 系列用于 SendInput 合成媒体键（对齐 macOS CGEvent NX_KEYTYPE）。

public static class VirtualKeyCodes
{
    public const ushort MediaNextTrack = 0xB0;
    public const ushort MediaPrevTrack = 0xB1;
    public const ushort MediaStop = 0xB2;
    /// <summary>媒体播放/暂停 toggle（对齐 macOS NX_KEYTYPE_PLAY toggle 语义）。</summary>
    public const ushort MediaPlayPause = 0xB3;

    /// <summary>左 Win 键（WH_KEYBOARD_LL soft-force 拦截用）。</summary>
    public const ushort LWin = 0x5B;
    /// <summary>右 Win 键（WH_KEYBOARD_LL soft-force 拦截用）。</summary>
    public const ushort RWin = 0x5C;
}

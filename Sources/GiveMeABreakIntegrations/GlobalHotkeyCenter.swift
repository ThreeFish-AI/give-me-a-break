import AppKit
import Carbon.HIToolbox

/// 全局快捷键中心：经 Carbon `RegisterEventHotKey` 注册系统级快捷键（macOS 官方的应用级全局
/// 热键机制，零 TCC 权限，事件被系统消费、不会透传给前台应用）。
///
/// 为什么需要它：LSUIElement 菜单栏应用的 `NSMenuItem.keyEquivalent` 仅在菜单展开时生效
/// （AppKit 原生行为，非全局热键），无法承担「任意应用前台即时触发」的诉求；`CGEventTap`
/// 拦截虽可全局但需要「输入监控」权限。本中心补足零权限的全局触发层。
final class GlobalHotkeyCenter {
    /// 事件回调经 C 函数指针，需静态访问点（单实例约定：AppRoot 全局创建一份）。
    static private(set) var shared: GlobalHotkeyCenter?

    private var hotkeyRefs: [UInt32: EventHotKeyRef?] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false

    /// 注册一个全局快捷键（应用存活期持续有效）。
    /// - Parameters:
    ///   - keyCode: Carbon 虚拟键码（如 `kVK_ANSI_K`）
    ///   - modifiers: Carbon 修饰键位掩码（如 `controlKey | optionKey | cmdKey`）
    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                GlobalHotkeyCenter.handle(event: event!)
            }, 1, &spec, nil, nil)
            guard status == noErr else {
                NSLog("[GiveMeABreak][hotkey] InstallEventHandler 失败：\(status)")
                return
            }
            handlerInstalled = true
            GlobalHotkeyCenter.shared = self
        }

        let id = nextID
        nextID += 1
        var hotKeyRef: EventHotKeyRef?
        let hotkeyID = EventHotKeyID(signature: OSType(0x4D41534B), id: id)  // 'MASK'
        let status = RegisterEventHotKey(keyCode, modifiers, hotkeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            NSLog("[GiveMeABreak][hotkey] RegisterEventHotKey 失败：\(status)（keyCode=\(keyCode) modifiers=0x\(String(modifiers, radix: 16))）")
            return
        }
        hotkeyRefs[id] = hotKeyRef
        actions[id] = action
        NSLog("[GiveMeABreak][hotkey] 已注册全局快捷键 keyCode=\(keyCode) modifiers=0x\(String(modifiers, radix: 16))")
    }

    private static func handle(event: EventRef) -> OSStatus {
        var hotkeyID = EventHotKeyID()
        let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                       EventParamType(typeEventHotKeyID), nil,
                                       MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)
        guard status == noErr else { return status }
        shared?.actions[hotkeyID.id]?()  // 热键事件经主事件循环派发，直接调用即为主线程
        return noErr
    }
}

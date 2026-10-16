import Carbon.HIToolbox

/// Carbon 全局快捷键：无需额外权限，注册冲突时返回失败。
final class HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var installed = false
    private static var nextID: UInt32 = 1
    private var ref: EventHotKeyRef?

    @discardableResult
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        if !Self.installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, ev, _ in
                var hk = EventHotKeyID()
                GetEventParameter(ev, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hk)
                DispatchQueue.main.async { HotKey.handlers[hk.id]?() }
                return noErr
            }, 1, &spec, nil, nil)
            Self.installed = true
        }
        let id = Self.nextID; Self.nextID += 1
        let st = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: 0x5154_5254, id: id),
                                     GetApplicationEventTarget(), 0, &ref)
        guard st == noErr else { return nil }
        Self.handlers[id] = action
    }
}

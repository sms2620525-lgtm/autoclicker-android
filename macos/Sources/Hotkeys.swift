import Carbon

final class Hotkeys {
    private var handler: EventHandlerRef?
    private var refs: [EventHotKeyRef] = []
    var onKey: (UInt32) -> Void
    private(set) var registered = false

    init(onKey: @escaping (UInt32) -> Void) {
        self.onKey = onKey
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, data in
            guard let event = event, let data = data else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                          EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &key)
            guard result == noErr else { return result }
            Unmanaged<Hotkeys>.fromOpaque(data).takeUnretainedValue().onKey(key.id)
            return noErr
        }, 1, &type, context, &handler)
        guard status == noErr else { return }
        var ok = true
        // Control+Option+S: target 1; Control+Option+D: target 2; Control+Option+Space: toggle.
        let keys: [(UInt32, UInt32)] = [(1, 1), (2, 3), (49, 2)]
        for (keyCode, id) in keys {
            var ref: EventHotKeyRef?
            let keyID = EventHotKeyID(signature: 0x54415042, id: id)
            let result = RegisterEventHotKey(keyCode, UInt32(controlKey | optionKey), keyID,
                                            GetApplicationEventTarget(), 0, &ref)
            if result == noErr, let ref = ref { refs.append(ref) } else { ok = false }
        }
        registered = ok
    }

    deinit {
        for ref in refs { UnregisterEventHotKey(ref) }
        if let handler = handler { RemoveEventHandler(handler) }
    }
}

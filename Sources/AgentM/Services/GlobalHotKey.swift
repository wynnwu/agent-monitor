import Carbon.HIToolbox

/// A minimal, dependency-free global hotkey via Carbon's RegisterEventHotKey.
/// Fires `action` on the main thread whenever the combo is pressed system-wide.
@MainActor
final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private let hotKeyID: UInt32

    // Carbon delivers hotkey events on the main thread; these statics are only
    // touched there, so unchecked is safe.
    nonisolated(unsafe) private static var actions: [UInt32: () -> Void] = [:]
    nonisolated(unsafe) private static var nextID: UInt32 = 1
    nonisolated(unsafe) private static var handlerInstalled = false

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        hotKeyID = GlobalHotKey.nextID
        GlobalHotKey.nextID += 1
        GlobalHotKey.actions[hotKeyID] = action
        GlobalHotKey.installHandlerIfNeeded()

        let id = EventHotKeyID(signature: 0x4147_4D54 /* 'AGMT' */, id: hotKeyID)
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            GlobalHotKey.actions[hotKeyID] = nil
            return nil
        }
    }

    deinit {
        GlobalHotKey.actions[hotKeyID] = nil
    }

    /// Unregister now so the hotkey can be disabled or replaced with a new combo.
    func invalidate() {
        if let ref { UnregisterEventHotKey(ref); self.ref = nil }
        GlobalHotKey.actions[hotKeyID] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, eventRef, _) -> OSStatus in
            guard let eventRef else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            if let action = GlobalHotKey.actions[id.id] {
                DispatchQueue.main.async { action() }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}


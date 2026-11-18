import Carbon

/// Registers Escape only while a pointer tool owns it, even when another app has focus.
@MainActor
final class FloatingToolEscapeShortcut {
    static let identifier: UInt32 = 13
    struct Registration {
        var register: () -> Bool
        var unregister: () -> Void
    }

    private let registration: Registration?
    private let dismiss: () -> Void
    private var hotKey: EventHotKeyRef?
    private(set) var isRegistered = false
    private var keyIsDown = false

    init(registration: Registration? = nil, dismiss: @escaping () -> Void) {
        self.registration = registration
        self.dismiss = dismiss
    }

    func update(active: Bool, blocked: Bool) {
        let enabled = active && !blocked
        guard enabled != isRegistered else { return }
        if enabled {
            if let registration {
                isRegistered = registration.register()
            } else {
                isRegistered = RegisterEventHotKey(UInt32(kVK_Escape), 0,
                    EventHotKeyID(signature: 0x5343484E, id: Self.identifier),
                    GetApplicationEventTarget(), 0, &hotKey) == noErr
            }
        } else {
            if let registration { registration.unregister() }
            else if let hotKey { UnregisterEventHotKey(hotKey) }
            hotKey = nil
            isRegistered = false
            keyIsDown = false
        }
    }

    func handle(pressed: Bool) {
        guard isRegistered else { return }
        if !pressed { keyIsDown = false; return }
        guard !keyIsDown else { return }
        keyIsDown = true
        dismiss()
    }
}

import Carbon

/// The system-wide ⌘U shortcut. Carbon's RegisterEventHotKey needs no Accessibility
/// permission. The event handler is installed once; enabling only (un)registers the key,
/// so turning the shortcut off and on can't stack handlers.
@MainActor
final class HotKey {
    private let action: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in hotKey.action() }
            return noErr
        }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    func setEnabled(_ enabled: Bool) {
        if enabled, hotKeyRef == nil {
            let id = EventHotKeyID(signature: OSType(0x4864_526D), id: 1)   // 'HdRm'
            let status = RegisterEventHotKey(UInt32(kVK_ANSI_U), UInt32(cmdKey), id,
                                             GetApplicationEventTarget(), 0, &hotKeyRef)
            if status != noErr {
                Log.app.error("Could not register ⌘U: \(status)")
            }
        } else if !enabled, let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
}

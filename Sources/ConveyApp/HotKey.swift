import Carbon.HIToolbox
import AppKit

/// Wraps Carbon's `RegisterEventHotKey` to register a global keyboard shortcut.
///
/// Carbon hotkeys do not require Accessibility permission (unlike CGEventTap-based
/// approaches), which is why this app uses them for the global toggle shortcut.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let handler: () -> Void
    private static var counter: UInt32 = 0

    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler
        HotKey.counter += 1
        let id = EventHotKeyID(signature: OSType(0x43_4E_56_59), id: HotKey.counter) // 'CNVY'

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            // Carbon delivers this callback on the main run loop, so it's safe to hop
            // to the MainActor synchronously here to call the (possibly MainActor-isolated) handler.
            MainActor.assumeIsolated {
                hotKey.handler()
            }
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)
        guard status == noErr else { return nil }

        guard RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr else {
            return nil
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

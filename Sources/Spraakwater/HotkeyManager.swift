import Carbon.HIToolbox
import Foundation

/// Global hotkey with separate press and release events (needed for push-to-talk).
final class HotkeyManager {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var isDown = false

    func register(_ hotkey: Hotkey) {
        unregister()

        if handlerRef == nil {
            var specs = [
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
            ]
            InstallEventHandler(
                GetApplicationEventTarget(),
                hotkeyEventHandler,
                specs.count,
                &specs,
                Unmanaged.passUnretained(self).toOpaque(),
                &handlerRef
            )
        }

        let id = EventHotKeyID(signature: OSType(0x4449_4354), id: 1) // "DICT"
        RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        isDown = false
    }

    fileprivate func handle(kind: UInt32) {
        if kind == UInt32(kEventHotKeyPressed) {
            guard !isDown else { return }
            isDown = true
            onPress?()
        } else if kind == UInt32(kEventHotKeyReleased) {
            guard isDown else { return }
            isDown = false
            onRelease?()
        }
    }
}

// Carbon calls this on the main thread, but the C callback itself cannot be actor-isolated.
private nonisolated func hotkeyEventHandler(
    _: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return noErr }
    let kind = GetEventKind(event)
    // Raw pointers are not Sendable, so carry the address across as an Int.
    let address = Int(bitPattern: userData)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
        Unmanaged<HotkeyManager>.fromOpaque(pointer).takeUnretainedValue().handle(kind: kind)
    }
    return noErr
}

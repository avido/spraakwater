import AppKit
import Carbon.HIToolbox
import Foundation

/// Global hotkey with separate press and release events (needed for push-to-talk).
/// Key combinations use Carbon, which needs no permission. A single modifier key is watched through
/// NSEvent, which needs Input Monitoring. While recording, Escape is registered as a cancel key.
final class HotkeyManager {
    private static let signature = OSType(0x4449_4354) // "DICT"
    private static let dictationID: UInt32 = 1
    private static let escapeID: UInt32 = 2

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onEscape: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var escapeRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var monitors: [Any] = []
    private var modifierKey: ModifierKey?
    private var isDown = false

    /// Returns false when the combination is already taken by macOS or another app.
    @discardableResult
    func register(_ hotkey: Hotkey) -> Bool {
        unregister()
        installHandlerIfNeeded()

        switch hotkey {
        case let .combo(keyCode, modifiers, _):
            let id = EventHotKeyID(signature: Self.signature, id: Self.dictationID)
            let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
            return status == noErr

        case let .modifier(key):
            modifierKey = key
            let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                let code = event.keyCode
                let raw = event.modifierFlags.rawValue
                MainActor.assumeIsolated { self?.handleFlags(keyCode: code, rawFlags: raw) }
            }
            let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                let code = event.keyCode
                let raw = event.modifierFlags.rawValue
                MainActor.assumeIsolated { self?.handleFlags(keyCode: code, rawFlags: raw) }
                return event
            }
            monitors = [global, local].compactMap { $0 }
            return true
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        modifierKey = nil
        isDown = false
    }

    /// Escape only works as a cancel key while a recording is running, so it is free the rest of the time.
    func registerEscape() {
        guard escapeRef == nil else { return }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: Self.signature, id: Self.escapeID)
        RegisterEventHotKey(UInt32(kVK_Escape), 0, id, GetApplicationEventTarget(), 0, &escapeRef)
    }

    func unregisterEscape() {
        if let escapeRef {
            UnregisterEventHotKey(escapeRef)
            self.escapeRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
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

    fileprivate func handle(kind: UInt32, id: UInt32) {
        if id == Self.escapeID {
            if kind == UInt32(kEventHotKeyPressed) { onEscape?() }
            return
        }
        if kind == UInt32(kEventHotKeyPressed) {
            press()
        } else if kind == UInt32(kEventHotKeyReleased) {
            release()
        }
    }

    private func handleFlags(keyCode: UInt16, rawFlags: UInt) {
        guard let key = modifierKey, keyCode == key.keyCode else { return }
        if key.isDown(in: NSEvent.ModifierFlags(rawValue: rawFlags)) {
            press()
        } else {
            release()
        }
    }

    private func press() {
        guard !isDown else { return }
        isDown = true
        onPress?()
    }

    private func release() {
        guard isDown else { return }
        isDown = false
        onRelease?()
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
    var hotKeyID = EventHotKeyID()
    GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    let id = hotKeyID.id
    // Raw pointers are not Sendable, so carry the address across as an Int.
    let address = Int(bitPattern: userData)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
        Unmanaged<HotkeyManager>.fromOpaque(pointer).takeUnretainedValue().handle(kind: kind, id: id)
    }
    return noErr
}

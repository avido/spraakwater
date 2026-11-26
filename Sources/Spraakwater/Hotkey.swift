import AppKit
import Carbon.HIToolbox

/// A single physical modifier key that works as the dictation key on its own.
enum ModifierKey: String, Codable, CaseIterable, Identifiable {
    case fn
    case rightOption
    case rightCommand
    case rightControl

    var id: String { rawValue }

    init?(keyCode: UInt16) {
        guard let match = Self.allCases.first(where: { $0.keyCode == keyCode }) else { return nil }
        self = match
    }

    var keyCode: UInt16 {
        switch self {
        case .fn: 63
        case .rightOption: 61
        case .rightCommand: 54
        case .rightControl: 62
        }
    }

    var cap: String {
        switch self {
        case .fn: "fn"
        case .rightOption: "⌥ rechts"
        case .rightCommand: "⌘ rechts"
        case .rightControl: "⌃ rechts"
        }
    }

    /// Whether this physical key is down, using the device-dependent bits so left and right can be told apart.
    func isDown(in flags: NSEvent.ModifierFlags) -> Bool {
        switch self {
        case .fn: flags.contains(.function)
        case .rightOption: flags.rawValue & 0x40 != 0
        case .rightCommand: flags.rawValue & 0x10 != 0
        case .rightControl: flags.rawValue & 0x2000 != 0
        }
    }
}

/// The key that starts a dictation: a key with modifiers, or one modifier key on its own.
enum Hotkey: Codable, Hashable {
    case combo(keyCode: UInt32, modifiers: UInt32, label: String)
    case modifier(ModifierKey)

    static let optionSpace = Hotkey.combo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), label: "Spatie")
    static let controlSpace = Hotkey.combo(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey), label: "Spatie")
    static let commandOptionSpace = Hotkey.combo(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(cmdKey | optionKey),
        label: "Spatie"
    )

    static let presets: [Hotkey] = [
        .optionSpace, .controlSpace, .commandOptionSpace,
        .modifier(.fn), .modifier(.rightOption), .modifier(.rightCommand),
    ]

    /// The shortcut split into keycaps, for example ["⌥", "Spatie"].
    var keyCaps: [String] {
        switch self {
        case let .combo(_, modifiers, label): Self.symbols(for: modifiers) + [label]
        case let .modifier(key): [key.cap]
        }
    }

    var label: String { keyCaps.joined(separator: " ") }

    var isModifierOnly: Bool {
        if case .modifier = self { return true }
        return false
    }

    // MARK: Building a combo from a key event

    private static let modifierSymbols: [(mask: Int, symbol: String)] = [
        (controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘"),
    ]

    static func symbols(for modifiers: UInt32) -> [String] {
        modifierSymbols.filter { modifiers & UInt32($0.mask) != 0 }.map(\.symbol)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result = 0
        if flags.contains(.command) { result |= cmdKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.control) { result |= controlKey }
        if flags.contains(.shift) { result |= shiftKey }
        return UInt32(result)
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Spatie", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "Page Up", kVK_PageDown: "Page Down",
    ]

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20",
    ]

    static func isFunctionKey(_ keyCode: UInt16) -> Bool {
        functionKeys[Int(keyCode)] != nil
    }

    /// Name shown on the keycap for a key, nil when the key has no usable name.
    static func name(forKeyCode keyCode: UInt16, characters: String?) -> String? {
        if let name = specialKeys[Int(keyCode)] ?? functionKeys[Int(keyCode)] { return name }
        guard let characters = characters?.trimmingCharacters(in: .whitespaces), !characters.isEmpty else { return nil }
        return characters.uppercased()
    }
}

/// Listens for the next key or key combination, so the user can pick any dictation shortcut.
/// It only listens while this app is in front, so it needs no extra permission.
@Observable
final class HotkeyCapture {
    private(set) var isCapturing = false
    private(set) var problem: String?

    @ObservationIgnored var onCaptured: ((Hotkey) -> Void)?
    @ObservationIgnored var onStateChange: ((Bool) -> Void)?
    @ObservationIgnored private var monitor: Any?
    /// A modifier that went down and has not been used as part of a combination yet.
    @ObservationIgnored private var candidate: ModifierKey?

    func start() {
        guard !isCapturing else { return }
        problem = nil
        candidate = nil
        isCapturing = true
        onStateChange?(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            let swallow = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return swallow ? nil : event
        }
    }

    func stop() {
        guard isCapturing else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        candidate = nil
        isCapturing = false
        onStateChange?(false)
    }

    /// Returns true when the event is consumed, so it does not beep or reach a text field.
    private func handle(_ event: NSEvent) -> Bool {
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let flags = event.modifierFlags.intersection(relevant)

        switch event.type {
        case .keyDown:
            candidate = nil
            if event.keyCode == UInt16(kVK_Escape), flags.isEmpty {
                stop()
                return true
            }
            guard let name = Hotkey.name(forKeyCode: event.keyCode, characters: event.charactersIgnoringModifiers) else {
                problem = "Deze toets kan niet als sneltoets gebruikt worden."
                return true
            }
            // A bare letter would fire while typing. Function keys are safe on their own.
            if !Hotkey.isFunctionKey(event.keyCode), flags.intersection([.command, .option, .control]).isEmpty {
                problem = "Gebruik minstens ⌘, ⌥ of ⌃ samen met de toets."
                return true
            }
            finish(.combo(keyCode: UInt32(event.keyCode), modifiers: Hotkey.carbonModifiers(from: flags), label: name))
            return true

        case .flagsChanged:
            guard let key = ModifierKey(keyCode: event.keyCode) else {
                // Some other modifier changed, so this is not a single-modifier shortcut.
                candidate = nil
                return false
            }
            if key.isDown(in: event.modifierFlags) {
                candidate = key
            } else if candidate == key {
                // Pressed and released with nothing in between: use the modifier on its own.
                finish(.modifier(key))
            }
            return false

        default:
            return false
        }
    }

    private func finish(_ hotkey: Hotkey) {
        stop()
        onCaptured?(hotkey)
    }
}

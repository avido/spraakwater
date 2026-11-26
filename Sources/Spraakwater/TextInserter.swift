import AppKit
import Carbon.HIToolbox

/// Puts text at the cursor of the frontmost app by pasting it with Cmd+V.
enum TextInserter {
    static var hasAccessibilityAccess: Bool { AXIsProcessTrusted() }

    static func requestAccessibilityAccess() {
        // The literal is the value of kAXTrustedCheckOptionPrompt (the global itself is not concurrency-safe).
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Returns false when pasting is not allowed. The text then stays on the clipboard.
    static func paste(_ text: String) async -> Bool {
        let board = NSPasteboard.general

        guard hasAccessibilityAccess else {
            board.clearContents()
            board.setString(text, forType: .string)
            requestAccessibilityAccess()
            return false
        }

        // Keep what the user had on the clipboard so we can put it back afterwards.
        let saved: [[(NSPasteboard.PasteboardType, Data)]] = (board.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }

        board.clearContents()
        board.setString(text, forType: .string)
        // Tell clipboard managers to ignore this temporary entry.
        board.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        let changeCount = board.changeCount

        postCommandV()
        try? await Task.sleep(for: .milliseconds(400))

        // Only restore when nobody copied something else in the meantime.
        if board.changeCount == changeCount, !saved.isEmpty {
            board.clearContents()
            let items = saved.map { entries -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in entries { item.setData(data, forType: type) }
                return item
            }
            board.writeObjects(items)
        }
        return true
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let key = CGKeyCode(kVK_ANSI_V)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}

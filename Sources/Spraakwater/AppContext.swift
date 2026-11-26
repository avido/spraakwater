import AppKit

enum AppCategory: String, CaseIterable, Identifiable {
    case mail
    case chat
    case code
    case notes
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mail: "E-mail"
        case .chat: "Chat"
        case .code: "Code en terminal"
        case .notes: "Notities en documenten"
        case .other: "Overig"
        }
    }
}

/// The app the user is dictating into, used to adjust the tone of the cleaned text.
struct AppContext {
    let name: String
    let category: AppCategory
    let isBrowser: Bool

    private static let mail: Set<String> = [
        "com.apple.mail", "com.microsoft.Outlook", "com.readdle.smartemail-Mac",
        "org.mozilla.thunderbird", "it.bloop.airmail2",
    ]
    private static let chat: Set<String> = [
        "com.tinyspeck.slackmacgap", "net.whatsapp.WhatsApp", "com.apple.MobileSMS",
        "com.microsoft.teams2", "com.microsoft.teams", "com.hnc.Discord", "ru.keepcoder.Telegram",
        "org.whispersystems.signal-desktop", "com.facebook.archon",
    ]
    private static let code: Set<String> = [
        "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.apple.Terminal",
        "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable", "com.sublimetext.4", "dev.zed.Zed",
    ]
    private static let notes: Set<String> = [
        "com.apple.Notes", "notion.id", "md.obsidian", "com.apple.iWork.Pages", "com.microsoft.Word",
        "com.apple.TextEdit", "net.shinyfrog.bear",
    ]
    private static let browsers: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "company.thebrowser.Browser",
        "com.microsoft.edgemac", "com.brave.Browser",
    ]

    /// The frontmost app right now, nil when it cannot be determined.
    static func current() -> AppContext? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier
        else { return nil }

        let category: AppCategory = if mail.contains(bundleID) {
            .mail
        } else if chat.contains(bundleID) {
            .chat
        } else if code.contains(bundleID) || bundleID.hasPrefix("com.jetbrains.") {
            .code
        } else if notes.contains(bundleID) {
            .notes
        } else {
            .other
        }
        return AppContext(
            name: app.localizedName ?? bundleID,
            category: category,
            isBrowser: browsers.contains(bundleID)
        )
    }
}

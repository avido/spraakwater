import SwiftUI

@main
struct SpraakwaterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let controller = AppController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(controller: controller)
        } label: {
            Image(nsImage: MenuBarIcon.image(for: controller.phase))
        }
        .menuBarExtraStyle(.window)
    }
}

/// On a Mac with a notch, macOS hides menu bar icons that do not fit next to it. Opening the app
/// again (Spotlight, Finder, the Dock or `open`) then shows the main window, so you are never locked out.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppController.applyDockVisibility(AppController.shared.settings.showInDock)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindow.show(.overview)
        return true
    }
}

struct MenuPanel: View {
    let controller: AppController
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let message = controller.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(Theme.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.red.opacity(0.1)))
            }

            if let info = controller.info {
                Text(info)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(0.06)))
            }

            if let saved = controller.savedRecording, controller.phase == .idle {
                savedRecordingCard(saved)
            }

            if controller.phase == .idle {
                hint
            }

            if controller.settings.historyEnabled {
                if !controller.history.entries.isEmpty {
                    historySection
                }
            } else if let lastText = controller.lastText {
                lastTextCard(lastText)
            }

            Divider()

            VStack(spacing: 2) {
                MenuRow(title: "Overzicht", shortcut: "⌘O") { MainWindow.show(.overview) }
                    .keyboardShortcut("o")
                MenuRow(title: "Instellingen", shortcut: "⌘,") { SettingsWindow.show() }
                    .keyboardShortcut(",")
                MenuRow(title: "Afsluiten", shortcut: "⌘Q") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .padding(.horizontal, -6)
            .padding(.top, -6)
        }
        .padding(16)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Spraakwater")
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: 6) {
                    StatusDot(phase: controller.phase)
                    Text(controller.phase.title)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var hint: some View {
        HStack(spacing: 6) {
            Text("Houd")
            ForEach(controller.settings.hotkey.keyCaps, id: \.self) { KeyCap(symbol: $0) }
            Text("ingedrukt en praat")
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }

    private func savedRecordingCard(_ saved: AppController.SavedRecording) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bewaarde opname")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Van \(saved.date.formatted(.relative(presentation: .named).locale(.dutch))). De transcriptie is niet gelukt.")
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            if saved.others > 0 {
                Text("Nog \(saved.others) andere bewaard.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                Button("Opnieuw proberen") { controller.retrySavedRecording() }
                    .foregroundStyle(Theme.red)
                Button("Verwijderen") { controller.discardSavedRecording() }
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.red.opacity(0.08)))
    }

    private var historySection: some View {
        let entries = controller.history.entries
        return VStack(alignment: .leading, spacing: 6) {
            Text("Geschiedenis")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(entries.prefix(50)) { entry in
                        HistoryRow(entry: entry) { controller.copyToClipboard(entry.text) }
                    }
                }
            }
            .frame(height: CGFloat(min(entries.count, 4)) * HistoryRow.height + CGFloat(min(entries.count, 4) - 1) * 2)
        }
    }

    private func lastTextCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Laatste tekst")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 12))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                controller.copyLastText()
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    copied = false
                }
            } label: {
                Label(copied ? "Gekopieerd" : "Kopieer", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .foregroundStyle(copied ? .secondary : Theme.red)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.05)))
    }
}

/// One earlier dictation. Clicking copies it.
private struct HistoryRow: View {
    static let height: CGFloat = 46

    let entry: HistoryEntry
    let onCopy: () -> Void
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        Button {
            onCopy()
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                copied = false
            }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.text)
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(copied ? Theme.red : .secondary)
                    .opacity(hovering || copied ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .leading)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.primary.opacity(hovering ? 0.07 : 0.03)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var subtitle: String {
        let time = entry.date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated).locale(.dutch))
        guard let app = entry.appName else { return time }
        return "\(time) in \(app)"
    }
}

/// A full-width menu row with a hover highlight, since the window style has no native menu items.
private struct MenuRow: View {
    let title: String
    let shortcut: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(shortcut).foregroundStyle(.tertiary)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.primary.opacity(hovering ? 0.08 : 0)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { hovering = $0 }
    }
}

struct StatusDot: View {
    let phase: AppController.Phase
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(phase == .recording ? Theme.red : .secondary.opacity(phase == .processing ? 0.9 : 0.45))
            .frame(width: 7, height: 7)
            .opacity(phase != .idle && pulse ? 0.35 : 1)
            .animation(phase == .idle ? .default : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

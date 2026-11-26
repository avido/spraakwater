import SwiftUI

@main
struct SpraakwaterApp: App {
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

            if controller.phase == .idle {
                hint
            }

            if let lastText = controller.lastText {
                lastTextCard(lastText)
            }

            Divider()

            VStack(spacing: 2) {
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

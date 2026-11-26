import AppKit
import SwiftUI

/// Opens the settings window. A menu bar app has no Settings scene to lean on, so we host it ourselves.
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: AppController.shared.settings))
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "Dicteer instellingen"
            newWindow.styleMask = [.titled, .closable]
            newWindow.isReleasedWhenClosed = false
            newWindow.setContentSize(NSSize(width: 520, height: 640))
            newWindow.center()
            window = newWindow
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @Bindable var settings: Settings
    @State private var accessibilityGranted = TextInserter.hasAccessibilityAccess
    @State private var microphone = MicrophoneAccess.current

    var body: some View {
        Form {
            Section("Transcriptie") {
                Picker("Dienst", selection: $settings.provider) {
                    ForEach(TranscriptionProvider.allCases) { Text($0.label).tag($0) }
                }
                Picker("Taal", selection: $settings.language) {
                    ForEach(DictationLanguage.allCases) { Text($0.label).tag($0) }
                }
                switch settings.provider {
                case .openAI:
                    keyField("OpenAI-sleutel", text: $settings.openAIKey, problem: settings.keyProblem(for: .openAI))
                case .groq:
                    keyField("Groq-sleutel", text: $settings.groqKey, problem: settings.keyProblem(for: .groq))
                }
            }

            Section("Tekst opruimen met Claude") {
                Toggle("Vulwoorden en fouten laten opruimen", isOn: $settings.cleanupEnabled)
                if settings.cleanupEnabled {
                    keyField("Anthropic-sleutel", text: $settings.anthropicKey, problem: settings.anthropicKeyProblem)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Extra schrijfregels")
                        TextEditor(text: $settings.extraInstructions)
                            .font(.body)
                            .frame(height: 70)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    }
                    Text("Model: \(TextCleaner.model)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Woordenlijst") {
                TextEditor(text: $settings.vocabulary)
                    .font(.body)
                    .frame(height: 70)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                Text("Namen en vaktermen die vaak verkeerd verstaan worden, gescheiden door een komma of een nieuwe regel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sneltoets") {
                Picker("Toets", selection: $settings.hotkey) {
                    ForEach(Hotkey.allCases) { Text($0.label).tag($0) }
                }
                Text("Houd de toets ingedrukt terwijl je praat. Een korte tik laat de opname doorlopen tot je nog een keer drukt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Rechten") {
                permissionRow(
                    "Microfoon",
                    granted: microphone == .granted,
                    pane: "Privacy_Microphone",
                    // Not in the system list yet: asking once is what adds the app to it.
                    ask: microphone == .undetermined
                        ? {
                            Task {
                                await MicrophoneAccess.request()
                                refreshPermissions()
                            }
                        }
                        : nil
                )
                permissionRow(
                    "Toegankelijkheid (om te plakken)",
                    granted: accessibilityGranted,
                    pane: "Privacy_Accessibility"
                )
                Button("Status opnieuw controleren") { refreshPermissions() }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshPermissions)
    }

    private func keyField(_ title: String, text: Binding<String>, problem: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                SecureField(title, text: text, prompt: Text("Plak hier je sleutel"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
            }
            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func permissionRow(
        _ title: String,
        granted: Bool,
        pane: String,
        ask: (() -> Void)? = nil
    ) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Text(title)
            Spacer()
            if let ask {
                Button("Toegang vragen", action: ask)
            } else if !granted {
                Button("Openen") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    private func refreshPermissions() {
        accessibilityGranted = TextInserter.hasAccessibilityAccess
        microphone = MicrophoneAccess.current
    }
}

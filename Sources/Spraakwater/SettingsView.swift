import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: Settings
    /// The big app header is only wanted when the settings stand alone, not inside the main window.
    var showsHeader = true
    @State private var accessibilityGranted = TextInserter.hasAccessibilityAccess
    @State private var microphone = MicrophoneAccess.current
    @State private var inputMonitoringGranted = CGPreflightListenEventAccess()
    @State private var limitDraft = 50.0
    @State private var draggingLimit = false
    @State private var capture = HotkeyCapture()
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchProblem: String?

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader { header }
            form
        }
        .tint(Theme.red)
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private var header: some View {
        HStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            VStack(alignment: .leading, spacing: 6) {
                Text("Spraakwater")
                    .font(.system(size: 26, weight: .semibold))
                Text("Versie \(version)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                readiness
                    .padding(.top, 4)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 34)
        .padding(.bottom, 18)
        .background(alignment: .trailing) {
            // Oversized, faded copy of the artwork so the header carries the illustration.
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFill()
                .frame(width: 320, height: 240)
                .opacity(0.22)
                .blur(radius: 1.5)
                .mask(
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                )
                .clipped()
        }
        .clipped()
    }

    /// Tells at a glance whether a dictation would work right now.
    private var readiness: some View {
        let problem = settings.configurationProblem
        return HStack(spacing: 6) {
            Circle()
                .fill(problem == nil ? Color.green : Theme.red)
                .frame(width: 7, height: 7)
            Text(problem == nil ? "Klaar om te dicteren" : "Nog niet ingesteld")
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(.primary.opacity(0.06)))
    }

    private var form: some View {
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
                    Text("Model: \(TextCleaner.model). Schrijfregels en toon per app stel je in bij Schrijfstijl.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Microfoon") {
                MicrophoneList(settings: settings)
            }

            Section("Sneltoets") {
                LabeledContent("Nu") {
                    HStack(spacing: 4) {
                        ForEach(settings.hotkey.keyCaps, id: \.self) { KeyCap(symbol: $0) }
                    }
                }
                HStack {
                    Menu("Snelle keuze") {
                        ForEach(Hotkey.presets, id: \.self) { preset in
                            Button(preset.label) { settings.hotkey = preset }
                        }
                    }
                    .fixedSize()
                    Spacer()
                    Button(capture.isCapturing ? "Stoppen" : "Eigen sneltoets opnemen") {
                        if capture.isCapturing { capture.stop() } else { capture.start() }
                    }
                }
                if capture.isCapturing {
                    Text("Druk nu de toets of combinatie die je wilt gebruiken. Een losse fn of rechter ⌥ ⌘ ⌃ kan ook. Esc stopt.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let problem = capture.problem ?? settings.hotkeyError {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Houd de toets ingedrukt terwijl je praat. Een korte tik laat de opname doorlopen tot je nog een keer drukt. Esc annuleert een opname.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Geschiedenis") {
                Toggle("Dictaten bewaren op deze Mac", isOn: $settings.historyEnabled)
                if settings.historyEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent("Aantal bewaren") {
                            Text("\(Int(limitDraft))")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: $limitDraft,
                            in: Double(Settings.historyLimitRange.lowerBound)...Double(Settings.historyLimitRange.upperBound),
                            step: 1
                        ) { editing in
                            draggingLimit = editing
                            if !editing { commitLimit() }
                        }
                        .onChange(of: limitDraft) {
                            // Keyboard steps do not report an end of editing, so settle after a short pause.
                            guard !draggingLimit else { return }
                            let value = limitDraft
                            Task {
                                try? await Task.sleep(for: .seconds(0.5))
                                if value == limitDraft { commitLimit() }
                            }
                        }
                        HStack {
                            Text("\(Settings.historyLimitRange.lowerBound)")
                            Spacer()
                            Text("\(Settings.historyLimitRange.upperBound)")
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                    LabeledContent("Nu bewaard") {
                        HStack {
                            Text("\(AppController.shared.history.entries.count)")
                                .foregroundStyle(.secondary)
                            Button("Wissen") { AppController.shared.history.clear() }
                        }
                    }
                }
                Text("De teksten blijven alleen op deze Mac. Zet je het aantal lager, dan worden oudere dictaten verwijderd zodra je de slider loslaat. Zet je de geschiedenis uit, dan wordt alles gewist.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Statistieken") {
                    Button("Terugzetten") { AppController.shared.statistics.reset() }
                }
                Text("De tellers op het overzicht (woorden, tijd, dagen op rij) staan los van de geschiedenis en bevatten geen tekst.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Opstarten") {
                Toggle("Start Spraakwater bij inloggen", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                Toggle("Toon Spraakwater in het Dock", isOn: $settings.showInDock)
                Text("Handig als je menubalk vol zit. macOS verbergt dan iconen die naast de notch vallen. Klik op het Dock-icoon om de instellingen te openen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let launchProblem {
                    Text(launchProblem)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
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
                if settings.hotkey.isModifierOnly {
                    permissionRow(
                        "Invoercontrole (voor een losse toets als fn)",
                        granted: inputMonitoringGranted,
                        pane: "Privacy_ListenEvent"
                    )
                }
                Button("Status opnieuw controleren") { refreshPermissions() }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            limitDraft = Double(settings.historyLimit)
            refreshPermissions()
            capture.onCaptured = { settings.hotkey = $0 }
            capture.onStateChange = { AppController.shared.setHotkeyCapturing($0) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            capture.stop()
        }
    }

    private func commitLimit() {
        let value = Int(limitDraft)
        if value != settings.historyLimit { settings.historyLimit = value }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            launchProblem = LaunchAtLogin.needsApproval
                ? "Keur Spraakwater goed bij Systeeminstellingen > Algemeen > Inlog-onderdelen."
                : nil
        } catch {
            launchProblem = "Dit lukt alleen vanuit de geinstalleerde app in Programma's. (\(error.localizedDescription))"
        }
        launchAtLogin = LaunchAtLogin.isEnabled
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
        inputMonitoringGranted = CGPreflightListenEventAccess()
        launchAtLogin = LaunchAtLogin.isEnabled
    }
}

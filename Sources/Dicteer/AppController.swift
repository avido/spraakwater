import AppKit
import Observation

@Observable
final class AppController {
    static let shared = AppController()

    enum Phase {
        case idle
        case recording
        case processing
    }

    /// A press shorter than this latches the recording on instead of stopping it on release.
    private static let tapThreshold: TimeInterval = 0.35
    private static let minimumDuration: TimeInterval = 0.5

    private(set) var phase: Phase = .idle
    private(set) var lastText: String?
    private(set) var message: String?

    let settings = Settings()

    /// Read by the overlay, which is why it is not private.
    @ObservationIgnored let spectrum = SpectrumAnalyzer()
    @ObservationIgnored private let recorder = AudioRecorder()
    @ObservationIgnored private let hotkeys = HotkeyManager()
    @ObservationIgnored private var pressedAt: Date?
    @ObservationIgnored private var ignoreNextRelease = false

    private init() {
        hotkeys.onPress = { [weak self] in self?.keyDown() }
        hotkeys.onRelease = { [weak self] in self?.keyUp() }
        hotkeys.register(settings.hotkey)
        settings.onHotkeyChange = { [weak self] hotkey in self?.hotkeys.register(hotkey) }

        // macOS only lists an app under Microphone after it has asked once, so ask right away.
        if MicrophoneAccess.current == .undetermined {
            Task { await MicrophoneAccess.request() }
        }
    }

    var iconName: String {
        switch phase {
        case .idle: "mic"
        case .recording: "record.circle.fill"
        case .processing: "ellipsis.circle"
        }
    }

    var statusText: String {
        switch phase {
        case .idle: "Klaar. Houd \(settings.hotkey.label) ingedrukt om te dicteren."
        case .recording: "Aan het opnemen..."
        case .processing: "Bezig met transcriberen..."
        }
    }

    func copyLastText() {
        guard let lastText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastText, forType: .string)
    }

    /// Single place where the phase changes, so the overlay and level meter always follow it.
    private func setPhase(_ newPhase: Phase) {
        phase = newPhase
        switch newPhase {
        case .recording:
            RecordingOverlay.show()
            spectrum.start()
        case .processing:
            spectrum.stop()
            RecordingOverlay.show()
        case .idle:
            spectrum.stop()
            RecordingOverlay.hide()
        }
    }

    // MARK: Hotkey

    private func keyDown() {
        switch phase {
        case .recording:
            // Second press of a latched recording stops it.
            ignoreNextRelease = true
            finishRecording()
        case .idle:
            startRecording()
        case .processing:
            NSSound.beep()
        }
    }

    private func keyUp() {
        if ignoreNextRelease {
            ignoreNextRelease = false
            return
        }
        guard phase == .recording, let pressedAt else { return }
        // A quick tap keeps recording until the next press. A held key stops on release.
        if Date().timeIntervalSince(pressedAt) < Self.tapThreshold { return }
        finishRecording()
    }

    // MARK: Recording

    private func startRecording() {
        // Validate before anything goes over the network.
        if let problem = settings.configurationProblem {
            fail(problem, openSettings: true)
            return
        }
        switch MicrophoneAccess.current {
        case .denied:
            fail(DicteerError.microphoneDenied.localizedDescription)
            return
        case .undetermined:
            Task { await MicrophoneAccess.request() }
            fail("Geef Dicteer toegang tot de microfoon en druk daarna nog een keer op de sneltoets.")
            return
        case .granted:
            break
        }

        do {
            try recorder.start()
            message = nil
            pressedAt = Date()
            setPhase(.recording)
            NSSound(named: "Tink")?.play()
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func finishRecording() {
        guard let recording = recorder.stop() else {
            setPhase(.idle)
            return
        }
        if recording.duration < Self.minimumDuration {
            try? FileManager.default.removeItem(at: recording.url)
            setPhase(.idle)
            return
        }
        setPhase(.processing)
        NSSound(named: "Pop")?.play()
        Task { await process(recording.url) }
    }

    // MARK: Pipeline

    private func process(_ fileURL: URL) async {
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            let provider = settings.provider
            var text = try await Transcriber().transcribe(
                fileURL: fileURL,
                provider: provider,
                apiKey: settings.key(for: provider).trimmingCharacters(in: .whitespacesAndNewlines),
                language: settings.language,
                vocabulary: settings.vocabularyWords
            )
            guard !text.isEmpty else {
                setPhase(.idle)
                return
            }

            if settings.cleanupEnabled {
                do {
                    text = try await TextCleaner().clean(
                        text,
                        apiKey: settings.anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines),
                        vocabulary: settings.vocabularyWords,
                        extraInstructions: settings.extraInstructions
                    )
                } catch {
                    // Never lose the dictation: fall back to the raw transcript.
                    message = "Opruimen mislukt, de ruwe tekst is geplakt. (\(error.localizedDescription))"
                }
            }

            lastText = text
            setPhase(.idle)
            let pasted = await TextInserter.paste(text)
            if !pasted {
                message = "Plakken mag nog niet. Zet Dicteer aan bij Toegankelijkheid. De tekst staat op je klembord."
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func fail(_ text: String, openSettings: Bool = false) {
        message = text
        setPhase(.idle)
        NSSound.beep()
        if openSettings {
            SettingsWindow.show()
        }
    }
}

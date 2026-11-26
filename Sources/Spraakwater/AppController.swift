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

    /// A recording that was saved because the transcription failed.
    struct SavedRecording {
        let url: URL
        let date: Date
        /// How many other saved recordings are waiting behind this one.
        let others: Int
    }

    /// A press shorter than this latches the recording on instead of stopping it on release.
    private static let tapThreshold: TimeInterval = 0.35
    private static let minimumDuration: TimeInterval = 0.5

    private(set) var phase: Phase = .idle
    private(set) var lastText: String?
    private(set) var message: String?
    private(set) var info: String?
    private(set) var savedRecording: SavedRecording?

    let settings = Settings()
    let history = HistoryStore()
    let statistics = StatisticsStore()

    /// Read by the overlay, which is why it is not private.
    @ObservationIgnored let spectrum = SpectrumAnalyzer()
    @ObservationIgnored private let recorder = AudioRecorder()
    @ObservationIgnored private let hotkeys = HotkeyManager()
    @ObservationIgnored private var pressedAt: Date?
    @ObservationIgnored private var ignoreNextRelease = false
    /// The recording that is being captured or transcribed right now, so it is not offered as "saved".
    @ObservationIgnored private var activeURL: URL?
    @ObservationIgnored private var recordingContext: AppContext?

    private init() {
        RecordingStore.purgeOld()
        refreshSavedRecording()

        hotkeys.onPress = { [weak self] in self?.keyDown() }
        hotkeys.onRelease = { [weak self] in self?.keyUp() }
        hotkeys.onEscape = { [weak self] in self?.cancelRecording() }
        recorder.onLimit = { [weak self] in
            guard self?.phase == .recording else { return }
            self?.finishRecording()
        }
        settings.onHotkeyChange = { [weak self] hotkey in self?.registerHotkey(hotkey) }
        settings.onHistoryDisabled = { [weak self] in self?.history.clear() }
        settings.onDockChange = { Self.applyDockVisibility($0) }
        history.limit = settings.historyLimit
        settings.onHistoryLimitChange = { [weak self] in self?.history.limit = $0 }
        registerHotkey(settings.hotkey)

        // macOS only lists an app under Microphone after it has asked once, so ask right away.
        if MicrophoneAccess.current == .undetermined {
            Task { await MicrophoneAccess.request() }
        }
    }

    var statusText: String {
        switch phase {
        case .idle: "Klaar. Houd \(settings.hotkey.label) ingedrukt om te dicteren."
        case .recording: "Aan het opnemen..."
        case .processing: "Bezig met transcriberen..."
        }
    }

    /// A menu bar app has no Dock icon by default. Turning it on makes it a regular app, so the Dock
    /// click (handled as a reopen) always gets you to the settings.
    static func applyDockVisibility(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
    }

    func copyLastText() {
        guard let lastText else { return }
        copyToClipboard(lastText)
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// The dictation key is switched off while the settings window records a new one.
    func setHotkeyCapturing(_ capturing: Bool) {
        if capturing {
            hotkeys.unregister()
        } else {
            registerHotkey(settings.hotkey)
        }
    }

    private func registerHotkey(_ hotkey: Hotkey) {
        let registered = hotkeys.register(hotkey)
        settings.hotkeyError = registered
            ? nil
            : "Deze sneltoets is al in gebruik door macOS of een andere app. Kies een andere."
        if registered, hotkey.isModifierOnly, !CGPreflightListenEventAccess() {
            // The system dialog also adds Spraakwater to the Input Monitoring list.
            CGRequestListenEventAccess()
        }
    }

    /// Single place where the phase changes, so the overlay and the cancel key always follow it.
    private func setPhase(_ newPhase: Phase) {
        phase = newPhase
        switch newPhase {
        case .recording:
            RecordingOverlay.show()
            hotkeys.registerEscape()
        case .processing:
            hotkeys.unregisterEscape()
            spectrum.reset()
            RecordingOverlay.show()
        case .idle:
            hotkeys.unregisterEscape()
            spectrum.reset()
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
            fail(SpraakwaterError.microphoneDenied.localizedDescription)
            return
        case .undetermined:
            Task { await MicrophoneAccess.request() }
            fail("Geef Spraakwater toegang tot de microfoon en druk daarna nog een keer op de sneltoets.")
            return
        case .granted:
            break
        }

        // Look at the frontmost app now, because by the time the text is ready you may be elsewhere.
        recordingContext = settings.cleanupEnabled && settings.contextEnabled ? AppContext.current() : nil

        do {
            activeURL = try recorder.start(deviceUID: settings.inputDeviceUID, spectrum: spectrum)
            message = nil
            info = nil
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
        let held = Date().timeIntervalSince(pressedAt ?? Date())
        if recording.duration < Self.minimumDuration {
            try? FileManager.default.removeItem(at: recording.url)
            activeURL = nil
            setPhase(.idle)
            // Held for a while but almost nothing recorded: the microphone gave no audio, so say so.
            if held >= 2, recording.duration < held / 2 {
                fail("De microfoon gaf geen geluid door. Controleer de gekozen microfoon bij Instellingen.")
            }
            return
        }
        setPhase(.processing)
        NSSound(named: "Pop")?.play()
        let context = recordingContext
        Task { await process(recording.url, context: context, isRetry: false) }
    }

    /// Escape while recording throws the recording away without transcribing it.
    private func cancelRecording() {
        guard phase == .recording else { return }
        recorder.cancel()
        activeURL = nil
        ignoreNextRelease = false
        setPhase(.idle)
        NSSound(named: "Bottle")?.play()
    }

    // MARK: Saved recordings

    func retrySavedRecording() {
        guard phase == .idle, let saved = savedRecording else { return }
        if let problem = settings.configurationProblem {
            fail(problem, openSettings: true)
            return
        }
        message = nil
        info = nil
        setPhase(.processing)
        Task { await process(saved.url, context: nil, isRetry: true) }
    }

    func discardSavedRecording() {
        guard phase == .idle, let saved = savedRecording else { return }
        try? FileManager.default.removeItem(at: saved.url)
        refreshSavedRecording()
    }

    private func refreshSavedRecording() {
        let items = RecordingStore.leftovers(excluding: activeURL)
        savedRecording = items.first.map { SavedRecording(url: $0.url, date: $0.date, others: items.count - 1) }
    }

    // MARK: Pipeline

    private func process(_ fileURL: URL, context: AppContext?, isRetry: Bool) async {
        activeURL = fileURL
        defer {
            activeURL = nil
            refreshSavedRecording()
        }

        // Read the length now, because the file is removed as soon as the transcript is in.
        let spokenSeconds = RecordingStore.duration(of: fileURL)

        var text: String
        do {
            let provider = settings.provider
            text = try await Transcriber().transcribe(
                fileURL: fileURL,
                provider: provider,
                apiKey: settings.key(for: provider).trimmingCharacters(in: .whitespacesAndNewlines),
                language: settings.language,
                vocabulary: Array(settings.vocabularyWords.prefix(60))
            )
        } catch {
            // Keep the recording on disk, so a dropped connection or a wrong key never costs a dictation.
            fail("\(error.localizedDescription) De opname is bewaard, probeer het zo opnieuw.")
            return
        }

        // The transcript is in hand, so the audio is no longer needed.
        try? FileManager.default.removeItem(at: fileURL)
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
                    extraInstructions: settings.extraInstructions,
                    context: context,
                    tone: context.map { settings.tone(for: $0.category) } ?? ""
                )
            } catch {
                // Never lose the dictation: fall back to the raw transcript.
                message = "Opruimen mislukt, de ruwe tekst is gebruikt. (\(error.localizedDescription))"
            }
        }

        lastText = text
        statistics.record(words: StatisticsStore.wordCount(text), seconds: spokenSeconds)
        if settings.historyEnabled {
            history.add(text: text, appName: context?.name)
        }
        setPhase(.idle)

        if isRetry {
            // The app you were in is long gone, so a paste would land in the wrong place.
            copyToClipboard(text)
            info = "De tekst staat op je klembord. Plak hem met ⌘V."
            return
        }
        let pasted = await TextInserter.paste(text)
        if !pasted {
            message = "Plakken mag nog niet. Zet Spraakwater aan bij Toegankelijkheid. De tekst staat op je klembord."
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

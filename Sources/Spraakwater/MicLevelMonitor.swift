import Accelerate
@preconcurrency import AVFoundation
import os

/// Latest input level and how many buffers arrived, written on the audio thread.
nonisolated final class LevelStore: Sendable {
    private let lock = OSAllocatedUnfairLock<(level: Float, buffers: Int)>(initialState: (0, 0))

    func record(_ level: Float) { lock.withLock { $0 = (level, $0.buffers + 1) } }
    var level: Float { lock.withLock { $0.level } }
    var buffers: Int { lock.withLock { $0.buffers } }
}

/// Listens to one microphone so the settings can show a live level, and so a microphone that
/// gives no sound is noticed before you start dictating.
///
/// A phone or Bluetooth microphone needs a moment to wake up and may briefly drop the connection,
/// so this waits longer for those, restarts itself when the audio route changes and only reports
/// a problem after a real silence in the data.
@Observable
final class MicLevelMonitor {
    /// Set when the microphone cannot be opened or stops giving audio.
    private(set) var problem: String?
    private(set) var isRunning = false

    @ObservationIgnored let store = LevelStore()
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var configObserver: NSObjectProtocol?
    @ObservationIgnored private var currentUID: String?
    @ObservationIgnored private var graceSeconds = 3
    @ObservationIgnored private var restartsLeft = 0

    /// `grace` is how many seconds without audio are fine, longer for a phone that has to wake up.
    func start(deviceUID: String, grace: Int = 3) {
        // Starting the same microphone again would close and reopen it, which a phone does not like.
        if isRunning, currentUID == deviceUID { return }
        stop()
        currentUID = deviceUID
        graceSeconds = grace
        restartsLeft = 3
        problem = nil
        open()
    }

    func stop() {
        watchdog?.cancel()
        watchdog = nil
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        teardownEngine()
        currentUID = nil
        isRunning = false
    }

    private func teardownEngine() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
    }

    private func open() {
        guard MicrophoneAccess.current == .granted, let uid = currentUID else { return }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        if !uid.isEmpty, let deviceID = AudioDevices.deviceID(forUID: uid) {
            do {
                try input.auAudioUnit.setDeviceID(deviceID)
            } catch {
                problem = "Deze microfoon reageert niet. Kies een andere."
                return
            }
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            problem = "Deze microfoon geeft geen geluid door. Kies een andere."
            return
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeTap(store))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            problem = "Deze microfoon kon niet worden geopend. Kies een andere."
            return
        }
        self.engine = engine
        isRunning = true

        // The system stops the engine when the audio route changes, for example when a phone connects.
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.routeChanged() }
        }
        startWatchdog()
    }

    private func routeChanged() {
        guard isRunning, restartsLeft > 0 else { return }
        restartsLeft -= 1
        watchdog?.cancel()
        teardownEngine()
        // Give the route a moment to settle before opening the microphone again.
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.open()
        }
    }

    /// Checks every second whether audio still arrives. Only a longer silence counts as a problem,
    /// and the message goes away again when audio comes back.
    private func startWatchdog() {
        watchdog?.cancel()
        let grace = graceSeconds
        watchdog = Task { [weak self] in
            var last = self?.store.buffers ?? 0
            var quiet = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, self.isRunning else { return }
                let now = self.store.buffers
                if now != last {
                    last = now
                    quiet = 0
                    if self.problem != nil { self.problem = nil }
                } else {
                    quiet += 1
                    if quiet >= grace {
                        self.problem = "Geen geluid ontvangen van deze microfoon. Kies een andere."
                    }
                }
            }
        }
    }

    private nonisolated static func makeTap(_ store: LevelStore) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var rms: Float = 0
            vDSP_rmsqv(channel, 1, &rms, vDSP_Length(buffer.frameLength))
            // About -55 dB (silence) to -10 dB (loud speech) maps to 0...1.
            let decibels = 20 * log10(rms + 1e-7)
            store.record(max(0, min(1, (decibels + 55) / 45)))
        }
    }
}

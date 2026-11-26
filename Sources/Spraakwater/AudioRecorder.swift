@preconcurrency import AVFoundation

enum MicrophoneAccess {
    case granted
    case undetermined
    case denied

    static var current: MicrophoneAccess {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .undetermined
        default: .denied
        }
    }

    static func request() async {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
    }
}

/// Where recordings live until they are transcribed. A recording stays on disk when the
/// transcription fails, so a dropped connection never costs you a dictation.
enum RecordingStore {
    /// Recordings that were never transcribed are removed after this many days.
    private static let keepDays = 7

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Spraakwater/Opnames", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func newFileURL() -> URL {
        directory.appendingPathComponent("opname-\(UUID().uuidString).wav")
    }

    /// Saved recordings, newest first. `excluding` is the recording that is being processed right now.
    static func leftovers(excluding active: URL? = nil) -> [(url: URL, date: Date)] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return urls
            .filter { $0.pathExtension == "wav" && $0 != active }
            .map { url in
                let date = (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
                return (url, date)
            }
            .sorted { $0.date > $1.date }
    }

    /// Length of a recording in seconds, 0 when the file cannot be read.
    static func duration(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    static func purgeOld() {
        let limit = Date().addingTimeInterval(-Double(keepDays) * 86400)
        for item in leftovers() where item.date < limit {
            try? FileManager.default.removeItem(at: item.url)
        }
    }
}

/// Converts the microphone buffers to 16 kHz mono and writes them to the WAV file, and feeds the overlay.
/// Runs on the audio thread, so it is not bound to the main actor and guards its state with a lock.
nonisolated final class RecordingWriter: @unchecked Sendable {
    static let sampleRate = 16000.0

    private let lock = NSLock()
    private var file: AVAudioFile?
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let spectrum: SpectrumProcessor
    private let maxFrames: AVAudioFramePosition
    private let onLimit: @Sendable () -> Void
    private var written: AVAudioFramePosition = 0
    private var limitReported = false

    init(
        url: URL,
        inputFormat: AVAudioFormat,
        spectrum: SpectrumProcessor,
        maxSeconds: Double,
        onLimit: @escaping @Sendable () -> Void
    ) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        guard let converter = AVAudioConverter(from: inputFormat, to: file.processingFormat) else {
            throw SpraakwaterError.recordingFailed
        }
        self.file = file
        self.converter = converter
        outputFormat = file.processingFormat
        self.spectrum = spectrum
        maxFrames = AVAudioFramePosition(maxSeconds * Self.sampleRate)
        self.onLimit = onLimit
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        spectrum.process(buffer)

        lock.lock()
        defer { lock.unlock() }
        guard let file, written < maxFrames else { return }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        // The input block runs synchronously inside convert, so this flag is never shared across threads.
        nonisolated(unsafe) var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, output.frameLength > 0 else { return }
        try? file.write(from: output)
        written += AVAudioFramePosition(output.frameLength)

        if written >= maxFrames, !limitReported {
            limitReported = true
            onLimit()
        }
    }

    /// Closes the file, which finalizes the WAV header. Returns how long the recording is.
    func close() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        file = nil
        return Double(written) / Self.sampleRate
    }
}

/// Records from the chosen microphone as 16 kHz mono PCM, which is all the transcription models need
/// and keeps uploads small.
final class AudioRecorder {
    /// 10 minutes of 16 kHz 16-bit mono is about 19 MB, under the 25 MB upload limit.
    private static let maxDuration: TimeInterval = 600

    /// Called when the safety cap is reached, so the controller can finish the recording.
    var onLimit: (() -> Void)?

    private var engine: AVAudioEngine?
    private var writer: RecordingWriter?
    private var url: URL?

    /// Starts recording and returns the file it writes to.
    /// An empty `deviceUID`, or a microphone that is not connected, means the system default.
    func start(deviceUID: String, spectrum: SpectrumAnalyzer) throws -> URL {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if !deviceUID.isEmpty, let deviceID = AudioDevices.deviceID(forUID: deviceUID) {
            do {
                try input.auAudioUnit.setDeviceID(deviceID)
            } catch {
                throw SpraakwaterError.microphoneUnavailable
            }
        }

        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw SpraakwaterError.recordingFailed }

        let url = RecordingStore.newFileURL()
        let writer = try RecordingWriter(
            url: url,
            inputFormat: format,
            spectrum: spectrum.makeProcessor(sampleRate: format.sampleRate),
            maxSeconds: Self.maxDuration,
            onLimit: { [weak self] in
                Task { @MainActor in self?.onLimit?() }
            }
        )

        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeTap(writer))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            _ = writer.close()
            try? FileManager.default.removeItem(at: url)
            throw SpraakwaterError.recordingFailed
        }

        self.engine = engine
        self.writer = writer
        self.url = url
        return url
    }

    /// Stops the recording and returns the file with its duration, nil when nothing was recording.
    func stop() -> (url: URL, duration: TimeInterval)? {
        guard let engine, let writer, let url else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let duration = writer.close()
        reset()
        return (url, duration)
    }

    /// Stops and throws the recording away.
    func cancel() {
        guard let result = stop() else { return }
        try? FileManager.default.removeItem(at: result.url)
    }

    private func reset() {
        engine = nil
        writer = nil
        url = nil
    }

    /// Built in a nonisolated context so the closure is not bound to the main actor,
    /// because the tap is called on the audio thread.
    private nonisolated static func makeTap(_ writer: RecordingWriter) -> AVAudioNodeTapBlock {
        { buffer, _ in writer.append(buffer) }
    }
}

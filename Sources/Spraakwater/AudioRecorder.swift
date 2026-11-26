import AVFoundation

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

/// Records 16 kHz mono PCM, which is all the transcription models need and keeps uploads small.
final class AudioRecorder {
    /// 10 minutes of 16 kHz 16-bit mono is about 19 MB, under the 25 MB upload limit.
    private static let maxDuration: TimeInterval = 600

    private var recorder: AVAudioRecorder?

    func start() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("spraakwater-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        guard recorder.record(forDuration: Self.maxDuration) else {
            throw SpraakwaterError.recordingFailed
        }
        self.recorder = recorder
    }

    /// Stops the recording and returns the file with its duration, nil when nothing was recording.
    func stop() -> (url: URL, duration: TimeInterval)? {
        guard let recorder else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        return (recorder.url, duration)
    }

    func cancel() {
        guard let recorder else { return }
        recorder.stop()
        try? FileManager.default.removeItem(at: recorder.url)
        self.recorder = nil
    }
}

import Accelerate
import AVFoundation
import os

/// Latest band values, written on the audio thread and read on the main thread.
nonisolated final class SpectrumStore: Sendable {
    private let lock = OSAllocatedUnfairLock<[Float]>(initialState: [])

    func set(_ values: [Float]) { lock.withLock { $0 = values } }
    func get() -> [Float] { lock.withLock { $0 } }
}

/// Holds the frequency bands (0...1) that the overlay draws. The recorder feeds it from its own
/// microphone tap through a processor, so there is only one engine on the microphone.
final class SpectrumAnalyzer {
    static let bandCount = 15

    nonisolated let store = SpectrumStore()

    func makeProcessor(sampleRate: Double) -> SpectrumProcessor {
        SpectrumProcessor(sampleRate: sampleRate, bandCount: Self.bandCount, store: store)
    }

    func reset() {
        store.set([])
    }
}

/// FFT work, only ever used from the audio thread.
nonisolated final class SpectrumProcessor: @unchecked Sendable {
    private static let size = 1024
    private static let log2Size: vDSP_Length = 10

    private let bandCount: Int
    private let store: SpectrumStore
    private let fft: FFTSetup
    private let window: [Float]
    /// For every band the range of FFT bins and the band's center frequency.
    private let bands: [(bins: Range<Int>, center: Float)]

    private var samples = [Float](repeating: 0, count: size)
    private var real = [Float](repeating: 0, count: size / 2)
    private var imag = [Float](repeating: 0, count: size / 2)
    private var power = [Float](repeating: 0, count: size / 2)
    /// Slowly decaying loudest band level, so the bars scale to how loud you speak.
    private var peakDB: Float = -50

    init(sampleRate: Double, bandCount: Int, store: SpectrumStore) {
        self.bandCount = bandCount
        self.store = store
        fft = vDSP_create_fftsetup(Self.log2Size, FFTRadix(kFFTRadix2))!

        var hann = [Float](repeating: 0, count: Self.size)
        vDSP_hann_window(&hann, vDSP_Length(Self.size), Int32(vDSP_HANN_NORM))
        window = hann

        // Log-spaced bands over the range that matters for speech.
        let low: Float = 100
        let high: Float = 6000
        let binWidth = Float(sampleRate) / Float(Self.size)
        let maxBin = Self.size / 2 - 1
        var result: [(bins: Range<Int>, center: Float)] = []
        for index in 0..<bandCount {
            let from = low * pow(high / low, Float(index) / Float(bandCount))
            let to = low * pow(high / low, Float(index + 1) / Float(bandCount))
            let startBin = min(maxBin, max(1, Int((from / binWidth).rounded())))
            let endBin = min(maxBin + 1, max(startBin + 1, Int((to / binWidth).rounded())))
            result.append((startBin..<endBin, (from * to).squareRoot()))
        }
        bands = result
    }

    deinit { vDSP_destroy_fftsetup(fft) }

    func process(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = min(Int(buffer.frameLength), Self.size)
        guard count > 0 else { return }

        for index in 0..<Self.size {
            samples[index] = index < count ? channel[index] : 0
        }
        vDSP.multiply(samples, window, result: &samples)

        real.withUnsafeMutableBufferPointer { realPointer in
            imag.withUnsafeMutableBufferPointer { imagPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imagPointer.baseAddress!)
                samples.withUnsafeBufferPointer { pointer in
                    pointer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Self.size / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(Self.size / 2))
                    }
                }
                vDSP_fft_zrip(fft, &split, 1, Self.log2Size, FFTDirection(kFFTDirection_Forward))
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(Self.size / 2))
            }
        }

        // Convert every band to decibels, with +3 dB per octave to compensate for speech rolling off.
        var decibels = [Float](repeating: -120, count: bandCount)
        for (index, band) in bands.enumerated() {
            var sum: Float = 0
            for bin in band.bins { sum += power[bin] }
            let meanPower = sum / Float(band.bins.count)
            let amplitude = meanPower.squareRoot() / Float(Self.size)
            let tilt = 3 * log2(band.center / 200)
            decibels[index] = 20 * log10(amplitude + 1e-9) + tilt
        }

        // The floor keeps room noise flat. The peak follows your loudness so normal speech never pins the bars.
        let frameMax = decibels.max() ?? -120
        peakDB = max(frameMax, peakDB - 0.35, -50)
        let floorDB: Float = -85
        let span = max(20, peakDB - floorDB)

        let values = decibels.map { value -> Float in
            let normalized = max(0, min(1, (value - floorDB) / span))
            return pow(normalized, 2.2)
        }
        store.set(values)
    }
}

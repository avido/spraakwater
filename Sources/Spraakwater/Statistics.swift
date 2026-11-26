import Foundation
import Observation

extension Locale {
    /// The UI is Dutch whatever the Mac's language is.
    static let dutch = Locale(identifier: "nl_NL")
}

/// Running totals for the overview. They hold no text, only counts, so they stay when the history is cleared
/// and do not shrink when the history is limited.
@Observable
final class StatisticsStore {
    /// Typing speed used to estimate how much time speaking saves. This is an assumption, not a measurement.
    static let typingWordsPerMinute = 40.0

    private struct Stored: Codable {
        var words = 0
        var speakingSeconds = 0.0
        var dictations = 0
        var days: [String] = []
    }

    private(set) var words = 0
    private(set) var speakingSeconds = 0.0
    private(set) var dictations = 0
    private(set) var days: Set<String> = []

    @ObservationIgnored private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Spraakwater", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("statistieken.json")
        load()
    }

    func record(words newWords: Int, seconds: Double, date: Date = Date()) {
        guard newWords > 0 else { return }
        words += newWords
        speakingSeconds += max(0, seconds)
        dictations += 1
        days.insert(Self.key(for: date))
        save()
    }

    func reset() {
        words = 0
        speakingSeconds = 0
        dictations = 0
        days = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Words per minute of speaking time, nil until there is enough speech to say something sensible.
    var wordsPerMinute: Int? {
        guard speakingSeconds >= 20 else { return nil }
        return Int((Double(words) / (speakingSeconds / 60)).rounded())
    }

    /// Time typing the same words would have taken, minus the time spent speaking them.
    var timeSaved: TimeInterval {
        max(0, Double(words) / Self.typingWordsPerMinute * 60 - speakingSeconds)
    }

    /// Consecutive days with at least one dictation, ending today or yesterday.
    var streak: Int {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: Date())
        if !days.contains(Self.key(for: day)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day),
                  days.contains(Self.key(for: yesterday))
            else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(Self.key(for: day)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace }.count
    }

    /// "3 u 20 min" or "4 dagen", short enough for a table cell.
    static func formatted(duration seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "0 min" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours < 48 {
            let rest = minutes % 60
            return rest == 0 ? "\(hours) u" : "\(hours) u \(rest) min"
        }
        return "\(hours / 24) dagen"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static func key(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(Stored.self, from: data)
        else { return }
        words = stored.words
        speakingSeconds = stored.speakingSeconds
        dictations = stored.dictations
        days = Set(stored.days)
    }

    private func save() {
        let stored = Stored(words: words, speakingSeconds: speakingSeconds, dictations: dictations, days: days.sorted())
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

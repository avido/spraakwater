import Foundation
import Observation

struct HistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let text: String
    let appName: String?
}

/// The last dictations, kept on this Mac only, so a text is never lost when it lands in the wrong place.
@Observable
final class HistoryStore {
    /// How many dictations are kept. 0 means no limit.
    var limit = 50 {
        didSet {
            guard limit != oldValue, trim() else { return }
            save()
        }
    }

    private(set) var entries: [HistoryEntry] = []

    @ObservationIgnored private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Spraakwater", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("geschiedenis.json")
        load()
    }

    func add(text: String, appName: String?) {
        entries.insert(HistoryEntry(id: UUID(), date: Date(), text: text, appName: appName), at: 0)
        trim()
        save()
    }

    /// Drops the oldest entries above the limit. Returns whether anything was removed.
    @discardableResult
    private func trim() -> Bool {
        guard limit > 0, entries.count > limit else { return false }
        entries.removeLast(entries.count - limit)
        return true
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
        // Dictations can be private, so only this user may read the file.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

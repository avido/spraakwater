import Carbon.HIToolbox
import Foundation
import Observation

enum TranscriptionProvider: String, CaseIterable, Identifiable {
    case openAI
    case groq

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openAI: "OpenAI (nauwkeuriger)"
        case .groq: "Groq (sneller en goedkoper)"
        }
    }

    var shortName: String {
        switch self {
        case .openAI: "OpenAI"
        case .groq: "Groq"
        }
    }

    var endpoint: URL {
        switch self {
        case .openAI: URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        case .groq: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
        }
    }

    var model: String {
        switch self {
        case .openAI: "gpt-4o-transcribe"
        case .groq: "whisper-large-v3"
        }
    }

    var keyPrefix: String {
        switch self {
        case .openAI: "sk-"
        case .groq: "gsk_"
        }
    }
}

enum DictationLanguage: String, CaseIterable, Identifiable {
    case dutch
    case english
    case automatic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dutch: "Nederlands"
        case .english: "Engels"
        case .automatic: "Automatisch herkennen"
        }
    }

    /// ISO 639-1 code sent to the API, nil lets the model detect the language.
    var code: String? {
        switch self {
        case .dutch: "nl"
        case .english: "en"
        case .automatic: nil
        }
    }
}

@Observable
final class Settings {
    private let defaults = UserDefaults.standard

    var provider: TranscriptionProvider {
        didSet { defaults.set(provider.rawValue, forKey: "provider") }
    }

    var language: DictationLanguage {
        didSet { defaults.set(language.rawValue, forKey: "language") }
    }

    var hotkey: Hotkey {
        didSet {
            if let data = try? JSONEncoder().encode(hotkey), let json = String(data: data, encoding: .utf8) {
                defaults.set(json, forKey: "hotkeyV2")
            }
            onHotkeyChange?(hotkey)
        }
    }

    /// Set when the chosen shortcut could not be registered, for example because macOS already uses it.
    var hotkeyError: String?

    /// Empty means the microphone macOS uses by default.
    var inputDeviceUID: String {
        didSet { defaults.set(inputDeviceUID, forKey: "inputDeviceUID") }
    }

    var historyEnabled: Bool {
        didSet {
            defaults.set(historyEnabled, forKey: "historyEnabled")
            if !historyEnabled { onHistoryDisabled?() }
        }
    }

    /// How many dictations the history keeps.
    static let historyLimitRange = 1...250

    var historyLimit: Int {
        didSet {
            defaults.set(historyLimit, forKey: "historyLimit")
            onHistoryLimitChange?(historyLimit)
        }
    }

    /// Shows Spraakwater in the Dock next to the menu bar icon, for when the menu bar has no room left.
    var showInDock: Bool {
        didSet {
            defaults.set(showInDock, forKey: "showInDock")
            onDockChange?(showInDock)
        }
    }

    var contextEnabled: Bool {
        didSet { defaults.set(contextEnabled, forKey: "contextEnabled") }
    }

    /// The chosen tone per kind of app, and the user's own text for the "custom" tone.
    var toneModes: [AppCategory: ToneStyle] {
        didSet { saveTones() }
    }

    var toneCustom: [AppCategory: String] {
        didSet { saveTones() }
    }

    var cleanupEnabled: Bool {
        didSet { defaults.set(cleanupEnabled, forKey: "cleanupEnabled") }
    }

    var vocabulary: String {
        didSet { defaults.set(vocabulary, forKey: "vocabulary") }
    }

    /// Writing rules that apply in every app, one sentence each.
    var writingRules: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(writingRules), let json = String(data: data, encoding: .utf8) {
                defaults.set(json, forKey: "writingRules")
            }
        }
    }

    var openAIKey: String {
        didSet { Keychain.write(openAIKey.trimmingCharacters(in: .whitespacesAndNewlines), account: "openai") }
    }

    var groqKey: String {
        didSet { Keychain.write(groqKey.trimmingCharacters(in: .whitespacesAndNewlines), account: "groq") }
    }

    var anthropicKey: String {
        didSet { Keychain.write(anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines), account: "anthropic") }
    }

    @ObservationIgnored var onHotkeyChange: ((Hotkey) -> Void)?
    @ObservationIgnored var onHistoryDisabled: (() -> Void)?
    @ObservationIgnored var onDockChange: ((Bool) -> Void)?
    @ObservationIgnored var onHistoryLimitChange: ((Int) -> Void)?

    init() {
        let defaults = UserDefaults.standard
        Settings.migrateLegacyDefaults(into: defaults)
        provider = TranscriptionProvider(rawValue: defaults.string(forKey: "provider") ?? "") ?? .openAI
        language = DictationLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .dutch
        hotkey = Settings.loadHotkey(from: defaults)
        inputDeviceUID = defaults.string(forKey: "inputDeviceUID") ?? ""
        historyEnabled = defaults.object(forKey: "historyEnabled") as? Bool ?? true
        historyLimit = min(max(defaults.object(forKey: "historyLimit") as? Int ?? 50, Settings.historyLimitRange.lowerBound), Settings.historyLimitRange.upperBound)
        showInDock = defaults.object(forKey: "showInDock") as? Bool ?? true
        contextEnabled = defaults.object(forKey: "contextEnabled") as? Bool ?? true
        let (modes, custom) = Settings.loadTones(from: defaults)
        toneModes = modes
        toneCustom = custom
        cleanupEnabled = defaults.object(forKey: "cleanupEnabled") as? Bool ?? true
        vocabulary = defaults.string(forKey: "vocabulary") ?? ""
        writingRules = Settings.loadRules(from: defaults)
        openAIKey = Keychain.read(account: "openai")
        groqKey = Keychain.read(account: "groq")
        anthropicKey = Keychain.read(account: "anthropic")
    }

    /// Reads the saved shortcut. The first version stored a plain name, which is still understood.
    private static func loadHotkey(from defaults: UserDefaults) -> Hotkey {
        if let json = defaults.string(forKey: "hotkeyV2"),
           let hotkey = try? JSONDecoder().decode(Hotkey.self, from: Data(json.utf8)) {
            return hotkey
        }
        switch defaults.string(forKey: "hotkey") {
        case "controlSpace": return .controlSpace
        case "commandOptionSpace": return .commandOptionSpace
        default: return .optionSpace
        }
    }

    /// Reads the tones. The first version stored one free text per app kind, which becomes a custom tone.
    private static func loadTones(from defaults: UserDefaults) -> ([AppCategory: ToneStyle], [AppCategory: String]) {
        let oldDefaults: [AppCategory: String] = [
            .mail: "Wat zorgvuldiger geschreven, volledige zinnen en nette alinea's. Voeg zelf geen aanhef of afsluiting toe.",
            .chat: "Informeel en kort, zoals je in een chat typt. Geen alinea's forceren.",
            .code: "Technisch en compact. Laat bestandsnamen, commando's, functienamen en code letterlijk staan.",
            .notes: "Gewone zinnen met een nieuwe alinea bij een nieuw onderwerp. Opsommingen mogen als de spreker opsomt.",
        ]
        var modes: [AppCategory: ToneStyle] = [:]
        var custom: [AppCategory: String] = [:]
        for category in AppCategory.styled {
            custom[category] = defaults.string(forKey: "toneCustom.\(category.rawValue)") ?? ""
            if let raw = defaults.string(forKey: "toneMode.\(category.rawValue)"), let mode = ToneStyle(rawValue: raw) {
                modes[category] = mode
            } else if let old = defaults.string(forKey: "tone.\(category.rawValue)"), old != oldDefaults[category] {
                modes[category] = .custom
                custom[category] = old
            } else {
                modes[category] = ToneStyle.initial(for: category)
            }
        }
        return (modes, custom)
    }

    private func saveTones() {
        for category in AppCategory.styled {
            defaults.set((toneModes[category] ?? .standard).rawValue, forKey: "toneMode.\(category.rawValue)")
            defaults.set(toneCustom[category] ?? "", forKey: "toneCustom.\(category.rawValue)")
        }
    }

    /// Reads the rules. The first version stored one text field, which is split into one rule per line.
    private static func loadRules(from defaults: UserDefaults) -> [String] {
        if let json = defaults.string(forKey: "writingRules"),
           let rules = try? JSONDecoder().decode([String].self, from: Data(json.utf8)) {
            return rules
        }
        let oldDefault = """
        Gebruik nooit een em-dash of en-dash. Zet in het Nederlands nooit een komma voor "en". \
        Schrijf direct en nuchter, in "je"-vorm.
        """
        guard let old = defaults.string(forKey: "extraInstructions"), old != oldDefault else {
            return WritingRules.defaults
        }
        return old.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The tone instruction for the kind of app being dictated into.
    func tone(for category: AppCategory) -> String {
        let mode = toneModes[category] ?? .standard
        if mode == .custom {
            return (toneCustom[category] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return mode.instruction
    }

    func resetTones() {
        for category in AppCategory.styled {
            toneModes[category] = ToneStyle.initial(for: category)
            toneCustom[category] = ""
        }
    }

    /// The rules as a list for the cleanup prompt.
    var extraInstructions: String {
        writingRules.map { "- \($0)" }.joined(separator: "\n")
    }

    /// Adds a rule. Returns what is wrong, nil when it was added.
    func addRule(_ text: String) -> String? {
        let rule = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if rule.isEmpty { return "Schrijf eerst een regel." }
        if rule.count > WritingRules.maxLength { return "Hou het onder de \(WritingRules.maxLength) tekens." }
        if writingRules.contains(where: { $0.caseInsensitiveCompare(rule) == .orderedSame }) {
            return "Deze regel staat er al."
        }
        writingRules.append(rule)
        return nil
    }

    func removeRule(_ rule: String) {
        writingRules.removeAll { $0 == rule }
    }

    /// Copies the preferences saved under the old Dicteer bundle id, once.
    private static func migrateLegacyDefaults(into defaults: UserDefaults) {
        guard defaults.object(forKey: "provider") == nil,
              let legacy = UserDefaults.standard.persistentDomain(forName: "nl.avido.dicteer")
        else { return }
        for (key, value) in legacy { defaults.set(value, forKey: key) }
    }

    /// Adds one or more terms, separated by commas or new lines. Returns what is wrong, nil when all were added.
    func addTerms(_ text: String) -> String? {
        let new = text
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if new.isEmpty { return "Typ eerst een woord of term." }
        var words = vocabularyWords
        let fresh = new.filter { term in !words.contains { $0.caseInsensitiveCompare(term) == .orderedSame } }
        if fresh.isEmpty { return new.count == 1 ? "Dit woord staat er al." : "Deze woorden staan er al." }
        words.insert(contentsOf: fresh.reversed(), at: 0)
        vocabulary = words.joined(separator: "\n")
        return nil
    }

    func removeTerm(_ term: String) {
        vocabulary = vocabularyWords.filter { $0 != term }.joined(separator: "\n")
    }

    var vocabularyWords: [String] {
        vocabulary
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func key(for provider: TranscriptionProvider) -> String {
        switch provider {
        case .openAI: openAIKey
        case .groq: groqKey
        }
    }

    // MARK: Validation (runs before any request is made)

    func keyProblem(for provider: TranscriptionProvider) -> String? {
        let key = key(for: provider).trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { return "Vul je \(provider.shortName)-sleutel in." }
        if !key.hasPrefix(provider.keyPrefix) { return "Dit lijkt geen \(provider.shortName)-sleutel (begint met \(provider.keyPrefix))." }
        return nil
    }

    var anthropicKeyProblem: String? {
        let key = anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { return "Vul je Anthropic-sleutel in of zet het opruimen uit." }
        if !key.hasPrefix("sk-ant-") { return "Dit lijkt geen Anthropic-sleutel (begint met sk-ant-)." }
        return nil
    }

    /// First problem that stops a dictation from working, nil when everything is filled in.
    var configurationProblem: String? {
        if let problem = keyProblem(for: provider) { return problem }
        if cleanupEnabled, let problem = anthropicKeyProblem { return problem }
        return nil
    }
}

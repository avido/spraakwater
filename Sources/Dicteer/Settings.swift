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

enum Hotkey: String, CaseIterable, Identifiable {
    case optionSpace
    case controlSpace
    case commandOptionSpace

    var id: String { rawValue }

    var label: String {
        switch self {
        case .optionSpace: "⌥ Spatie"
        case .controlSpace: "⌃ Spatie"
        case .commandOptionSpace: "⌘⌥ Spatie"
        }
    }

    var keyCode: UInt32 { UInt32(kVK_Space) }

    var modifiers: UInt32 {
        switch self {
        case .optionSpace: UInt32(optionKey)
        case .controlSpace: UInt32(controlKey)
        case .commandOptionSpace: UInt32(cmdKey | optionKey)
        }
    }
}

@Observable
final class Settings {
    static let defaultInstructions = """
    Gebruik nooit een em-dash of en-dash. Zet in het Nederlands nooit een komma voor "en". \
    Schrijf direct en nuchter, in "je"-vorm.
    """

    private let defaults = UserDefaults.standard

    var provider: TranscriptionProvider {
        didSet { defaults.set(provider.rawValue, forKey: "provider") }
    }

    var language: DictationLanguage {
        didSet { defaults.set(language.rawValue, forKey: "language") }
    }

    var hotkey: Hotkey {
        didSet {
            defaults.set(hotkey.rawValue, forKey: "hotkey")
            onHotkeyChange?(hotkey)
        }
    }

    var cleanupEnabled: Bool {
        didSet { defaults.set(cleanupEnabled, forKey: "cleanupEnabled") }
    }

    var vocabulary: String {
        didSet { defaults.set(vocabulary, forKey: "vocabulary") }
    }

    var extraInstructions: String {
        didSet { defaults.set(extraInstructions, forKey: "extraInstructions") }
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

    init() {
        let defaults = UserDefaults.standard
        provider = TranscriptionProvider(rawValue: defaults.string(forKey: "provider") ?? "") ?? .openAI
        language = DictationLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .dutch
        hotkey = Hotkey(rawValue: defaults.string(forKey: "hotkey") ?? "") ?? .optionSpace
        cleanupEnabled = defaults.object(forKey: "cleanupEnabled") as? Bool ?? true
        vocabulary = defaults.string(forKey: "vocabulary") ?? ""
        extraInstructions = defaults.string(forKey: "extraInstructions") ?? Settings.defaultInstructions
        openAIKey = Keychain.read(account: "openai")
        groqKey = Keychain.read(account: "groq")
        anthropicKey = Keychain.read(account: "anthropic")
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
